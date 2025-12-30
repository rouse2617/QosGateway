-- ratelimit/l2_bucket.lua
-- L2 Application Bucket: 应用层令牌桶管理
-- 管理 Redis 中的应用级配额，支持保底配额和突发配额

local _M = {
    _VERSION = '1.0.0'
}

local redis_client = require "ratelimit.redis"
local cjson = require "cjson.safe"

-- 配置常量
local CONFIG = {
    DEFAULT_GUARANTEED = 10000,     -- 默认保底配额
    DEFAULT_BURST = 50000,          -- 默认突发配额
    DEFAULT_PRIORITY = 2,           -- 默认优先级
    DEFAULT_MAX_BORROW = 10000,     -- 默认最大借用
    KEY_PREFIX = "ratelimit:l2:",   -- Redis 键前缀
}

--- 获取应用的 Redis 键
--- @param app_id string 应用 ID
--- @return string key Redis 键
local function get_app_key(app_id)
    return CONFIG.KEY_PREFIX .. app_id
end

--- 获取令牌 (使用 Redis Lua 脚本)
--- @param app_id string 应用 ID
--- @param cost number 请求 Cost
--- @return table result 结果
function _M.acquire(app_id, cost)
    local key = get_app_key(app_id)
    local now = ngx.now()
    
    local result, err = redis_client.eval_script("ACQUIRE", {key}, {cost, now})
    
    if err then
        return {
            allowed = false,
            code = "redis_error",
            error = err
        }
    end
    
    if type(result) ~= "table" then
        return {
            allowed = false,
            code = "invalid_response"
        }
    end
    
    local allowed = result[1] == 1
    local remaining = result[2] or 0
    local available_burst = result[3] or 0
    
    return {
        allowed = allowed,
        remaining = remaining,
        available_burst = available_burst,
        code = allowed and "success" or "exhausted",
        retry_after = allowed and 0 or 1
    }
end

--- 批量获取令牌 (供 L3 预取)
--- @param app_id string 应用 ID
--- @param amount number 请求数量
--- @return number granted 实际获取数量
function _M.acquire_batch(app_id, amount)
    local key = get_app_key(app_id)
    local now = ngx.now()
    
    local result, err = redis_client.eval_script("ACQUIRE", {key}, {amount, now})
    
    if err or type(result) ~= "table" then
        return 0
    end
    
    if result[1] == 1 then
        return amount
    else
        -- 返回可用的令牌数
        return math.max(0, result[2] or 0)
    end
end

--- 上报消耗 (从 L3 批量同步)
--- @param app_id string 应用 ID
--- @param cost number 消耗的 Cost
--- @param count number 请求数量
--- @return boolean success 是否成功
function _M.report_consumption(app_id, cost, count)
    local key = get_app_key(app_id)
    
    local red, err = redis_client.get_connection()
    if not red then
        return false
    end
    
    -- 使用 pipeline 批量更新
    red:init_pipeline()
    red:hincrby(key, "total_consumed", cost)
    red:hincrby(key, "total_requests", count)
    red:hset(key, "last_report", ngx.now())
    
    local results, err = red:commit_pipeline()
    redis_client.release_connection(red)
    
    return err == nil
end

--- 获取应用配置
--- @param app_id string 应用 ID
--- @return table config 应用配置
function _M.get_config(app_id)
    local key = get_app_key(app_id)
    
    local red, err = redis_client.get_connection()
    if not red then
        return nil, err
    end
    
    local result, err = red:hgetall(key)
    redis_client.release_connection(red)
    
    if err or not result or #result == 0 then
        return {
            app_id = app_id,
            guaranteed_quota = CONFIG.DEFAULT_GUARANTEED,
            burst_quota = CONFIG.DEFAULT_BURST,
            priority = CONFIG.DEFAULT_PRIORITY,
            max_borrow = CONFIG.DEFAULT_MAX_BORROW,
        }
    end
    
    -- 转换为 table
    local config = {}
    for i = 1, #result, 2 do
        config[result[i]] = result[i + 1]
    end
    
    return {
        app_id = app_id,
        guaranteed_quota = tonumber(config.guaranteed_quota) or CONFIG.DEFAULT_GUARANTEED,
        burst_quota = tonumber(config.burst_quota) or CONFIG.DEFAULT_BURST,
        priority = tonumber(config.priority) or CONFIG.DEFAULT_PRIORITY,
        max_borrow = tonumber(config.max_borrow) or CONFIG.DEFAULT_MAX_BORROW,
        current_tokens = tonumber(config.current_tokens) or 0,
        borrowed = tonumber(config.borrowed) or 0,
        debt = tonumber(config.debt) or 0,
        total_consumed = tonumber(config.total_consumed) or 0,
        total_requests = tonumber(config.total_requests) or 0,
    }
end

--- 设置应用配置
--- @param app_id string 应用 ID
--- @param config table 配置
--- @return boolean success 是否成功
function _M.set_config(app_id, config)
    local key = get_app_key(app_id)
    
    local red, err = redis_client.get_connection()
    if not red then
        return false, err
    end
    
    -- 构建参数
    local args = {}
    if config.guaranteed_quota then
        table.insert(args, "guaranteed_quota")
        table.insert(args, config.guaranteed_quota)
    end
    if config.burst_quota then
        table.insert(args, "burst_quota")
        table.insert(args, config.burst_quota)
    end
    if config.priority then
        table.insert(args, "priority")
        table.insert(args, config.priority)
    end
    if config.max_borrow then
        table.insert(args, "max_borrow")
        table.insert(args, config.max_borrow)
    end
    
    if #args > 0 then
        local ok, err = red:hmset(key, unpack(args))
        redis_client.release_connection(red)
        return ok ~= nil, err
    end
    
    redis_client.release_connection(red)
    return true
end

--- 初始化应用令牌桶
--- @param app_id string 应用 ID
--- @param config table 配置 (可选)
--- @return boolean success 是否成功
function _M.init_bucket(app_id, config)
    config = config or {}
    
    local guaranteed = config.guaranteed_quota or CONFIG.DEFAULT_GUARANTEED
    local burst = config.burst_quota or CONFIG.DEFAULT_BURST
    local priority = config.priority or CONFIG.DEFAULT_PRIORITY
    local max_borrow = config.max_borrow or CONFIG.DEFAULT_MAX_BORROW
    
    local key = get_app_key(app_id)
    
    local red, err = redis_client.get_connection()
    if not red then
        return false, err
    end
    
    -- 使用 HSETNX 避免覆盖已存在的值
    red:init_pipeline()
    red:hsetnx(key, "guaranteed_quota", guaranteed)
    red:hsetnx(key, "burst_quota", burst)
    red:hsetnx(key, "priority", priority)
    red:hsetnx(key, "max_borrow", max_borrow)
    red:hsetnx(key, "current_tokens", guaranteed)
    red:hsetnx(key, "last_refill", ngx.now())
    red:hsetnx(key, "borrowed", 0)
    red:hsetnx(key, "debt", 0)
    red:hsetnx(key, "total_consumed", 0)
    red:hsetnx(key, "total_requests", 0)
    
    local results, err = red:commit_pipeline()
    redis_client.release_connection(red)
    
    return err == nil
end

--- 获取应用状态
--- @param app_id string 应用 ID
--- @return table status 状态
function _M.get_status(app_id)
    local config = _M.get_config(app_id)
    if not config then
        return nil
    end
    
    return {
        app_id = app_id,
        current_tokens = config.current_tokens,
        guaranteed_quota = config.guaranteed_quota,
        burst_quota = config.burst_quota,
        borrowed = config.borrowed,
        debt = config.debt,
        utilization = config.current_tokens / config.burst_quota,
        total_consumed = config.total_consumed,
        total_requests = config.total_requests,
    }
end

--- 重置应用令牌
--- @param app_id string 应用 ID
--- @param tokens number 令牌数 (可选，默认为 guaranteed_quota)
--- @return boolean success 是否成功
function _M.reset_tokens(app_id, tokens)
    local key = get_app_key(app_id)
    
    local red, err = redis_client.get_connection()
    if not red then
        return false, err
    end
    
    if not tokens then
        local guaranteed = red:hget(key, "guaranteed_quota")
        tokens = tonumber(guaranteed) or CONFIG.DEFAULT_GUARANTEED
    end
    
    red:hset(key, "current_tokens", tokens)
    red:hset(key, "last_refill", ngx.now())
    
    redis_client.release_connection(red)
    return true
end

--- 获取所有应用列表
--- @return table apps 应用列表
function _M.list_apps()
    local red, err = redis_client.get_connection()
    if not red then
        return {}, err
    end
    
    local keys, err = red:keys(CONFIG.KEY_PREFIX .. "*")
    redis_client.release_connection(red)
    
    if err or not keys then
        return {}
    end
    
    local apps = {}
    for _, key in ipairs(keys) do
        local app_id = string.sub(key, #CONFIG.KEY_PREFIX + 1)
        table.insert(apps, app_id)
    end
    
    return apps
end

--- 删除应用
--- @param app_id string 应用 ID
--- @return boolean success 是否成功
function _M.delete_app(app_id)
    local key = get_app_key(app_id)
    
    local red, err = redis_client.get_connection()
    if not red then
        return false, err
    end
    
    local ok, err = red:del(key)
    redis_client.release_connection(red)
    
    return ok ~= nil
end

return _M
