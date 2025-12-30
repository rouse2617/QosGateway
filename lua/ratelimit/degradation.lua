-- ratelimit/degradation.lua
-- Degradation Manager: 降级管理器
-- 管理 Redis 故障时的降级策略和自动恢复

local _M = {
    _VERSION = '1.0.0'
}

local shared = ngx.shared.ratelimit_dict
local redis_client = require "ratelimit.redis"
local cjson = require "cjson.safe"

-- 降级级别定义
local LEVELS = {
    NORMAL = "normal",           -- 正常模式
    MILD = "mild",               -- 轻度降级：增加 L3 缓存
    SIGNIFICANT = "significant", -- 显著降级：切换 reserved 模式
    FAIL_OPEN = "fail_open"      -- 完全降级：Fail-Open 模式
}

local CONFIG = {
    CHECK_INTERVAL = 5,          -- 健康检查间隔（秒）
    LATENCY_MILD = 10,           -- 轻度降级阈值（ms）
    LATENCY_SIGNIFICANT = 100,   -- 显著降级阈值（ms）
    LATENCY_FAIL_OPEN = 1000,    -- Fail-Open 阈值（ms）
    RECOVERY_CHECKS = 3,         -- 恢复所需连续成功次数
    FAIL_OPEN_TOKENS = 100,      -- Fail-Open 模式令牌数
    L3_CACHE_MULTIPLIER = 2,     -- 轻度降级时 L3 缓存倍数
}

--- 获取当前降级级别
--- @return string level 降级级别
function _M.get_level()
    return shared:get("degradation:level") or LEVELS.NORMAL
end

--- 设置降级级别
--- @param level string 降级级别
--- @param reason string 原因
local function set_level(level, reason)
    local old_level = _M.get_level()
    if old_level == level then return end
    
    shared:set("degradation:level", level)
    shared:set("degradation:reason", reason)
    shared:set("degradation:changed_at", ngx.now())
    
    ngx.log(ngx.WARN, string.format(
        "[degradation] Level changed: %s -> %s, reason: %s",
        old_level, level, reason
    ))
    
    -- 发布降级事件
    _M.publish_event(level, reason)
end

--- 检查 Redis 健康状态
--- @return table status 健康状态
function _M.check_redis_health()
    local start_time = ngx.now()
    local status = {
        available = false,
        latency_ms = 0,
        error = nil
    }
    
    local ok, err = pcall(function()
        local red = redis_client.get_connection()
        if not red then
            status.error = "connection_failed"
            return
        end
        
        local res, ping_err = red:ping()
        if not res then
            status.error = ping_err or "ping_failed"
            return
        end
        
        status.available = true
        redis_client.release_connection(red)
    end)
    
    if not ok then
        status.error = err
    end
    
    status.latency_ms = (ngx.now() - start_time) * 1000
    
    -- 记录延迟历史
    _M.record_latency(status.latency_ms)
    
    return status
end

--- 记录延迟历史
--- @param latency_ms number 延迟（毫秒）
function _M.record_latency(latency_ms)
    local key = "degradation:latency_history"
    local history_str = shared:get(key)
    local history = {}
    
    if history_str then
        history = cjson.decode(history_str) or {}
    end
    
    table.insert(history, {
        latency = latency_ms,
        timestamp = ngx.now()
    })
    
    -- 保留最近 100 条记录
    while #history > 100 do
        table.remove(history, 1)
    end
    
    shared:set(key, cjson.encode(history))
end

--- 获取平均延迟
--- @param window_seconds number 时间窗口（秒）
--- @return number avg_latency 平均延迟（毫秒）
function _M.get_avg_latency(window_seconds)
    window_seconds = window_seconds or 60
    local key = "degradation:latency_history"
    local history_str = shared:get(key)
    
    if not history_str then return 0 end
    
    local history = cjson.decode(history_str) or {}
    local now = ngx.now()
    local sum = 0
    local count = 0
    
    for _, record in ipairs(history) do
        if now - record.timestamp <= window_seconds then
            sum = sum + record.latency
            count = count + 1
        end
    end
    
    return count > 0 and (sum / count) or 0
end

--- 评估并更新降级级别
function _M.evaluate()
    local health = _M.check_redis_health()
    local current_level = _M.get_level()
    local new_level = current_level
    local reason = ""
    
    if not health.available then
        -- Redis 不可用
        new_level = LEVELS.FAIL_OPEN
        reason = "redis_unavailable: " .. (health.error or "unknown")
        shared:set("degradation:recovery_count", 0)
    else
        local avg_latency = _M.get_avg_latency(30)
        
        if avg_latency >= CONFIG.LATENCY_FAIL_OPEN then
            new_level = LEVELS.FAIL_OPEN
            reason = string.format("latency_critical: %.2fms", avg_latency)
            shared:set("degradation:recovery_count", 0)
        elseif avg_latency >= CONFIG.LATENCY_SIGNIFICANT then
            new_level = LEVELS.SIGNIFICANT
            reason = string.format("latency_high: %.2fms", avg_latency)
            shared:set("degradation:recovery_count", 0)
        elseif avg_latency >= CONFIG.LATENCY_MILD then
            new_level = LEVELS.MILD
            reason = string.format("latency_elevated: %.2fms", avg_latency)
            shared:set("degradation:recovery_count", 0)
        else
            -- 延迟正常，尝试恢复
            if current_level ~= LEVELS.NORMAL then
                local recovery_count = (shared:get("degradation:recovery_count") or 0) + 1
                shared:set("degradation:recovery_count", recovery_count)
                
                if recovery_count >= CONFIG.RECOVERY_CHECKS then
                    new_level = LEVELS.NORMAL
                    reason = "recovered"
                    shared:set("degradation:recovery_count", 0)
                end
            end
        end
    end
    
    if new_level ~= current_level then
        set_level(new_level, reason)
    end
    
    return new_level
end

--- 获取降级策略参数
--- @return table params 策略参数
function _M.get_strategy_params()
    local level = _M.get_level()
    
    local params = {
        level = level,
        l3_cache_multiplier = 1,
        use_reserved_mode = false,
        fail_open_tokens = 0,
        sync_interval_multiplier = 1
    }
    
    if level == LEVELS.MILD then
        params.l3_cache_multiplier = CONFIG.L3_CACHE_MULTIPLIER
        params.sync_interval_multiplier = 2
    elseif level == LEVELS.SIGNIFICANT then
        params.l3_cache_multiplier = CONFIG.L3_CACHE_MULTIPLIER * 2
        params.use_reserved_mode = true
        params.sync_interval_multiplier = 5
    elseif level == LEVELS.FAIL_OPEN then
        params.fail_open_tokens = CONFIG.FAIL_OPEN_TOKENS
    end
    
    return params
end

--- 检查是否处于 Fail-Open 模式
--- @return boolean is_fail_open
function _M.is_fail_open()
    return _M.get_level() == LEVELS.FAIL_OPEN
end

--- 发布降级事件
--- @param level string 降级级别
--- @param reason string 原因
function _M.publish_event(level, reason)
    local event = {
        type = "degradation_change",
        level = level,
        reason = reason,
        timestamp = ngx.now()
    }
    
    -- 尝试发布到 Redis
    pcall(function()
        local red = redis_client.get_connection()
        if red then
            red:publish("ratelimit:events", cjson.encode(event))
            redis_client.release_connection(red)
        end
    end)
end

--- 获取降级状态
--- @return table status 状态信息
function _M.get_status()
    return {
        level = _M.get_level(),
        reason = shared:get("degradation:reason") or "",
        changed_at = shared:get("degradation:changed_at") or 0,
        avg_latency_ms = _M.get_avg_latency(60),
        recovery_count = shared:get("degradation:recovery_count") or 0,
        strategy = _M.get_strategy_params()
    }
end

--- 手动设置降级级别
--- @param level string 降级级别
--- @param reason string 原因
--- @return boolean success
function _M.manual_set_level(level, reason)
    if not LEVELS[string.upper(level)] then
        return false, "invalid level"
    end
    
    set_level(level, "manual: " .. (reason or ""))
    return true
end

--- 启动健康检查定时器
function _M.start_health_timer()
    local handler
    handler = function(premature)
        if premature then return end
        
        pcall(_M.evaluate)
        
        ngx.timer.at(CONFIG.CHECK_INTERVAL, handler)
    end
    
    ngx.timer.at(CONFIG.CHECK_INTERVAL, handler)
end

-- 导出常量
_M.LEVELS = LEVELS

return _M
