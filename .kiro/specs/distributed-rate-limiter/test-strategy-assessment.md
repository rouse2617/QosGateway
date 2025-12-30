# 分布式三层令牌桶限流系统测试策略评估报告

**评估日期**: 2025-12-31
**评估对象**: C:\Users\hrp\code\nginx\.kiro\specs\distributed-rate-limiter\tasks.md
**评估范围**: 测试覆盖度、测试类型、测试工具、测试数据、改进建议
**评估人**: Test Engineer Specialist

---

## 执行摘要

### 总体评分: 7.5/10

**优势**:
- 清晰的属性测试(Property 1-20)定义，覆盖核心功能
- 合理的Checkpoint验证机制
- 测试工具选择务实(busted + lua-quickcheck)
- 标记可选测试任务，支持MVP快速交付

**关键改进领域**:
- 集成测试覆盖不足(仅5%)
- 缺少端到端测试场景
- 性能测试策略不完整
- 并发测试用例不充分
- 测试数据管理策略缺失

---

## 1. 测试覆盖度评估

### 1.1 单元测试覆盖度分析

#### 当前状态

| 模块 | 属性测试覆盖 | 测试数量 | 覆盖度评估 |
|------|-------------|---------|-----------|
| Cost Calculator | Property 1 | 1 | **不足** (需要至少8个测试) |
| L3 Bucket | Properties 2, 10, 12 | 3 | **不足** (需要至少12个测试) |
| L2 Bucket | Properties 3, 4 | 2 | **不足** (需要至少10个测试) |
| Borrow Manager | Properties 5, 13 | 2 | **不足** (需要至少8个测试) |
| Emergency Manager | Property 6 | 1 | **不足** (需要至少6个测试) |
| Reconciler | Properties 7, 14 | 2 | **不足** (需要至少8个测试) |
| Connection Limiter | Properties 15-20 | 6 | **中等** (需要至少15个测试) |
| Reservation Manager | Properties 8, 9 | 2 | **不足** (需要至少6个测试) |
| Config Validator | Property 11 | 1 | **不足** (需要至少5个测试) |

**问题识别**:
1. **属性测试密度过低**: 20个属性测试覆盖9个模块，平均每个模块仅2.2个测试
2. **边界条件测试缺失**: 未明确测试零值、最大值、溢出等边界场景
3. **错误路径测试不足**: 仅关注正常流程，缺少异常处理验证
4. **并发安全性测试缺失**: L3 shared dict、Redis Lua脚本的原子性未验证

#### 建议补充的单元测试

```lua
-- 1. Cost Calculator 边界测试
describe("Cost Calculator - Boundary Cases", function()
  it("should handle zero body size", function()
    local cost = cost_calculator.calculate("GET", 0)
    assert.equals(1, cost)  -- 仅 C_base
  end)

  it("should cap at MAX_COST", function()
    local cost = cost_calculator.calculate("PUT", 10000000000)
    assert.equals(1000000, cost)
  end)

  it("should handle exact quantum boundary (65536 bytes)", function()
    local cost = cost_calculator.calculate("GET", 65536)
    assert.equals(2, cost)  -- 1 + 1*1
  end)

  it("should handle quantum+1 boundary (65537 bytes)", function()
    local cost = cost_calculator.calculate("GET", 65537)
    assert.equals(3, cost)  -- 1 + ceil(65537/65536)*1 = 1+2
  end)
end)

-- 2. L3 Bucket 并发测试
describe("L3 Bucket - Concurrent Access", function()
  it("should handle 100 concurrent acquire operations safely", function()
    local threads = {}
    for i = 1, 100 do
      threads[i] = ngx.thread.spawn(function()
        return l3_bucket.acquire("app1", 10)
      end)
    end

    local success_count = 0
    for _, thread in ipairs(threads) do
      local ok, result = ngx.thread.wait(thread)
      if ok and result.success then
        success_count = success_count + 1
      end
    end

    -- 验证总扣减正确
    local final_tokens = l3_bucket.get_tokens("app1")
    assert.equals(1000 - success_count * 10, final_tokens)
  end)
end)

-- 3. Connection Limiter 泄漏检测测试
describe("Connection Limiter - Leak Detection", function()
  it("should detect and cleanup leaked connections", function()
    -- 模拟连接泄漏
    local conn_id = connection_limiter.acquire("app1", "cluster1")
    connection_limiter.simulate_leak(conn_id)  -- 不调用 release

    -- 快进时间超过超时阈值
    mock_time.advance(301)

    -- 触发清理
    local leaked = connection_limiter.cleanup_leaked_connections()
    assert.equals(1, leaked)

    -- 验证计数器已修正
    local stats = connection_limiter.get_stats("app1", "cluster1")
    assert.equals(0, stats.app.current)
  end)
end)
```

### 1.2 集成测试覆盖度分析

#### 当前状态

| 集成场景 | 覆盖状态 | 测试任务编号 |
|---------|---------|-------------|
| L3 <-> L2 令牌同步 | **缺失** | - |
| L2 <-> L1 借用流程 | **缺失** | - |
| 三层协同限流 | **缺失** | - |
| Redis Lua 脚本原子性 | **缺失** | - |
| Nginx shared dict 并发 | **缺失** | - |
| 配置热更新传播 | **缺失** | - |
| 降级策略触发 | **缺失** | - |
| 对账机制修正 | **缺失** | - |

**问题识别**:
1. **任务文档中集成测试完全缺失**: 所有属性测试都是单元级别
2. **三层协同场景未验证**: L1/L2/L3联合工作流程未测试
3. **分布式一致性问题**: 未测试多Nginx节点场景下的令牌分配

#### 建议补充的集成测试

```lua
-- 集成测试 1: 三层令牌桶协同流程
describe("Three-Layer Token Bucket Integration", function()
  it("should correctly deduct tokens across L1->L2->L3", function()
    -- 初始化: L1=100000, L2=10000, L3=1000
    setup_three_layers()

    -- 请求消耗 100 令牌
    local result = rate_limiter.check("app1", "user1", "cluster1", 100)

    assert.is_true(result.allowed)

    -- 验证: L3 扣减 100
    assert.equals(900, l3_bucket.get_tokens("app1"))

    -- 触发批量同步到 L2
    l3_bucket.sync_pending("app1")
    assert.equals(9900, l2_bucket.get_tokens("app1"))  -- 10000 - 100

    -- 验证 L1 未受影响(未触发借用)
    assert.equals(100000, l1_allocator.get_available("cluster1"))
  end)

  it("should trigger borrowing when L2 exhausted", function()
    setup_three_layers({
      l1 = 100000,
      l2_guaranteed = 1000,
      l2_burst = 2000,
      l3 = 500
    })

    -- 消耗完 L2 配额
    consume_tokens("app1", 2000)  -- burst_quota

    -- 再次请求应该触发借用
    local result = rate_limiter.check("app1", "user1", "cluster1", 100)
    assert.is_true(result.allowed)
    assert.equals("borrowed", result.source)

    -- 验证 L1 扣减和债务记录
    assert.equals(100000 - 100, l1_allocator.get_available("cluster1"))
    assert.equals(120, l2_bucket.get_debt("app1"))  -- 100 + 20%利息
  end)
end)

-- 集成测试 2: Redis Lua 脚本原子性
describe("Redis Lua Script Atomicity", function()
  it("should ensure atomic three-layer deduction", function()
    local app_id = "atomic_test"
    redis_client.hset(app_id, "current_tokens", 1000)

    -- 并发执行 100 次扣减，每次 10 令牌
    local threads = {}
    for i = 1, 100 do
      threads[i] = ngx.thread.spawn(function()
        return l2_bucket.acquire_atomic(app_id, 10)
      end)
    end

    -- 等待所有线程完成
    local total_acquired = 0
    for _, thread in ipairs(threads) do
      local ok, result = ngx.thread.wait(thread)
      if ok and result.success then
        total_acquired = total_acquired + 10
      end
    end

    -- 验证原子性: 最终值应该是 1000 - total_acquired
    local final_tokens = redis_client.hget(app_id, "current_tokens")
    assert.equals(1000 - total_acquired, tonumber(final_tokens))
  end)
end)
```

### 1.3 端到端测试覆盖度分析

#### 当前状态

| E2E 场景 | 覆盖状态 | 优先级 |
|---------|---------|-------|
| 正常请求完整流程 | **缺失** | P0 |
| 紧急模式激活与恢复 | **缺失** | P0 |
| Redis 故障降级 | **缺失** | P0 |
| 连接限制触发与恢复 | **缺失** | P0 |
| 多应用隔离验证 | **缺失** | P1 |
| 配置热更新端到端 | **缺失** | P1 |
| 对账机制修正演示 | **缺失** | P1 |

**问题识别**:
1. **任务文档中E2E测试完全缺失**: Checkpoint 26仅要求"确保所有测试通过"
2. **用户视角验证不足**: 未从客户端角度验证完整请求生命周期
3. **故障恢复流程未测试**: 紧急模式、降级、恢复的端到端场景缺失

#### 建议补充的E2E测试

```javascript
// E2E 测试 1: 正常请求完整流程 (k6)
import http from 'k6/http';
import { check } from 'k6';

export default function() {
  // 1. 发送请求到 Nginx
  let res = http.post('http://localhost/api/v1/objects', JSON.stringify({
    size: 1048576  // 1MB
  }), {
    headers: {
      'X-App-Id': 'test-app',
      'X-User-Id': 'user1',
      'X-Cluster-Id': 'cluster1',
      'Content-Type': 'application/json'
    }
  });

  // 2. 验证响应状态
  check(res, {
    'status is 200': (r) => r.status === 200,
    'has rate limit headers': (r) =>
      r.headers['X-RateLimit-Cost'] &&
      r.headers['X-RateLimit-Remaining'],
    'has connection headers': (r) =>
      r.headers['X-Connection-Limit'] &&
      r.headers['X-Connection-Current'],
    'cost is correct': (r) => {
      // PUT 1MB = 5 + ceil(1048576/65536) * 1 = 5 + 16 = 21
      return parseInt(r.headers['X-RateLimit-Cost']) === 21;
    }
  });

  // 3. 验证令牌已扣减(通过 Redis)
  let redis = Redis.connect('redis://localhost:6379');
  let l3_tokens = redis.get('app:test-app:tokens');
  let l2_tokens = redis.hget('app:test-app', 'current_tokens');

  check(res, {
    'L3 tokens deducted': () => l3_tokens < 1000,
    'L2 tokens synced': () => l2_tokens < 10000
  });
}

// E2E 测试 2: Redis 故障降级流程
import { Redis } from 'k6/experimental/redis';

export function testRedisFailover() {
  // 1. 正常请求
  let res1 = http.get('http://localhost/api/v1/objects', {
    headers: { 'X-App-Id': 'test-app' }
  });
  check(res1, { 'normal request OK': (r) => r.status === 200 });

  // 2. 模拟 Redis 故障
  exec.command('docker-stop redis');

  // 3. 验证进入 Fail-Open 模式
  let res2 = http.get('http://localhost/api/v1/objects', {
    headers: { 'X-App-Id': 'test-app' }
  });
  check(res2, {
    'fail-open allows request': (r) => r.status === 200,
    'response indicates degradation': (r) =>
      r.headers['X-RateLimit-Mode'] === 'fail_open'
  });

  // 4. 恢复 Redis
  exec.command('docker-start redis');

  // 5. 等待自动恢复
  sleep(5);

  // 6. 验证恢复正常模式
  let res3 = http.get('http://localhost/api/v1/objects', {
    headers: { 'X-App-Id': 'test-app' }
  });
  check(res3, {
    'recovered to normal': (r) =>
      r.headers['X-RateLimit-Mode'] === 'normal'
  });
}

// E2E 测试 3: 紧急模式端到端
export function testEmergencyModeE2E() {
  // 1. 消耗集群到 95% 触发自动紧急模式
  for (let i = 0; i < 950; i++) {
    http.post('/admin/api/v1/apps/test1/consume', JSON.stringify({
      cost: 100
    }));
  }

  // 2. 验证紧急模式已激活
  let status = http.get('/admin/api/v1/emergency/status');
  check(status, {
    'emergency mode active': (r) =>
      JSON.parse(r.body).active === true
  });

  // 3. 验证 P0 请求通过
  let res_p0 = http.get('/api/v1/objects', {
    headers: { 'X-App-Id': 'critical-app' }  // P0
  });
  check(res_p0, { 'P0 allowed': (r) => r.status === 200 });

  // 4. 验证 P3 请求被拒绝
  let res_p3 = http.get('/api/v1/objects', {
    headers: { 'X-App-Id': 'low-priority-app' }  // P3
  });
  check(res_p3, { 'P3 rejected': (r) => r.status === 429 });
}
```

---

## 2. 测试类型分析

### 2.1 标记 * 的属性测试分析

#### 可跳测试评估

| 测试任务 | 标记 * | 建议处理 | 理由 |
|---------|--------|---------|------|
| 1.3 设置测试框架 | * | **不可跳过** | 测试基础设施是后续测试的前提 |
| 2.2 Cost Calculator 属性测试 | * | **不可跳过** | 核心算法，必须100%正确 |
| 4.5 L3 Bucket 属性测试 | * | **不可跳过** | 性能关键路径，并发安全性必须验证 |
| 7.3 L2 Bucket 属性测试 | * | **不可跳过** | Redis Lua 脚本原子性必须验证 |
| 10.4 Borrow Manager 属性测试 | * | **可延后** | 复杂功能，MVP可先实现基础借用 |
| 12.4 Emergency Manager 属性测试 | * | **可延后** | 紧急模式是高级功能，MVP可手动测试 |
| 13.4 Reconciler 属性测试 | * | **不可跳过** | 对账机制防止令牌泄漏，必须验证 |
| 15.9 Connection Limiter 属性测试 | * | **不可跳过** | 连接泄漏会导致资源耗尽 |
| 17.4 Reservation Manager 属性测试 | * | **可延后** | 预留功能MVP可不实现 |
| 18.4 Config Validator 属性测试 | * | **不可跳过** | 错误配置会导致生产事故 |

**结论**:
- **必须测试(不可跳过)**: 7/10 (70%)
- **可延后测试**: 3/10 (30%)
- **建议**: 重新评估标记 * 的合理性，核心功能测试不应标记为可选

### 2.2 Checkpoint 验证充分性评估

#### 当前 Checkpoint 分析

| Checkpoint | 验证内容 | 充分性 | 改进建议 |
|-----------|---------|-------|---------|
| CP3: Cost Calculator | "确保所有 Cost Calculator 测试通过" | **不足** | 增加: 公式正确性验证、性能基准测试 |
| CP5: L3 Bucket | "确保本地令牌扣减和回滚正确" | **不足** | 增加: 并发安全性测试、Fail-Open触发测试 |
| CP8: L2 Bucket | "验证 Redis Lua 脚本原子性" | **中等** | 增加: 脚本性能测试、集群拓扑变更测试 |
| CP11: Borrow Manager | "验证利息计算和还款顺序" | **不足** | 增加: 并发借用测试、max_borrow边界测试 |
| CP14: 核心限流功能 | "确保 L1/L2/L3 三层协同工作" | **不足** | 增加: 端到端请求流程测试、多节点场景 |
| CP16: Connection Limiter | "验证泄漏检测和清理功能" | **不足** | 增加: 长时间运行泄漏测试、幂等性测试 |
| CP19: 高级功能 | "验证端到端配置更新流程" | **不足** | 增加: Pub/Sub传播延迟测试、配置回滚测试 |
| CP24: 完整系统 | "确保所有模块集成正确" | **不足** | 增加: 完整E2E场景、故障注入测试 |
| CP26: 系统完整性 | "验证端到端限流流程" | **不足** | 增加: 生产环境仿真、压力测试 |

**建议的增强Checkpoint验证脚本**:

```bash
#!/bin/bash
# checkpoint_validation.sh

checkpoint_3_validate() {
  echo "=== Checkpoint 3: Cost Calculator Validation ==="

  # 1. 运行单元测试
  busted tests/unit/cost_calculator_spec.lua

  # 2. 验证所有 HTTP 方法的 C_base 值
  lua -e "
    local cost = require 'ratelimit.cost'
    assert(cost.calculate('GET', 0) == 1, 'GET C_base incorrect')
    assert(cost.calculate('PUT', 0) == 5, 'PUT C_base incorrect')
    assert(cost.calculate('DELETE', 0) == 2, 'DELETE C_base incorrect')
    assert(cost.calculate('LIST', 0) == 3, 'LIST C_base incorrect')
    print('All C_base values correct')
  "

  # 3. 验证 Cost 上限
  lua -e "
    local cost = require 'ratelimit.cost'
    assert(cost.calculate('PUT', 1e10) == 1000000, 'MAX_COST not enforced')
    print('MAX_COST enforcement correct')
  "

  # 4. 性能基准测试
  k6 run --vus 10 --duration 10s tests/performance/cost_calculation_bench.js
  # 验证 P99 < 1ms
}

checkpoint_14_validate() {
  echo "=== Checkpoint 14: Core Rate Limiting Validation ==="

  # 1. 三层协同测试
  busted tests/integration/three_layer_flow_spec.lua

  # 2. 端到端请求流程测试
  k6 run tests/e2e/happy_path_e2e.js

  # 3. 并发压力测试
  k6 run --vus 100 --duration 30s tests/performance/concurrent_load_k6.js

  # 4. 验证关键指标
  lua -e "
    local redis = require 'resty.redis'
    local red = redis:new()

    -- 验证 L1 = sum(L2)
    local l1_avail = red:get('cluster:capacity:available')
    local l2_apps = red:keys('app:*:current_tokens')
    local l2_total = 0
    for _, app_key in ipairs(l2_apps) do
      l2_total = l2_total + tonumber(red:get(app_key))
    end

    local drift = math.abs(l1_avail - l2_total)
    assert(drift < l1_avail * 0.05, 'Drift exceeds 5%: ' .. drift)
    print('Global reconciliation OK, drift: ' .. drift .. ' tokens')
  "
}

checkpoint_26_validate() {
  echo "=== Checkpoint 26: System Integrity Validation ==="

  # 1. 全量单元测试
  busted tests/unit/ --coverage

  # 2. 全量集成测试
  busted tests/integration/

  # 3. 端到端测试套件
  k6 run tests/e2e/*.js

  # 4. 性能回归测试
  k6 run tests/performance/regression_test.js

  # 5. 配置验证
  gixy /etc/nginx/nginx.conf
  lua scripts/validate_all_configs.lua

  # 6. 混沌测试(抽样)
  busted tests/ chaos/redis_failure_chaos_spec.lua

  # 7. 生产环境仿真
  k6 run --vus 1000 --duration 5m --scenario production_simulation \
    tests/e2e/production_like_load.js

  echo "=== All Checkpoints Passed ==="
}
```

### 2.3 性能测试覆盖度评估

#### 当前状态

| 性能测试类型 | 任务文档提及 | 详细设计 | 优先级 |
|------------|------------|---------|-------|
| 基准性能测试 | **缺失** | testing-framework-design.md 有提及 | P0 |
| 负载测试 | **缺失** | testing-framework-design.md 有提及 | P0 |
| 压力测试 | **缺失** | testing-framework-design.md 有提及 | P0 |
| 浸泡测试 | **缺失** | testing-framework-design.md 有提及 | P1 |
| 延迟测试 | **缺失** | testing-framework-design.md 有提及 | P0 |
| 并发测试 | **部分覆盖** | Connection Limiter 有部分 | P0 |

**问题识别**:
1. **任务文档中性能测试完全缺失**: 尽管design.md定义了性能目标(P99<10ms, 50k TPS)
2. **无性能回归检测机制**: 未定义性能基线和允许偏差范围
3. **缺少资源消耗监控**: 未测试内存、CPU、Redis连接数等资源指标

**建议补充的性能测试任务**:

```javascript
// 性能测试 1: 基准性能测试 (k6)
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '1m', target: 100 },   // Ramp up
    { duration: '3m', target: 100 },   // Stable load
    { duration: '1m', target: 0 },     // Ramp down
  ],
  thresholds: {
    'http_req_duration': [
      { threshold: 'p(50)<5', abortOnFail: false },   // P50 < 5ms
      { threshold: 'p(95)<10', abortOnFail: false },  // P95 < 10ms
      { threshold: 'p(99)<20', abortOnFail: true },   // P99 < 20ms (abort if fail)
    ],
    'http_req_failed': [
      { threshold: 'rate<0.01', abortOnFail: true },  // Error rate < 1%
    ],
  },
};

export default function() {
  let res = http.get('http://localhost/api/v1/objects', {
    headers: {
      'X-App-Id': 'perf-test-app',
      'X-User-Id': 'user' + __VU,
      'X-Cluster-Id': 'cluster1',
    }
  });

  check(res, {
    'status is 200': (r) => r.status === 200,
    'has rate limit headers': (r) => r.headers['X-RateLimit-Cost'],
  });

  sleep(1);
}

// 性能测试 2: 最大吞吐量测试 (wrk)
// wrk -t4 -c100 -d30s --latency -H "X-App-Id: perf-test" http://localhost/api/v1/objects
// 目标: 找到 P99 < 10ms 时的最大 TPS

// 性能测试 3: L3 缓存命中率测试
import { Redis } from 'k6/experimental/redis';

export function testCacheHitRate() {
  let redis = new Redis({
    addr: 'localhost:6379',
  });

  // 执行 10000 次请求
  for (let i = 0; i < 10000; i++) {
    http.get('/api/v1/objects', {
      headers: { 'X-App-Id': 'cache-test' }
    });
  }

  // 验证缓存命中率
  let l3_hits = redis.incr('app:cache-test:local_hits');
  let l2_fetches = redis.incr('app:cache-test:remote_fetches');

  let hit_rate = l3_hits / (l3_hits + l2_fetches);

  console.log(`L3 Cache Hit Rate: ${(hit_rate * 100).toFixed(2)}%`);

  if (hit_rate < 0.95) {
    throw new Error(`Cache hit rate below 95%: ${hit_rate}`);
  }
}

// 性能测试 4: Redis 延迟测试
import { check } from 'k6';
import redis from 'k6/experimental/redis';

export function testRedisLatency() {
  let client = new redis.Client({
    addr: 'localhost:6379',
  });

  let latencies = [];

  for (let i = 0; i < 1000; i++) {
    let start = new Date();
    client.get('app:test:tokens');
    let elapsed = new Date() - start;
    latencies.push(elapsed);
  }

  // 计算 P50/P95/P99
  latencies.sort((a, b) => a - b);
  let p50 = latencies[Math.floor(latencies.length * 0.5)];
  let p95 = latencies[Math.floor(latencies.length * 0.95)];
  let p99 = latencies[Math.floor(latencies.length * 0.99)];

  console.log(`Redis Latency - P50: ${p50}ms, P95: ${p95}ms, P99: ${p99}ms`);

  check({
    'redis_p50_under_1ms': () => p50 < 1,
    'redis_p95_under_5ms': () => p95 < 5,
    'redis_p99_under_10ms': () => p99 < 10,
  });
}

// 性能测试 5: 连接限制器延迟测试
export function testConnectionLimiterLatency() {
  let latencies = [];

  for (let i = 0; i < 10000; i++) {
    let start = new Date();

    let res = http.get('/api/v1/objects', {
      headers: {
        'X-App-Id': 'conn-test',
        'X-Cluster-Id': 'cluster1',
      }
    });

    let elapsed = new Date() - start;
    latencies.push(elapsed);

    if (res.status !== 200 && res.status !== 429) {
      throw new Error(`Unexpected status: ${res.status}`);
    }
  }

  latencies.sort((a, b) => a - b);
  let p99 = latencies[Math.floor(latencies.length * 0.99)];

  console.log(`Connection Limiter P99: ${p99}ms`);

  if (p99 > 0.5) {  // 目标: <0.5ms
    throw new Error(`Connection limiter too slow: ${p99}ms`);
  }
}
```

### 2.4 压力测试计划评估

#### 缺失的压力测试场景

| 压力场景 | 测试目标 | 验证点 | 优先级 |
|---------|---------|-------|-------|
| 最大 TPS 探测 | 找到系统极限 | P99<10ms 时的最大 TPS | P0 |
| 并发连接数限制 | 验证连接限制器 | 10k 并发连接不崩溃 | P0 |
| Redis 内存耗尽 | 验证降级策略 | OOM 时优雅降级 | P0 |
| 突发流量 | 验证 burst quota | 10倍流量突发处理 | P1 |
| 长时间运行 | 验证内存泄漏 | 24小时无内存泄漏 | P1 |
| 令牌桶耗尽 | 验证拒绝行为 | 正确返回 429 和 Retry-After | P0 |

**建议的压力测试脚本**:

```javascript
// 压力测试 1: 最大 TPS 探测
export function findMaxTPS() {
  let tps = 1000;
  let max_sustainable_tps = 0;

  while (tps <= 100000) {
    console.log(`Testing TPS: ${tps}`);

    let result = k6.run({
      vus: tps / 10,  // 每个VU 10 RPS
      duration: '30s',
      thresholds: {
        'http_req_duration{type:plain}': ['p(99)<10'],
      }
    });

    if (result.metrics.http_req_duration.values['p(99')] < 10) {
      max_sustainable_tps = tps;
      tps = tps * 1.2;  // 增加 20%
    } else {
      break;
    }
  }

  console.log(`Max sustainable TPS: ${max_sustainable_tps}`);

  if (max_sustainable_tps < 50000) {
    throw new Error(`Below target TPS: ${max_sustainable_tps} < 50000`);
  }
}

// 压力测试 2: Redis 内存耗尽测试
export function testRedisOOM() {
  // 1. 填充 Redis 到 90% 内存
  fillRedisMemory(0.9);

  // 2. 发送请求
  let res = http.get('/api/v1/objects', {
    headers: { 'X-App-Id': 'oom-test' }
  });

  // 3. 验证降级行为
  check(res, {
    'should not crash': (r) => r.status !== 500,
    'should return 429 or 200': (r) => [200, 429].includes(r.status),
    'should indicate degradation': (r) =>
      r.headers['X-RateLimit-Mode'] === 'fail_open' ||
      r.headers['X-RateLimit-Mode'] === 'degraded'
  });
}

// 压力测试 3: 10k 并发连接测试
export function test10kConcurrentConnections() {
  let clients = [];

  // 建立 10000 个并发连接
  for (let i = 0; i < 10000; i++) {
    let client = new http.Client();
    clients.push({
      client,
      request: client.asyncGet('/api/v1/objects', {
        headers: {
          'X-App-Id': 'concurrent-test',
          'X-Connection-Id': `conn-${i}`
        }
      })
    });
  }

  // 等待所有请求完成
  let responses = Promise.all(clients.map(c => c.request));

  // 验证
  let success = responses.filter(r => r.status === 200).length;
  let rejected = responses.filter(r => r.status === 429).length;
  let errors = responses.filter(r => r.status === 500).length;

  console.log(`Success: ${success}, Rejected: ${rejected}, Errors: ${errors}`);

  check({
    'no_server_errors': () => errors === 0,
    'proper_rejection': () => success + rejected === 10000,
  });
}
```

---

## 3. 测试工具评估

### 3.1 busted 框架适用性评估

#### 优势分析

| 特性 | 适用性 | 评分 |
|------|-------|------|
| BDD 风格语法 (describe/it) | ✅ 优秀 | 9/10 |
| OpenResty 集成 | ✅ 原生支持 | 10/10 |
| Mock/Stub 内置 | ✅ 方便 | 8/10 |
| 异步测试支持 | ✅ 必需 | 9/10 |
| CLI 友好 | ✅ CI/CD 集成好 | 9/10 |
| 覆盖率报告 | ✅ 支持 luacov | 8/10 |

#### 限制与建议

**限制**:
1. **并发测试能力弱**: busted 本身不支持多线程并发测试
   - **解决方案**: 使用 OpenResty 的 `ngx.thread.spawn`
2. **性能基准测试缺失**: busted 是功能测试框架，不适合性能测试
   - **解决方案**: 集成 `libk6` 或独立的 benchmark 工具
3. **混沌测试不支持**: 无故障注入能力
   - **解决方案**: 使用 Toxiproxy 或 Chaos Mesh

**配置建议**:

```lua
-- .busted.lua
return {
  _all = {
    coverage = true,
    lpath = "lua/?.lua;lua/?/init.lua;tests/?.lua",
  },
  unit = {
    coverage = true,
    exclude = {
      "tests/integration",
      "tests/e2e",
      "tests/performance",
    }
  },
  integration = {
    coverage = false,  -- 集成测试不计算覆盖率
  },
  performance = {
    -- 性能测试使用 k6，不在 busted 中运行
  }
}
```

### 3.2 lua-quickcheck 属性测试可行性

#### 当前任务文档中的使用

任务文档标记了 20 个属性测试(Property 1-20)，但未详细说明测试方法。

#### lua-quickcheck 可行性分析

| 属性测试类型 | lua-quickcheck 支持度 | 替代方案 |
|------------|---------------------|---------|
| Property 1: Cost 公式正确性 | ✅ 支持 | busted + 参数化测试 |
| Property 2: 令牌扣减一致性 | ⚠️ 部分支持 | 需要自定义 generator |
| Property 10: 本地令牌非负不变性 | ✅ 支持 | busted + 循环断言 |
| Property 15: 连接获取-释放一致性 | ⚠️ 有限支持 | 并发测试更合适 |

**问题识别**:
1. **lua-quickcheck 不成熟**: 相比 Haskell QuickCheck, Lua 生态的属性测试工具较弱
2. **Generator 编写复杂**: 需要为每个数据类型编写生成器
3. **并发属性测试困难**: 属性测试框架通常不支持并发场景

**建议策略**:

```lua
-- 方案 1: 使用 busted + 参数化测试 (推荐)
describe("Cost Calculator - Property Testing", function()
  -- Property 1: Cost 公式单调性 (body_size 增加，Cost 不减)
  it("should be monotonic with body_size", function()
    for method in pairs({"GET", "PUT", "POST", "DELETE"}) do
      for size = 0, 10000000, 65536 do
        local cost1 = cost_calculator.calculate(method, size)
        local cost2 = cost_calculator.calculate(method, size + 1)
        assert(cost2 >= cost1, string.format(
          "Cost not monotonic: %s(%d)=%d, %s(%d)=%d",
          method, size, cost1, method, size + 1, cost2
        ))
      end
    end
  end)

  -- Property 2: Cost 上限约束
  it("should never exceed MAX_COST", function()
    for i = 1, 1000 do
      local method = random_element({"GET", "PUT", "POST", "DELETE"})
      local size = math.random(0, 10000000000)
      local cost = cost_calculator.calculate(method, size)
      assert(cost <= 1000000, string.format(
        "Cost exceeds MAX_COST: %d for %s %d bytes", cost, method, size
      ))
    end
  end)
end)

-- 方案 2: 使用 lua-quickcheck (可选，高级场景)
local qc = require "quickcheck"

qc.property("token deduction never makes tokens negative",
  function(app_id, initial_tokens, cost)
    -- Setup
    l3_bucket.set_tokens(app_id, initial_tokens)

    -- Action
    local result = l3_bucket.acquire(app_id, cost)

    -- Assert
    local final_tokens = l3_bucket.get_tokens(app_id)
    return final_tokens >= 0, string.format("tokens negative: %d", final_tokens)
  end,
  qc.gen {
    app_id = qc.gen.string(8, 8),
    initial_tokens = qc.gen.int(0, 10000),
    cost = qc.gen.int(1, 1000)
  }
)
```

**建议**:
- **MVP 阶段**: 使用 busted + 参数化测试，简单直接
- **生产阶段**: 补充 lua-quickcheck 进行深度属性验证

### 3.3 Test::Nginx 集成测试适用性

#### Test::Nginx 分析

Test::Nginx (test-nginx) 是 OpenResty 官方的集成测试框架。

**优势**:
1. **真实 Nginx 环境**: 启动实际的 Nginx 进程测试
2. **HTTP 协议测试**: 完整测试请求/响应生命周期
3. **Perl 驱动**: 灵活的测试逻辑

**劣势**:
1. **Perl 依赖**: 需要 Perl 环境
2. **学习曲线**: Lua 开发者不熟悉 Perl
3. **启动慢**: 每次测试需要启动 Nginx

**评估结论**:
- **对于本项目**: **不推荐** 作为主要测试框架
- **理由**:
  - 任务文档使用 busted，保持一致性
  - Test::Nginx 适合 Nginx C 模块开发，对 Lua 模块过于重量级
  - 可以用 `busted + lua-resty-http` 替代

**替代方案**:

```lua
-- 使用 busted 进行集成测试
describe("Nginx Integration", function()
  local http = require "resty.http"

  local httpc

  before_each(function()
    httpc = http.new()
    assert(httpc:set_timeout(1000))
  end)

  it("should integrate with Nginx access_by_lua", function()
    -- 启动测试 Nginx 实例
    local nginx = test_nginx.start({
      lua_script = "access_by_lua_block { local ratelimit = require 'ratelimit'; ratelimit.check() }"
    })

    -- 发送请求
    local res, err = httpc:request_uri("http://localhost:1984/api/v1/objects", {
      method = "GET",
      headers = {
        ["X-App-Id"] = "test-app",
        ["X-User-Id"] = "user1",
        ["X-Cluster-Id"] = "cluster1",
      }
    })

    -- 验证响应
    assert.is_nil(err)
    assert.equals(200, res.status)
    assert.is_not_nil(res.headers["X-RateLimit-Cost"])

    -- 清理
    nginx:stop()
  end)
end)
```

### 3.4 wrk/vegeta 性能测试场景

#### wrk vs vegeta vs k6 对比

| 工具 | 优势 | 劣势 | 推荐场景 |
|------|------|------|---------|
| **wrk** | 极低开销，多线程 | 无内置阈值验证，无JS支持 | 基准TPS测试 |
| **vegeta** | 简单CLI，报告丰富 | 社区较小 | 持续负载测试 |
| **k6** | JS脚本，强大阈值，Grafana集成 | 资源开销稍大 | E2E+性能综合测试 |

**推荐方案**: **k6 为主，wrk 为辅**

**原因**:
1. k6 支持复杂场景(Redis故障、紧急模式、配置更新)
2. k6 阈值验证自动化集成CI/CD
3. wrk 用于快速基准验证

**性能测试场景覆盖**:

```javascript
// k6 场景 1: 基准负载测试
export let options = {
  scenarios: {
    constant_load: {
      executor: 'constant-vus',
      vus: 100,
      duration: '5m',
      gracefulStop: '30s',
    },
    ramp_up_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 100 },
        { duration: '2m', target: 500 },
        { duration: '2m', target: 1000 },
        { duration: '1m', target: 0 },
      ],
      gracefulStop: '30s',
    },
  },
  thresholds: {
    'http_req_duration{type:plain}': ['p(99)<20'],
    'http_req_failed': ['rate<0.05'],
  },
};

// wrk 场景 2: 快速基准测试
// wrk -t4 -c100 -d30s --latency -H "X-App-Id: bench" http://localhost/api/v1/objects
// 目标: 快速验证 P99 延迟

// k6 场景 3: 浸泡测试 (24小时)
export let options = {
  stages: [
    { duration: '5m', target: 100 },
    { duration: '23h50m', target: 100 },  // 稳定运行 24 小时
    { duration: '5m', target: 0 },
  ],
  thresholds: {
    'http_req_duration{type:plain}': ['p(99)<20'],  // 整个24小时内都要满足
  },
};

// 监控内存泄漏
export function teardown() {
  let mem_before = __ENV.MEM_BEFORE;
  let mem_after = getMemoryUsage();

  if (mem_after - mem_before > 100 * 1024 * 1024) {  // 100MB
    throw new Error(`Memory leak detected: ${mem_after - mem_before} bytes`);
  }
}
```

---

## 4. 测试数据设计

### 4.1 测试数据需求分析

#### 当前缺失

| 数据类型 | 任务文档 | 设计文档 | 评估 |
|---------|---------|---------|------|
| Cost 计算测试数据 | ❌ 缺失 | ✅ 有示例 | **不足** |
| 应用配额配置 | ❌ 缺失 | ✅ 有示例 | **不足** |
| 集群容量配置 | ❌ 缺失 | ✅ 有示例 | **不足** |
| 并发测试场景 | ❌ 缺失 | ❌ 缺失 | **严重缺失** |
| 异常场景数据 | ❌ 缺失 | ❌ 缺失 | **严重缺失** |
| 性能基准数据 | ❌ 缺失 | ❌ 缺失 | **严重缺失** |

### 4.2 边界条件测试用例

#### Cost Calculator 边界测试

```lua
-- tests/fixtures/cost_boundary_data.lua
local boundary_data = {
  -- 零值边界
  zero_body = {
    { method = "GET", size = 0, expected = 1 },
    { method = "PUT", size = 0, expected = 5 },
  },

  -- Quantum 边界 (65536 bytes)
  quantum_boundaries = {
    { method = "GET", size = 65535, expected = 1 },          -- 0 quantum
    { method = "GET", size = 65536, expected = 2 },          -- 1 quantum
    { method = "GET", size = 65537, expected = 3 },          -- 2 quantum
  },

  -- 最大值边界
  max_cost = {
    { method = "PUT", size = 1000000000, expected = 1000000 },  -- Capped
    { method = "PUT", size = 2^63 - 1, expected = 1000000 },    -- Max int
  },

  -- 负值边界 (异常输入)
  negative_input = {
    { method = "GET", size = -1, expected_error = "invalid_body_size" },
    { method = "GET", size = nil, expected = 1 },  -- nil = 0
  },

  -- 浮点数边界
  float_input = {
    { method = "GET", size = 65536.5, expected = 2 },  -- 向下取整
    { method = "GET", size = 65536.9, expected = 2 },
  },
}

describe("Cost Calculator - Boundary Tests", function()
  for _, test_case in ipairs(boundary_data.zero_body) do
    it(string.format("should handle zero body: %s", test_case.method), function()
      local cost = cost_calculator.calculate(test_case.method, test_case.size)
      assert.equals(test_case.expected, cost)
    end)
  end

  for _, test_case in ipairs(boundary_data.quantum_boundaries) do
    it(string.format("should handle quantum boundary: %d bytes", test_case.size), function()
      local cost = cost_calculator.calculate(test_case.method, test_case.size)
      assert.equals(test_case.expected, cost)
    end)
  end

  for _, test_case in ipairs(boundary_data.max_cost) do
    it("should cap at MAX_COST", function()
      local cost = cost_calculator.calculate(test_case.method, test_case.size)
      assert.equals(test_case.expected, cost)
    end)
  end
end)
```

#### Token Bucket 边界测试

```lua
-- tests/fixtures/token_boundary_data.lua
local token_boundary_data = {
  -- 空桶场景
  empty_bucket = {
    { current = 0, cost = 1, expected_success = false },
    { current = 0, cost = 0, expected_success = true },
  },

  -- 满桶场景
  full_bucket = {
    { current = 1000, cost = 1000, expected_success = true, remaining = 0 },
    { current = 1000, cost = 1001, expected_success = false },
  },

  -- 精确匹配场景
  exact_match = {
    { current = 100, cost = 100, expected_success = true, remaining = 0 },
  },

  -- Overflow 场景
  overflow = {
    { current = 2^63 - 1, cost = 1, expected_success = true },  -- Max int - 1
    { current = 100, cost = -1, expected_error = "invalid_cost" },
  },
}

describe("Token Bucket - Boundary Tests", function()
  for _, test_case in ipairs(token_boundary_data.empty_bucket) do
    it("should handle empty bucket", function()
      setup_bucket("test", test_case.current)
      local result = token_bucket.acquire("test", test_case.cost)

      if test_case.expected_success then
        assert.is_true(result.success)
      else
        assert.is_false(result.success)
      end
    end)
  end
end)
```

### 4.3 并发场景测试用例

#### 并发冲突场景

```lua
-- tests/fixtures/concurrent_scenarios.lua
local concurrent_scenarios = {
  -- 场景 1: 1000 个并发请求同时扣减
  thousand_concurrent_deduction = {
    initial_tokens = 10000,
    concurrent_requests = 1000,
    cost_per_request = 10,
    expected_total_deduction = 10000,  -- 不超过初始值
  },

  -- 场景 2: 100 个并发请求同时回滚
  hundred_concurrent_rollback = {
    initial_tokens = 1000,
    concurrent_rollback = 100,
    cost_per_rollback = 5,
    expected_final = 1500,  -- 1000 + 100*5
  },

  -- 场景 3: 并发扣减和回滚混合
  mixed_concurrent_operations = {
    initial_tokens = 10000,
    concurrent_deductions = 500,
    concurrent_rollbacks = 500,
    cost_deduction = 10,
    cost_rollback = 5,
    expect_no_negative = true,
  },

  -- 场景 4: 批量同步并发
  concurrent_batch_sync = {
    initial_tokens = 100000,
    concurrent_syncs = 100,
    pending_cost_per_sync = 1000,
    expected_l2_total = 100000,  -- sum of all syncs
  },
}

describe("Concurrent Scenarios", function()
  it("should handle 1000 concurrent deductions safely", function()
    local scenario = concurrent_scenarios.thousand_concurrent_deduction

    setup_bucket("app1", scenario.initial_tokens)

    local threads = {}
    for i = 1, scenario.concurrent_requests do
      threads[i] = ngx.thread.spawn(function()
        return token_bucket.acquire("app1", scenario.cost_per_request)
      end)
    end

    local success_count = 0
    for _, thread in ipairs(threads) do
      local ok, result = ngx.thread.wait(thread)
      if ok and result.success then
        success_count = success_count + 1
      end
    end

    -- 验证原子性: 总扣减不超过初始值
    local final_tokens = get_bucket_tokens("app1")
    local total_deduction = scenario.initial_tokens - final_tokens

    assert.equals(
      scenario.expected_total_deduction,
      total_deduction,
      string.format("Atomicity violation: deducted %d but initial was %d",
        total_deduction, scenario.initial_tokens)
    )
  end)

  it("should handle concurrent deductions and rollbacks", function()
    local scenario = concurrent_scenarios.mixed_concurrent_operations

    setup_bucket("app2", scenario.initial_tokens)

    local threads = {}

    -- 启动 500 个扣减线程
    for i = 1, scenario.concurrent_deductions do
      threads[i] = ngx.thread.spawn(function()
        return token_bucket.acquire("app2", scenario.cost_deduction)
      end)
    end

    -- 启动 500 个回滚线程
    for i = 1, scenario.concurrent_rollbacks do
      threads[500 + i] = ngx.thread.spawn(function()
        return token_bucket.rollback("app2", scenario.cost_rollback)
      end)
    end

    -- 等待所有线程
    for _, thread in ipairs(threads) do
      ngx.thread.wait(thread)
    end

    -- 验证不变性: 令牌数永远非负
    local final_tokens = get_bucket_tokens("app2")

    if scenario.expect_no_negative then
      assert.is_true(final_tokens >= 0,
        string.format("Token negative: %d", final_tokens))
    end
  end)
end)
```

#### Race Condition 场景

```lua
describe("Race Condition Tests", function()
  it("should prevent double-acquisition race", function()
    local app_id = "race_test"
    setup_bucket(app_id, 100)

    -- 两个线程同时尝试获取最后 100 个令牌
    local thread1 = ngx.thread.spawn(function()
      return token_bucket.acquire(app_id, 100)
    end)

    local thread2 = ngx.thread.spawn(function()
      return token_bucket.acquire(app_id, 100)
    end)

    local result1 = ngx.thread.wait(thread1)
    local result2 = ngx.thread.wait(thread2)

    -- 只有一个应该成功
    local success_count = 0
    if result1.success then success_count = success_count + 1 end
    if result2.success then success_count = success_count + 1 end

    assert.equals(1, success_count, "Race condition: both threads acquired")

    -- 验证令牌未超发
    local final_tokens = get_bucket_tokens(app_id)
    assert.equals(0, final_tokens)
  end)

  it("should prevent batch sync race", function()
    local app_id = "sync_race"
    setup_bucket(app_id, 0)

    -- 两个线程同时批量同步
    local thread1 = ngx.thread.spawn(function()
      return l3_bucket.sync_pending(app_id)
    end)

    local thread2 = ngx.thread.spawn(function()
      return l3_bucket.sync_pending(app_id)
    end)

    local result1 = ngx.thread.wait(thread1)
    local result2 = ngx.thread.wait(thread2)

    -- 验证只同步一次
    assert.is_true(result1.synced or result2.synced)
    assert.is_false(result1.synced and result2.synced, "Double sync detected")
  end)
end)
```

### 4.4 异常场景测试用例

#### 网络异常场景

```lua
describe("Network Failure Scenarios", function()
  it("should handle Redis connection timeout", function()
    -- 使用 Toxiproxy 模拟超时
    toxiproxy.create_proxy("redis", "6379", "26379")
    toxiproxy.add_toxic("redis", "timeout", {
      timeout = 5000  -- 5秒超时
    })

    local result = l3_bucket.acquire("app1", 100)

    -- 应该进入 Fail-Open 模式
    assert.is_true(result.success)
    assert.equals("fail_open", result.mode)

    -- 清理
    toxiproxy.remove_proxy("redis")
  end)

  it("should handle Redis connection reset", function()
    toxiproxy.create_proxy("redis", "6379", "26379")

    -- 建立连接
    local redis = redis_client:new()
    redis:connect("localhost", 26379)

    -- 中断连接
    toxiproxy.add_toxic("redis", "reset_peer", {})

    -- 验证自动重连
    local result = l3_bucket.acquire("app1", 100)

    -- 应该重试并成功或进入 Fail-Open
    assert.is_true(result.success or result.mode == "fail_open")

    toxiproxy.remove_proxy("redis")
  end)

  it("should handle partial Redis Cluster failure", function()
    -- Redis Cluster 有 3 master，关闭 1 个
    redis_cluster.stop_master(2)

    local result = l3_bucket.acquire("app1", 100)

    -- 应该降级但继续服务
    assert.is_true(result.success)
    assert.equals("degraded", result.mode)

    -- 恢复
    redis_cluster.start_master(2)
  end)
end)
```

#### 数据异常场景

```lua
describe("Data Corruption Scenarios", function()
  it("should handle Redis data type mismatch", function()
    local app_key = "app:data_mismatch"

    -- 设置错误的数据类型 (string 而不是 hash)
    redis_client:set(app_key, "invalid_data")

    local ok, err = pcall(function()
      return l2_bucket.acquire("data_mismatch", 100)
    end)

    -- 应该优雅处理错误
    assert.is_false(ok)
    assert.is_not_nil(err)
    assert.is_true(string.find(err, "data_type") ~= nil)
  end)

  it("should handle missing required fields", function()
    local app_key = "app:missing_fields"

    -- 创建不完整的 hash
    redis_client:hmset(app_key, {
      guaranteed_quota = 1000,
      -- 缺少 burst_quota 和 current_tokens
    })

    local result = l2_bucket.acquire("missing_fields", 100)

    -- 应该使用默认值
    assert.is_true(result.success)
    assert.is_not_nil(result.burst_quota)
  end)

  it("should handle invalid token values", function()
    local app_key = "app:invalid_tokens"

    -- 设置负数令牌
    redis_client:hset(app_key, "current_tokens", -100)

    local result = l2_bucket.acquire("invalid_tokens", 100)

    -- 应该检测并修正
    assert.is_false(result.success)
    assert.equals("invalid_state", result.reason)

    -- 触发修正后应该恢复
    reconciler.fix_app("invalid_tokens")
    local fixed_tokens = redis_client:hget(app_key, "current_tokens")
    assert.equals(0, tonumber(fixed_tokens))
  end)
end)
```

#### 资源耗尽场景

```lua
describe("Resource Exhaustion Scenarios", function()
  it("should handle Nginx shared dict full", function()
    local dict = ngx.shared.ratelimit

    -- 填充 shared dict 到 95%
    fill_shared_dict(dict, 0.95)

    local result = l3_bucket.acquire("app1", 100)

    -- 应该仍然工作
    assert.is_true(result.success)

    -- 验证驱逐策略生效
    local oldest_key = dict:get_keys(1)[1]
    dict:delete(oldest_key)
  end)

  it("should handle Redis OOM", function()
    -- 填充 Redis 到 95% 内存
    fill_redis_memory(0.95)

    local result = l3_bucket.acquire("app1", 100)

    -- 应该进入降级模式
    assert.is_true(result.success)
    assert.equals("degraded", result.mode)

    -- 清理
    flush_redis_test_data()
  end)

  it("should handle connection pool exhaustion", function()
    -- 限制 Redis 连接池大小为 10
    configure_redis_pool({ pool_size = 10 })

    local threads = {}
    for i = 1, 100 do
      threads[i] = ngx.thread.spawn(function()
        return l3_bucket.acquire("app1", 100)
      end)
    end

    -- 所有请求应该最终完成(可能等待)
    local success_count = 0
    for _, thread in ipairs(threads) do
      local ok, result = ngx.thread.wait(thread)
      if ok and result.success then
        success_count = success_count + 1
      end
    end

    assert.equals(100, success_count)
  end)
end)
```

---

## 5. 测试改进建议

### 5.1 建议补充的测试任务

#### 新增单元测试任务

在现有任务 1.3 之后添加:

```
- [ ] 1.4 实现边界条件测试套件
  - 实现 Cost Calculator 边界测试 (零值、最大值、量子边界)
  - 实现 Token Bucket 边界测试 (空桶、满桶、溢出)
  - 实现 Connection Limiter 边界测试 (零连接、最大连接)
  - _Requirements: All modules_

- [ ] 1.5 实现并发安全测试套件
  - 实现 L3 shared dict 并发测试
  - 实现 Redis Lua 脚本原子性测试
  - 实现多线程令牌扣减测试
  - _Requirements: 15.2, 15.4, 15.5_
```

#### 新增集成测试任务

在现有任务 24 之后添加:

```
- [ ] 24.1 三层令牌桶集成测试
  - 测试 L3 -> L2 -> L1 完整扣减流程
  - 测试批量同步机制
  - 测试借用流程
  - 测试对账修正机制
  - _Requirements: 2, 3, 4, 5, 7_

- [ ] 24.2 降级策略集成测试
  - 测试 Redis 延迟触发降级
  - 测试 Redis 故障触发 Fail-Open
  - 测试自动恢复机制
  - _Requirements: 11.1, 11.2, 11.3, 11.5_

- [ ] 24.3 配置管理集成测试
  - 测试配置热更新
  - 测试 Redis Pub/Sub 配置传播
  - 测试配置验证失败回滚
  - _Requirements: 10.5, 10.6, 16.5_
```

#### 新增端到端测试任务

在现有任务 26 之前添加:

```
- [ ] 25.6 实现端到端测试套件
  - 实现 k6 E2E 测试脚本
  - 实现正常请求完整流程测试
  - 实现紧急模式端到端测试
  - 实现故障恢复端到端测试
  - 实现多应用隔离验证
  - _Requirements: All integration requirements_

- [ ] 25.7 实现性能基准测试
  - 实现 P50/P95/P99 延迟基准
  - 实现 L3 缓存命中率验证
  - 实现 Redis 延迟基准测试
  - 实现 Connection Limiter 延迟基准
  - _Requirements: 8.3, 17.6, Performance targets_
```

### 5.2 建议的测试优先级

#### P0 测试 (MVP 必需)

| 测试类型 | 测试任务 | 理由 |
|---------|---------|------|
| 单元测试 | Property 1-20 | 核心算法正确性 |
| 边界测试 | 1.4 | 防止生产事故 |
| 并发测试 | 1.5 | 保证数据一致性 |
| 集成测试 | 24.1, 24.2 | 验证三层协同 |
| E2E 测试 | 25.6 (正常流程) | 用户视角验证 |
| 性能测试 | 25.7 (延迟基准) | 满足性能目标 |
| 配置验证 | 18.4, Gixy | 防止配置错误 |

**时间估算**: 约 20-25 人天

#### P1 测试 (生产必需)

| 测试类型 | 测试任务 | 理由 |
|---------|---------|------|
| 集成测试 | 24.3 (配置热更新) | 运维能力 |
| E2E 测试 | 25.6 (紧急模式、故障恢复) | 可靠性验证 |
| 性能测试 | 25.7 (最大 TPS) | 容量规划 |
| 压力测试 | 连接限制、Redis OOM | 极限场景 |
| 混沌测试 | Redis 故障、网络分区 | 故障恢复 |

**时间估算**: 约 15-20 人天

#### P2 测试 (增强优化)

| 测试类型 | 测试任务 | 理由 |
|---------|---------|------|
| 性能测试 | 浸泡测试 (24小时) | 内存泄漏检测 |
| 混沌测试 | Pod Kill、资源限制 | Kubernetes 场景 |
| 属性测试 | lua-quickcheck 深度验证 | 数学正确性 |

**时间估算**: 约 10-15 人天

### 5.3 CI/CD 集成建议

#### CI Pipeline 配置

```yaml
# .github/workflows/test.yml
name: Test Suite

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  # Job 1: 快速单元测试 (每次提交都跑)
  unit_tests:
    name: Unit Tests
    runs-on: ubuntu-latest
    timeout-minutes: 10

    steps:
      - uses: actions/checkout@v3

      - name: Setup OpenResty
        uses: actions/setup-openresty@v1
        with:
          openresty-version: '1.21.4'

      - name: Install dependencies
        run: |
          luarocks install busted
          luarocks install luacov
          luarocks install lua-redis
          luarocks install lua-resty-http

      - name: Run unit tests with coverage
        run: |
          busted tests/unit/ --coverage

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v3
        with:
          file: ./luacov.report.out

  # Job 2: 集成测试 (PR 时跑)
  integration_tests:
    name: Integration Tests
    runs-on: ubuntu-latest
    timeout-minutes: 20

    services:
      redis:
        image: redis:7-cluster
        ports:
          - 6379:6379

    steps:
      - uses: actions/checkout@v3

      - name: Setup OpenResty
        uses: actions/setup-openresty@v1

      - name: Install dependencies
        run: |
          luarocks install busted
          luarocks install lua-redis

      - name: Run integration tests
        run: busted tests/integration/
        env:
          REDIS_HOST: localhost
          REDIS_PORT: 6379

  # Job 3: E2E 测试 (合并到 main 前跑)
  e2e_tests:
    name: E2E Tests
    runs-on: ubuntu-latest
    timeout-minutes: 30

    services:
      nginx:
        image: openresty/openresty:1.21.4
        ports:
          - 80:80
      redis:
        image: redis:7-cluster
        ports:
          - 6379:6379

    steps:
      - uses: actions/checkout@v3

      - name: Setup k6
        run: |
          curl https://github.com/grafana/k6/releases/download/v0.45.0/k6-v0.45.0-linux-amd64.tar.gz -L | tar xvz
          sudo mv k6-v0.45.0-linux-amd64/k6 /usr/local/bin/

      - name: Deploy test environment
        run: |
          docker-compose up -d
          sleep 10  # Wait for services ready

      - name: Run E2E tests
        run: k6 run tests/e2e/*.js

      - name: Cleanup
        run: docker-compose down

  # Job 4: 性能回归测试 (每日跑)
  performance_tests:
    name: Performance Regression
    runs-on: ubuntu-latest
    timeout-minutes: 60

    # 只在 main 分支或 schedule 时运行
    if: github.ref == 'refs/heads/main' || github.event_name == 'schedule'

    steps:
      - uses: actions/checkout@v3

      - name: Setup OpenResty and k6
        run: |
          # Setup commands...

      - name: Run performance benchmarks
        run: |
          k6 run tests/performance/baseline_load_k6.js
          k6 run tests/performance/latency_bench.lua

      - name: Compare with baseline
        run: |
          python scripts/compare_performance.py \
            --current results.json \
            --baseline baseline.json \
            --threshold 5  # 5% regression threshold

      - name: Publish performance report
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: performance-report
          path: results/

  # Job 5: 配置验证 (每次提交)
  config_validation:
    name: Config Validation
    runs-on: ubuntu-latest
    timeout-minutes: 5

    steps:
      - uses: actions/checkout@v3

      - name: Install Gixy
        run: pip install gixy

      - name: Validate nginx.conf
        run: |
          gixy nginx/conf/nginx.conf

      - name: Validate Lua syntax
        run: |
          for file in lua/ratelimit/*.lua; do
            luac -p "$file"
          done
```

#### CD Pipeline 配置

```yaml
# .github/workflows/deploy.yml
name: Deploy to Production

on:
  push:
    tags:
      - 'v*'

jobs:
  # Pre-deployment 测试关卡
  pre_deployment_tests:
    name: Pre-deployment Tests
    runs-on: ubuntu-latest
    timeout-minutes: 60

    steps:
      - uses: actions/checkout@v3

      - name: Run full test suite
        run: |
          busted tests/unit/ tests/integration/
          k6 run tests/e2e/*.js

      - name: Run performance tests
        run: |
          k6 run tests/performance/regression_test.js

      - name: Run chaos tests (sampling)
        run: |
          busted tests/chaos/redis_failure_chaos_spec.lua

  # 金丝雀发布测试
  canary_test:
    name: Canary Deployment Test
    runs-on: ubuntu-latest
    needs: pre_deployment_tests
    timeout-minutes: 30

    steps:
      - name: Deploy canary (1% traffic)
        run: |
          kubectl apply -f k8s/canary.yaml

      - name: Monitor canary metrics
        run: |
          python scripts/monitor_canary.py \
            --duration 300 \
            --error_threshold 0.01 \
            --latency_p99_threshold 20

      - name: Promote to 100% or rollback
        run: |
          if [[ $CANARY_SUCCESS == "true" ]]; then
            kubectl apply -f k8s/production.yaml
          else
            kubectl rollout undo deployment/rate-limiter
            exit 1
          fi
```

#### 测试结果可视化

```python
# scripts/generate_test_report.py
import json
import matplotlib.pyplot as plt

def generate_test_report():
    # 读取测试结果
    with open('test_results.json') as f:
        results = json.load(f)

    # 生成覆盖率报告
    coverage = results['coverage']
    print(f"Code Coverage: {coverage['percent']}%")

    if coverage['percent'] < 90:
        print("WARNING: Coverage below 90%")

    # 生成性能报告
    performance = results['performance']
    plt.figure(figsize=(12, 6))

    # P99 延迟趋势
    plt.subplot(1, 2, 1)
    plt.plot(performance['p99_latency_history'])
    plt.title('P99 Latency Trend (ms)')
    plt.xlabel('Build')
    plt.ylabel('P99 (ms)')

    # TPS 趋势
    plt.subplot(1, 2, 2)
    plt.plot(performance['tps_history'])
    plt.title('Throughput Trend (TPS)')
    plt.xlabel('Build')
    plt.ylabel('TPS')

    plt.savefig('performance_trend.png')

    # 发布到 Slack
    if results['status'] == 'passed':
        slack.notify(
            text=f"✅ All tests passed\nCoverage: {coverage['percent']}%",
            attachments=['performance_trend.png']
        )
    else:
        slack.notify(
            text=f"❌ Tests failed\n{results['failures']} failures",
            severity='error'
        )
```

### 5.4 测试数据管理策略

#### 测试数据分层

```
tests/
├── fixtures/
│   ├── app_configs.lua           # 应用配额测试数据
│   ├── cluster_configs.lua       # 集群配置测试数据
│   ├── cost_profiles.lua         # Cost 计算测试数据
│   ├── boundary_data.lua         # 边界条件测试数据
│   ├── concurrent_scenarios.lua  # 并发场景测试数据
│   └── performance_baselines.json # 性能基线数据
│
├── factories/
│   ├── app_factory.lua           # 应用配置工厂
│   ├── request_factory.lua       # 请求工厂
│   └── token_factory.lua         # 令牌工厂
│
└── helpers/
    ├── test_data_generator.lua   # 测试数据生成器
    ├── test_data_loader.lua      # 测试数据加载器
    └── test_data_cleaner.lua     # 测试数据清理器
```

#### 测试数据生成器

```lua
-- tests/helpers/test_data_generator.lua
local test_data_generator = {}

function test_data_generator.random_app_config()
  return {
    app_id = random_string(8),
    guaranteed_quota = math.random(1000, 10000),
    burst_quota = function()
      local g = math.random(1000, 10000)
      return math.floor(g * math.random(1.5, 5))
    end,
    priority = math.random(0, 3),
    max_borrow = math.random(5000, 20000),
  }
end

function test_data_generator.random_request()
  local methods = {"GET", "PUT", "POST", "DELETE", "LIST"}
  return {
    method = methods[math.random(1, #methods)],
    body_size = math.random(0, 10485760),  -- 0-10MB
    app_id = random_string(8),
    user_id = random_string(8),
    cluster_id = random_string(8),
  }
end

function test_data_generator.boundary_requests()
  return {
    { method = "GET", body_size = 0 },           -- 零值
    { method = "GET", body_size = 65536 },       -- 1 quantum
    { method = "GET", body_size = 65537 },       -- quantum+1
    { method = "PUT", body_size = 1048576 },     -- 1MB
    { method = "PUT", body_size = 10000000000 }, -- 超大值
  }
end

return test_data_generator
```

#### 测试数据清理策略

```lua
-- tests/helpers/test_data_cleaner.lua
local test_data_cleaner = {}

function test_data_cleaner.cleanup_redis()
  local redis = require "resty.redis"
  local red = redis:new()

  -- 清理测试应用数据
  local test_apps = red:keys("app:test_*")
  for _, app_key in ipairs(test_apps) do
    red:del(app_key)
  end

  -- 清理测试集群数据
  local test_clusters = red:keys("cluster:test_*")
  for _, cluster_key in ipairs(test_clusters) do
    red:del(cluster_key)
  end

  -- 清理测试连接数据
  local test_conns = red:keys("conn:test_*")
  for _, conn_key in ipairs(test_conns) do
    red:del(conn_key)
  end
end

function test_data_cleaner.cleanup_shared_dict()
  local dict = ngx.shared.ratelimit

  -- 清理测试应用令牌
  local keys = dict:get_keys(0)  -- 获取所有键
  for _, key in ipairs(keys) do
    if string.match(key, "^app:test_") then
      dict:delete(key)
    end
  end
end

return test_data_cleaner
```

---

## 6. 总结与行动计划

### 6.1 关键发现总结

#### 严重问题 (必须修复)

1. **集成测试覆盖不足**: 任务文档中集成测试完全缺失
   - **影响**: 无法验证三层协同工作
   - **修复**: 补充任务 24.1-24.3

2. **E2E 测试完全缺失**: 端到端场景未测试
   - **影响**: 无法保证用户视角的系统可靠性
   - **修复**: 补充任务 25.6

3. **性能测试策略不完整**: 尽管有性能目标，但无验证方法
   - **影响**: 无法保证性能达标
   - **修复**: 补充任务 25.7

4. **并发安全测试不充分**: L3 shared dict 和 Redis Lua 脚本的原子性未验证
   - **影响**: 生产环境可能出现数据不一致
   - **修复**: 补充任务 1.5

#### 中等问题 (建议改进)

5. **属性测试密度过低**: 20个属性测试覆盖9个模块，平均2.2个/模块
   - **影响**: 边界条件和异常路径覆盖不足
   - **修复**: 补充任务 1.4 (边界测试)

6. **Checkpoint 验证不充分**: Checkpoint 仅要求"确保测试通过"，无具体验证标准
   - **影响**: 无法保证阶段性质量
   - **修复**: 增强Checkpoint验证脚本

7. **测试数据管理缺失**: 无测试数据生成和清理策略
   - **影响**: 测试不可靠、维护困难
   - **修复**: 建立测试数据管理机制

#### 轻微问题 (可选优化)

8. **标记 * 的测试任务不合理**: 核心功能测试不应标记为可选
   - **影响**: 可能导致MVP质量不足
   - **修复**: 重新评估标记

9. **测试工具评估不完整**: 未充分评估 lua-quickcheck 和 Test::Nginx
   - **影响**: 可能选择不合适的工具
   - **修复**: 已在本文档第3节完成评估

10. **CI/CD 集成建议缺失**: 无自动化测试流程
    - **影响**: 测试执行效率低
    - **修复**: 已在本文档第5.3节提供方案

### 6.2 行动计划

#### 第一阶段: 核心测试补充 (Week 1-2)

```
优先级: P0 (MVP 必需)
目标: 补充严重缺失的测试

任务列表:
□ 1.4 实现边界条件测试套件
□ 1.5 实现并发安全测试套件
□ 24.1 三层令牌桶集成测试
□ 24.2 降级策略集成测试
□ 25.6 实现端到端测试套件
□ 25.7 实现性能基准测试

交付物:
- tests/unit/boundary_*.spec.lua (5个文件)
- tests/integration/three_layer_spec.lua
- tests/integration/degradation_spec.lua
- tests/e2e/happy_path_e2e.js
- tests/e2e/emergency_mode_e2e.js
- tests/performance/latency_bench.lua
- tests/performance/cache_hit_bench.lua

验收标准:
- 单元测试覆盖率 ≥ 85%
- 集成测试覆盖所有三层交互
- E2E 测试覆盖关键用户流程
- 性能测试验证 P99 < 10ms
```

#### 第二阶段: 测试基础设施 (Week 3)

```
优先级: P0 (MVP 必需)
目标: 建立测试数据管理和 CI/CD

任务列表:
□ 建立测试数据管理机制
  - tests/fixtures/*.lua
  - tests/factories/*.lua
  - tests/helpers/test_data_*.lua

□ 配置 CI/CD Pipeline
  - .github/workflows/test.yml
  - .github/workflows/deploy.yml

□ 增强Checkpoint验证
  - scripts/checkpoint_validation.sh

交付物:
- tests/fixtures/boundary_data.lua
- tests/helpers/test_data_generator.lua
- .github/workflows/test.yml
- checkpoint_validation.sh

验收标准:
- 所有测试可在 CI 环境运行
- 测试数据自动生成和清理
- Checkpoint 验证自动化
```

#### 第三阶段: 高级测试补充 (Week 4-5)

```
优先级: P1 (生产必需)
目标: 补充压力测试和混沌测试

任务列表:
□ 24.3 配置热更新集成测试
□ 25.6 (补充) 故障恢复 E2E 测试
□ 25.7 (补充) 最大 TPS 探测测试
□ 实现压力测试套件
  - 连接限制压力测试
  - Redis OOM 测试
  - 10k 并发连接测试

□ 实现混沌测试套件
  - Redis 故障注入
  - 网络分区模拟
  - Pod Kill 场景

交付物:
- tests/integration/config_update_spec.lua
- tests/e2e/failover_e2e.js
- tests/performance/max_tps_k6.js
- tests/performance/connection_limit_stress_k6.js
- tests/chaos/redis_failure_chaos_spec.lua

验收标准:
- 压力测试验证系统极限
- 混沌测试验证故障恢复
- 所有测试可在 CI/CD 运行
```

#### 第四阶段: 测试优化与完善 (Week 6+)

```
优先级: P2 (增强优化)
目标: 提升测试质量和可维护性

任务列表:
□ 补充属性测试 (lua-quickcheck)
□ 实现 24小时浸泡测试
□ 实现性能回归检测
□ 建立测试报告可视化
□ 编写测试最佳实践文档

交付物:
- tests/property/quickcheck_*.spec.lua
- tests/performance/soak_test_k6.js
- scripts/generate_test_report.py
- docs/testing_best_practices.md

验收标准:
- 属性测试覆盖所有不变量
- 测试报告自动生成和发布
- 测试文档完善
```

### 6.3 成功指标

#### 测试覆盖度指标

| 指标 | 当前值 | 目标值 | 测量方法 |
|------|--------|--------|---------|
| 单元测试覆盖率 | 未知 | ≥90% | luacov |
| 集成测试覆盖率 | 0% | ≥80% | 手动统计 |
| E2E 场景覆盖 | 0% | ≥10个场景 | 测试用例数 |
| 性能基准覆盖 | 0% | 100% | 所有性能目标 |

#### 测试质量指标

| 指标 | 目标值 | 测量方法 |
|------|--------|---------|
| 测试通过率 | 100% | CI Dashboard |
| Flaky 测试率 | <0.1% | CI 历史记录 |
| 测试执行时间 | <5分钟 | CI 计时 |
| 测试可靠性 | >99.9% | CI 失败率 |

#### 生产质量指标

| 指标 | 目标值 | 测量方法 |
|------|--------|---------|
| P99 延迟 | <10ms | Prometheus |
| L3 缓存命中率 | >95% | Prometheus |
| 系统可用性 | >99.9% | Uptime |
| 生产缺陷率 | <5个/月 | Bug Tracker |

---

## 附录

### A. 测试工具对比矩阵

详细对比已在第3节提供。

### B. 测试用例模板

已在第4节提供。

### C. CI/CD 配置示例

已在第5.3节提供。

### D. 测试数据示例

已在第4.2-4.4节提供。

---

**文档版本**: 1.0.0
**最后更新**: 2025-12-31
**审核状态**: 待审核
**下一步**: 根据本评估报告更新 tasks.md 和 testing-framework-design.md
