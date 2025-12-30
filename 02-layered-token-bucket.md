# 分层令牌桶架构详解

## 一、架构总览

### 1.1 三层架构图

```
┌─────────────────────────────────────────────────────────────┐
│                    L1: 集群层 (Cluster)                      │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Redis Cluster (全局配额)                    ││
│  │  • 物理资源底线保护                                      ││
│  │  • 跨应用公平调度                                        ││
│  │  • 容量: 1,000,000 tokens/s                             ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────┬───────────────────────────────┘
                              │ Token 分配
┌─────────────────────────────▼───────────────────────────────┐
│                    L2: 应用层 (Application)                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   App A      │  │   App B      │  │   App C      │       │
│  │  保底: 10k   │  │  保底: 20k   │  │  保底: 5k    │       │
│  │  突发: 50k   │  │  突发: 80k   │  │  突发: 20k   │       │
│  │  优先级: P1  │  │  优先级: P0  │  │  优先级: P2  │       │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
└─────────┼─────────────────┼─────────────────┼───────────────┘
          │                 │                 │
┌─────────▼─────────────────▼─────────────────▼───────────────┐
│                    L3: 本地层 (Local)                        │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐        │
│  │ Nginx-1 │  │ Nginx-2 │  │ Nginx-3 │  │ Nginx-N │        │
│  │预留:1000│  │预留:1000│  │预留:1000│  │预留:1000│        │
│  │ <1ms    │  │ <1ms    │  │ <1ms    │  │ <1ms    │        │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 设计原则

| 原则 | 说明 |
|------|------|
| 边缘计算 | 95%+ 请求在 L3 本地完成 |
| 中心管理 | 配置和配额由 Redis 集中管理 |
| 异步同步 | 批量上报，减少 Redis 压力 |
| 优雅降级 | 任一层故障不影响整体可用性 |

---

## 二、L1 集群层详解

### 2.1 职责定义

```
L1 集群层的核心职责：
├── 物理资源保护
│   └── 防止底层存储/计算被压垮
├── 全局配额管理
│   └── 所有应用的配额总和不超过集群容量
├── 公平调度
│   └── 资源紧张时按优先级分配
└── 容量规划
    └── 提供配额使用数据支持扩容决策
```

### 2.2 数据模型

```lua
-- Redis 数据结构
-- Key: ratelimit:l1:{cluster_id}

-- Hash 存储集群配置
HSET ratelimit:l1:cluster-01 max_capacity 1000000
HSET ratelimit:l1:cluster-01 current_used 750000
HSET ratelimit:l1:cluster-01 reserved_ratio 0.1
HSET ratelimit:l1:cluster-01 burst_ratio 1.2

-- Sorted Set 存储应用配额分配
ZADD ratelimit:l1:cluster-01:apps 10000 "app-a"
ZADD ratelimit:l1:cluster-01:apps 20000 "app-b"
ZADD ratelimit:l1:cluster-01:apps 5000 "app-c"
```

### 2.3 配额分配算法

```lua
-- l1_allocator.lua
local function allocate_quota(cluster_id, app_id, requested)
    local cluster_key = "ratelimit:l1:" .. cluster_id
    
    local script = [[
        local max_cap = tonumber(redis.call('HGET', KEYS[1], 'max_capacity'))
        local current = tonumber(redis.call('HGET', KEYS[1], 'current_used')) or 0
        local reserved = tonumber(redis.call('HGET', KEYS[1], 'reserved_ratio')) or 0.1
        
        -- 可分配容量 = 总容量 × (1 - 预留比例) - 已分配
        local available = max_cap * (1 - reserved) - current
        local granted = math.min(available, tonumber(ARGV[1]))
        
        if granted > 0 then
            redis.call('HINCRBY', KEYS[1], 'current_used', granted)
            redis.call('ZINCRBY', KEYS[1] .. ':apps', granted, ARGV[2])
        end
        
        return granted
    ]]
    
    return redis.eval(script, 1, cluster_key, requested, app_id)
end
```

### 2.4 过载保护

```lua
-- 当集群使用率超过阈值时触发
local function check_overload(cluster_id)
    local cluster_key = "ratelimit:l1:" .. cluster_id
    
    local max_cap = redis.call('HGET', cluster_key, 'max_capacity')
    local current = redis.call('HGET', cluster_key, 'current_used')
    local usage_ratio = current / max_cap
    
    if usage_ratio > 0.9 then
        -- 触发配额削减
        return trigger_quota_reduction(cluster_id, usage_ratio)
    end
    
    return false
end

local function trigger_quota_reduction(cluster_id, usage_ratio)
    -- 按优先级削减配额
    local apps = redis.call('ZRANGE', cluster_key .. ':apps', 0, -1, 'WITHSCORES')
    local reduction_factor = 1 - (usage_ratio - 0.9) / 0.1  -- 90%-100% 线性削减
    
    for i = 1, #apps, 2 do
        local app_id = apps[i]
        local current_quota = apps[i + 1]
        local priority = get_app_priority(app_id)
        
        -- 低优先级应用削减更多
        local app_reduction = reduction_factor * (1 + (priority - 1) * 0.2)
        local new_quota = current_quota * app_reduction
        
        redis.call('ZADD', cluster_key .. ':apps', new_quota, app_id)
    end
end
```

---

## 三、L2 应用层详解

### 3.1 职责定义

```
L2 应用层的核心职责：
├── SLA 保障
│   └── 为每个应用提供保底配额
├── 突发处理
│   └── 允许短时间超出保底配额
├── 配额隔离
│   └── 应用间互不影响
└── 弹性伸缩
    └── 根据实际使用动态调整
```

### 3.2 数据模型

```lua
-- Redis 数据结构
-- Key: ratelimit:l2:{app_id}

-- Hash 存储应用配置
HSET ratelimit:l2:video-service guaranteed_quota 20000
HSET ratelimit:l2:video-service burst_quota 80000
HSET ratelimit:l2:video-service current_tokens 20000
HSET ratelimit:l2:video-service priority 0
HSET ratelimit:l2:video-service burst_remaining 60000
HSET ratelimit:l2:video-service last_refill 1704067200

-- 配置示例
local APP_CONFIG = {
    app_id = "video-service",
    guaranteed_quota = 20000,    -- 保底 2万 tokens/s
    burst_quota = 80000,         -- 突发上限 8万 tokens/s
    burst_duration = 60,         -- 突发持续时间 60秒
    priority = 0,                -- 最高优先级
    refill_rate = 20000,         -- 每秒补充 2万 tokens
}
```

### 3.3 令牌桶实现

```lua
-- l2_token_bucket.lua
local _M = {}

-- 获取令牌
function _M.acquire(app_id, cost)
    local key = "ratelimit:l2:" .. app_id
    
    local script = [[
        local key = KEYS[1]
        local cost = tonumber(ARGV[1])
        local now = tonumber(ARGV[2])
        
        -- 获取配置
        local guaranteed = tonumber(redis.call('HGET', key, 'guaranteed_quota'))
        local burst = tonumber(redis.call('HGET', key, 'burst_quota'))
        local current = tonumber(redis.call('HGET', key, 'current_tokens')) or guaranteed
        local last_refill = tonumber(redis.call('HGET', key, 'last_refill')) or now
        
        -- 计算令牌补充
        local elapsed = now - last_refill
        local refill_rate = guaranteed  -- 每秒补充保底配额
        local refilled = math.min(burst, current + elapsed * refill_rate)
        
        -- 尝试扣减
        if refilled >= cost then
            redis.call('HSET', key, 'current_tokens', refilled - cost)
            redis.call('HSET', key, 'last_refill', now)
            return 1  -- 成功
        else
            redis.call('HSET', key, 'current_tokens', refilled)
            redis.call('HSET', key, 'last_refill', now)
            return 0  -- 失败
        end
    ]]
    
    local now = ngx.now()
    return redis.eval(script, 1, key, cost, now)
end

-- 批量获取令牌（用于 L3 预取）
function _M.acquire_batch(app_id, amount)
    local key = "ratelimit:l2:" .. app_id
    
    local script = [[
        local key = KEYS[1]
        local requested = tonumber(ARGV[1])
        local now = tonumber(ARGV[2])
        
        -- 获取当前令牌
        local current = tonumber(redis.call('HGET', key, 'current_tokens')) or 0
        local granted = math.min(current, requested)
        
        if granted > 0 then
            redis.call('HINCRBY', key, 'current_tokens', -granted)
        end
        
        return granted
    ]]
    
    local now = ngx.now()
    return redis.eval(script, 1, key, amount, now)
end

return _M
```

### 3.4 突发配额管理

```lua
-- burst_manager.lua
local function handle_burst(app_id, extra_needed)
    local key = "ratelimit:l2:" .. app_id
    
    local script = [[
        local key = KEYS[1]
        local extra = tonumber(ARGV[1])
        local now = tonumber(ARGV[2])
        
        local burst_remaining = tonumber(redis.call('HGET', key, 'burst_remaining')) or 0
        local burst_start = tonumber(redis.call('HGET', key, 'burst_start')) or 0
        local burst_duration = tonumber(redis.call('HGET', key, 'burst_duration')) or 60
        
        -- 检查突发窗口是否过期
        if now - burst_start > burst_duration then
            -- 重置突发配额
            local burst_quota = tonumber(redis.call('HGET', key, 'burst_quota'))
            local guaranteed = tonumber(redis.call('HGET', key, 'guaranteed_quota'))
            burst_remaining = burst_quota - guaranteed
            redis.call('HSET', key, 'burst_start', now)
        end
        
        -- 从突发配额借用
        local granted = math.min(burst_remaining, extra)
        if granted > 0 then
            redis.call('HINCRBY', key, 'burst_remaining', -granted)
            return granted
        end
        
        return 0
    ]]
    
    return redis.eval(script, 1, key, extra_needed, ngx.now())
end
```

---

## 四、L3 本地层详解

### 4.1 职责定义

```
L3 本地层的核心职责：
├── 亚毫秒响应
│   └── 95%+ 请求 <1ms 完成
├── 减少 Redis 访问
│   └── 批量同步，减少 100-1000× 调用
├── 本地缓存
│   └── 预取令牌，本地决策
└── 故障隔离
    └── Redis 故障时独立运行
```

### 4.2 数据结构

```lua
-- 本地内存数据结构（Nginx shared dict 或 Lua table）
local LOCAL_BUCKET = {
    app_id = "video-service",
    node_id = "nginx-worker-01",
    
    -- 令牌状态
    tokens = 1000,              -- 当前本地令牌
    reserve_target = 1000,      -- 目标预留量
    refill_threshold = 0.2,     -- 20% 时触发补充
    
    -- 同步状态
    pending_consumption = 0,    -- 待上报消耗
    pending_requests = 0,       -- 待上报请求数
    last_sync = 0,              -- 上次同步时间
    sync_interval = 0.1,        -- 100ms 同步间隔
    batch_threshold = 1000,     -- 1000 次操作触发同步
    
    -- 统计
    local_hits = 0,             -- 本地命中次数
    remote_calls = 0,           -- 远程调用次数
}
```

### 4.3 核心实现

```lua
-- l3_local_bucket.lua
local _M = {}
local shared_dict = ngx.shared.ratelimit
local l2_client = require("l2_token_bucket")

-- 配置
local CONFIG = {
    RESERVE_TARGET = 1000,
    REFILL_THRESHOLD = 0.2,
    SYNC_INTERVAL = 0.1,
    BATCH_THRESHOLD = 1000,
}

-- 获取本地令牌
function _M.acquire(app_id, cost)
    local key = "local:" .. app_id
    
    -- 获取当前令牌
    local tokens = shared_dict:get(key .. ":tokens") or 0
    
    if tokens >= cost then
        -- 本地扣减
        shared_dict:incr(key .. ":tokens", -cost)
        shared_dict:incr(key .. ":pending_consumption", cost)
        shared_dict:incr(key .. ":pending_requests", 1)
        shared_dict:incr(key .. ":local_hits", 1)
        
        -- 检查是否需要补充
        _M.check_refill(app_id)
        
        -- 检查是否需要同步
        _M.check_sync(app_id)
        
        return true
    else
        -- 本地不足，尝试从 L2 获取
        return _M.fetch_from_l2(app_id, cost)
    end
end

-- 从 L2 获取令牌
function _M.fetch_from_l2(app_id, cost)
    local key = "local:" .. app_id
    
    -- 请求补充量 = 目标预留 + 当前需求
    local fetch_amount = CONFIG.RESERVE_TARGET + cost
    
    local granted = l2_client.acquire_batch(app_id, fetch_amount)
    shared_dict:incr(key .. ":remote_calls", 1)
    
    if granted >= cost then
        -- 补充成功
        shared_dict:incr(key .. ":tokens", granted - cost)
        shared_dict:incr(key .. ":pending_consumption", cost)
        shared_dict:incr(key .. ":pending_requests", 1)
        return true
    elseif granted > 0 then
        -- 部分补充
        shared_dict:incr(key .. ":tokens", granted)
    end
    
    return false
end

-- 检查是否需要补充
function _M.check_refill(app_id)
    local key = "local:" .. app_id
    local tokens = shared_dict:get(key .. ":tokens") or 0
    
    if tokens < CONFIG.RESERVE_TARGET * CONFIG.REFILL_THRESHOLD then
        -- 异步补充
        ngx.timer.at(0, function()
            local fetch_amount = CONFIG.RESERVE_TARGET - tokens
            local granted = l2_client.acquire_batch(app_id, fetch_amount)
            if granted > 0 then
                shared_dict:incr(key .. ":tokens", granted)
            end
        end)
    end
end

-- 检查是否需要同步
function _M.check_sync(app_id)
    local key = "local:" .. app_id
    local pending = shared_dict:get(key .. ":pending_requests") or 0
    local last_sync = shared_dict:get(key .. ":last_sync") or 0
    local now = ngx.now()
    
    local should_sync = pending >= CONFIG.BATCH_THRESHOLD or
                        (now - last_sync) >= CONFIG.SYNC_INTERVAL
    
    if should_sync then
        ngx.timer.at(0, function()
            _M.sync_to_l2(app_id)
        end)
    end
end

-- 同步到 L2
function _M.sync_to_l2(app_id)
    local key = "local:" .. app_id
    
    -- 原子获取并重置
    local consumption = shared_dict:get(key .. ":pending_consumption") or 0
    local requests = shared_dict:get(key .. ":pending_requests") or 0
    
    if consumption > 0 or requests > 0 then
        shared_dict:set(key .. ":pending_consumption", 0)
        shared_dict:set(key .. ":pending_requests", 0)
        shared_dict:set(key .. ":last_sync", ngx.now())
        
        -- 上报到 L2
        l2_client.report_consumption(app_id, consumption, requests)
    end
end

return _M
```

### 4.4 令牌流转时序

```
时间线（100ms 窗口内）：

T=0ms:   L3 本地: 1000 tokens
         ├── 请求1: GET 1KB, Cost=2, 扣减后=998
         ├── 请求2: PUT 10KB, Cost=6, 扣减后=992
         └── ...

T=30ms:  L3 本地: 200 tokens (低于阈值 20%)
         └── 触发异步补充请求

T=35ms:  L2 返回 800 tokens
         └── L3 本地: 1000 tokens

T=50ms:  累计 1000 次请求
         └── 触发批量同步

T=100ms: 定时同步
         └── 上报消耗统计到 L2

┌────────────────────────────────────────────────────────────┐
│  令牌变化曲线                                               │
│                                                            │
│  1000 ┤████████████████                    ████████████████│
│       │                ████                                │
│   700 ┤                    ████                            │
│       │                        ████                        │
│   200 ┤                            ████ ← 触发补充          │
│       │                                                    │
│       └────────────────────────────────────────────────────│
│        0    10    30    35    50                      100ms│
└────────────────────────────────────────────────────────────┘
```

---

## 五、层间通信协议

### 5.1 通信模式

```
┌─────────────────────────────────────────────────────────────┐
│                      通信模式总览                            │
├─────────────────┬───────────────────────────────────────────┤
│ L3 → L2         │ 令牌申请、消耗上报                         │
│ L2 → L1         │ 配额申请、使用统计                         │
│ L1 → L2         │ 配额调整通知、过载告警                     │
│ L2 → L3         │ 配置更新推送                              │
└─────────────────┴───────────────────────────────────────────┘
```

### 5.2 消息格式

```lua
-- 令牌申请请求
local TOKEN_REQUEST = {
    type = "token_request",
    app_id = "video-service",
    node_id = "nginx-01",
    requested = 1000,
    current_local = 200,
    timestamp = 1704067200.123,
}

-- 令牌申请响应
local TOKEN_RESPONSE = {
    type = "token_response",
    app_id = "video-service",
    granted = 800,
    remaining_l2 = 15000,
    next_refill = 1704067201.0,
}

-- 消耗上报
local CONSUMPTION_REPORT = {
    type = "consumption_report",
    app_id = "video-service",
    node_id = "nginx-01",
    period_start = 1704067200.0,
    period_end = 1704067200.1,
    total_cost = 5000,
    request_count = 1200,
    by_method = {
        GET = {cost = 2000, count = 800},
        PUT = {cost = 3000, count = 400},
    },
}

-- 配置更新
local CONFIG_UPDATE = {
    type = "config_update",
    app_id = "video-service",
    guaranteed_quota = 25000,  -- 新配额
    burst_quota = 100000,
    effective_time = 1704067260,
}
```

### 5.3 Redis Pub/Sub 通道

```lua
-- 配置更新通道
local function subscribe_config_updates(app_id)
    local channel = "ratelimit:config:" .. app_id
    
    local red = redis:new()
    red:subscribe(channel)
    
    while true do
        local msg = red:read_reply()
        if msg and msg[1] == "message" then
            local config = cjson.decode(msg[3])
            apply_config_update(app_id, config)
        end
    end
end

-- 发布配置更新
local function publish_config_update(app_id, new_config)
    local channel = "ratelimit:config:" .. app_id
    local red = redis:new()
    red:publish(channel, cjson.encode(new_config))
end
```
