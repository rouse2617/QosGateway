-- ratelimit/l3_bucket.lua
-- L3 Local Bucket: 本地令牌桶管理
-- 管理 Nginx 共享内存中的本地令牌缓存，实现亚毫秒级限流决策

local _M = {
    _VERSION = '1.0.0'
}

local shared = ngx.shared.ratelimit_dict

-- 配置常量
local CONFIG = {
    RESERVE_TARGET = 1000,          -- 目标预留量
    REFILL_THRESHOLD = 0.2,         -- 20% 触发补充
    SYNC_INTERVAL = 0.1,            -- 100ms 同步间隔
    BATCH_THRESHOLD = 1000,         -- 1000 次触发同步
    FAIL_OPEN_TOKENS = 100,         -- Fail-Open 模式令牌数
    DEFAULT_TOKENS = 1000,          -- 默认初始令牌数
    MAX_PENDING_COST = 100000,      -- 最大待同步消耗
}

--- 获取应用的键前缀
--- @param app_id string 应用 ID
--- @return string prefix 键前缀
local function get_key_prefix(app_id)
    return "app:" .. app_id
end

--- 初始化应用的本地令牌桶
--- @param app_id string 应用 ID
--- @param initial_tokens number 初始令牌数 (可选)
--- @return boolean success 是否成功
function _M.init_bucket(app_id, initial_tokens)
    local prefix = get_key_prefix(app_id)
    initial_tokens = initial_tokens or CONFIG.DEFAULT_TOKENS
    
    -- 使用 safe_add 避免覆盖已存在的值
    shared:safe_add(prefix .. ":tokens", initial_tokens)
    shared:safe_add(prefix .. ":pending_cost", 0)
    shared:safe_add(prefix .. ":pending_count", 0)
    shared:safe_add(prefix .. ":last_sync", ngx.now())
    shared:safe_add(prefix .. ":reserved", 0)
    shared:safe_add(prefix .. ":rollback_count", 0)
    
    return true
end

--- 获取当前模式
--- @return string mode 当前模式 (normal/fail_open)
local function get_mode()
    return shared:get("mode") or "normal"
end

--- 设置系统模式
--- @param mode string 模式 (normal/fail_open)
function _M.set_mode(mode)
    shared:set("mode", mode)
    if mode == "fail_open" then
        shared:set("fail_open_start", ngx.now())
    end
end

--- Fail-Open 模式处理
--- @param app_id string 应用 ID
--- @param cost number 请求 Cost
--- @return boolean allowed 是否允许
--- @return table reason 原因详情
function _M.handle_fail_open(app_id, cost)
    local prefix = get_key_prefix(app_id)
    local fail_open_key = prefix .. ":fail_open_used"
    
    -- 获取已使用的 Fail-Open 令牌
    local used = shared:get(fail_open_key) or 0
    
    if used + cost > CONFIG.FAIL_OPEN_TOKENS then
        return false, {
            code = "fail_open_exhausted",
            remaining = math.max(0, CONFIG.FAIL_OPEN_TOKENS - used),
            cost = cost
        }
    end
    
    -- 扣减 Fail-Open 令牌
    shared:incr(fail_open_key, cost, 0)
    
    return true, {
        code = "fail_open_allowed",
        remaining = CONFIG.FAIL_OPEN_TOKENS - used - cost,
        cost = cost
    }
end

--- 检查是否需要异步补充
--- @param app_id string 应用 ID
--- @param remaining number 剩余令牌
--- @return boolean need_refill 是否需要补充
local function need_async_refill(app_id, remaining)
    return remaining < CONFIG.RESERVE_TARGET * CONFIG.REFILL_THRESHOLD
end

--- 触发异步补充 (通过 ngx.timer)
--- @param app_id string 应用 ID
function _M.async_refill(app_id)
    local prefix = get_key_prefix(app_id)
    local refill_key = prefix .. ":refill_pending"
    
    -- 检查是否已有补充请求在进行中
    if shared:get(refill_key) then
        return
    end
    
    -- 标记补充请求
    shared:set(refill_key, true, 1)  -- 1秒过期
    
    -- 异步执行补充
    ngx.timer.at(0, function(premature)
        if premature then return end
        
        local l2_bucket = require "ratelimit.l2_bucket"
        local ok, tokens = pcall(l2_bucket.acquire_batch, app_id, CONFIG.RESERVE_TARGET)
        
        if ok and tokens and tokens > 0 then
            shared:incr(prefix .. ":tokens", tokens, 0)
        end
        
        shared:delete(refill_key)
    end)
end

--- 检查是否需要批量同步
--- @param app_id string 应用 ID
--- @return boolean need_sync 是否需要同步
local function need_batch_sync(app_id)
    local prefix = get_key_prefix(app_id)
    
    local pending_count = shared:get(prefix .. ":pending_count") or 0
    local last_sync = shared:get(prefix .. ":last_sync") or 0
    local now = ngx.now()
    
    return pending_count >= CONFIG.BATCH_THRESHOLD or 
           (now - last_sync) >= CONFIG.SYNC_INTERVAL
end

--- 执行批量同步
--- @param app_id string 应用 ID
function _M.batch_sync(app_id)
    local prefix = get_key_prefix(app_id)
    
    local pending_cost = shared:get(prefix .. ":pending_cost") or 0
    local pending_count = shared:get(prefix .. ":pending_count") or 0
    
    if pending_cost <= 0 then
        return
    end
    
    -- 异步上报到 L2
    ngx.timer.at(0, function(premature)
        if premature then return end
        
        local l2_bucket = require "ratelimit.l2_bucket"
        local ok = pcall(l2_bucket.report_consumption, app_id, pending_cost, pending_count)
        
        if ok then
            -- 重置计数器
            shared:incr(prefix .. ":pending_cost", -pending_cost)
            shared:incr(prefix .. ":pending_count", -pending_count)
            shared:set(prefix .. ":last_sync", ngx.now())
        end
    end)
end

--- 同步获取令牌 (本地不足时)
--- @param app_id string 应用 ID
--- @param cost number 请求 Cost
--- @return boolean allowed 是否允许
--- @return table reason 原因详情
function _M.sync_acquire(app_id, cost)
    local l2_bucket = require "ratelimit.l2_bucket"
    
    -- 尝试从 L2 获取
    local ok, result = pcall(l2_bucket.acquire, app_id, cost)
    
    if not ok then
        -- L2 不可用，检查是否切换到 Fail-Open
        local mode = get_mode()
        if mode == "fail_open" then
            return _M.handle_fail_open(app_id, cost)
        end
        
        return false, {
            code = "l2_unavailable",
            remaining = 0,
            cost = cost,
            error = result
        }
    end
    
    if result.allowed then
        -- 补充本地令牌
        local prefix = get_key_prefix(app_id)
        if result.refill and result.refill > 0 then
            shared:incr(prefix .. ":tokens", result.refill, 0)
        end
        
        return true, {
            code = "l2_hit",
            remaining = result.remaining or 0,
            cost = cost
        }
    else
        return false, {
            code = result.code or "l2_exhausted",
            remaining = result.remaining or 0,
            cost = cost,
            retry_after = result.retry_after or 1
        }
    end
end

--- 获取令牌
--- @param app_id string 应用 ID
--- @param cost number 请求 Cost
--- @return boolean allowed 是否允许
--- @return table reason 原因详情
function _M.acquire(app_id, cost)
    local prefix = get_key_prefix(app_id)
    local mode = get_mode()
    
    -- Fail-Open 模式处理
    if mode == "fail_open" then
        return _M.handle_fail_open(app_id, cost)
    end
    
    -- 确保桶已初始化
    if not shared:get(prefix .. ":tokens") then
        _M.init_bucket(app_id)
    end
    
    -- 正常模式：检查本地令牌
    local tokens = shared:get(prefix .. ":tokens") or 0
    
    if tokens >= cost then
        -- 本地扣减 (使用 incr 保证原子性)
        local new_tokens = shared:incr(prefix .. ":tokens", -cost)
        
        -- 检查是否扣减成功 (防止并发导致负数)
        if new_tokens and new_tokens >= 0 then
            -- 更新待同步计数器
            shared:incr(prefix .. ":pending_cost", cost, 0)
            shared:incr(prefix .. ":pending_count", 1, 0)
            
            local remaining = new_tokens
            
            -- 检查是否需要异步补充
            if need_async_refill(app_id, remaining) then
                _M.async_refill(app_id)
            end
            
            -- 检查是否需要批量同步
            if need_batch_sync(app_id) then
                _M.batch_sync(app_id)
            end
            
            return true, {
                code = "local_hit",
                remaining = remaining,
                cost = cost
            }
        else
            -- 并发导致负数，回滚
            if new_tokens then
                shared:incr(prefix .. ":tokens", cost)
            end
        end
    end
    
    -- 本地不足，同步获取
    return _M.sync_acquire(app_id, cost)
end

--- 令牌回滚（请求取消时）
--- @param app_id string 应用 ID
--- @param cost number 需要回滚的 Cost
--- @return boolean success 是否成功
function _M.rollback(app_id, cost)
    if cost <= 0 then
        return true
    end
    
    local prefix = get_key_prefix(app_id)
    
    -- 回滚令牌
    shared:incr(prefix .. ":tokens", cost, 0)
    
    -- 减少待同步消耗
    local pending = shared:get(prefix .. ":pending_cost") or 0
    if pending >= cost then
        shared:incr(prefix .. ":pending_cost", -cost)
    end
    
    -- 记录回滚次数
    shared:incr(prefix .. ":rollback_count", 1, 0)
    
    return true
end

--- 获取桶状态
--- @param app_id string 应用 ID
--- @return table status 桶状态
function _M.get_status(app_id)
    local prefix = get_key_prefix(app_id)
    
    return {
        tokens = shared:get(prefix .. ":tokens") or 0,
        pending_cost = shared:get(prefix .. ":pending_cost") or 0,
        pending_count = shared:get(prefix .. ":pending_count") or 0,
        last_sync = shared:get(prefix .. ":last_sync") or 0,
        reserved = shared:get(prefix .. ":reserved") or 0,
        rollback_count = shared:get(prefix .. ":rollback_count") or 0,
        mode = get_mode()
    }
end

--- 设置令牌数 (供对账使用)
--- @param app_id string 应用 ID
--- @param tokens number 令牌数
function _M.set_tokens(app_id, tokens)
    local prefix = get_key_prefix(app_id)
    shared:set(prefix .. ":tokens", tokens)
end

--- 获取配置 (供测试使用)
--- @return table config 配置
function _M.get_config()
    return {
        RESERVE_TARGET = CONFIG.RESERVE_TARGET,
        REFILL_THRESHOLD = CONFIG.REFILL_THRESHOLD,
        SYNC_INTERVAL = CONFIG.SYNC_INTERVAL,
        BATCH_THRESHOLD = CONFIG.BATCH_THRESHOLD,
        FAIL_OPEN_TOKENS = CONFIG.FAIL_OPEN_TOKENS,
    }
end

return _M
