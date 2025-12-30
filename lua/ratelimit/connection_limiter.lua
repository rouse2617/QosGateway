-- ratelimit/connection_limiter.lua
-- Connection Limiter: 连接限制器
-- 管理并发连接数限制，支持 per-app 和 per-cluster 两个维度

local _M = {
    _VERSION = '1.0.0'
}

local shared_dict = ngx.shared.connlimit_dict
local cjson = require "cjson.safe"

-- 配置常量
local CONFIG = {
    CLEANUP_INTERVAL = 30,        -- 清理间隔（秒）
    CONNECTION_TIMEOUT = 300,     -- 连接超时（秒）
    TRACK_RETENTION = 3600,       -- 追踪记录保留时间（秒）
    DEFAULT_APP_LIMIT = 1000,     -- 默认 App 连接限制
    DEFAULT_CLUSTER_LIMIT = 5000, -- 默认 Cluster 连接限制
    MAX_CLEANUP_KEYS = 1000,      -- 每次清理最大扫描键数
    RETRY_MAX = 3,                -- 原子操作最大重试次数
}

--- 输入验证
--- @param app_id string 应用 ID
--- @param cluster_id string 集群 ID
--- @return boolean valid 是否有效
--- @return string error 错误信息
local function validate_input(app_id, cluster_id)
    if not app_id or type(app_id) ~= "string" or #app_id == 0 or #app_id > 128 then
        return false, "invalid app_id"
    end
    if not cluster_id or type(cluster_id) ~= "string" or #cluster_id == 0 or #cluster_id > 128 then
        return false, "invalid cluster_id"
    end
    -- 防止路径遍历和特殊字符
    if app_id:match("[^%w%-_]") or cluster_id:match("[^%w%-_]") then
        return false, "invalid characters in id"
    end
    return true, nil
end

--- 获取或初始化连接数据
--- @param key string 键名
--- @param default_limit number 默认限制
--- @return table data 连接数据
local function get_or_init_data(key, default_limit)
    local data_str = shared_dict:get(key)
    if data_str then
        local data, err = cjson.decode(data_str)
        if data then
            return data
        end
        ngx.log(ngx.WARN, "Failed to decode connection data: ", err)
    end
    return {
        current = 0,
        limit = default_limit,
        rejected = 0,
        peak = 0,
        last_update = ngx.now()
    }
end

--- 原子递增连接计数（使用 CAS 模式）
--- @param key string 键名
--- @param default_limit number 默认限制
--- @return boolean success 是否成功
--- @return table data 更新后的数据
local function atomic_increment(key, default_limit)
    for i = 1, CONFIG.RETRY_MAX do
        local data = get_or_init_data(key, default_limit)
        local old_str = shared_dict:get(key)
        
        -- 检查限制
        if data.current >= data.limit then
            data.rejected = data.rejected + 1
            shared_dict:set(key, cjson.encode(data))
            return false, data
        end
        
        -- 递增计数
        data.current = data.current + 1
        data.peak = math.max(data.peak, data.current)
        data.last_update = ngx.now()
        
        local new_str = cjson.encode(data)
        
        -- CAS 操作
        if old_str then
            local current_str = shared_dict:get(key)
            if current_str == old_str then
                shared_dict:set(key, new_str)
                return true, data
            end
        else
            local ok = shared_dict:safe_add(key, new_str)
            if ok then
                return true, data
            end
        end
    end
    
    ngx.log(ngx.ERR, "atomic_increment failed after ", CONFIG.RETRY_MAX, " retries")
    return false, nil
end

--- 原子递减连接计数
--- @param key string 键名
local function atomic_decrement(key)
    for i = 1, CONFIG.RETRY_MAX do
        local data_str = shared_dict:get(key)
        if not data_str then return end
        
        local data, err = cjson.decode(data_str)
        if not data then
            ngx.log(ngx.WARN, "Failed to decode for decrement: ", err)
            return
        end
        
        data.current = math.max(0, data.current - 1)
        data.last_update = ngx.now()
        
        local new_str = cjson.encode(data)
        local current_str = shared_dict:get(key)
        
        if current_str == data_str then
            shared_dict:set(key, new_str)
            return
        end
    end
    ngx.log(ngx.WARN, "atomic_decrement failed after retries")
end

--- 生成唯一连接 ID
--- @return string conn_id 连接 ID
local function generate_conn_id()
    local now = ngx.now()
    local random_part = string.format("%08x", math.random(0, 0xFFFFFFFF))
    return string.format("%s:%s:%d:%s",
        ngx.var.server_addr or "unknown",
        ngx.var.connection or "0",
        math.floor(now * 1000000),
        random_part
    )
end

--- 初始化连接限制器
--- @return boolean success 是否成功
function _M.init()
    if not shared_dict then
        return nil, "connlimit_dict not found"
    end
    _M.start_cleanup_timer()
    _M.start_stats_timer()
    ngx.log(ngx.NOTICE, "Connection limiter initialized")
    return true
end

--- 检查并获取连接
--- @param app_id string 应用 ID
--- @param cluster_id string 集群 ID
--- @return boolean allowed 是否允许
--- @return table result 结果详情
function _M.acquire(app_id, cluster_id)
    -- 输入验证
    local valid, err = validate_input(app_id, cluster_id)
    if not valid then
        return false, { code = "invalid_input", message = err }
    end
    
    local now = ngx.now()
    local app_key = "conn:app:" .. app_id
    local cluster_key = "conn:cluster:" .. cluster_id
    
    -- 1. 原子递增 App 计数
    local app_ok, app_data = atomic_increment(app_key, CONFIG.DEFAULT_APP_LIMIT)
    if not app_ok then
        _M.record_rejection(app_id, cluster_id, "app_limit_exceeded")
        return false, {
            code = "app_limit_exceeded",
            limit = app_data and app_data.limit or CONFIG.DEFAULT_APP_LIMIT,
            current = app_data and app_data.current or 0,
            retry_after = 1
        }
    end
    
    -- 2. 原子递增 Cluster 计数
    local cluster_ok, cluster_data = atomic_increment(cluster_key, CONFIG.DEFAULT_CLUSTER_LIMIT)
    if not cluster_ok then
        -- 回滚 App 计数
        atomic_decrement(app_key)
        _M.record_rejection(app_id, cluster_id, "cluster_limit_exceeded")
        return false, {
            code = "cluster_limit_exceeded",
            limit = cluster_data and cluster_data.limit or CONFIG.DEFAULT_CLUSTER_LIMIT,
            current = cluster_data and cluster_data.current or 0,
            retry_after = 1
        }
    end
    
    -- 3. 生成唯一连接追踪 ID
    local conn_id = generate_conn_id()
    
    -- 4. 记录连接追踪
    local track_data = {
        app_id = app_id,
        cluster_id = cluster_id,
        created_at = now,
        last_seen = now,
        client_ip = ngx.var.remote_addr or "unknown",
        status = "active"
    }
    
    local track_key = "conn:track:" .. conn_id
    shared_dict:set(track_key, cjson.encode(track_data), CONFIG.CONNECTION_TIMEOUT)
    
    -- 5. 存储到请求上下文
    ngx.ctx.conn_limit_id = conn_id
    ngx.ctx.conn_limit_app = app_id
    ngx.ctx.conn_limit_cluster = cluster_id
    
    return true, {
        code = "allowed",
        conn_id = conn_id,
        app_remaining = app_data.limit - app_data.current,
        cluster_remaining = cluster_data.limit - cluster_data.current
    }
end

--- 更新连接活跃时间
function _M.heartbeat()
    local conn_id = ngx.ctx.conn_limit_id
    if not conn_id then return end
    
    local track_key = "conn:track:" .. conn_id
    local track_data_str = shared_dict:get(track_key)
    if not track_data_str then return end
    
    local track_data = cjson.decode(track_data_str)
    if track_data and track_data.status == "active" then
        track_data.last_seen = ngx.now()
        shared_dict:set(track_key, cjson.encode(track_data), CONFIG.CONNECTION_TIMEOUT)
    end
end

--- 释放连接
function _M.release()
    local conn_id = ngx.ctx.conn_limit_id
    local app_id = ngx.ctx.conn_limit_app
    local cluster_id = ngx.ctx.conn_limit_cluster
    
    if not conn_id then return end
    
    local track_key = "conn:track:" .. conn_id
    local track_data_str = shared_dict:get(track_key)
    
    if not track_data_str then
        ngx.log(ngx.WARN, "Connection tracking not found: ", conn_id)
        return
    end
    
    local track_data = cjson.decode(track_data_str)
    if not track_data then return end
    
    -- 幂等性检查
    if track_data.status == "released" then
        return
    end
    
    -- 原子递减计数
    atomic_decrement("conn:app:" .. app_id)
    atomic_decrement("conn:cluster:" .. cluster_id)
    
    -- 标记为已释放
    track_data.status = "released"
    track_data.released_at = ngx.now()
    track_data.duration = track_data.released_at - track_data.created_at
    shared_dict:set(track_key, cjson.encode(track_data), 60)
    
    -- 清理上下文
    ngx.ctx.conn_limit_id = nil
    ngx.ctx.conn_limit_app = nil
    ngx.ctx.conn_limit_cluster = nil
end

--- 强制释放连接
--- @param track_key string 追踪键
--- @param track_data table 追踪数据
local function force_release_connection(track_key, track_data)
    ngx.log(ngx.WARN, string.format(
        "Force releasing leaked connection: app=%s, cluster=%s, age=%.2fs",
        track_data.app_id, track_data.cluster_id,
        ngx.now() - track_data.last_seen
    ))
    
    atomic_decrement("conn:app:" .. track_data.app_id)
    atomic_decrement("conn:cluster:" .. track_data.cluster_id)
    
    track_data.status = "force_released"
    track_data.released_at = ngx.now()
    track_data.leaked = true
    shared_dict:set(track_key, cjson.encode(track_data), CONFIG.TRACK_RETENTION)
end

--- 清理泄漏连接
--- @return number leaked_count 泄漏连接数
function _M.cleanup_leaked_connections()
    local now = ngx.now()
    local leaked_count = 0
    
    local keys = shared_dict:get_keys(CONFIG.MAX_CLEANUP_KEYS)
    
    for _, key in ipairs(keys) do
        if string.match(key, "^conn:track:") then
            local track_data_str = shared_dict:get(key)
            if track_data_str then
                local track_data = cjson.decode(track_data_str)
                if track_data and track_data.status == "active" then
                    local age = now - track_data.last_seen
                    if age > CONFIG.CONNECTION_TIMEOUT then
                        leaked_count = leaked_count + 1
                        force_release_connection(key, track_data)
                    end
                end
            end
        end
    end
    
    shared_dict:set("conn:cleanup:last_run", now)
    if leaked_count > 0 then
        shared_dict:incr("conn:leaked:total", leaked_count, 0)
        ngx.log(ngx.NOTICE, "Connection cleanup: leaked=", leaked_count)
    end
    
    return leaked_count
end

--- 记录拒绝事件
function _M.record_rejection(app_id, cluster_id, reason)
    shared_dict:incr("conn:rejected:total", 1, 0)
    ngx.log(ngx.WARN, string.format(
        "Connection rejected: app=%s, cluster=%s, reason=%s, ip=%s",
        app_id, cluster_id, reason, ngx.var.remote_addr or "unknown"
    ))
end

--- 启动清理定时器
function _M.start_cleanup_timer()
    local handler
    handler = function(premature)
        if premature then return end
        pcall(_M.cleanup_leaked_connections)
        ngx.timer.at(CONFIG.CLEANUP_INTERVAL, handler)
    end
    ngx.timer.at(CONFIG.CLEANUP_INTERVAL, handler)
end

--- 启动统计上报定时器
function _M.start_stats_timer()
    local handler
    handler = function(premature)
        if premature then return end
        pcall(_M.report_stats_to_redis)
        ngx.timer.at(10, handler)
    end
    ngx.timer.at(10, handler)
end

--- 上报统计到 Redis
function _M.report_stats_to_redis()
    local redis_client = require "ratelimit.redis"
    local red, err = redis_client.get_connection()
    if not red then return end
    
    -- 收集本地统计
    local stats = {
        rejected_total = shared_dict:get("conn:rejected:total") or 0,
        leaked_total = shared_dict:get("conn:leaked:total") or 0,
        last_cleanup = shared_dict:get("conn:cleanup:last_run") or 0,
    }
    
    -- 上报到 Redis
    local node_id = ngx.var.server_addr or "unknown"
    local key = "connlimit:stats:node:" .. node_id
    
    red:hmset(key,
        "rejected_total", stats.rejected_total,
        "leaked_total", stats.leaked_total,
        "last_cleanup", stats.last_cleanup,
        "last_report", ngx.now()
    )
    red:expire(key, 300)
    
    redis_client.release_connection(red)
end

--- 获取统计信息
--- @param app_id string 应用 ID
--- @param cluster_id string 集群 ID
--- @return table stats 统计信息
function _M.get_stats(app_id, cluster_id)
    local app_key = "conn:app:" .. app_id
    local cluster_key = "conn:cluster:" .. cluster_id
    
    local app_data = get_or_init_data(app_key, CONFIG.DEFAULT_APP_LIMIT)
    local cluster_data = get_or_init_data(cluster_key, CONFIG.DEFAULT_CLUSTER_LIMIT)
    
    return {
        app = app_data,
        cluster = cluster_data,
        global = {
            total_rejected = shared_dict:get("conn:rejected:total") or 0,
            total_leaked = shared_dict:get("conn:leaked:total") or 0,
            last_cleanup = shared_dict:get("conn:cleanup:last_run") or 0
        }
    }
end

--- 设置连接限制
--- @param app_id string 应用 ID
--- @param limit number 限制值
function _M.set_app_limit(app_id, limit)
    local key = "conn:app:" .. app_id
    local data = get_or_init_data(key, limit)
    data.limit = limit
    shared_dict:set(key, cjson.encode(data))
end

--- 设置集群连接限制
--- @param cluster_id string 集群 ID
--- @param limit number 限制值
function _M.set_cluster_limit(cluster_id, limit)
    local key = "conn:cluster:" .. cluster_id
    local data = get_or_init_data(key, limit)
    data.limit = limit
    shared_dict:set(key, cjson.encode(data))
end

--- 设置响应头
function _M.set_response_headers(result)
    if result then
        ngx.header["X-Connection-Limit"] = result.limit or ""
        ngx.header["X-Connection-Current"] = result.current or ""
        ngx.header["X-Connection-Remaining"] = result.app_remaining or ""
    end
end

--- 获取配置
function _M.get_config()
    return CONFIG
end

return _M
