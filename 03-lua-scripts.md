# Lua 脚本完整实现

## 一、Redis Lua 脚本

### 1.1 原子令牌获取脚本

```lua
-- scripts/acquire_tokens.lua
-- 原子获取令牌，支持令牌补充

local key = KEYS[1]              -- ratelimit:l2:{app_id}
local cost = tonumber(ARGV[1])   -- 请求的 Cost
local now = tonumber(ARGV[2])    -- 当前时间戳

-- 获取配置
local guaranteed = tonumber(redis.call('HGET', key, 'guaranteed_quota')) or 10000
local burst = tonumber(redis.call('HGET', key, 'burst_quota')) or 50000
local current = tonumber(redis.call('HGET', key, 'current_tokens')) or guaranteed
local last_refill = tonumber(redis.call('HGET', key, 'last_refill')) or now

-- 计算令牌补充（漏桶算法）
local elapsed = math.max(0, now - last_refill)
local refill_amount = elapsed * guaranteed
local new_tokens = math.min(burst, current + refill_amount)

-- 尝试扣减
if new_tokens >= cost then
    local remaining = new_tokens - cost
    redis.call('HSET', key, 'current_tokens', remaining)
    redis.call('HSET', key, 'last_refill', now)
    redis.call('HINCRBY', key, 'total_consumed', cost)
    redis.call('HINCRBY', key, 'total_requests', 1)
    
    return {1, remaining, burst - remaining}  -- 成功, 剩余, 可突发
else
    redis.call('HSET', key, 'current_tokens', new_tokens)
    redis.call('HSET', key, 'last_refill', now)
    
    return {0, new_tokens, 0}  -- 失败, 当前令牌, 0
end
```

### 1.2 批量令牌预取脚本

```lua
-- scripts/batch_acquire.lua
-- L3 从 L2 批量预取令牌

local key = KEYS[1]                  -- ratelimit:l2:{app_id}
local requested = tonumber(ARGV[1])  -- 请求数量
local node_id = ARGV[2]              -- 节点 ID
local now = tonumber(ARGV[3])        -- 当前时间戳

-- 获取当前状态
local current = tonumber(redis.call('HGET', key, 'current_tokens')) or 0
local burst = tonumber(redis.call('HGET', key, 'burst_quota')) or 50000

-- 计算可授予数量（最多授予请求量的 80%，保留一些给其他节点）
local max_grant = math.min(current * 0.8, requested)
local granted = math.floor(max_grant)

if granted > 0 then
    redis.call('HINCRBY', key, 'current_tokens', -granted)
    
    -- 记录分配给哪个节点
    local alloc_key = key .. ':allocations'
    redis.call('HSET', alloc_key, node_id, granted)
    redis.call('HSET', alloc_key, node_id .. ':time', now)
end

return {granted, current - granted}
```


### 1.3 三层原子扣减脚本

```lua
-- scripts/three_layer_deduct.lua
-- 三层联动原子扣减

local user_key = KEYS[1]             -- user:{app_id}:{user_id}
local cost = tonumber(ARGV[1])
local app_id = ARGV[2]
local user_id = ARGV[3]
local now = tonumber(ARGV[4])

local app_key = "ratelimit:l2:" .. app_id
local cluster_key = "ratelimit:l1:cluster"

-- Step 1: 检查 L1 集群配额
local cluster_available = tonumber(redis.call('GET', cluster_key .. ':available')) or 0
local emergency_mode = redis.call('GET', cluster_key .. ':emergency_mode')

if emergency_mode == 'true' then
    -- 紧急模式：只允许高优先级请求
    local priority = redis.call('HGET', app_key, 'priority') or 2
    if tonumber(priority) > 0 then
        return {0, 'emergency_mode', 0, 0}
    end
end

if cluster_available < cost then
    return {0, 'cluster_exhausted', cluster_available, 0}
end

-- Step 2: 检查 L2 应用配额
local app_tokens = tonumber(redis.call('HGET', app_key, 'current_tokens')) or 0
local guaranteed = tonumber(redis.call('HGET', app_key, 'guaranteed_quota')) or 0
local burst = tonumber(redis.call('HGET', app_key, 'burst_quota')) or 0
local last_refill = tonumber(redis.call('HGET', app_key, 'last_refill')) or now

-- 令牌补充
local elapsed = math.max(0, now - last_refill)
local refilled = math.min(burst, app_tokens + elapsed * guaranteed)

if refilled < cost then
    -- 尝试从 L1 借用
    local can_borrow = math.min(cluster_available - cost, cost * 2)
    if can_borrow >= cost then
        redis.call('DECRBY', cluster_key .. ':available', cost)
        redis.call('HINCRBY', app_key, 'borrowed', cost)
        redis.call('HINCRBY', app_key, 'debt', math.ceil(cost * 1.2))
        redis.call('HSET', app_key, 'last_refill', now)
        return {1, 'borrowed', cluster_available - cost, 0}
    else
        return {0, 'app_exhausted', cluster_available, refilled}
    end
end

-- Step 3: 正常扣减
local new_tokens = refilled - cost
redis.call('HSET', app_key, 'current_tokens', new_tokens)
redis.call('HSET', app_key, 'last_refill', now)
redis.call('DECRBY', cluster_key .. ':available', cost)

-- 更新统计
redis.call('HINCRBY', app_key, 'total_consumed', cost)
redis.call('HINCRBY', app_key, 'total_requests', 1)
redis.call('HINCRBY', user_key, 'consumed', cost)

return {1, 'success', cluster_available - cost, new_tokens}
```

---

## 二、批量对账脚本

### 2.1 L3 到 L2 消耗上报

```lua
-- scripts/batch_report.lua
-- L3 批量上报消耗到 L2

local app_id = ARGV[1]
local node_id = ARGV[2]
local consumed = tonumber(ARGV[3])
local requests = tonumber(ARGV[4])
local period_start = tonumber(ARGV[5])
local period_end = tonumber(ARGV[6])

local app_key = "ratelimit:l2:" .. app_id
local stats_key = "ratelimit:stats:" .. app_id
local node_key = stats_key .. ":nodes:" .. node_id

-- 更新应用级统计
redis.call('HINCRBY', stats_key, 'total_consumed', consumed)
redis.call('HINCRBY', stats_key, 'total_requests', requests)
redis.call('HSET', stats_key, 'last_report', period_end)

-- 更新节点级统计
redis.call('HSET', node_key, 'consumed', consumed)
redis.call('HSET', node_key, 'requests', requests)
redis.call('HSET', node_key, 'period_start', period_start)
redis.call('HSET', node_key, 'period_end', period_end)
redis.call('HSET', node_key, 'last_seen', period_end)

-- 设置节点过期时间（用于检测离线节点）
redis.call('EXPIRE', node_key, 300)

-- 添加到活跃节点集合
redis.call('SADD', stats_key .. ':active_nodes', node_id)

return {1, 'reported'}
```

### 2.2 定时对账脚本

```lua
-- scripts/reconcile.lua
-- 每 60 秒运行，修正 L3 与 L2 的差异

local app_id = ARGV[1]
local tolerance = tonumber(ARGV[2]) or 0.1  -- 10% 容差

local app_key = "ratelimit:l2:" .. app_id
local stats_key = "ratelimit:stats:" .. app_id

-- 获取配置值
local guaranteed = tonumber(redis.call('HGET', app_key, 'guaranteed_quota')) or 0
local burst = tonumber(redis.call('HGET', app_key, 'burst_quota')) or 0
local current = tonumber(redis.call('HGET', app_key, 'current_tokens')) or 0

-- 获取统计值
local total_consumed = tonumber(redis.call('HGET', stats_key, 'total_consumed')) or 0
local last_reconcile = tonumber(redis.call('HGET', stats_key, 'last_reconcile')) or 0
local now = tonumber(ARGV[3])

-- 计算期望值
local elapsed = now - last_reconcile
local expected_refill = elapsed * guaranteed
local expected_tokens = math.min(burst, current + expected_refill - total_consumed)

-- 检查偏差
local drift = 0
if expected_tokens > 0 then
    drift = math.abs(current - expected_tokens) / expected_tokens
end

local corrected = false
if drift > tolerance then
    -- 修正令牌数
    redis.call('HSET', app_key, 'current_tokens', expected_tokens)
    redis.call('HSET', stats_key, 'last_correction', now)
    redis.call('HINCRBY', stats_key, 'correction_count', 1)
    corrected = true
end

-- 更新对账时间
redis.call('HSET', stats_key, 'last_reconcile', now)
redis.call('HSET', stats_key, 'total_consumed', 0)  -- 重置周期消耗

return {corrected and 1 or 0, drift, current, expected_tokens}
```

### 2.3 全局对账脚本

```lua
-- scripts/global_reconcile.lua
-- 全局对账，确保 L1 = sum(L2)

local cluster_key = "ratelimit:l1:cluster"
local apps_key = cluster_key .. ":apps"

-- 获取所有应用
local apps = redis.call('SMEMBERS', apps_key)
local total_allocated = 0
local corrections = {}

for _, app_id in ipairs(apps) do
    local app_key = "ratelimit:l2:" .. app_id
    local current = tonumber(redis.call('HGET', app_key, 'current_tokens')) or 0
    local borrowed = tonumber(redis.call('HGET', app_key, 'borrowed')) or 0
    total_allocated = total_allocated + current + borrowed
end

-- 获取 L1 状态
local cluster_capacity = tonumber(redis.call('GET', cluster_key .. ':capacity')) or 1000000
local cluster_available = tonumber(redis.call('GET', cluster_key .. ':available')) or 0

-- 计算期望的可用量
local expected_available = cluster_capacity - total_allocated

-- 检查并修正
local drift = math.abs(cluster_available - expected_available)
if drift > cluster_capacity * 0.05 then  -- 5% 容差
    redis.call('SET', cluster_key .. ':available', expected_available)
    table.insert(corrections, {
        type = 'cluster',
        old = cluster_available,
        new = expected_available,
        drift = drift
    })
end

return cjson.encode({
    total_allocated = total_allocated,
    cluster_available = expected_available,
    corrections = corrections
})
```

---

## 三、紧急模式脚本

### 3.1 激活紧急模式

```lua
-- scripts/emergency_activate.lua
-- 激活紧急模式

local cluster_key = "ratelimit:l1:cluster"
local reason = ARGV[1]
local operator = ARGV[2]
local now = tonumber(ARGV[3])
local duration = tonumber(ARGV[4]) or 300  -- 默认 5 分钟

-- 设置紧急模式
redis.call('SET', cluster_key .. ':emergency_mode', 'true')
redis.call('SET', cluster_key .. ':emergency_reason', reason)
redis.call('SET', cluster_key .. ':emergency_operator', operator)
redis.call('SET', cluster_key .. ':emergency_start', now)
redis.call('SET', cluster_key .. ':emergency_duration', duration)

-- 设置自动过期
redis.call('EXPIRE', cluster_key .. ':emergency_mode', duration)

-- 记录事件
local event = cjson.encode({
    type = 'emergency_activated',
    reason = reason,
    operator = operator,
    timestamp = now,
    duration = duration
})
redis.call('LPUSH', 'ratelimit:events', event)
redis.call('LTRIM', 'ratelimit:events', 0, 999)  -- 保留最近 1000 条

-- 发布通知
redis.call('PUBLISH', 'ratelimit:emergency', event)

return {1, 'activated', duration}
```

### 3.2 解除紧急模式

```lua
-- scripts/emergency_deactivate.lua
-- 解除紧急模式

local cluster_key = "ratelimit:l1:cluster"
local operator = ARGV[1]
local now = tonumber(ARGV[2])

-- 检查当前状态
local is_emergency = redis.call('GET', cluster_key .. ':emergency_mode')
if is_emergency ~= 'true' then
    return {0, 'not_in_emergency'}
end

-- 解除紧急模式
redis.call('DEL', cluster_key .. ':emergency_mode')
redis.call('DEL', cluster_key .. ':emergency_reason')

-- 记录事件
local start_time = redis.call('GET', cluster_key .. ':emergency_start') or now
local duration = now - tonumber(start_time)

local event = cjson.encode({
    type = 'emergency_deactivated',
    operator = operator,
    timestamp = now,
    duration = duration
})
redis.call('LPUSH', 'ratelimit:events', event)

-- 发布通知
redis.call('PUBLISH', 'ratelimit:emergency', event)

return {1, 'deactivated', duration}
```

### 3.3 紧急模式下的限流逻辑

```lua
-- scripts/emergency_check.lua
-- 紧急模式下的请求检查

local cluster_key = "ratelimit:l1:cluster"
local app_id = ARGV[1]
local cost = tonumber(ARGV[2])

-- 检查紧急模式
local is_emergency = redis.call('GET', cluster_key .. ':emergency_mode')
if is_emergency ~= 'true' then
    return {1, 'normal_mode'}
end

-- 获取应用优先级
local app_key = "ratelimit:l2:" .. app_id
local priority = tonumber(redis.call('HGET', app_key, 'priority')) or 2

-- 紧急模式策略
-- P0: 允许 100% 配额
-- P1: 允许 50% 配额
-- P2: 允许 10% 配额
-- P3+: 拒绝

local quota_ratio = {
    [0] = 1.0,
    [1] = 0.5,
    [2] = 0.1
}

local allowed_ratio = quota_ratio[priority] or 0

if allowed_ratio == 0 then
    return {0, 'emergency_blocked', priority}
end

-- 检查是否在允许的配额内
local guaranteed = tonumber(redis.call('HGET', app_key, 'guaranteed_quota')) or 0
local emergency_quota = guaranteed * allowed_ratio
local current = tonumber(redis.call('HGET', app_key, 'emergency_used')) or 0

if current + cost > emergency_quota then
    return {0, 'emergency_quota_exceeded', emergency_quota - current}
end

-- 记录紧急模式下的使用
redis.call('HINCRBY', app_key, 'emergency_used', cost)

return {1, 'emergency_allowed', emergency_quota - current - cost}
```


---

## 四、令牌借用机制脚本

### 4.1 借用令牌

```lua
-- scripts/borrow_tokens.lua
-- 从 L1 借用令牌到 L2

local app_id = ARGV[1]
local amount = tonumber(ARGV[2])
local now = tonumber(ARGV[3])

local app_key = "ratelimit:l2:" .. app_id
local cluster_key = "ratelimit:l1:cluster"

-- 检查借用限制
local max_borrow = tonumber(redis.call('HGET', app_key, 'max_borrow')) or 10000
local current_borrowed = tonumber(redis.call('HGET', app_key, 'borrowed')) or 0
local current_debt = tonumber(redis.call('HGET', app_key, 'debt')) or 0

if current_borrowed + amount > max_borrow then
    return {0, 'borrow_limit_exceeded', max_borrow - current_borrowed}
end

-- 检查 L1 可用量
local cluster_available = tonumber(redis.call('GET', cluster_key .. ':available')) or 0
local reserved_ratio = tonumber(redis.call('GET', cluster_key .. ':reserved_ratio')) or 0.1
local cluster_capacity = tonumber(redis.call('GET', cluster_key .. ':capacity')) or 1000000

-- 保留一定比例不可借用
local borrowable = cluster_available - cluster_capacity * reserved_ratio
if borrowable < amount then
    return {0, 'cluster_insufficient', borrowable}
end

-- 执行借用
local interest_rate = 0.2  -- 20% 利息
local debt_amount = math.ceil(amount * (1 + interest_rate))

redis.call('DECRBY', cluster_key .. ':available', amount)
redis.call('HINCRBY', app_key, 'current_tokens', amount)
redis.call('HINCRBY', app_key, 'borrowed', amount)
redis.call('HINCRBY', app_key, 'debt', debt_amount)
redis.call('HSET', app_key, 'last_borrow', now)

-- 记录借用历史
local borrow_record = cjson.encode({
    amount = amount,
    debt = debt_amount,
    timestamp = now
})
redis.call('LPUSH', app_key .. ':borrow_history', borrow_record)
redis.call('LTRIM', app_key .. ':borrow_history', 0, 99)

return {1, 'borrowed', amount, debt_amount}
```

### 4.2 归还令牌

```lua
-- scripts/repay_tokens.lua
-- 归还借用的令牌

local app_id = ARGV[1]
local amount = tonumber(ARGV[2])
local now = tonumber(ARGV[3])

local app_key = "ratelimit:l2:" .. app_id
local cluster_key = "ratelimit:l1:cluster"

-- 获取当前借贷状态
local borrowed = tonumber(redis.call('HGET', app_key, 'borrowed')) or 0
local debt = tonumber(redis.call('HGET', app_key, 'debt')) or 0

if borrowed == 0 then
    return {0, 'no_debt'}
end

-- 计算实际归还量
local repay_amount = math.min(amount, debt)
local principal_ratio = borrowed / debt
local principal_repaid = math.floor(repay_amount * principal_ratio)

-- 执行归还
redis.call('HINCRBY', app_key, 'borrowed', -principal_repaid)
redis.call('HINCRBY', app_key, 'debt', -repay_amount)
redis.call('INCRBY', cluster_key .. ':available', principal_repaid)

-- 记录归还
local repay_record = cjson.encode({
    amount = repay_amount,
    principal = principal_repaid,
    timestamp = now
})
redis.call('LPUSH', app_key .. ':repay_history', repay_record)
redis.call('LTRIM', app_key .. ':repay_history', 0, 99)

local remaining_debt = debt - repay_amount
return {1, 'repaid', repay_amount, remaining_debt}
```

---

## 五、Nginx Lua 模块

### 5.1 主入口模块

```lua
-- nginx/lua/ratelimit/init.lua
local _M = {
    _VERSION = '1.0.0'
}

local cost_calc = require("ratelimit.cost")
local l3_bucket = require("ratelimit.l3_bucket")
local redis_client = require("ratelimit.redis")
local metrics = require("ratelimit.metrics")

-- 初始化
function _M.init()
    -- 初始化共享内存
    local ok, err = l3_bucket.init()
    if not ok then
        ngx.log(ngx.ERR, "Failed to init L3 bucket: ", err)
        return false
    end
    
    -- 初始化 Redis 连接池
    redis_client.init({
        host = os.getenv("REDIS_HOST") or "127.0.0.1",
        port = tonumber(os.getenv("REDIS_PORT")) or 6379,
        pool_size = 50,
        idle_timeout = 60000,
    })
    
    return true
end

-- 请求限流检查
function _M.check(app_id, user_id)
    local method = ngx.req.get_method()
    local content_length = tonumber(ngx.var.content_length) or 0
    
    -- 计算 Cost
    local cost = cost_calc.calculate(method, content_length)
    ngx.ctx.ratelimit_cost = cost
    
    -- L3 本地检查
    local allowed, reason = l3_bucket.acquire(app_id, cost)
    
    -- 记录指标
    metrics.record_request(app_id, method, cost, allowed)
    
    if not allowed then
        -- 返回 429
        ngx.status = 429
        ngx.header["Retry-After"] = reason.retry_after or 1
        ngx.header["X-RateLimit-Remaining"] = reason.remaining or 0
        ngx.say('{"error": "rate_limit_exceeded", "reason": "' .. (reason.code or 'unknown') .. '"}')
        return ngx.exit(429)
    end
    
    -- 设置响应头
    ngx.header["X-RateLimit-Cost"] = cost
    ngx.header["X-RateLimit-Remaining"] = reason.remaining or 0
end

-- 响应阶段处理
function _M.log()
    local cost = ngx.ctx.ratelimit_cost or 0
    local app_id = ngx.ctx.app_id
    
    -- 获取实际响应大小
    local bytes_sent = tonumber(ngx.var.bytes_sent) or 0
    local actual_cost = cost_calc.calculate(ngx.req.get_method(), bytes_sent)
    
    -- 如果实际 Cost 与预估差异大，记录日志
    if actual_cost > cost * 1.5 then
        ngx.log(ngx.WARN, "Cost underestimated: estimated=", cost, " actual=", actual_cost)
        -- 补扣差额
        l3_bucket.adjust(app_id, actual_cost - cost)
    end
    
    -- 触发批量同步检查
    l3_bucket.check_sync(app_id)
end

return _M
```

### 5.2 L3 本地令牌桶模块

```lua
-- nginx/lua/ratelimit/l3_bucket.lua
local _M = {}

local shared = ngx.shared.ratelimit
local redis_client = require("ratelimit.redis")

local CONFIG = {
    RESERVE_TARGET = 1000,
    REFILL_THRESHOLD = 0.2,
    SYNC_INTERVAL = 0.1,
    BATCH_THRESHOLD = 1000,
    FAIL_OPEN_TOKENS = 100,
}

function _M.init()
    -- 初始化共享内存结构
    shared:set("initialized", true)
    return true
end

function _M.acquire(app_id, cost)
    local key_prefix = "app:" .. app_id
    
    -- 获取本地令牌
    local tokens = shared:get(key_prefix .. ":tokens") or 0
    local mode = shared:get("mode") or "normal"
    
    -- Fail-Open 模式
    if mode == "fail_open" then
        local fail_open_used = shared:get(key_prefix .. ":fail_open_used") or 0
        if fail_open_used < CONFIG.FAIL_OPEN_TOKENS then
            shared:incr(key_prefix .. ":fail_open_used", cost)
            return true, {remaining = CONFIG.FAIL_OPEN_TOKENS - fail_open_used - cost, code = "fail_open"}
        else
            return false, {remaining = 0, retry_after = 1, code = "fail_open_exhausted"}
        end
    end
    
    -- 正常模式
    if tokens >= cost then
        shared:incr(key_prefix .. ":tokens", -cost)
        shared:incr(key_prefix .. ":pending_cost", cost)
        shared:incr(key_prefix .. ":pending_count", 1)
        
        local remaining = tokens - cost
        
        -- 检查是否需要补充
        if remaining < CONFIG.RESERVE_TARGET * CONFIG.REFILL_THRESHOLD then
            _M.async_refill(app_id)
        end
        
        return true, {remaining = remaining, code = "local_hit"}
    else
        -- 本地不足，同步获取
        return _M.sync_acquire(app_id, cost)
    end
end

function _M.sync_acquire(app_id, cost)
    local key_prefix = "app:" .. app_id
    
    -- 从 L2 获取令牌
    local fetch_amount = CONFIG.RESERVE_TARGET + cost
    local ok, granted = pcall(function()
        return redis_client.batch_acquire(app_id, fetch_amount)
    end)
    
    if not ok then
        -- Redis 故障，切换到 Fail-Open
        ngx.log(ngx.ERR, "Redis error, switching to fail-open: ", granted)
        shared:set("mode", "fail_open")
        shared:set("fail_open_start", ngx.now())
        return _M.acquire(app_id, cost)  -- 重新尝试
    end
    
    if granted >= cost then
        shared:set(key_prefix .. ":tokens", granted - cost)
        shared:incr(key_prefix .. ":pending_cost", cost)
        shared:incr(key_prefix .. ":pending_count", 1)
        shared:incr(key_prefix .. ":remote_calls", 1)
        return true, {remaining = granted - cost, code = "remote_fetch"}
    else
        -- 配额不足
        return false, {remaining = granted, retry_after = 1, code = "quota_exhausted"}
    end
end

function _M.async_refill(app_id)
    ngx.timer.at(0, function(premature)
        if premature then return end
        
        local key_prefix = "app:" .. app_id
        local current = shared:get(key_prefix .. ":tokens") or 0
        local fetch_amount = CONFIG.RESERVE_TARGET - current
        
        if fetch_amount > 0 then
            local ok, granted = pcall(function()
                return redis_client.batch_acquire(app_id, fetch_amount)
            end)
            
            if ok and granted > 0 then
                shared:incr(key_prefix .. ":tokens", granted)
            end
        end
    end)
end

function _M.check_sync(app_id)
    local key_prefix = "app:" .. app_id
    local pending_count = shared:get(key_prefix .. ":pending_count") or 0
    local last_sync = shared:get(key_prefix .. ":last_sync") or 0
    local now = ngx.now()
    
    local should_sync = pending_count >= CONFIG.BATCH_THRESHOLD or
                        (now - last_sync) >= CONFIG.SYNC_INTERVAL
    
    if should_sync and pending_count > 0 then
        ngx.timer.at(0, function(premature)
            if premature then return end
            _M.do_sync(app_id)
        end)
    end
end

function _M.do_sync(app_id)
    local key_prefix = "app:" .. app_id
    
    -- 原子获取并重置
    local pending_cost = shared:get(key_prefix .. ":pending_cost") or 0
    local pending_count = shared:get(key_prefix .. ":pending_count") or 0
    
    if pending_cost > 0 or pending_count > 0 then
        shared:set(key_prefix .. ":pending_cost", 0)
        shared:set(key_prefix .. ":pending_count", 0)
        shared:set(key_prefix .. ":last_sync", ngx.now())
        
        -- 上报到 L2
        local ok, err = pcall(function()
            redis_client.report_consumption(app_id, pending_cost, pending_count)
        end)
        
        if not ok then
            ngx.log(ngx.ERR, "Failed to sync to L2: ", err)
            -- 恢复待上报数据
            shared:incr(key_prefix .. ":pending_cost", pending_cost)
            shared:incr(key_prefix .. ":pending_count", pending_count)
        end
    end
end

function _M.adjust(app_id, delta)
    local key_prefix = "app:" .. app_id
    shared:incr(key_prefix .. ":pending_cost", delta)
end

return _M
```


### 5.3 Redis 客户端模块

```lua
-- nginx/lua/ratelimit/redis.lua
local _M = {}

local redis = require("resty.redis")
local cjson = require("cjson")

local CONFIG = {
    host = "127.0.0.1",
    port = 6379,
    timeout = 1000,
    pool_size = 50,
    idle_timeout = 60000,
}

-- 预加载的 Lua 脚本 SHA
local SCRIPTS = {}

function _M.init(config)
    CONFIG = setmetatable(config or {}, {__index = CONFIG})
end

local function get_connection()
    local red = redis:new()
    red:set_timeout(CONFIG.timeout)
    
    local ok, err = red:connect(CONFIG.host, CONFIG.port)
    if not ok then
        return nil, err
    end
    
    return red
end

local function release_connection(red)
    if red then
        red:set_keepalive(CONFIG.idle_timeout, CONFIG.pool_size)
    end
end

-- 批量获取令牌
function _M.batch_acquire(app_id, amount)
    local red, err = get_connection()
    if not red then
        error("Redis connection failed: " .. (err or "unknown"))
    end
    
    local script = [[
        local key = KEYS[1]
        local requested = tonumber(ARGV[1])
        local now = tonumber(ARGV[2])
        
        local current = tonumber(redis.call('HGET', key, 'current_tokens')) or 0
        local granted = math.min(current * 0.8, requested)
        granted = math.floor(granted)
        
        if granted > 0 then
            redis.call('HINCRBY', key, 'current_tokens', -granted)
        end
        
        return granted
    ]]
    
    local key = "ratelimit:l2:" .. app_id
    local res, err = red:eval(script, 1, key, amount, ngx.now())
    release_connection(red)
    
    if not res then
        error("Redis eval failed: " .. (err or "unknown"))
    end
    
    return tonumber(res) or 0
end

-- 上报消耗
function _M.report_consumption(app_id, consumed, requests)
    local red, err = get_connection()
    if not red then
        error("Redis connection failed: " .. (err or "unknown"))
    end
    
    local script = [[
        local app_key = KEYS[1]
        local stats_key = KEYS[2]
        local consumed = tonumber(ARGV[1])
        local requests = tonumber(ARGV[2])
        local node_id = ARGV[3]
        local now = tonumber(ARGV[4])
        
        redis.call('HINCRBY', stats_key, 'total_consumed', consumed)
        redis.call('HINCRBY', stats_key, 'total_requests', requests)
        redis.call('HSET', stats_key, 'last_report', now)
        redis.call('HSET', stats_key .. ':node:' .. node_id, 'last_seen', now)
        
        return 1
    ]]
    
    local app_key = "ratelimit:l2:" .. app_id
    local stats_key = "ratelimit:stats:" .. app_id
    local node_id = ngx.var.hostname or "unknown"
    
    local res, err = red:eval(script, 2, app_key, stats_key, consumed, requests, node_id, ngx.now())
    release_connection(red)
    
    if not res then
        error("Redis eval failed: " .. (err or "unknown"))
    end
    
    return true
end

-- 检查紧急模式
function _M.check_emergency()
    local red, err = get_connection()
    if not red then
        return false, err
    end
    
    local res = red:get("ratelimit:l1:cluster:emergency_mode")
    release_connection(red)
    
    return res == "true"
end

-- 订阅配置更新
function _M.subscribe_config(app_id, callback)
    local red, err = get_connection()
    if not red then
        return nil, err
    end
    
    local channel = "ratelimit:config:" .. app_id
    red:subscribe(channel)
    
    while true do
        local res, err = red:read_reply()
        if res then
            if res[1] == "message" then
                local config = cjson.decode(res[3])
                callback(config)
            end
        else
            ngx.log(ngx.ERR, "Subscribe error: ", err)
            break
        end
    end
    
    release_connection(red)
end

return _M
```

---

## 六、定时任务脚本

### 6.1 令牌补充定时器

```lua
-- nginx/lua/ratelimit/timer.lua
local _M = {}

local redis_client = require("ratelimit.redis")

-- 每秒执行一次令牌补充
function _M.start_refill_timer()
    local handler
    handler = function(premature)
        if premature then return end
        
        -- 执行令牌补充
        local ok, err = pcall(function()
            _M.refill_all_apps()
        end)
        
        if not ok then
            ngx.log(ngx.ERR, "Refill timer error: ", err)
        end
        
        -- 重新调度
        ngx.timer.at(1, handler)
    end
    
    ngx.timer.at(1, handler)
end

-- 每 60 秒执行一次对账
function _M.start_reconcile_timer()
    local handler
    handler = function(premature)
        if premature then return end
        
        local ok, err = pcall(function()
            _M.reconcile_all()
        end)
        
        if not ok then
            ngx.log(ngx.ERR, "Reconcile timer error: ", err)
        end
        
        ngx.timer.at(60, handler)
    end
    
    ngx.timer.at(60, handler)
end

-- 每 5 秒检查一次紧急模式
function _M.start_emergency_check_timer()
    local handler
    handler = function(premature)
        if premature then return end
        
        local is_emergency = redis_client.check_emergency()
        local shared = ngx.shared.ratelimit
        
        if is_emergency then
            shared:set("emergency_mode", true)
            ngx.log(ngx.WARN, "Emergency mode detected")
        else
            shared:set("emergency_mode", false)
        end
        
        ngx.timer.at(5, handler)
    end
    
    ngx.timer.at(5, handler)
end

return _M
```
