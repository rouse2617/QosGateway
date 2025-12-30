# Design Document: 分布式三层令牌桶限流系统

## Overview

本设计文档描述基于 OpenResty 的分布式三层令牌桶限流系统的技术架构和实现方案。系统采用 L1(集群层) → L2(应用层) → L3(本地层) 的分层架构，通过 Cost 归一化算法统一处理 IOPS 和带宽约束，实现云存储平台的公平、高效流量控制。

### 设计目标

- **性能**: P99 延迟 <50ms，L3 缓存命中率 >95%
- **可用性**: 系统可用性 >99.9%，支持优雅降级
- **一致性**: Token 漂移 <5%，支持定期对账修正
- **可扩展性**: 支持 50k+ TPS，水平扩展

### 技术栈

- **网关层**: OpenResty (Nginx + LuaJIT)
- **存储层**: Redis Cluster
- **监控**: Prometheus + Grafana
- **语言**: Lua (OpenResty)

## Architecture

### 系统架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        Client Requests                           │
└─────────────────────────────┬───────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────┐
│                    连接限制层 (Connection Limiter)               │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  lua_shared_dict connlimit_dict (10MB)                      ││
│  │  • Per-App 连接计数 (conn:app:{app_id})                     ││
│  │  • Per-Cluster 连接计数 (conn:cluster:{cluster_id})         ││
│  │  • 连接追踪表 (conn:track:{connection_id})                  ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────┬───────────────────────────────────┘
                              │ 连接检查通过
┌─────────────────────────────▼───────────────────────────────────┐
│                    L3: 本地层 (OpenResty)                        │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  lua_shared_dict (100MB)                                    ││
│  │  • 本地令牌缓存 (app:tokens)                                 ││
│  │  • 待同步消耗 (app:pending_cost)                            ││
│  │  • 预留管理 (app:reservations)                              ││
│  └─────────────────────────────────────────────────────────────┘│
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ access_by   │→ │ content_by  │→ │ log_by      │              │
│  │ (限流检查)   │  │ (业务处理)   │  │ (消耗上报)   │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
└─────────────────────────────┬───────────────────────────────────┘
                              │ 批量同步 (100ms / 1000 requests)
┌─────────────────────────────▼───────────────────────────────────┐
│                    L2: 应用层 (Redis)                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │   App A      │  │   App B      │  │   App C      │           │
│  │ guaranteed:  │  │ guaranteed:  │  │ guaranteed:  │           │
│  │   10k/s      │  │   20k/s      │  │   5k/s       │           │
│  │ burst: 50k   │  │ burst: 80k   │  │ burst: 20k   │           │
│  │ priority: P1 │  │ priority: P0 │  │ priority: P2 │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
└─────────────────────────────┬───────────────────────────────────┘
                              │ 配额分配 / 借用
┌─────────────────────────────▼───────────────────────────────────┐
│                    L1: 集群层 (Redis Cluster)                    │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  全局配额管理                                                ││
│  │  • max_capacity: 1,000,000 tokens/s                         ││
│  │  • reserved_ratio: 10%                                      ││
│  │  • emergency_threshold: 95%                                 ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

### 请求处理流程

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│  Client  │────▶│  Nginx   │────▶│ Conn Chk │────▶│ L3 Check │────▶│ Backend  │
└──────────┘     └──────────┘     └────┬─────┘     └────┬─────┘     └──────────┘
                                       │                │
                      ┌────────────────┤                │
                      │                │                │
                      ▼                ▼                ▼
                 ┌─────────┐     ┌─────────┐     ┌─────────┐
                 │ 连接超限 │     │ 连接通过 │     │ 本地充足 │
                 │ 429     │     │ <0.5ms  │     │ <1ms    │
                 └─────────┘     └────┬────┘     └────┬────┘
                                      │               │
                                      ▼               ▼
                                 ┌─────────┐     ┌─────────┐
                                 │ L3 令牌  │     │ 扣减本地 │
                                 │ 检查     │     │ 返回成功 │
                                 └─────────┘     └─────────┘
```

### 请求处理流程（详细）

```
请求到达
   │
   ├─→ [连接限制] ← 检查并发连接数
   │   ├─→ App 连接超限？ → 429 (app_limit_exceeded)
   │   ├─→ Cluster 连接超限？ → 429 (cluster_limit_exceeded)
   │   └─→ 通过 ↓ (记录连接追踪)
   │
   ├─→ [L3 令牌桶] ← 本地令牌检查
   │   ├─→ 通过 ↓
   │   └─→ 不足 → 从 L2 获取
   │
   ├─→ [L2 令牌桶] ← 应用配额
   │   └─→ 通过 ↓
   │
   ├─→ [L1 集群] ← 集群配额
   │   └─→ 通过 ↓
   │
处理请求
   │
   ├─→ [释放连接] ← log_by_lua 阶段
   │
   └─→ [清理定时器] ← 定期清理泄漏连接
```

## Components and Interfaces

### 1. Cost Calculator (成本计算器)

负责将请求转换为统一的 Cost 值。

```lua
-- ratelimit/cost.lua
local _M = {}

local CONFIG = {
    UNIT_QUANTUM = 65536,  -- 64KB
    DEFAULT_C_BW = 1,
    MAX_COST = 1000000,
}

local BASE_COST = {
    GET = 1, HEAD = 1,
    PUT = 5, POST = 5, PATCH = 3,
    DELETE = 2,
    LIST = 3,
    COPY = 6,
    MULTIPART_INIT = 2,
    MULTIPART_UPLOAD = 4,
    MULTIPART_COMPLETE = 8,
    MULTIPART_ABORT = 3,
}

--- 计算请求的 Cost 值
--- @param method string HTTP 方法
--- @param body_size number 请求体大小 (bytes)
--- @param c_bw number 带宽系数 (可选，默认 1)
--- @return number cost 计算得到的 Cost 值
--- @return table details 计算详情
function _M.calculate(method, body_size, c_bw)
    method = string.upper(method or "GET")
    body_size = tonumber(body_size) or 0
    c_bw = tonumber(c_bw) or CONFIG.DEFAULT_C_BW
    
    local c_base = BASE_COST[method] or 1
    local bw_units = 0
    if body_size > 0 then
        bw_units = math.ceil(body_size / CONFIG.UNIT_QUANTUM)
    end
    local c_bandwidth = bw_units * c_bw
    local total_cost = math.min(c_base + c_bandwidth, CONFIG.MAX_COST)
    
    return total_cost, {
        c_base = c_base,
        c_bandwidth = c_bandwidth,
        bw_units = bw_units,
        method = method,
        body_size = body_size
    }
end

return _M
```

### 2. L3 Local Bucket (本地令牌桶)

管理 Nginx 共享内存中的本地令牌缓存。

```lua
-- ratelimit/l3_bucket.lua
local _M = {}

local shared = ngx.shared.ratelimit

local CONFIG = {
    RESERVE_TARGET = 1000,      -- 目标预留量
    REFILL_THRESHOLD = 0.2,     -- 20% 触发补充
    SYNC_INTERVAL = 0.1,        -- 100ms 同步间隔
    BATCH_THRESHOLD = 1000,     -- 1000 次触发同步
    FAIL_OPEN_TOKENS = 100,     -- Fail-Open 模式令牌数
}

--- 获取令牌
--- @param app_id string 应用 ID
--- @param cost number 请求 Cost
--- @return boolean allowed 是否允许
--- @return table reason 原因详情
function _M.acquire(app_id, cost)
    local key_prefix = "app:" .. app_id
    local mode = shared:get("mode") or "normal"
    
    -- Fail-Open 模式处理
    if mode == "fail_open" then
        return _M.handle_fail_open(app_id, cost)
    end
    
    -- 正常模式：检查本地令牌
    local tokens = shared:get(key_prefix .. ":tokens") or 0
    
    if tokens >= cost then
        -- 本地扣减
        shared:incr(key_prefix .. ":tokens", -cost)
        shared:incr(key_prefix .. ":pending_cost", cost)
        shared:incr(key_prefix .. ":pending_count", 1)
        
        local remaining = tokens - cost
        
        -- 检查是否需要异步补充
        if remaining < CONFIG.RESERVE_TARGET * CONFIG.REFILL_THRESHOLD then
            _M.async_refill(app_id)
        end
        
        return true, {remaining = remaining, code = "local_hit"}
    else
        -- 本地不足，同步获取
        return _M.sync_acquire(app_id, cost)
    end
end

--- 令牌回滚（请求取消时）
--- @param app_id string 应用 ID
--- @param cost number 需要回滚的 Cost
--- @return boolean success 是否成功
function _M.rollback(app_id, cost)
    local key_prefix = "app:" .. app_id
    shared:incr(key_prefix .. ":tokens", cost)
    shared:incr(key_prefix .. ":pending_cost", -cost)
    shared:incr(key_prefix .. ":rollback_count", 1)
    return true
end

return _M
```

### 3. L2 Application Bucket (应用层令牌桶)

管理 Redis 中的应用级配额。

```lua
-- ratelimit/l2_bucket.lua
local _M = {}

--- 原子获取令牌的 Redis Lua 脚本
local ACQUIRE_SCRIPT = [[
    local key = KEYS[1]
    local cost = tonumber(ARGV[1])
    local now = tonumber(ARGV[2])
    
    -- 获取配置
    local guaranteed = tonumber(redis.call('HGET', key, 'guaranteed_quota')) or 10000
    local burst = tonumber(redis.call('HGET', key, 'burst_quota')) or 50000
    local current = tonumber(redis.call('HGET', key, 'current_tokens')) or guaranteed
    local last_refill = tonumber(redis.call('HGET', key, 'last_refill')) or now
    
    -- 计算令牌补充
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
        return {1, remaining, burst - remaining}
    else
        redis.call('HSET', key, 'current_tokens', new_tokens)
        redis.call('HSET', key, 'last_refill', now)
        return {0, new_tokens, 0}
    end
]]

--- 批量获取令牌（供 L3 预取）
--- @param app_id string 应用 ID
--- @param amount number 请求数量
--- @return number granted 实际获取数量
function _M.acquire_batch(app_id, amount)
    -- 实现批量获取逻辑
end

return _M
```

### 4. Borrow Manager (借用管理器)

管理令牌借用和归还。

```lua
-- ratelimit/borrow.lua
local _M = {}

local INTEREST_RATE = 0.2  -- 20% 利息

--- 借用令牌的 Redis Lua 脚本
local BORROW_SCRIPT = [[
    local app_key = KEYS[1]
    local cluster_key = KEYS[2]
    local amount = tonumber(ARGV[1])
    local now = tonumber(ARGV[2])
    
    -- 检查借用限制
    local max_borrow = tonumber(redis.call('HGET', app_key, 'max_borrow')) or 10000
    local current_borrowed = tonumber(redis.call('HGET', app_key, 'borrowed')) or 0
    
    if current_borrowed + amount > max_borrow then
        return {0, 'borrow_limit_exceeded', max_borrow - current_borrowed}
    end
    
    -- 检查集群可用量
    local cluster_available = tonumber(redis.call('GET', cluster_key .. ':available')) or 0
    local reserved_ratio = tonumber(redis.call('GET', cluster_key .. ':reserved_ratio')) or 0.1
    local cluster_capacity = tonumber(redis.call('GET', cluster_key .. ':capacity')) or 1000000
    
    local borrowable = cluster_available - cluster_capacity * reserved_ratio
    if borrowable < amount then
        return {0, 'cluster_insufficient', borrowable}
    end
    
    -- 执行借用
    local debt_amount = math.ceil(amount * 1.2)  -- 20% 利息
    redis.call('DECRBY', cluster_key .. ':available', amount)
    redis.call('HINCRBY', app_key, 'current_tokens', amount)
    redis.call('HINCRBY', app_key, 'borrowed', amount)
    redis.call('HINCRBY', app_key, 'debt', debt_amount)
    
    return {1, 'borrowed', amount, debt_amount}
]]

return _M
```

### 5. Emergency Manager (紧急模式管理器)

管理紧急模式的激活和配额分配。

```lua
-- ratelimit/emergency.lua
local _M = {}

-- 优先级配额比例
local PRIORITY_RATIOS = {
    [0] = 1.0,   -- P0: 100%
    [1] = 0.5,   -- P1: 50%
    [2] = 0.1,   -- P2: 10%
    [3] = 0.0,   -- P3+: 0%
}

--- 检查紧急模式下的请求
--- @param app_id string 应用 ID
--- @param cost number 请求 Cost
--- @return boolean allowed 是否允许
--- @return string reason 原因
function _M.check_emergency_request(app_id, cost)
    -- 获取应用优先级
    local priority = _M.get_app_priority(app_id)
    local ratio = PRIORITY_RATIOS[priority] or 0
    
    if ratio == 0 then
        return false, "emergency_blocked"
    end
    
    -- 检查紧急配额
    local emergency_quota = _M.get_emergency_quota(app_id, ratio)
    local used = _M.get_emergency_used(app_id)
    
    if used + cost > emergency_quota then
        return false, "emergency_quota_exceeded"
    end
    
    return true, "emergency_allowed"
end

return _M
```

### 6. Reservation Manager (预留管理器)

管理长时间操作的令牌预留。

```lua
-- ratelimit/reservation.lua
local _M = {}

local shared = ngx.shared.ratelimit
local DEFAULT_TIMEOUT = 3600  -- 1 小时

--- 创建令牌预留
--- @param app_id string 应用 ID
--- @param estimated_cost number 预估 Cost
--- @return string reservation_id 预留 ID
function _M.create(app_id, estimated_cost)
    local reservation_id = ngx.md5(app_id .. ngx.now() .. math.random())
    local key = "reservation:" .. reservation_id
    
    shared:set(key .. ":app_id", app_id)
    shared:set(key .. ":estimated", estimated_cost)
    shared:set(key .. ":actual", 0)
    shared:set(key .. ":created_at", ngx.now())
    shared:set(key .. ":expires_at", ngx.now() + DEFAULT_TIMEOUT)
    
    -- 预扣令牌
    local bucket_key = "app:" .. app_id
    shared:incr(bucket_key .. ":tokens", -estimated_cost)
    shared:incr(bucket_key .. ":reserved", estimated_cost)
    
    return reservation_id
end

--- 完成预留并对账
--- @param reservation_id string 预留 ID
--- @param actual_cost number 实际 Cost
--- @return boolean success 是否成功
--- @return number diff 差额（正数表示退还，负数表示补扣）
function _M.complete(reservation_id, actual_cost)
    local key = "reservation:" .. reservation_id
    local app_id = shared:get(key .. ":app_id")
    local estimated = shared:get(key .. ":estimated") or 0
    
    if not app_id then
        return false, 0
    end
    
    local diff = estimated - actual_cost
    local bucket_key = "app:" .. app_id
    
    -- 对账：退还或补扣
    if diff > 0 then
        shared:incr(bucket_key .. ":tokens", diff)
    elseif diff < 0 then
        shared:incr(bucket_key .. ":tokens", diff)  -- 负数，实际是扣减
    end
    
    shared:incr(bucket_key .. ":reserved", -estimated)
    
    -- 清理预留记录
    shared:delete(key .. ":app_id")
    shared:delete(key .. ":estimated")
    shared:delete(key .. ":actual")
    shared:delete(key .. ":created_at")
    shared:delete(key .. ":expires_at")
    
    return true, diff
end

return _M
```

### 7. Config Validator (配置验证器)

验证配置更新的合法性。

```lua
-- ratelimit/config_validator.lua
local _M = {}

--- 验证应用配置
--- @param config table 配置对象
--- @return boolean valid 是否有效
--- @return table errors 错误列表
function _M.validate_app_config(config)
    local errors = {}
    
    -- 检查必填字段
    if not config.app_id or config.app_id == "" then
        table.insert(errors, "app_id is required")
    end
    
    if not config.guaranteed_quota or config.guaranteed_quota <= 0 then
        table.insert(errors, "guaranteed_quota must be positive")
    end
    
    -- 检查 burst >= guaranteed
    if config.burst_quota and config.burst_quota < config.guaranteed_quota then
        table.insert(errors, "burst_quota must be >= guaranteed_quota")
    end
    
    -- 检查优先级范围
    if config.priority and (config.priority < 0 or config.priority > 3) then
        table.insert(errors, "priority must be 0-3")
    end
    
    return #errors == 0, errors
end

--- 验证集群配额总和
--- @param cluster_capacity number 集群容量
--- @param app_quotas table 应用配额列表
--- @return boolean valid 是否有效
--- @return string error 错误信息
function _M.validate_cluster_capacity(cluster_capacity, app_quotas)
    local total_guaranteed = 0
    for _, quota in ipairs(app_quotas) do
        total_guaranteed = total_guaranteed + (quota.guaranteed_quota or 0)
    end
    
    local max_allowed = cluster_capacity * 0.9
    if total_guaranteed > max_allowed then
        return false, string.format(
            "sum of guaranteed_quotas (%d) exceeds 90%% of cluster_capacity (%d)",
            total_guaranteed, max_allowed
        )
    end
    
    return true, nil
end

return _M
```

### 8. Connection Limiter (连接限制器)

管理并发连接数限制，支持 per-app 和 per-cluster 两个维度。

```lua
-- ratelimit/connection_limiter.lua
local _M = {
    _VERSION = '1.0.0'
}

local shared_dict = ngx.shared.connlimit_dict
local cjson = require("cjson.safe")  -- 使用 safe 版本避免解析异常

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

--- 获取或初始化连接数据（带原子性保证）
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
        
        -- CAS 操作：如果原值未变则更新
        if old_str then
            local current_str = shared_dict:get(key)
            if current_str == old_str then
                shared_dict:set(key, new_str)
                return true, data
            end
            -- 值已变化，重试
        else
            -- 新键，直接设置
            local ok = shared_dict:safe_add(key, new_str)
            if ok then
                return true, data
            end
            -- 其他 worker 已创建，重试
        end
    end
    
    ngx.log(ngx.ERR, "atomic_increment failed after ", CONFIG.RETRY_MAX, " retries for key: ", key)
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
    ngx.log(ngx.WARN, "atomic_decrement failed after retries for key: ", key)
end

--- 生成唯一连接 ID（防止重复）
--- @return string conn_id 连接 ID
local function generate_conn_id()
    local now = ngx.now()
    local random_part = string.format("%08x", math.random(0, 0xFFFFFFFF))
    return string.format("%s:%s:%d:%s",
        ngx.var.server_addr or "unknown",
        ngx.var.connection or "0",
        math.floor(now * 1000000),  -- 微秒精度
        random_part
    )
end

--- 初始化连接限制器
--- @return boolean success 是否成功
--- @return string error 错误信息
function _M.init()
    if not shared_dict then
        return nil, "connlimit_dict not found"
    end
    _M.start_cleanup_timer()
    _M.start_stats_timer()
    ngx.log(ngx.NOTICE, "Connection limiter initialized")
    return true
end

--- 检查并获取连接（带原子性保证）
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

--- 更新连接活跃时间（用于长连接）
function _M.heartbeat()
    local conn_id = ngx.ctx.conn_limit_id
    if not conn_id then return end
    
    local track_key = "conn:track:" .. conn_id
    local track_data_str = shared_dict:get(track_key)
    if not track_data_str then return end
    
    local track_data, err = cjson.decode(track_data_str)
    if not track_data then
        ngx.log(ngx.WARN, "Failed to decode track data for heartbeat: ", err)
        return
    end
    
    if track_data.status == "active" then
        track_data.last_seen = ngx.now()
        shared_dict:set(track_key, cjson.encode(track_data), CONFIG.CONNECTION_TIMEOUT)
    end
end

--- 释放连接（在 log_by_lua 阶段调用）
function _M.release()
    local conn_id = ngx.ctx.conn_limit_id
    local app_id = ngx.ctx.conn_limit_app
    local cluster_id = ngx.ctx.conn_limit_cluster
    
    if not conn_id then return end
    
    local track_key = "conn:track:" .. conn_id
    local track_data_str = shared_dict:get(track_key)
    
    if not track_data_str then
        ngx.log(ngx.WARN, "Connection tracking not found for release: ", conn_id)
        return
    end
    
    local track_data, err = cjson.decode(track_data_str)
    if not track_data then
        ngx.log(ngx.WARN, "Failed to decode track data for release: ", err)
        return
    end
    
    -- 幂等性检查：防止重复释放
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

--- 强制释放连接（用于泄漏清理）
--- @param track_key string 追踪键
--- @param track_data table 追踪数据
local function force_release_connection(track_key, track_data)
    -- 记录泄漏日志
    ngx.log(ngx.WARN, string.format(
        "Force releasing leaked connection: id=%s, app=%s, cluster=%s, age=%.2fs, ip=%s",
        track_key,
        track_data.app_id,
        track_data.cluster_id,
        ngx.now() - track_data.last_seen,
        track_data.client_ip or "unknown"
    ))
    
    -- 原子递减计数
    atomic_decrement("conn:app:" .. track_data.app_id)
    atomic_decrement("conn:cluster:" .. track_data.cluster_id)
    
    -- 标记为强制释放
    track_data.status = "force_released"
    track_data.released_at = ngx.now()
    track_data.leaked = true
    shared_dict:set(track_key, cjson.encode(track_data), CONFIG.TRACK_RETENTION)
end

--- 清理泄漏连接（优化版：限制扫描数量）
--- @return number leaked_count 泄漏连接数
function _M.cleanup_leaked_connections()
    local now = ngx.now()
    local leaked_count = 0
    
    -- 限制每次扫描的键数量，避免阻塞
    local keys = shared_dict:get_keys(CONFIG.MAX_CLEANUP_KEYS)
    
    for _, key in ipairs(keys) do
        if string.match(key, "^conn:track:") then
            local track_data_str = shared_dict:get(key)
            if track_data_str then
                local track_data, err = cjson.decode(track_data_str)
                if track_data then
                    if track_data.status == "active" then
                        local age = now - track_data.last_seen
                        if age > CONFIG.CONNECTION_TIMEOUT then
                            leaked_count = leaked_count + 1
                            force_release_connection(key, track_data)
                        end
                    end
                else
                    ngx.log(ngx.WARN, "Failed to decode track data during cleanup: ", err)
                    -- 删除损坏的记录
                    shared_dict:delete(key)
                end
            end
        end
    end
    
    shared_dict:set("conn:cleanup:last_run", now)
    if leaked_count > 0 then
        shared_dict:incr("conn:leaked:total", leaked_count, 0)
        ngx.log(ngx.NOTICE, "Connection cleanup completed: leaked=", leaked_count)
    end
    
    return leaked_count
end

--- 记录拒绝事件
--- @param app_id string 应用 ID
--- @param cluster_id string 集群 ID
--- @param reason string 拒绝原因
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
        
        local ok, err = pcall(_M.cleanup_leaked_connections)
        if not ok then
            ngx.log(ngx.ERR, "Cleanup timer error: ", err)
        end
        
        -- 重新调度
        local ok2, err2 = ngx.timer.at(CONFIG.CLEANUP_INTERVAL, handler)
        if not ok2 then
            ngx.log(ngx.ERR, "Failed to reschedule cleanup timer: ", err2)
        end
    end
    
    local ok, err = ngx.timer.at(CONFIG.CLEANUP_INTERVAL, handler)
    if not ok then
        ngx.log(ngx.ERR, "Failed to start cleanup timer: ", err)
    end
end

--- 启动统计上报定时器
function _M.start_stats_timer()
    local interval = 10  -- 每10秒上报一次
    
    local handler
    handler = function(premature)
        if premature then return end
        
        local ok, err = pcall(_M.report_stats_to_redis)
        if not ok then
            ngx.log(ngx.ERR, "Stats report error: ", err)
        end
        
        ngx.timer.at(interval, handler)
    end
    
    ngx.timer.at(interval, handler)
end

--- 上报统计到 Redis
function _M.report_stats_to_redis()
    -- 实现统计上报逻辑
end

--- 获取统计信息
--- @param app_id string 应用 ID
--- @param cluster_id string 集群 ID
--- @return table stats 统计信息
function _M.get_stats(app_id, cluster_id)
    local app_key = "conn:app:" .. app_id
    local cluster_key = "conn:cluster:" .. cluster_id
    
    local app_data_str = shared_dict:get(app_key)
    local cluster_data_str = shared_dict:get(cluster_key)
    
    local app_data = nil
    local cluster_data = nil
    
    if app_data_str then
        app_data = cjson.decode(app_data_str)
    end
    if cluster_data_str then
        cluster_data = cjson.decode(cluster_data_str)
    end
    
    return {
        app = app_data or {},
        cluster = cluster_data or {},
        global = {
            total_rejected = shared_dict:get("conn:rejected:total") or 0,
            total_leaked = shared_dict:get("conn:leaked:total") or 0,
            last_cleanup = shared_dict:get("conn:cleanup:last_run") or 0
        }
    }
end

--- 设置响应头
function _M.set_response_headers(result)
    if result then
        ngx.header["X-Connection-Limit"] = result.limit or ""
        ngx.header["X-Connection-Current"] = result.current or ""
        ngx.header["X-Connection-Remaining"] = result.app_remaining or ""
    end
end

return _M
```

### 降级策略

连接限制器支持以下降级策略：

```lua
-- 降级级别定义
local CONN_DEGRADATION_LEVELS = {
    [0] = {  -- 正常
        name = "normal",
        cleanup_interval = 30,
        max_cleanup_keys = 1000,
    },
    [1] = {  -- 轻微降级
        name = "mild",
        cleanup_interval = 60,      -- 降低清理频率
        max_cleanup_keys = 500,
    },
    [2] = {  -- 显著降级
        name = "significant",
        cleanup_interval = 120,
        max_cleanup_keys = 200,
    },
    [3] = {  -- 完全降级 (Fail-Open)
        name = "fail_open",
        cleanup_interval = nil,     -- 停止清理
        max_cleanup_keys = 0,
        -- Fail-Open: 允许所有连接但不追踪
    },
}
```

## Data Models

### Redis 数据结构

#### L1 集群层

```
# 集群配置
ratelimit:l1:cluster
├── capacity: 1000000          # 总容量
├── available: 850000          # 可用量
├── reserved_ratio: 0.1        # 预留比例
├── emergency_mode: false      # 紧急模式
├── emergency_reason: ""       # 紧急原因
└── emergency_start: 0         # 紧急开始时间

# 应用配额分配
ratelimit:l1:cluster:apps (Sorted Set)
├── app-a: 10000
├── app-b: 20000
└── app-c: 5000
```

#### L2 应用层

```
# 应用配置 (Hash)
ratelimit:l2:{app_id}
├── guaranteed_quota: 20000    # 保底配额
├── burst_quota: 80000         # 突发上限
├── current_tokens: 45000      # 当前令牌
├── priority: 0                # 优先级
├── max_borrow: 10000          # 最大借用
├── borrowed: 0                # 已借用
├── debt: 0                    # 债务
├── last_refill: 1704067200    # 上次补充时间
├── total_consumed: 0          # 总消耗
└── total_requests: 0          # 总请求数

# 应用统计 (Hash)
ratelimit:stats:{app_id}
├── total_consumed: 0
├── total_requests: 0
├── last_report: 0
├── last_reconcile: 0
└── correction_count: 0
```

#### L3 本地层 (Nginx shared_dict)

```
# 应用本地缓存
app:{app_id}:tokens            # 本地令牌数
app:{app_id}:pending_cost      # 待同步消耗
app:{app_id}:pending_count     # 待同步请求数
app:{app_id}:last_sync         # 上次同步时间
app:{app_id}:reserved          # 预留令牌
app:{app_id}:rollback_count    # 回滚次数

# 预留记录
reservation:{id}:app_id        # 所属应用
reservation:{id}:estimated     # 预估 Cost
reservation:{id}:actual        # 实际 Cost
reservation:{id}:created_at    # 创建时间
reservation:{id}:expires_at    # 过期时间

# 全局状态
mode                           # normal / fail_open
emergency_mode                 # true / false
fail_open_start                # Fail-Open 开始时间
```

#### 连接限制层 (Nginx shared_dict connlimit_dict)

```
# Per-App 连接计数 (JSON)
conn:app:{app_id}
├── current: 100               # 当前连接数
├── limit: 1000                # 限制值
├── rejected: 5                # 拒绝次数
├── peak: 150                  # 峰值连接数
└── last_update: 1704067200.123

# Per-Cluster 连接计数 (JSON)
conn:cluster:{cluster_id}
├── current: 500               # 当前连接数
├── limit: 5000                # 限制值
├── rejected: 20               # 拒绝次数
├── peak: 600                  # 峰值连接数
└── last_update: 1704067200.123

# 连接追踪表 (JSON, TTL=300s)
conn:track:{connection_id}
├── app_id: "my-app"           # 所属应用
├── cluster_id: "cluster-01"   # 所属集群
├── created_at: 1704067200.123 # 创建时间
├── last_seen: 1704067200.123  # 最后活跃时间
├── client_ip: "192.168.1.100" # 客户端 IP
├── status: "active"           # 状态: active / released / force_released
├── released_at: null          # 释放时间
└── duration: null             # 连接持续时间

# 全局统计
conn:rejected:total            # 总拒绝次数
conn:leaked:total              # 总泄漏次数
conn:cleanup:last_run          # 上次清理时间
```

#### 连接限制 Redis 数据结构

```
# 应用连接配置 (Hash)
connlimit:config:{app_id}
├── max_connections: 1000      # 最大连接数
├── burst_connections: 1200    # 突发连接数
├── priority: 0                # 优先级
└── enabled: true              # 是否启用

# 集群连接配置 (Hash)
connlimit:cluster:{cluster_id}
├── max_connections: 5000      # 最大连接数
└── reserved_ratio: 0.1        # 预留比例

# 应用连接统计 (Hash)
connlimit:stats:{app_id}
├── current_connections: 100   # 当前连接数
├── peak_connections: 150      # 峰值连接数
├── total_rejected: 50         # 总拒绝次数
└── last_report: 1704067200    # 上次上报时间

# 节点连接统计 (Hash, TTL=300s)
connlimit:stats:{app_id}:node:{node_id}
├── current: 50                # 当前连接数
├── peak: 80                   # 峰值连接数
└── last_seen: 1704067200      # 最后上报时间

# 连接事件日志 (List, 最近 1000 条)
connlimit:events:{app_id}
└── [{"type":"rejected","ip":"1.2.3.4","timestamp":1704067200}, ...]
```



## Error Handling

### 错误类型与处理策略

| 错误类型 | 错误码 | 处理策略 |
|---------|--------|---------|
| 本地令牌不足 | `local_exhausted` | 同步从 L2 获取 |
| L2 配额不足 | `app_exhausted` | 尝试借用或拒绝 |
| L1 集群耗尽 | `cluster_exhausted` | 返回 429 |
| Redis 超时 | `redis_timeout` | 切换 Fail-Open |
| Redis 连接失败 | `redis_connection_failed` | 切换 Fail-Open |
| 紧急模式阻止 | `emergency_blocked` | 返回 429 |
| 借用限制超出 | `borrow_limit_exceeded` | 返回 429 |
| 配置验证失败 | `config_validation_failed` | 返回 400 |
| App 连接超限 | `app_limit_exceeded` | 返回 429 |
| Cluster 连接超限 | `cluster_limit_exceeded` | 返回 429 |
| 连接泄漏检测 | `connection_leaked` | 强制释放并记录 |

### 降级策略

```lua
-- 降级级别定义
local DEGRADATION_LEVELS = {
    [0] = {  -- 正常
        name = "normal",
        l3_reserve = 1000,
        sync_interval = 0.1,
    },
    [1] = {  -- 轻微降级 (Redis 延迟 10-100ms)
        name = "mild",
        l3_reserve = 2000,      -- 增加本地缓存
        sync_interval = 0.5,    -- 降低同步频率
    },
    [2] = {  -- 显著降级 (Redis 延迟 >100ms)
        name = "significant",
        l3_reserve = 5000,
        sync_interval = 1.0,
    },
    [3] = {  -- 完全降级 (Redis 不可用)
        name = "fail_open",
        l3_reserve = 100,       -- Fail-Open 限制
        sync_interval = nil,    -- 停止同步
    },
}
```

### HTTP 响应格式

```lua
-- 429 Too Many Requests
{
    "error": "rate_limit_exceeded",
    "reason": "app_exhausted",
    "retry_after": 1,
    "remaining": 0,
    "cost": 17
}

-- 响应头
X-RateLimit-Cost: 17
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1704067260
Retry-After: 1
```

## Testing Strategy

### 测试框架

- **单元测试**: busted (Lua 测试框架)
- **属性测试**: lua-quickcheck (属性基测试)
- **集成测试**: Test::Nginx (OpenResty 集成测试)
- **性能测试**: wrk / vegeta

### 测试分层

1. **单元测试**: 测试各模块的独立功能
   - Cost 计算正确性
   - 配置验证逻辑
   - 令牌桶算法

2. **属性测试**: 验证系统不变量
   - Cost 计算的确定性
   - 令牌操作的原子性
   - 借用/归还的一致性

3. **集成测试**: 测试模块间交互
   - L3 → L2 同步
   - 紧急模式切换
   - 降级恢复

4. **端到端测试**: 测试完整流程
   - 请求限流流程
   - 配置热更新
   - 故障恢复



## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Cost Calculation Correctness

*For any* valid HTTP method and body size, the Cost Calculator SHALL compute cost using the formula `Cost = C_base + ceil(body_size / 65536) × C_bw`, and the result SHALL never exceed 1,000,000.

**Validates: Requirements 1.1, 1.7**

### Property 2: Token Deduction Consistency

*For any* token deduction operation where local tokens are sufficient, the L3 bucket SHALL reduce tokens by exactly the cost amount, and the pending_consumption counter SHALL increase by the same amount.

**Validates: Requirements 2.3, 2.7**

### Property 3: Token Refill Correctness

*For any* L2 bucket with guaranteed_quota G and elapsed time T since last refill, the refill amount SHALL equal `min(burst_quota, current_tokens + T × G)`.

**Validates: Requirements 3.4, 3.5**

### Property 4: Burst Quota Invariant

*For any* application bucket, the current_tokens SHALL never exceed the configured burst_quota.

**Validates: Requirements 3.5**

### Property 5: Borrowing Correctness

*For any* borrow operation of amount A, the debt SHALL equal `ceil(A × 1.2)`, the borrowed amount SHALL not exceed max_borrow, and borrowing SHALL be rejected if cluster available is below reserved ratio.

**Validates: Requirements 5.2, 5.3, 5.7**

### Property 6: Emergency Mode Quota Ratios

*For any* application with priority P during emergency mode, the allowed quota ratio SHALL be: P0=100%, P1=50%, P2=10%, P3+=0%.

**Validates: Requirements 4.6, 6.3, 6.4**

### Property 7: Global Reconciliation Invariant

*For any* reconciliation operation, after completion the sum of all L2 application tokens plus borrowed amounts SHALL equal the L1 cluster capacity minus available.

**Validates: Requirements 7.2, 7.3**

### Property 8: Token Rollback Correctness

*For any* request cancellation, the pre-deducted tokens SHALL be returned to the L3 bucket, restoring the token count to its pre-deduction value.

**Validates: Requirements 13.1**

### Property 9: Reservation Round-Trip

*For any* reservation with estimated_cost E and actual_cost A, completing the reservation SHALL adjust tokens by (E - A): returning excess if E > A, or deducting shortfall if A > E.

**Validates: Requirements 14.3, 14.4, 14.5**

### Property 10: Local Tokens Non-Negative Invariant

*For any* L3 local bucket, the token count SHALL never go negative.

**Validates: Requirements 15.4**

### Property 11: Config Validation Correctness

*For any* configuration update, the validator SHALL reject configs where: sum(guaranteed_quotas) > cluster_capacity × 0.9, OR burst_quota < guaranteed_quota, OR priority is outside range [0, 3].

**Validates: Requirements 16.2, 16.3, 16.4**

### Property 12: Refill Threshold Trigger

*For any* L3 bucket where tokens fall below 20% of reserve target after deduction, an async refill from L2 SHALL be triggered.

**Validates: Requirements 2.4**

### Property 13: Repayment Order

*For any* repayment operation, the repayment SHALL be applied to debt first, reducing both debt and borrowed amounts proportionally.

**Validates: Requirements 5.5**

### Property 14: Drift Tolerance Correction

*For any* reconciliation where token drift exceeds 10% tolerance, the Reconciler SHALL correct the tokens to the expected value.

**Validates: Requirements 7.2, 15.5, 15.6**

### Property 15: Connection Acquire-Release Consistency

*For any* successful connection acquire operation, the connection counter SHALL increase by exactly 1, and upon release (normal or forced), the counter SHALL decrease by exactly 1.

**Validates: Connection Limiter Requirements**

### Property 16: Connection Limit Enforcement

*For any* connection acquire request where current connections >= limit, the Connection Limiter SHALL reject the request and increment the rejected counter.

**Validates: Connection Limiter Requirements**

### Property 17: Connection Counter Non-Negative Invariant

*For any* connection counter (per-app or per-cluster), the current value SHALL never go negative.

**Validates: Connection Limiter Requirements**

### Property 18: Connection Leak Detection Correctness

*For any* tracked connection where (now - last_seen) > CONNECTION_TIMEOUT and status == "active", the cleanup process SHALL force-release the connection and increment the leaked counter.

**Validates: Connection Limiter Requirements**

### Property 19: Connection Peak Tracking

*For any* connection acquire operation, if the new current count exceeds the recorded peak, the peak SHALL be updated to the new current count.

**Validates: Connection Limiter Requirements**

### Property 20: Connection Release Idempotency

*For any* connection release operation on a connection with status == "released", the operation SHALL be a no-op and SHALL NOT decrement the connection counter.

**Validates: Connection Limiter Requirements**


## Admin Console Architecture

### 技术栈

- **后端**: Go (Gin/Echo framework)
- **前端**: Vue 3 + TypeScript + Vite
- **UI 组件库**: Element Plus / Naive UI
- **图表库**: ECharts
- **状态管理**: Pinia
- **HTTP 客户端**: Axios

### 系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    Admin Console Architecture                    │
│                    Token 管理平台 (Token Management Platform)    │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Frontend (Vue 3 + TypeScript + Vite)                      │  │
│  │  • Dashboard 仪表盘                                        │  │
│  │  • Application 管理                                        │  │
│  │  • Cluster 配置                                            │  │
│  │  • Connection Limit 配置                                   │  │
│  │  • Emergency Mode 控制                                     │  │
│  │  • Real-time Metrics 图表 (ECharts)                        │  │
│  │  • UI: Element Plus / Naive UI                             │  │
│  │  • State: Pinia                                            │  │
│  └───────────────────┬───────────────────────────────────────┘  │
│                      │ HTTP/WebSocket                            │
│  ┌───────────────────▼───────────────────────────────────────┐  │
│  │  Backend API (Go - Gin/Echo)                               │  │
│  │  • RESTful API (/api/v1/*)                                 │  │
│  │  • WebSocket (real-time metrics)                           │  │
│  │  • JWT Authentication (golang-jwt)                         │  │
│  │  • Rate Limiting Middleware                                │  │
│  │  • Audit Logging                                           │  │
│  │  • Redis Client (go-redis)                                 │  │
│  └───────────────────┬───────────────────────────────────────┘  │
│                      │                                           │
│  ┌───────────────────▼───────────────────────────────────────┐  │
│  │  Data Layer                                                │  │
│  │  • Redis (配置存储、实时指标)                              │  │
│  │  • Prometheus (历史指标)                                   │  │
│  │  • PostgreSQL (用户、审计日志) [可选]                      │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### 9. Admin Backend API (Go)

管理控制台后端 API 服务，使用 Go 语言和 Gin 框架实现。

```go
// admin/main.go
package main

import (
    "context"
    "log"
    "net/http"
    "time"

    "github.com/gin-gonic/gin"
    "github.com/go-redis/redis/v8"
    "github.com/golang-jwt/jwt/v5"
    "github.com/gorilla/websocket"
)

// Config 配置结构
type Config struct {
    RedisAddr   string
    JWTSecret   string
    ServerPort  string
}

// App 应用配置结构
type App struct {
    AppID           string `json:"app_id" binding:"required"`
    GuaranteedQuota int64  `json:"guaranteed_quota" binding:"required,gt=0"`
    BurstQuota      int64  `json:"burst_quota" binding:"required"`
    Priority        int    `json:"priority" binding:"min=0,max=3"`
    MaxConnections  int64  `json:"max_connections"`
    Enabled         bool   `json:"enabled"`
}

// Server API 服务器
type Server struct {
    router      *gin.Engine
    redisClient *redis.Client
    config      *Config
}

// NewServer 创建服务器实例
func NewServer(cfg *Config) *Server {
    rdb := redis.NewClient(&redis.Options{
        Addr: cfg.RedisAddr,
    })

    s := &Server{
        router:      gin.Default(),
        redisClient: rdb,
        config:      cfg,
    }
    s.setupRoutes()
    return s
}

// setupRoutes 设置路由
func (s *Server) setupRoutes() {
    // 中间件
    s.router.Use(gin.Recovery())
    s.router.Use(CORSMiddleware())

    // 公开端点
    s.router.GET("/health", s.HealthCheck)

    // API v1 路由组
    v1 := s.router.Group("/api/v1")
    v1.Use(s.AuthMiddleware())
    {
        // 应用管理
        v1.GET("/apps", s.ListApps)
        v1.POST("/apps", s.CreateApp)
        v1.GET("/apps/:id", s.GetApp)
        v1.PUT("/apps/:id", s.UpdateApp)
        v1.DELETE("/apps/:id", s.DeleteApp)

        // 集群管理
        v1.GET("/clusters", s.ListClusters)
        v1.PUT("/clusters/:id", s.UpdateCluster)

        // 连接限制管理
        v1.GET("/connections", s.ListConnectionLimits)
        v1.PUT("/connections/:app_id", s.UpdateConnectionLimit)

        // 紧急模式
        v1.GET("/emergency", s.GetEmergencyStatus)
        v1.POST("/emergency/activate", s.ActivateEmergency)
        v1.POST("/emergency/deactivate", s.DeactivateEmergency)

        // 实时指标
        v1.GET("/metrics", s.GetMetrics)
        v1.GET("/metrics/apps/:id", s.GetAppMetrics)
        v1.GET("/metrics/connections", s.GetConnectionMetrics)

        // WebSocket 实时推送
        v1.GET("/ws", s.WebSocketHandler)
    }
}

// AuthMiddleware JWT 认证中间件
func (s *Server) AuthMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        authHeader := c.GetHeader("Authorization")
        if authHeader == "" {
            c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
            c.Abort()
            return
        }

        tokenString := authHeader[7:] // 移除 "Bearer " 前缀
        token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
            return []byte(s.config.JWTSecret), nil
        })

        if err != nil || !token.Valid {
            c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid_token"})
            c.Abort()
            return
        }

        claims := token.Claims.(jwt.MapClaims)
        c.Set("user_id", claims["sub"])
        c.Next()
    }
}

// ListApps 获取应用列表
func (s *Server) ListApps(c *gin.Context) {
    ctx := context.Background()
    
    // 从 Redis 获取所有应用配置
    keys, err := s.redisClient.Keys(ctx, "ratelimit:l2:*").Result()
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }

    apps := make([]map[string]interface{}, 0)
    for _, key := range keys {
        data, err := s.redisClient.HGetAll(ctx, key).Result()
        if err == nil {
            apps = append(apps, map[string]interface{}{
                "app_id": key[13:], // 移除 "ratelimit:l2:" 前缀
                "config": data,
            })
        }
    }

    c.JSON(http.StatusOK, gin.H{
        "data":  apps,
        "total": len(apps),
    })
}

// CreateApp 创建应用
func (s *Server) CreateApp(c *gin.Context) {
    var app App
    if err := c.ShouldBindJSON(&app); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "validation_failed", "details": err.Error()})
        return
    }

    // 验证配置
    if err := s.validateAppConfig(&app); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "validation_failed", "details": err.Error()})
        return
    }

    ctx := context.Background()
    key := "ratelimit:l2:" + app.AppID

    // 保存到 Redis
    err := s.redisClient.HSet(ctx, key,
        "guaranteed_quota", app.GuaranteedQuota,
        "burst_quota", app.BurstQuota,
        "priority", app.Priority,
        "max_connections", app.MaxConnections,
        "enabled", app.Enabled,
    ).Err()

    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "save_failed", "message": err.Error()})
        return
    }

    // 发布配置更新事件
    s.redisClient.Publish(ctx, "ratelimit:config:update", app.AppID)

    // 记录审计日志
    s.auditLog(c, "create_app", app)

    c.JSON(http.StatusCreated, gin.H{"data": app})
}

// GetMetrics 获取实时指标
func (s *Server) GetMetrics(c *gin.Context) {
    ctx := context.Background()
    timeRange := c.DefaultQuery("range", "1h")

    // 获取 L1 可用量
    l1Available, _ := s.redisClient.Get(ctx, "ratelimit:l1:cluster:available").Int64()
    
    // 获取紧急模式状态
    emergencyMode, _ := s.redisClient.Get(ctx, "ratelimit:l1:cluster:emergency_mode").Result()

    // 获取 Redis 延迟
    start := time.Now()
    s.redisClient.Ping(ctx)
    redisLatency := time.Since(start).Milliseconds()

    c.JSON(http.StatusOK, gin.H{
        "l1_available":       l1Available,
        "emergency_mode":     emergencyMode == "true",
        "redis_latency_ms":   redisLatency,
        "time_range":         timeRange,
        "timestamp":          time.Now().Unix(),
    })
}

// ActivateEmergency 激活紧急模式
func (s *Server) ActivateEmergency(c *gin.Context) {
    var req struct {
        Reason   string `json:"reason"`
        Duration int    `json:"duration"`
    }
    
    if err := c.ShouldBindJSON(&req); err != nil {
        req.Reason = "manual_activation"
        req.Duration = 300
    }

    ctx := context.Background()
    key := "ratelimit:l1:cluster"

    pipe := s.redisClient.Pipeline()
    pipe.HSet(ctx, key, "emergency_mode", true)
    pipe.HSet(ctx, key, "emergency_reason", req.Reason)
    pipe.HSet(ctx, key, "emergency_start", time.Now().Unix())
    pipe.HSet(ctx, key, "emergency_duration", req.Duration)
    _, err := pipe.Exec(ctx)

    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "activation_failed", "message": err.Error()})
        return
    }

    // 发布紧急模式事件
    s.redisClient.Publish(ctx, "ratelimit:emergency", "activated")

    s.auditLog(c, "activate_emergency", req)

    c.JSON(http.StatusOK, gin.H{"message": "emergency_mode_activated"})
}

// WebSocketHandler WebSocket 实时推送
func (s *Server) WebSocketHandler(c *gin.Context) {
    upgrader := websocket.Upgrader{
        CheckOrigin: func(r *http.Request) bool { return true },
    }

    conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
    if err != nil {
        return
    }
    defer conn.Close()

    ticker := time.NewTicker(5 * time.Second)
    defer ticker.Stop()

    for range ticker.C {
        metrics := s.collectRealtimeMetrics()
        if err := conn.WriteJSON(metrics); err != nil {
            break
        }
    }
}

// validateAppConfig 验证应用配置
func (s *Server) validateAppConfig(app *App) error {
    if app.BurstQuota < app.GuaranteedQuota {
        return fmt.Errorf("burst_quota must be >= guaranteed_quota")
    }
    return nil
}

// auditLog 记录审计日志
func (s *Server) auditLog(c *gin.Context, action string, details interface{}) {
    userID, _ := c.Get("user_id")
    log.Printf("AUDIT: user=%v action=%s details=%+v ip=%s",
        userID, action, details, c.ClientIP())
}

// collectRealtimeMetrics 收集实时指标
func (s *Server) collectRealtimeMetrics() map[string]interface{} {
    ctx := context.Background()
    l1Available, _ := s.redisClient.Get(ctx, "ratelimit:l1:cluster:available").Int64()
    
    return map[string]interface{}{
        "type":         "metrics",
        "l1_available": l1Available,
        "timestamp":    time.Now().Unix(),
    }
}

// CORSMiddleware CORS 中间件
func CORSMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        c.Header("Access-Control-Allow-Origin", "*")
        c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        c.Header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        if c.Request.Method == "OPTIONS" {
            c.AbortWithStatus(204)
            return
        }
        c.Next()
    }
}

func main() {
    cfg := &Config{
        RedisAddr:  "localhost:6379",
        JWTSecret:  "your-secret-key",
        ServerPort: ":8080",
    }

    server := NewServer(cfg)
    log.Printf("Admin API server starting on %s", cfg.ServerPort)
    server.router.Run(cfg.ServerPort)
}
```

### 10. Admin Frontend Components (Vue 3 + TypeScript)

前端组件设计，使用 Vue 3 + TypeScript + Vite 构建。

```
admin-frontend/
├── package.json
├── vite.config.ts
├── tsconfig.json
├── index.html
├── src/
│   ├── main.ts                        # 入口文件
│   ├── App.vue                        # 根组件
│   ├── components/
│   │   ├── Dashboard/
│   │   │   ├── OverviewCard.vue       # 概览卡片
│   │   │   ├── MetricsChart.vue       # 指标图表 (ECharts)
│   │   │   ├── TopAppsTable.vue       # Top 应用表格
│   │   │   ├── TokenFlowChart.vue     # L1/L2/L3 令牌流动图
│   │   │   └── AlertPanel.vue         # 告警面板
│   │   ├── Apps/
│   │   │   ├── AppList.vue            # 应用列表
│   │   │   ├── AppForm.vue            # 应用表单
│   │   │   ├── AppDetail.vue          # 应用详情
│   │   │   └── QuotaEditor.vue        # 配额编辑器
│   │   ├── Connections/
│   │   │   ├── ConnectionList.vue     # 连接限制列表
│   │   │   ├── ConnectionForm.vue     # 连接限制表单
│   │   │   └── ConnectionStats.vue    # 连接统计
│   │   ├── Emergency/
│   │   │   ├── EmergencyPanel.vue     # 紧急模式面板
│   │   │   └── EmergencyHistory.vue   # 紧急模式历史
│   │   └── Common/
│   │       ├── AppHeader.vue          # 页头
│   │       ├── AppSidebar.vue         # 侧边栏
│   │       └── ConfirmDialog.vue      # 确认对话框
│   ├── views/
│   │   ├── DashboardView.vue          # 仪表盘页面
│   │   ├── AppsView.vue               # 应用管理页面
│   │   ├── ClustersView.vue           # 集群配置页面
│   │   ├── ConnectionsView.vue        # 连接限制页面
│   │   ├── EmergencyView.vue          # 紧急模式页面
│   │   └── SettingsView.vue           # 系统设置页面
│   ├── stores/                        # Pinia 状态管理
│   │   ├── auth.ts                    # 认证状态
│   │   ├── apps.ts                    # 应用状态
│   │   ├── metrics.ts                 # 指标状态
│   │   └── websocket.ts               # WebSocket 连接
│   ├── api/                           # API 层 (Axios)
│   │   ├── client.ts                  # API 客户端配置
│   │   ├── apps.ts                    # 应用 API
│   │   ├── metrics.ts                 # 指标 API
│   │   └── emergency.ts               # 紧急模式 API
│   ├── types/                         # TypeScript 类型定义
│   │   ├── app.ts                     # 应用类型
│   │   ├── metrics.ts                 # 指标类型
│   │   └── api.ts                     # API 响应类型
│   ├── composables/                   # Vue 3 组合式函数
│   │   ├── useWebSocket.ts            # WebSocket 连接
│   │   ├── useMetrics.ts              # 指标数据
│   │   └── useAuth.ts                 # 认证逻辑
│   └── router/
│       └── index.ts                   # Vue Router 配置
```

#### 前端技术栈详情

```json
// package.json (关键依赖)
{
  "name": "ratelimit-admin",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vue-tsc && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "vue": "^3.4.0",
    "vue-router": "^4.2.0",
    "pinia": "^2.1.0",
    "axios": "^1.6.0",
    "echarts": "^5.4.0",
    "element-plus": "^2.4.0",
    "@element-plus/icons-vue": "^2.3.0"
  },
  "devDependencies": {
    "@vitejs/plugin-vue": "^4.5.0",
    "typescript": "^5.3.0",
    "vite": "^5.0.0",
    "vue-tsc": "^1.8.0"
  }
}
```

#### 核心组件示例

```vue
<!-- src/views/DashboardView.vue -->
<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useMetricsStore } from '@/stores/metrics'
import { useWebSocket } from '@/composables/useWebSocket'
import OverviewCard from '@/components/Dashboard/OverviewCard.vue'
import MetricsChart from '@/components/Dashboard/MetricsChart.vue'
import TopAppsTable from '@/components/Dashboard/TopAppsTable.vue'
import AlertPanel from '@/components/Dashboard/AlertPanel.vue'

const metricsStore = useMetricsStore()
const { connect, disconnect } = useWebSocket()

const timeRange = ref<'1h' | '6h' | '24h' | '7d'>('1h')
const autoRefresh = ref(true)

onMounted(async () => {
  await metricsStore.fetchMetrics(timeRange.value)
  connect()
})

onUnmounted(() => {
  disconnect()
})
</script>

<template>
  <div class="dashboard">
    <el-row :gutter="20" class="overview-row">
      <el-col :span="6">
        <OverviewCard
          title="总应用数"
          :value="metricsStore.overview.totalApps"
          icon="Apps"
        />
      </el-col>
      <el-col :span="6">
        <OverviewCard
          title="L1 可用率"
          :value="`${metricsStore.overview.l1AvailableRatio}%`"
          icon="Gauge"
          :status="metricsStore.overview.l1AvailableRatio < 20 ? 'danger' : 'success'"
        />
      </el-col>
      <el-col :span="6">
        <OverviewCard
          title="活跃连接"
          :value="metricsStore.connectionStats.active"
          icon="Connection"
        />
      </el-col>
      <el-col :span="6">
        <OverviewCard
          title="紧急模式"
          :value="metricsStore.emergencyMode ? '已激活' : '正常'"
          icon="Warning"
          :status="metricsStore.emergencyMode ? 'danger' : 'success'"
        />
      </el-col>
    </el-row>

    <el-row :gutter="20" class="charts-row">
      <el-col :span="16">
        <el-card>
          <template #header>
            <div class="card-header">
              <span>请求速率</span>
              <el-radio-group v-model="timeRange" size="small">
                <el-radio-button label="1h">1小时</el-radio-button>
                <el-radio-button label="6h">6小时</el-radio-button>
                <el-radio-button label="24h">24小时</el-radio-button>
                <el-radio-button label="7d">7天</el-radio-button>
              </el-radio-group>
            </div>
          </template>
          <MetricsChart :data="metricsStore.requestRate" />
        </el-card>
      </el-col>
      <el-col :span="8">
        <AlertPanel :alerts="metricsStore.alerts" />
      </el-col>
    </el-row>

    <el-row :gutter="20">
      <el-col :span="24">
        <TopAppsTable :apps="metricsStore.topApps" />
      </el-col>
    </el-row>
  </div>
</template>

<style scoped>
.dashboard {
  padding: 20px;
}
.overview-row {
  margin-bottom: 20px;
}
.charts-row {
  margin-bottom: 20px;
}
.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
</style>
```

```typescript
// src/stores/metrics.ts
import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { metricsApi } from '@/api/metrics'
import type { Metrics, Alert, TopApp } from '@/types/metrics'

export const useMetricsStore = defineStore('metrics', () => {
  const metrics = ref<Metrics | null>(null)
  const alerts = ref<Alert[]>([])
  const loading = ref(false)

  const overview = computed(() => ({
    totalApps: metrics.value?.l2_stats?.total || 0,
    activeApps: metrics.value?.l2_stats?.active || 0,
    l1AvailableRatio: metrics.value?.l1_available 
      ? Math.round((metrics.value.l1_available / 1000000) * 100) 
      : 0,
  }))

  const connectionStats = computed(() => metrics.value?.connection_stats || {
    active: 0,
    peak: 0,
    rejected_1h: 0,
  })

  const emergencyMode = computed(() => metrics.value?.emergency_mode || false)

  const requestRate = computed(() => metrics.value?.request_rate || [])

  const topApps = computed(() => metrics.value?.top_apps || [])

  async function fetchMetrics(timeRange: string) {
    loading.value = true
    try {
      const response = await metricsApi.getMetrics(timeRange)
      metrics.value = response.data
    } finally {
      loading.value = false
    }
  }

  function updateFromWebSocket(data: Partial<Metrics>) {
    if (metrics.value) {
      Object.assign(metrics.value, data)
    }
  }

  function addAlert(alert: Alert) {
    alerts.value.unshift(alert)
    if (alerts.value.length > 100) {
      alerts.value.pop()
    }
  }

  return {
    metrics,
    alerts,
    loading,
    overview,
    connectionStats,
    emergencyMode,
    requestRate,
    topApps,
    fetchMetrics,
    updateFromWebSocket,
    addAlert,
  }
})
```

```typescript
// src/composables/useWebSocket.ts
import { ref, onUnmounted } from 'vue'
import { useMetricsStore } from '@/stores/metrics'

export function useWebSocket() {
  const ws = ref<WebSocket | null>(null)
  const connected = ref(false)
  const metricsStore = useMetricsStore()

  function connect() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/api/v1/ws`
    
    ws.value = new WebSocket(wsUrl)
    
    ws.value.onopen = () => {
      connected.value = true
      console.log('WebSocket connected')
    }
    
    ws.value.onmessage = (event) => {
      const data = JSON.parse(event.data)
      if (data.type === 'metrics') {
        metricsStore.updateFromWebSocket(data)
      } else if (data.type === 'alert') {
        metricsStore.addAlert(data)
      }
    }
    
    ws.value.onclose = () => {
      connected.value = false
      // 自动重连
      setTimeout(connect, 5000)
    }
  }

  function disconnect() {
    if (ws.value) {
      ws.value.close()
      ws.value = null
    }
  }

  onUnmounted(disconnect)

  return { connect, disconnect, connected }
}
```

### Dashboard 数据模型

```typescript
// 仪表盘数据接口定义
interface DashboardData {
  overview: {
    total_apps: number;
    active_apps: number;
    total_requests_1h: number;
    total_cost_1h: number;
    l1_available_ratio: number;
    emergency_mode: boolean;
  };
  
  metrics: {
    request_rate: TimeSeriesData[];
    cost_distribution: HistogramData;
    token_availability: {
      l1: number;
      l2_avg: number;
      l3_cache_hit: number;
    };
    connection_stats: {
      active: number;
      peak: number;
      rejected_1h: number;
      leaked_1h: number;
    };
  };
  
  top_apps: {
    app_id: string;
    requests_1h: number;
    cost_1h: number;
    connections: number;
    status: 'normal' | 'warning' | 'critical';
  }[];
  
  alerts: {
    id: string;
    severity: 'info' | 'warning' | 'critical';
    message: string;
    timestamp: number;
    acknowledged: boolean;
  }[];
  
  redis_health: {
    status: 'healthy' | 'degraded' | 'down';
    latency_p99: number;
    connection_pool_usage: number;
  };
}

// WebSocket 实时更新消息
interface RealtimeUpdate {
  type: 'metrics' | 'alert' | 'config_change' | 'emergency';
  data: any;
  timestamp: number;
}
```

### API 端点规范

```yaml
openapi: 3.0.0
info:
  title: Rate Limiter Admin API
  version: 1.0.0

paths:
  /api/v1/apps:
    get:
      summary: 获取应用列表
      parameters:
        - name: page
          in: query
          schema:
            type: integer
            default: 1
        - name: limit
          in: query
          schema:
            type: integer
            default: 20
      responses:
        200:
          description: 成功
          content:
            application/json:
              schema:
                type: object
                properties:
                  data:
                    type: array
                    items:
                      $ref: '#/components/schemas/App'
                  total:
                    type: integer
    
    post:
      summary: 创建应用
      requestBody:
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/AppCreate'
      responses:
        201:
          description: 创建成功
        400:
          description: 验证失败

  /api/v1/metrics:
    get:
      summary: 获取实时指标
      parameters:
        - name: range
          in: query
          schema:
            type: string
            enum: [1h, 6h, 24h, 7d]
            default: 1h
      responses:
        200:
          description: 成功
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Metrics'

  /api/v1/emergency/activate:
    post:
      summary: 激活紧急模式
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                reason:
                  type: string
                duration:
                  type: integer
                  default: 300
      responses:
        200:
          description: 激活成功

components:
  schemas:
    App:
      type: object
      properties:
        app_id:
          type: string
        guaranteed_quota:
          type: integer
        burst_quota:
          type: integer
        priority:
          type: integer
          minimum: 0
          maximum: 3
        max_connections:
          type: integer
        enabled:
          type: boolean
    
    Metrics:
      type: object
      properties:
        l1_available:
          type: integer
        l2_stats:
          type: object
        l3_cache_hit_ratio:
          type: number
        request_rate:
          type: array
        connection_stats:
          type: object
        emergency_mode:
          type: boolean
        redis_latency:
          type: number
```
