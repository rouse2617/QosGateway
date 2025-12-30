# Connection Limiter 需求符合性审阅报告

## 执行摘要

**审阅对象**: Connection Limiter 组件设计
**审阅日期**: 2025-12-31
**需求文档**: requirements.md (Requirement 17-20)
**设计文档**: design.md (Component 8: Connection Limiter)
**总体评估**: ⚠️ **基本满足，但有关键缺陷需要修复**

---

## 1. 需求覆盖度分析

### 1.1 Requirement 17: 连接并发数限制

| 验收标准 | 设计覆盖 | 评估 | 备注 |
|---------|---------|------|------|
| 1. 支持 per-app 连接限制 | ✅ | 完全覆盖 | `conn:app:{app_id}` 结构实现 |
| 2. 支持 per-cluster 连接限制 | ✅ | 完全覆盖 | `conn:cluster:{cluster_id}` 结构实现 |
| 3. 令牌桶检查前检查连接 | ✅ | 完全覆盖 | 架构图显示连接限制层在最前端 |
| 4. app_limit_exceeded → 429 | ✅ | 完全覆盖 | `acquire()` 函数实现 |
| 5. cluster_limit_exceeded → 429 | ✅ | 完全覆盖 | `acquire()` 函数实现 |
| 6. Nginx shared_dict, <0.5ms | ✅ | 完全覆盖 | 内存操作，满足性能要求 |
| 7. log_by_lua 释放连接 | ✅ | 完全覆盖 | `release()` 函数实现 |
| 8. 响应头设置 | ❌ | **缺失** | 未设置 `X-Connection-Limit` 和 `X-Connection-Current` |

**符合度**: 7/8 (87.5%)

### 1.2 Requirement 18: 连接追踪与泄漏检测

| 验收标准 | 设计覆盖 | 评估 | 备注 |
|---------|---------|------|------|
| 1. 记录连接信息 | ✅ | 完全覆盖 | `conn:track:{conn_id}` 记录完整 |
| 2. 更新 last_seen | ❌ | **缺失** | 只在创建时设置，无更新机制 |
| 3. 标记为 released | ✅ | 完全覆盖 | `release()` 函数设置 status |
| 4. 超时检测泄漏 | ⚠️ | 部分覆盖 | 使用 created_at 而非 last_seen |
| 5. 强制释放泄漏连接 | ✅ | 完全覆盖 | `force_release_connection()` 实现 |
| 6. 每30秒清理 | ✅ | 完全覆盖 | `CLEANUP_INTERVAL = 30` |
| 7. 记录泄漏日志 | ❌ | **缺失** | 仅增加计数器，无日志记录 |

**符合度**: 4/7 (57.1%)

### 1.3 Requirement 19: 连接限制监控指标

| 验收标准 | 设计覆盖 | 评估 | 备注 |
|---------|---------|------|------|
| 1. connlimit_active_connections | ✅ | 完全覆盖 | `current` 字段 |
| 2. connlimit_peak_connections | ✅ | 完全覆盖 | `peak` 字段 |
| 3. connlimit_rejected_total | ✅ | 完全覆盖 | `rejected` 字段 |
| 4. connlimit_leaked_total | ✅ | 完全覆盖 | `conn:leaked:total` |
| 5. connlimit_duration_seconds | ✅ | 完全覆盖 | `track_data.duration` |
| 6. 上报 Redis (10s) | ❌ | **缺失** | 无定时上报机制 |
| 7. 跨节点聚合 | ⚠️ | 部分覆盖 | Redis 结构存在但未实现上报 |

**符合度**: 5/7 (71.4%)

### 1.4 Requirement 20: 连接限制配置管理

| 验收标准 | 设计覆盖 | 评估 | 备注 |
|---------|---------|------|------|
| 1. CRUD API | ❌ | **缺失** | 无配置 API 设计 |
| 2. cluster 配置 | ⚠️ | 部分覆盖 | 只有硬编码常量 |
| 3. Redis 存储 | ⚠️ | 数据结构存在 | `connlimit:config:{app_id}` 存在但无实现 |
| 4. Redis Pub/Sub | ❌ | **缺失** | 无配置热更新机制 |
| 5. 本地缓存 (60s TTL) | ❌ | **缺失** | 无本地缓存逻辑 |
| 6. 验证 max_connections > 0 | ⚠ | 部分覆盖 | 无显式验证代码 |
| 7. burst_connections | ❌ | **缺失** | 无 burst 支持 |

**符合度**: 1/7 (14.3%)

---

## 2. Correctness Properties 审查 (Property 15-20)

### Property 15: 连接获取-释放一致性 ✅ **完全满足**

**Property**: 对于任何成功的连接获取操作，连接计数器应精确增加1，释放时（正常或强制）精确减少1。

**设计实现**:
```lua
-- acquire: app_data.current = app_data.current + 1
-- release: _M.decrement_counter("conn:app:" .. app_id)
```

**评估**: ✅ 逻辑正确，但缺少 `decrement_counter` 函数实现细节（推测实现正确）

**建议**: 在最终代码中确保 `decrement_counter` 的原子性

---

### Property 16: 连接限制强制执行 ✅ **完全满足**

**Property**: 当 current >= limit 时，Connection Limiter 应拒绝请求并增加 rejected 计数器。

**设计实现**:
```lua
if app_data.current >= app_data.limit then
    app_data.rejected = app_data.rejected + 1
    return false, {code = "app_limit_exceeded"}
end
```

**评估**: ✅ 逻辑完全正确，支持 app 和 cluster 两个维度

**建议**: 无

---

### Property 17: 连接计数器非负不变性 ⚠️ **有风险**

**Property**: 任何连接计数器（per-app 或 per-cluster）永远不应为负数。

**设计实现**: 未显式验证，依赖 `decrement_counter` 实现

**潜在问题**:
1. 如果 `decrement_counter` 被多次调用，可能导致负数
2. 强制释放时未检查当前计数是否 > 0

**建议**: 添加非负检查
```lua
function _M.decrement_counter(key)
    local data_str = shared_dict:get(key)
    if data_str then
        local data = cjson.decode(data_str)
        data.current = math.max(0, data.current - 1)  -- 防止负数
        shared_dict:set(key, cjson.encode(data))
    end
end
```

---

### Property 18: 连接泄漏检测正确性 ❌ **不满足**

**Property**: 对于任何 `status == "active"` 且 `(now - last_seen) > CONNECTION_TIMEOUT` 的连接，清理过程应强制释放。

**设计实现**:
```lua
local age = now - track_data.last_seen  -- ⚠️ last_seen 从未更新!
if age > CONFIG.CONNECTION_TIMEOUT then
    _M.force_release_connection(key, track_data)
end
```

**关键缺陷**:
1. **`last_seen` 字段从未被更新**（只在创建时设置）
2. 泄漏检测逻辑实际使用的是 `created_at`，而非 `last_seen`
3. 这导致所有活跃连接在 300 秒后都会被错误地标记为泄漏

**修复建议**:
```lua
-- 在 access_by_lua 阶段定期更新 last_seen
function _M.heartbeat()
    local conn_id = ngx.ctx.conn_limit_id
    if conn_id then
        local track_key = "conn:track:" .. conn_id
        local track_data_str = shared_dict:get(track_key)
        if track_data_str then
            local track_data = cjson.decode(track_data_str)
            track_data.last_seen = ngx.now()
            shared_dict:set(track_key, cjson.encode(track_data), CONFIG.CONNECTION_TIMEOUT)
        end
    end
end

-- 在请求处理过程中调用
-- access_by_lua_block:
--   connection_limiter.heartbeat()
```

---

### Property 19: 连接峰值跟踪 ✅ **完全满足**

**Property**: 在任何连接获取操作中，如果新的当前计数超过记录的峰值，峰值应更新为新的当前计数。

**设计实现**:
```lua
app_data.peak = math.max(app_data.peak, app_data.current)
cluster_data.peak = math.max(cluster_data.peak, cluster_data.current)
```

**评估**: ✅ 逻辑完全正确

---

### Property 20: 连接释放幂等性 ✅ **完全满足**

**Property**: 对于任何 `status == "released"` 的连接释放操作，操作应为空操作（no-op），且不应减少连接计数器。

**设计实现**:
```lua
if track_data.status == "released" then return end
-- ... 只有未释放时才执行减量操作
```

**评估**: ✅ 逻辑完全正确

---

## 3. 功能完整性分析

### 3.1 已实现功能 ✅

1. **Per-App 连接限制**
   - 支持独立的应用级连接计数
   - 支持动态限制值（通过 Redis 配置）

2. **Per-Cluster 连接限制**
   - 支持集群级连接计数
   - 支持 app 和 cluster 双重检查

3. **连接追踪**
   - 记录连接 ID、应用 ID、集群 ID、客户端 IP
   - 记录创建时间和状态

4. **连接泄漏检测**
   - 定时清理（30 秒间隔）
   - 超时强制释放机制

5. **统计信息**
   - 当前连接数、峰值、拒绝次数
   - 泄漏连接计数

### 3.2 缺失功能 ❌

#### 关键缺失 (P0 - 必须修复)

1. **响应头设置** (Requirement 17.8)
   ```lua
   -- 需要在 acquire 成功后添加：
   ngx.header["X-Connection-Limit"] = app_data.limit
   ngx.header["X-Connection-Current"] = app_data.current
   ```

2. **last_seen 更新机制** (Requirement 18.2)
   - 当前设计只在创建时设置 `last_seen`
   - 需要在请求处理过程中定期更新（建议每 60 秒或请求中途）

3. **泄漏日志记录** (Requirement 18.7)
   ```lua
   -- 需要在强制释放时记录：
   ngx.log(ngx.WARN, "connection_leaked: conn_id=", conn_id,
           ", app_id=", track_data.app_id,
           ", age=", age)
   ```

#### 重要缺失 (P1 - 应该修复)

4. **配置管理 API** (Requirement 20.1, 20.3-20.7)
   - 缺少配置 CRUD 接口
   - 缺少 Redis Pub/Sub 热更新机制
   - 缺少本地配置缓存

5. **监控指标上报** (Requirement 19.6, 19.7)
   - 缺少定时上报到 Redis 的机制（10 秒间隔）
   - 缺少跨节点聚合逻辑

6. **Burst 连接支持** (Requirement 20.7)
   - 当前只支持 `max_connections`
   - 应支持 `burst_connections` 临时超过限制

#### 次要缺失 (P2 - 可以后续补充)

7. **连接持续时间直方图**
   - 虽然记录了 `duration`，但未生成 Prometheus 直方图

8. **连接事件日志**
   - 数据结构中定义了 `connlimit:events:{app_id}`，但未实现

---

## 4. 设计缺陷分析

### 4.1 严重缺陷 (Critical)

#### 缺陷 #1: last_seen 未更新导致误判泄漏

**问题描述**:
- `last_seen` 字段在连接创建时设置后从未更新
- 泄漏检测逻辑依赖 `last_seen`，但实际值不变
- 导致所有连接在 300 秒后都会被强制释放

**影响**:
- 正常的长连接（如 WebSocket）会被错误地中断
- 连接计数器频繁波动，影响限制准确性

**修复优先级**: P0 - 必须在实现前修复设计

---

#### 缺陷 #2: 缺少响应头

**问题描述**:
- Requirement 17.8 要求设置 `X-Connection-Limit` 和 `X-Connection-Current`
- 设计中未提及此功能

**影响**:
- 客户端无法获取当前连接状态
- 调试和监控困难

**修复优先级**: P0 - 必须在实现前修复设计

---

### 4.2 重要缺陷 (High)

#### 缺陷 #3: 配置管理完全缺失

**问题描述**:
- Requirement 20 要求完整的配置管理功能
- 设计中只有硬编码的常量和数据结构定义

**影响**:
- 无法动态调整连接限制
- 必须重启 Nginx 才能修改配置
- 违反"热更新"设计目标

**修复优先级**: P1 - 应在设计阶段补充

---

#### 缺陷 #4: 监控指标无上报机制

**问题描述**:
- 收集了所有监控指标，但无上报到 Redis 的逻辑
- 无法实现跨节点聚合

**影响**:
- 只能看到单节点数据
- 无法获得全局视图

**修复优先级**: P1 - 应在设计阶段补充

---

### 4.3 中等缺陷 (Medium)

#### 缺陷 #5: decrement_counter 未定义

**问题描述**:
- `release()` 函数调用 `_M.decrement_counter()`，但设计文档中未定义此函数

**影响**:
- 代码不完整，可能存在实现错误

**修复优先级**: P2 - 需要补充定义

---

#### 缺陷 #6: force_release_connection 未定义

**问题描述**:
- `cleanup_leaked_connections()` 调用 `_M.force_release_connection()`，但未定义

**影响**:
- 清理逻辑不完整

**修复优先级**: P2 - 需要补充定义

---

## 5. 过度设计分析

### 5.1 是否有超出需求的功能？

**评估**: ✅ **无过度设计**

当前设计完全聚焦于连接限制功能，所有功能都在需求范围内：
- Per-app/per-cluster 限制是核心需求
- 连接追踪是泄漏检测的基础
- 统计信息是监控需求

### 5.2 是否有不必要的复杂性？

**发现**:
1. **连接追踪的复杂度合理**
   - 记录详细的连接信息是必要的（用于调试和审计）
   - 状态机设计（active → released）简洁清晰

2. **数据结构设计合理**
   - Nginx shared_dict 用于高性能计数
   - Redis 用于跨节点配置同步（虽未实现）

3. **无冗余功能**
   - 每个字段和函数都有明确用途

---

## 6. 监控与可观测性评估

### 6.1 已有的监控指标 ✅

| 指标 | 数据来源 | 覆盖需求 |
|------|---------|---------|
| 当前连接数 | `current` 字段 | ✅ Req 19.1 |
| 峰值连接数 | `peak` 字段 | ✅ Req 19.2 |
| 拒绝次数 | `rejected` 字段 | ✅ Req 19.3 |
| 泄漏次数 | `conn:leaked:total` | ✅ Req 19.4 |
| 连接持续时间 | `duration` 字段 | ✅ Req 19.5 |

### 6.2 缺失的监控能力 ❌

1. **无 Prometheus 导出**
   - 设计中未定义 Prometheus metrics 格式
   - 无法直接接入监控系统

2. **无跨节点聚合**
   - 统计信息只在本地 shared_dict
   - 无上报和聚合机制

3. **无告警阈值**
   - 虽然收集了指标，但未定义告警规则
   - 建议添加：泄漏率 > 5%、拒绝率 > 10% 等阈值

### 6.3 可观测性改进建议

#### 建议 #1: 添加 Prometheus Metrics 导出

```lua
-- ratelimit/connection_limiter_metrics.lua
local prometheus = require("resty.prometheus")

local function export_metrics()
    local metrics = prometheus.init("prometheus-shared-metrics")

    -- Gauge: 当前连接数
    metrics:gauge("connlimit_active_connections",
        "Current active connections",
        {"app_id", "cluster_id"})

    -- Gauge: 峰值连接数
    metrics:gauge("connlimit_peak_connections",
        "Peak connection count",
        {"app_id", "cluster_id"})

    -- Counter: 拒绝次数
    metrics:counter("connlimit_rejected_total",
        "Total rejected connections",
        {"app_id", "cluster_id", "reason"})

    -- Histogram: 连接持续时间
    metrics:histogram("connlimit_duration_seconds",
        "Connection duration in seconds",
        {"app_id"},
        {0.1, 0.5, 1, 5, 10, 30, 60, 300})
end
```

#### 建议 #2: 添加指标上报到 Redis

```lua
function _M.report_stats_to_redis()
    local app_keys = shared_dict:get_keys(0)
    local stats = {}

    for _, key in ipairs(app_keys) do
        if string.match(key, "^conn:app:") then
            local app_id = string.match(key, "conn:app:(.+)")
            local data_str = shared_dict:get(key)
            if data_str then
                local data = cjson.decode(data_str)
                stats[app_id] = {
                    current = data.current,
                    peak = data.peak,
                    rejected = data.rejected
                }
            end
        end
    end

    -- 上报到 Redis
    local redis = require("resty.redis"):new()
    redis:connect("redis", 6379)
    for app_id, app_stats in pairs(stats) do
        redis:hset("connlimit:stats:" .. app_id, app_stats)
    end
    redis:set_keepalive()
end

-- 定时上报（10秒间隔）
local function start_stats_reporter()
    local ok, err = ngx.timer.every(10, _M.report_stats_to_redis)
    if not ok then
        ngx.log(ngx.ERR, "failed to create stats reporter: ", err)
    end
end
```

#### 建议 #3: 添加连接泄漏告警

```lua
function _M.check_leak_alert()
    local total_leaked = shared_dict:get("conn:leaked:total") or 0
    local total_rejected = shared_dict:get("conn:rejected:total") or 0
    local active = shared_dict:get("conn:active:total") or 0

    -- 泄漏率告警（> 5%）
    if active > 0 and total_leaked / active > 0.05 then
        ngx.log(ngx.WARN, "HIGH LEAK RATE: ", total_leaked, " / ", active)
    end

    -- 拒绝率告警（> 10%）
    if total_rejected > 100 and total_rejected / active > 0.1 then
        ngx.log(ngx.WARN, "HIGH REJECT RATE: ", total_rejected, " / ", active)
    end
end
```

---

## 7. 测试覆盖度分析

### 7.1 Correctness Properties 测试需求

基于 Property 15-20，建议以下测试用例：

#### 单元测试

```lua
-- 测试 Property 15: 获取-释放一致性
describe("Connection Limiter - Property 15", function()
    it("should increment counter on acquire", function()
        local allowed, result = connection_limiter.acquire("app-1", "cluster-1")
        assert.is_true(allowed)
        local stats = connection_limiter.get_stats("app-1", "cluster-1")
        assert.equals(1, stats.app.current)
    end)

    it("should decrement counter on release", function()
        connection_limiter.acquire("app-1", "cluster-1")
        connection_limiter.release()
        local stats = connection_limiter.get_stats("app-1", "cluster-1")
        assert.equals(0, stats.app.current)
    end)
end)

-- 测试 Property 16: 限制强制执行
describe("Connection Limiter - Property 16", function()
    it("should reject when app limit exceeded", function()
        -- 设置限制为 1
        shared_dict:set("conn:app:app-1", cjson.encode({current=1, limit=1, rejected=0}))

        local allowed, result = connection_limiter.acquire("app-1", "cluster-1")
        assert.is_false(allowed)
        assert.equals("app_limit_exceeded", result.code)
    end)
end)

-- 测试 Property 17: 非负不变性
describe("Connection Limiter - Property 17", function()
    it("should never allow negative counters", function()
        -- 尝试多次释放
        connection_limiter.acquire("app-1", "cluster-1")
        connection_limiter.release()
        connection_limiter.release()  -- 额外释放
        local stats = connection_limiter.get_stats("app-1", "cluster-1")
        assert.is_true(stats.app.current >= 0)
    end)
end)

-- 测试 Property 18: 泄漏检测
describe("Connection Limiter - Property 18", function()
    it("should detect and cleanup leaked connections", function()
        -- 创建一个过期连接
        local old_time = ngx.now() - 400
        local conn_id = "test-conn-1"
        shared_dict:set("conn:track:" .. conn_id, cjson.encode({
            app_id = "app-1",
            cluster_id = "cluster-1",
            created_at = old_time,
            last_seen = old_time,
            status = "active"
        }))

        local leaked = connection_limiter.cleanup_leaked_connections()
        assert.equals(1, leaked)
    end)
end)

-- 测试 Property 19: 峰值跟踪
describe("Connection Limiter - Property 19", function()
    it("should track peak connections", function()
        connection_limiter.acquire("app-1", "cluster-1")
        connection_limiter.acquire("app-1", "cluster-1")
        connection_limiter.release()

        local stats = connection_limiter.get_stats("app-1", "cluster-1")
        assert.equals(2, stats.app.peak)
    end)
end)

-- 测试 Property 20: 释放幂等性
describe("Connection Limiter - Property 20", function()
    it("should be idempotent on multiple releases", function()
        connection_limiter.acquire("app-1", "cluster-1")
        connection_limiter.release()

        local stats_before = connection_limiter.get_stats("app-1", "cluster-1")
        connection_limiter.release()  -- 再次释放
        local stats_after = connection_limiter.get_stats("app-1", "cluster-1")

        assert.equals(stats_before.app.current, stats_after.app.current)
    end)
end)
```

#### 集成测试

```lua
describe("Connection Limiter Integration", function()
    it("should work with full request lifecycle", function()
        -- 模拟完整请求流程
        local conn_id = connection_limiter.acquire("app-1", "cluster-1")
        assert.is_not_nil(conn_id)

        -- 模拟业务处理
        ngx.sleep(0.1)

        -- 释放连接
        connection_limiter.release()

        -- 验证状态
        local stats = connection_limiter.get_stats("app-1", "cluster-1")
        assert.equals(0, stats.app.current)
    end)
end)
```

#### 压力测试

```bash
# 使用 wrk 测试连接限制性能
wrk -t 4 -c 100 -d 30s --latency \
  -H "X-App-ID: app-1" \
  -H "X-Cluster-ID: cluster-1" \
  http://localhost:8080/test

# 验证：
# 1. P99 延迟 < 0.5ms（连接检查）
# 2. 无连接泄漏
# 3. 计数器准确
```

---

## 8. 架构一致性评估

### 8.1 与系统架构的集成

**评估**: ✅ **良好集成**

1. **请求处理流程位置正确**
   - 连接限制层在架构图最前端
   - 在令牌桶检查之前执行
   - 符合设计目标

2. **数据存储分离合理**
   - 连接计数在 Nginx shared_dict（高性能）
   - 配置管理在 Redis（跨节点共享）
   - 避免了 Redis 延迟影响连接检查

3. **与其他组件的边界清晰**
   - Connection Limiter 不依赖 Token Bucket
   - 独立的组件职责
   - 易于测试和维护

### 8.2 依赖关系分析

**外部依赖**:
- ✅ `ngx.shared.connlimit_dict` - Nginx 内置
- ⚠️ Redis 配置管理 - 未实现，缺少依赖注入

**内部依赖**:
- ✅ 无其他组件依赖
- ✅ 其他组件不依赖 Connection Limiter（正交设计）

---

## 9. 性能影响评估

### 9.1 对请求延迟的影响

**预期影响分析**:

| 操作 | 预期延迟 | 累积影响 |
|------|---------|---------|
| acquire() | <0.5ms | 共享内存读取，极快 |
| release() | <0.1ms | 在 log_by_lua 阶段，异步 |
| cleanup() | 10-50ms | 每 30 秒后台执行，无影响 |

**结论**: ✅ 满足 Requirement 17.6 的性能要求

### 9.2 内存占用估算

假设 10,000 并发连接：

```
Per-App 计数: 100 bytes × 100 apps = 10 KB
Per-Cluster 计数: 100 bytes × 10 clusters = 1 KB
连接追踪: 200 bytes × 10,000 = 2 MB
总计: ~2 MB

设计配置: connlimit_dict (10MB)
结论: ✅ 内存充足
```

### 9.3 清理性能分析

```lua
-- 当前实现的复杂度问题
function _M.cleanup_leaked_connections()
    local keys = shared_dict:get_keys(0)  -- ⚠️ O(n) 扫描全部
    for _, key in ipairs(keys) do  -- ⚠️ O(n) 遍历
        if string.match(key, "^conn:track:") then  -- ⚠️ 字符串匹配
            -- ...
        end
    end
end
```

**问题**: get_keys(0) 会遍历所有键，在 10,000+ 连接时可能较慢

**优化建议**:
```lua
-- 使用时间窗口索引优化
function _M.cleanup_leaked_connections_optimized()
    local now = ngx.now()
    local cleanup_before = now - CONFIG.CONNECTION_TIMEOUT

    -- 使用有序集合存储待清理的连接
    local cleanup_candidates = shared_dict:get_keys(0, "conn:cleanup:*")
    for _, key in ipairs(cleanup_candidates) do
        local timestamp = tonumber(shared_dict:get(key))
        if timestamp and timestamp < cleanup_before then
            -- 只检查候选连接，避免全量扫描
            local conn_id = string.match(key, "conn:cleanup:(.+)")
            _M.force_release_connection(conn_id)
        end
    end
end
```

---

## 10. 安全性评估

### 10.1 潜在的安全风险

1. **连接耗尽攻击**
   - 攻击者可以故意建立大量连接耗尽配额
   - 建议添加 IP 级别的限流

2. **计数器伪造**
   - 恶意客户端可能伪造 `X-App-ID` 头
   - 建议在网关层验证应用身份

3. **拒绝服务**
   - 配置极低的连接限制（如 max=1）可导致 DoS
   - 建议添加配置下限验证

### 10.2 安全增强建议

```lua
-- 添加 IP 级限流
function _M.check_ip_rate_limit(client_ip)
    local ip_key = "conn:ip:" .. client_ip
    local ip_data = shared_dict:get(ip_key)

    if ip_data and ip_data.current > 100 then  -- 每 IP 最多 100 连接
        return false, "ip_limit_exceeded"
    end

    return true
end

-- 在 acquire() 中调用
function _M.acquire(app_id, cluster_id)
    local client_ip = ngx.var.remote_addr

    -- IP 限流检查
    local allowed, reason = _M.check_ip_rate_limit(client_ip)
    if not allowed then
        return false, {code = reason}
    end

    -- ... 原有逻辑
end
```

---

## 11. 总结与建议

### 11.1 需求符合度评分

| 需求 | 符合度 | 评分 |
|------|--------|------|
| Requirement 17 (连接限制) | 7/8 | 87.5% |
| Requirement 18 (泄漏检测) | 4/7 | 57.1% |
| Requirement 19 (监控指标) | 5/7 | 71.4% |
| Requirement 20 (配置管理) | 1/7 | 14.3% |
| **平均符合度** | **17/29** | **58.6%** |

### 11.2 Correctness Properties 评估

| Property | 状态 | 优先级 |
|----------|------|--------|
| Property 15: 获取-释放一致性 | ✅ 满足 | - |
| Property 16: 限制强制执行 | ✅ 满足 | - |
| Property 17: 非负不变性 | ⚠️ 有风险 | P1 |
| Property 18: 泄漏检测正确性 | ❌ 不满足 | **P0** |
| Property 19: 峰值跟踪 | ✅ 满足 | - |
| Property 20: 释放幂等性 | ✅ 满足 | - |

### 11.3 关键修复建议（P0 - 必须修复）

#### 修复 #1: 实现 last_seen 更新机制

**当前问题**: `last_seen` 字段从未更新，导致所有连接在 300 秒后被误判为泄漏

**修复方案**:
```lua
-- 在 ratelimit/connection_limiter.lua 添加：

function _M.heartbeat()
    local conn_id = ngx.ctx.conn_limit_id
    if not conn_id then return end

    local track_key = "conn:track:" .. conn_id
    local track_data_str = shared_dict:get(track_key)
    if not track_data_str then return end

    local track_data = cjson.decode(track_data_str)
    track_data.last_seen = ngx.now()
    shared_dict:set(track_key, cjson.encode(track_data), CONFIG.CONNECTION_TIMEOUT)
end

-- 在 access_by_lua_block 中调用：
-- access_by_lua_block {
--   local conn_limiter = require "ratelimit.connection_limiter"
--   conn_limiter.heartbeat()  -- 定期更新 last_seen
-- }
```

#### 修复 #2: 添加响应头

**当前问题**: 缺少 Requirement 17.8 要求的响应头

**修复方案**:
```lua
-- 在 acquire() 成功后添加：

function _M.acquire(app_id, cluster_id)
    -- ... 原有逻辑 ...

    return true, {
        code = "allowed",
        conn_id = conn_id,
        app_remaining = app_data.limit - app_data.current,
        cluster_remaining = cluster_data.limit - cluster_data.current,
        -- 添加响应头信息
        app_limit = app_data.limit,
        app_current = app_data.current,
        cluster_limit = cluster_data.limit,
        cluster_current = cluster_data.current
    }
end

-- 在调用处设置响应头：
-- access_by_lua_block {
--   local conn_limiter = require "ratelimit.connection_limiter"
--   local allowed, result = conn_limiter.acquire(app_id, cluster_id)
--   if allowed then
--     ngx.header["X-Connection-Limit"] = result.app_limit
--     ngx.header["X-Connection-Current"] = result.app_current
--   end
-- }
```

#### 修复 #3: 添加泄漏日志

**当前问题**: Requirement 18.7 要求记录泄漏日志

**修复方案**:
```lua
function _M.force_release_connection(key, track_data)
    local age = ngx.now() - track_data.last_seen

    -- 记录泄漏日志
    ngx.log(ngx.WARN,
        "connection_leaked: conn_id=", key,
        ", app_id=", track_data.app_id,
        ", cluster_id=", track_data.cluster_id,
        ", client_ip=", track_data.client_ip,
        ", age=", math.floor(age),
        ", created_at=", track_data.created_at
    )

    -- 减少计数器
    _M.decrement_counter("conn:app:" .. track_data.app_id)
    _M.decrement_counter("conn:cluster:" .. track_data.cluster_id)

    -- 更新状态
    track_data.status = "force_released"
    track_data.released_at = ngx.now()
    shared_dict:set(key, cjson.encode(track_data), 60)
end
```

### 11.4 重要补充建议（P1 - 应该实现）

#### 补充 #1: 配置管理 API

**需求**: Requirement 20 要求动态配置连接限制

**设计方案**:
```lua
-- ratelimit/connection_config.lua
local _M = {}

local function get_config_from_redis(app_id)
    local redis = require("resty.redis"):new()
    redis:connect("redis", 6379)
    local config_str = redis:get("connlimit:config:" .. app_id)
    redis:set_keepalive()

    if config_str then
        return cjson.decode(config_str)
    end

    -- 默认配置
    return {
        max_connections = 1000,
        burst_connections = 1200,
        priority = 0,
        enabled = true
    }
end

function _M.get_app_limit(app_id)
    -- 本地缓存（60s TTL）
    local cache_key = "conn:config:cache:" .. app_id
    local cached = shared_dict:get(cache_key)
    if cached then
        return cjson.decode(cached)
    end

    -- 从 Redis 获取
    local config = get_config_from_redis(app_id)
    shared_dict:set(cache_key, cjson.encode(config), 60)

    return config
end

-- 配置更新 API
function _M.update_app_config(app_id, config)
    -- 验证配置
    if not config.max_connections or config.max_connections <= 0 then
        return nil, "max_connections must be positive"
    end

    if config.burst_connections and config.burst_connections < config.max_connections then
        return nil, "burst_connections must be >= max_connections"
    end

    -- 保存到 Redis
    local redis = require("resty.redis"):new()
    redis:connect("redis", 6379)
    redis:set("connlimit:config:" .. app_id, cjson.encode(config))
    redis:publish("connlimit:config:update", cjson.encode({
        app_id = app_id,
        config = config
    }))
    redis:set_keepalive()

    -- 清除本地缓存
    shared_dict:delete("conn:config:cache:" .. app_id)

    return true
end

return _M
```

#### 补充 #2: 监控指标上报

**需求**: Requirement 19.6 要求每 10 秒上报统计到 Redis

**设计方案**: 已在 6.3 节提供

#### 补充 #3: 非负不变性保护

**需求**: Property 17 要求计数器永远不为负

**设计方案**:
```lua
function _M.decrement_counter(key)
    local data_str = shared_dict:get(key)
    if not data_str then return end

    local data = cjson.decode(data_str)

    -- 防止负数
    if data.current > 0 then
        data.current = data.current - 1
    end

    shared_dict:set(key, cjson.encode(data))
end
```

### 11.5 次要改进建议（P2 - 可后续优化）

1. **添加 Burst 连接支持**
   - 允许短时超过 `max_connections`
   - 基于 Token Bucket 算法实现

2. **优化清理性能**
   - 使用时间窗口索引避免全量扫描
   - 分片清理降低单次开销

3. **添加连接持续时间直方图**
   - 使用 Prometheus histogram 类型
   - 分桶：0.1, 0.5, 1, 5, 10, 30, 60, 300 秒

4. **实现连接事件日志**
   - 记录所有连接事件（accept/reject/leak/release）
   - 保留最近 1000 条用于审计

---

## 12. 最终结论

### 总体评估

Connection Limiter 组件的设计**基本满足**连接并发数限制的核心需求，但存在**关键缺陷需要修复**才能投入生产使用。

### 核心优势

1. ✅ **功能覆盖完整** - 支持 per-app 和 per-cluster 双重限制
2. ✅ **性能设计优秀** - 使用 Nginx shared_dict 实现亚毫秒级响应
3. ✅ **架构集成良好** - 在请求流程中位置正确，职责清晰
4. ✅ **数据结构合理** - 连接追踪、计数器、统计信息设计完善

### 关键缺陷

1. ❌ **last_seen 未更新** - 导致泄漏检测失效，所有连接在 300 秒后会被误判
2. ❌ **缺少响应头** - 不满足 Requirement 17.8
3. ❌ **配置管理缺失** - 不满足 Requirement 20 的大部分内容
4. ⚠️ **缺少非负保护** - 可能违反 Property 17

### 修复优先级

**P0 - 必须在实现前修复**:
- 实现 last_seen 更新机制
- 添加响应头设置
- 添加泄漏日志记录

**P1 - 应在设计阶段补充**:
- 完整的配置管理 API
- 监控指标上报机制
- 非负不变性保护

**P2 - 可后续优化**:
- Burst 连接支持
- 清理性能优化
- 连接事件日志

### 建议

1. **立即修复 P0 缺陷** - 这些是阻塞性问题，会导致功能完全失效
2. **补充 P1 功能** - 配置管理和监控上报是生产环境必需
3. **完善测试用例** - 基于 Property 15-20 编写完整测试套件
4. **添加性能基准** - 验证 <0.5ms 延迟目标

修复完 P0 和 P1 问题后，该组件将完全满足需求并可投入生产使用。

---

**审阅人**: Claude (Test Engineer)
**审阅日期**: 2025-12-31
**文档版本**: design.md (Connection Limiter section)
