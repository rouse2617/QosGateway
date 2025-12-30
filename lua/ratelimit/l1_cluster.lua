-- ratelimit/l1_cluster.lua
-- L1 Cluster Layer: 集群层配额管理
-- 管理全局资源配额，支持紧急模式和配额削减

local _M = {
    _VERSION = '1.0.0'
}

local redis_client = require "ratelimit.redis"
local cjson = require "cjson.safe"

-- 配置常量
local CONFIG = {
    KEY_PREFIX = "ratelimit:l1:cluster",
    DEFAULT_CAPACITY = 1000000,         -- 默认集群容量
    RESERVED_RATIO = 0.1,               -- 10% 预留
    EMERGENCY_THRESHOLD = 0.95,         -- 95% 触发紧急模式
    REDUCTION_THRESHOLD = 0.9,          -- 90% 触发配额削减
    RECONCILE_INTERVAL = 60,            -- 60秒对账周期
}

--- 获取集群键
--- @return string key 集群键
local function get_cluster_key()
    return CONFIG.KEY_PREFIX
end

--- 初始化集群配置
--- @param capacity number 集群容量 (可选)
--- @return boolean success 是否成功
function _M.init_cluster(capacity)
    capacity = capacity or CONFIG.DEFAULT_CAPACITY
    local key = get_cluster_key()
    
    local red, err = redis_client.get_connection()
    if not red then
        return false, err
    end
    
    -- 使用 SETNX 避免覆盖
    red:init_pipeline()
    red:setnx(key .. ":capacity", capacity)
    red:setnx(key .. ":available", capacity)
    red:setnx(key .. ":reserved_ratio", CONFIG.RESERVED_RATIO)
    red:setnx(key .. ":emergency_mode", "false")
    red:setnx(key .. ":emergency_reason", "")
    red:setnx(key .. ":emergency_start", 0)
    red:setnx(key .. ":last_reconcile", ngx.now())
    
    local results, err = red:commit_pipeline()
    redis_client.release_connection(red)
    
    return err == nil
end

--- 获取集群状态
--- @return table status 集群状态
function _M.get_status()
    local key = get_cluster_key()
    
    local red, err = redis_client.get_connection()
    if not red then
        return nil, err
    end
    
    red:init_pipeline()
    red:get(key .. ":capacity")
    red:get(key .. ":available")
    red:get(key .. ":reserved_ratio")
    red:get(key .. ":emergency_mode")
    red:get(key .. ":emergency_reason")
    red:get(key .. ":emergency_start")
    red:get(key .. ":last_reconcile")
    
    local results, err = red:commit_pipeline()
    redis_client.release_connection(red)
    
    if err or not results then
        return nil, err
    end
    
    local capacity = tonumber(results[1]) or CONFIG.DEFAULT_CAPACITY
    local available = tonumber(results[2]) or capacity
    
    return {
        capacity = capacity,
        available = available,
        reserved_ratio = tonumber(results[3]) or CONFIG.RESERVED_RATIO,
        emergency_mode = results[4] == "true",
        emergency_reason = results[5] or "",
        emergency_start = tonumber(results[6]) or 0,
        last_reconcile = tonumber(results[7]) or 0,
        usage_ratio = 1 - (available / capacity),
        reserved_amount = capacity * (tonumber(results[3]) or CONFIG.RESERVED_RATIO),
    }
end

--- 检查是否需要触发紧急模式
--- @return boolean need_emergency 是否需要紧急模式
--- @return string reason 原因
function _M.check_emergency_trigger()
    local status = _M.get_status()
    if not status then
        return false, "status_unavailable"
    end
    
    if status.emergency_mode then
        return false, "already_in_emergency"
    end
    
    if status.usage_ratio >= CONFIG.EMERGENCY_THRESHOLD then
        return true, "usage_exceeded_threshold"
    end
    
    return false, "normal"
end

--- 激活紧急模式
--- @param reason string 原因
--- @param duration number 持续时间 (秒，可选)
--- @return boolean success 是否成功
function _M.activate_emergency(reason, duration)
    local key = get_cluster_key()
    duration = duration or 300  -- 默认 5 分钟
    
    local red, err = redis_client.get_connection()
    if not red then
        return false, err
    end
    
    red:init_pipeline()
    red:set(key .. ":emergency_mode", "true")
    red:set(key .. ":emergency_reason", reason or "manual")
    red:set(key .. ":emergency_start", ngx.now())
    red:set(key .. ":emergency_duration", duration)
    
    local results, err = red:commit_pipeline()
    redis_client.release_connection(red)
    
    if err then
        return false, err
    end
    
    -- 发布紧急模式事件
    _M.publish_event("emergency_activated", {
        reason = reason,
        duration = duration,
        timestamp = ngx.now()
    })
    
    ngx.log(ngx.WARN, "Emergency mode activated: ", reason)
    return true
end

--- 停用紧急模式
--- @return boolean success 是否成功
function _M.deactivate_emergency()
    local key = get_cluster_key()
    
    local red, err = redis_client.get_connection()
    if not red then
        return false, err
    end
    
    red:init_pipeline()
    red:set(key .. ":emergency_mode", "false")
    red:set(key .. ":emergency_reason", "")
    red:set(key .. ":emergency_start", 0)
    
    local results, err = red:commit_pipeline()
    redis_client.release_connection(red)
    
    if err then
        return false, err
    end
    
    -- 发布事件
    _M.publish_event("emergency_deactivated", {
        timestamp = ngx.now()
    })
    
    ngx.log(ngx.NOTICE, "Emergency mode deactivated")
    return true
end

--- 检查紧急模式是否过期
--- @return boolean expired 是否过期
function _M.check_emergency_expiry()
    local key = get_cluster_key()
    
    local red, err = redis_client.get_connection()
    if not red then
        return false
    end
    
    local emergency_mode = red:get(key .. ":emergency_mode")
    if emergency_mode ~= "true" then
        redis_client.release_connection(red)
        return false
    end
    
    local start = tonumber(red:get(key .. ":emergency_start")) or 0
    local duration = tonumber(red:get(key .. ":emergency_duration")) or 300
    
    redis_client.release_connection(red)
    
    if ngx.now() - start > duration then
        _M.deactivate_emergency()
        return true
    end
    
    return false
end

--- 分配配额给应用
--- @param app_id string 应用 ID
--- @param amount number 配额数量
--- @return boolean success 是否成功
--- @return number granted 实际分配数量
function _M.allocate_quota(app_id, amount)
    local key = get_cluster_key()
    
    local red, err = redis_client.get_connection()
    if not red then
        return false, 0
    end
    
    -- 获取当前可用量
    local available = tonumber(red:get(key .. ":available")) or 0
    local capacity = tonumber(red:get(key .. ":capacity")) or CONFIG.DEFAULT_CAPACITY
    local reserved = capacity * CONFIG.RESERVED_RATIO
    
    -- 计算可分配量
    local allocatable = available - reserved
    local granted = math.min(amount, math.max(0, allocatable))
    
    if granted > 0 then
        red:decrby(key .. ":available", granted)
    end
    
    redis_client.release_connection(red)
    
    return granted > 0, granted
end

--- 归还配额
--- @param app_id string 应用 ID
--- @param amount number 配额数量
--- @return boolean success 是否成功
function _M.return_quota(app_id, amount)
    local key = get_cluster_key()
    
    local red, err = redis_client.get_connection()
    if not red then
        return false, err
    end
    
    local capacity = tonumber(red:get(key .. ":capacity")) or CONFIG.DEFAULT_CAPACITY
    local available = tonumber(red:get(key .. ":available")) or 0
    
    -- 确保不超过容量
    local new_available = math.min(capacity, available + amount)
    red:set(key .. ":available", new_available)
    
    redis_client.release_connection(red)
    return true
end

--- 执行全局对账
--- @return table result 对账结果
function _M.reconcile()
    local key = get_cluster_key()
    local l2_bucket = require "ratelimit.l2_bucket"
    
    local red, err = redis_client.get_connection()
    if not red then
        return nil, err
    end
    
    -- 获取所有应用
    local apps = l2_bucket.list_apps()
    
    -- 计算所有应用的令牌总和
    local total_used = 0
    for _, app_id in ipairs(apps) do
        local config = l2_bucket.get_config(app_id)
        if config then
            local borrowed = config.borrowed or 0
            local guaranteed = config.guaranteed_quota or 0
            total_used = total_used + guaranteed + borrowed
        end
    end
    
    -- 获取集群容量
    local capacity = tonumber(red:get(key .. ":capacity")) or CONFIG.DEFAULT_CAPACITY
    
    -- 计算预期可用量
    local expected_available = capacity - total_used
    local current_available = tonumber(red:get(key .. ":available")) or 0
    
    -- 计算漂移
    local drift = math.abs(expected_available - current_available)
    local drift_ratio = drift / capacity
    
    -- 如果漂移超过 10%，进行修正
    local corrected = false
    if drift_ratio > 0.1 then
        red:set(key .. ":available", expected_available)
        corrected = true
        ngx.log(ngx.WARN, "Reconciliation corrected drift: ", drift, " (", drift_ratio * 100, "%)")
    end
    
    -- 更新对账时间
    red:set(key .. ":last_reconcile", ngx.now())
    
    redis_client.release_connection(red)
    
    return {
        total_apps = #apps,
        total_used = total_used,
        capacity = capacity,
        expected_available = expected_available,
        current_available = current_available,
        drift = drift,
        drift_ratio = drift_ratio,
        corrected = corrected,
        timestamp = ngx.now()
    }
end

--- 发布事件
--- @param event_type string 事件类型
--- @param data table 事件数据
function _M.publish_event(event_type, data)
    local red, err = redis_client.get_connection()
    if not red then
        return
    end
    
    local message = cjson.encode({
        type = event_type,
        data = data,
        timestamp = ngx.now()
    })
    
    red:publish("ratelimit:events", message)
    redis_client.release_connection(red)
end

--- 设置集群容量
--- @param capacity number 容量
--- @return boolean success 是否成功
function _M.set_capacity(capacity)
    local key = get_cluster_key()
    
    local red, err = redis_client.get_connection()
    if not red then
        return false, err
    end
    
    local old_capacity = tonumber(red:get(key .. ":capacity")) or CONFIG.DEFAULT_CAPACITY
    local old_available = tonumber(red:get(key .. ":available")) or old_capacity
    
    -- 按比例调整可用量
    local ratio = old_available / old_capacity
    local new_available = capacity * ratio
    
    red:set(key .. ":capacity", capacity)
    red:set(key .. ":available", new_available)
    
    redis_client.release_connection(red)
    
    _M.publish_event("capacity_changed", {
        old_capacity = old_capacity,
        new_capacity = capacity
    })
    
    return true
end

return _M
