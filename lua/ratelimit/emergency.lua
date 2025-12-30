-- ratelimit/emergency.lua
-- Emergency Manager: 紧急模式管理器
-- 管理紧急模式的激活、配额分配和生命周期

local _M = {
    _VERSION = '1.0.0'
}

local redis_client = require "ratelimit.redis"
local l1_cluster = require "ratelimit.l1_cluster"
local cjson = require "cjson.safe"

-- 配置常量
local CONFIG = {
    DEFAULT_DURATION = 300,         -- 默认持续时间 5 分钟
    AUTO_TRIGGER_THRESHOLD = 0.95,  -- 95% 自动触发
    CHECK_INTERVAL = 10,            -- 检查间隔 10 秒
}

-- 优先级配额比例
local PRIORITY_RATIOS = {
    [0] = 1.0,   -- P0: 100%
    [1] = 0.5,   -- P1: 50%
    [2] = 0.1,   -- P2: 10%
    [3] = 0.0,   -- P3+: 0%
}

--- 获取应用优先级
--- @param app_id string 应用 ID
--- @return number priority 优先级
function _M.get_app_priority(app_id)
    local l2_bucket = require "ratelimit.l2_bucket"
    local config = l2_bucket.get_config(app_id)
    
    if config then
        return config.priority or 2
    end
    
    return 2  -- 默认 P2
end

--- 获取紧急模式下的配额比例
--- @param priority number 优先级
--- @return number ratio 配额比例
function _M.get_quota_ratio(priority)
    return PRIORITY_RATIOS[priority] or 0
end

--- 获取紧急模式下的配额
--- @param app_id string 应用 ID
--- @param ratio number 配额比例
--- @return number quota 紧急配额
function _M.get_emergency_quota(app_id, ratio)
    local l2_bucket = require "ratelimit.l2_bucket"
    local config = l2_bucket.get_config(app_id)
    
    if config then
        return config.guaranteed_quota * ratio
    end
    
    return 0
end

--- 获取紧急模式下已使用的配额
--- @param app_id string 应用 ID
--- @return number used 已使用配额
function _M.get_emergency_used(app_id)
    local key = "ratelimit:emergency:used:" .. app_id
    
    local red, err = redis_client.get_connection()
    if not red then
        return 0
    end
    
    local used = tonumber(red:get(key)) or 0
    redis_client.release_connection(red)
    
    return used
end

--- 记录紧急模式下的消耗
--- @param app_id string 应用 ID
--- @param cost number 消耗
function _M.record_emergency_consumption(app_id, cost)
    local key = "ratelimit:emergency:used:" .. app_id
    
    local red, err = redis_client.get_connection()
    if not red then
        return
    end
    
    red:incrby(key, cost)
    red:expire(key, CONFIG.DEFAULT_DURATION + 60)  -- 比紧急模式多保留 1 分钟
    
    redis_client.release_connection(red)
end

--- 检查紧急模式下的请求
--- @param app_id string 应用 ID
--- @param cost number 请求 Cost
--- @return boolean allowed 是否允许
--- @return table result 结果详情
function _M.check_emergency_request(app_id, cost)
    -- 获取应用优先级
    local priority = _M.get_app_priority(app_id)
    local ratio = _M.get_quota_ratio(priority)
    
    -- P3+ 完全阻止
    if ratio == 0 then
        return false, {
            code = "emergency_blocked",
            priority = priority,
            reason = "low_priority_blocked"
        }
    end
    
    -- 检查紧急配额
    local emergency_quota = _M.get_emergency_quota(app_id, ratio)
    local used = _M.get_emergency_used(app_id)
    
    if used + cost > emergency_quota then
        return false, {
            code = "emergency_quota_exceeded",
            priority = priority,
            quota = emergency_quota,
            used = used,
            cost = cost
        }
    end
    
    -- 记录消耗
    _M.record_emergency_consumption(app_id, cost)
    
    return true, {
        code = "emergency_allowed",
        priority = priority,
        quota = emergency_quota,
        remaining = emergency_quota - used - cost
    }
end

--- 激活紧急模式
--- @param reason string 原因
--- @param duration number 持续时间 (秒，可选)
--- @return boolean success 是否成功
function _M.activate(reason, duration)
    duration = duration or CONFIG.DEFAULT_DURATION
    
    local ok, err = l1_cluster.activate_emergency(reason, duration)
    if not ok then
        return false, err
    end
    
    -- 重置所有应用的紧急消耗计数
    _M.reset_all_emergency_usage()
    
    ngx.log(ngx.WARN, "Emergency mode activated: ", reason, ", duration: ", duration, "s")
    return true
end

--- 停用紧急模式
--- @return boolean success 是否成功
function _M.deactivate()
    local ok, err = l1_cluster.deactivate_emergency()
    if not ok then
        return false, err
    end
    
    ngx.log(ngx.NOTICE, "Emergency mode deactivated")
    return true
end

--- 获取紧急模式状态
--- @return table status 状态
function _M.get_status()
    local cluster_status = l1_cluster.get_status()
    if not cluster_status then
        return {
            active = false,
            error = "cluster_status_unavailable"
        }
    end
    
    return {
        active = cluster_status.emergency_mode,
        reason = cluster_status.emergency_reason,
        start_time = cluster_status.emergency_start,
        usage_ratio = cluster_status.usage_ratio,
        threshold = CONFIG.AUTO_TRIGGER_THRESHOLD
    }
end

--- 检查是否需要自动激活紧急模式
--- @return boolean triggered 是否触发
function _M.check_auto_trigger()
    local status = l1_cluster.get_status()
    if not status then
        return false
    end
    
    -- 已经在紧急模式
    if status.emergency_mode then
        return false
    end
    
    -- 检查使用率
    if status.usage_ratio >= CONFIG.AUTO_TRIGGER_THRESHOLD then
        _M.activate("auto_trigger_high_usage")
        return true
    end
    
    return false
end

--- 检查紧急模式是否过期
--- @return boolean expired 是否过期
function _M.check_expiry()
    return l1_cluster.check_emergency_expiry()
end

--- 重置所有应用的紧急消耗计数
function _M.reset_all_emergency_usage()
    local red, err = redis_client.get_connection()
    if not red then
        return
    end
    
    -- 获取所有紧急消耗键
    local keys, err = red:keys("ratelimit:emergency:used:*")
    if keys and #keys > 0 then
        for _, key in ipairs(keys) do
            red:del(key)
        end
    end
    
    redis_client.release_connection(red)
end

--- 获取所有应用的紧急模式统计
--- @return table stats 统计
function _M.get_all_stats()
    local l2_bucket = require "ratelimit.l2_bucket"
    local apps = l2_bucket.list_apps()
    
    local stats = {}
    for _, app_id in ipairs(apps) do
        local priority = _M.get_app_priority(app_id)
        local ratio = _M.get_quota_ratio(priority)
        local quota = _M.get_emergency_quota(app_id, ratio)
        local used = _M.get_emergency_used(app_id)
        
        table.insert(stats, {
            app_id = app_id,
            priority = priority,
            ratio = ratio,
            quota = quota,
            used = used,
            remaining = quota - used
        })
    end
    
    return stats
end

--- 启动紧急模式检查定时器
function _M.start_check_timer()
    local handler
    handler = function(premature)
        if premature then return end
        
        -- 检查自动触发
        pcall(_M.check_auto_trigger)
        
        -- 检查过期
        pcall(_M.check_expiry)
        
        -- 重新调度
        ngx.timer.at(CONFIG.CHECK_INTERVAL, handler)
    end
    
    ngx.timer.at(CONFIG.CHECK_INTERVAL, handler)
end

--- 获取配置
--- @return table config 配置
function _M.get_config()
    return {
        DEFAULT_DURATION = CONFIG.DEFAULT_DURATION,
        AUTO_TRIGGER_THRESHOLD = CONFIG.AUTO_TRIGGER_THRESHOLD,
        PRIORITY_RATIOS = PRIORITY_RATIOS,
    }
end

return _M
