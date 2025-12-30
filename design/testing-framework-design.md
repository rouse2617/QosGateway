# Comprehensive Testing Framework Design
## OpenResty-Based Distributed Rate Limiting System with Three-Layer Token Bucket Architecture

**Document Version:** 1.0.0
**Date:** 2025-12-31
**Author:** Testing Framework Design Team

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Testing Philosophy & Approach](#2-testing-philosophy--approach)
3. [Testing Tools & Frameworks](#3-testing-tools--frameworks)
4. [Test Architecture](#4-test-architecture)
5. [Test Coverage Areas](#5-test-coverage-areas)
6. [Test Directory Structure](#6-test-directory-structure)
7. [Test Data Management](#7-test-data-management)
8. [Unit Testing Strategy](#8-unit-testing-strategy)
9. [Integration Testing Strategy](#9-integration-testing-strategy)
10. [End-to-End Testing Strategy](#10-end-to-end-testing-strategy)
11. [Performance & Load Testing](#11-performance--load-testing)
12. [Configuration Validation](#12-configuration-validation)
13. [Chaos Testing](#13-chaos-testing)
14. [CI/CD Integration](#14-cicd-integration)
15. [Sample Test Templates](#15-sample-test-templates)
16. [Performance Testing Scenarios](#16-performance-testing-scenarios)

---

## 1. Executive Summary

### 1.1 System Overview

This testing framework is designed for a sophisticated distributed rate limiting system with:

- **Three-Layer Token Bucket Architecture:**
  - L1 (Cluster Layer): Redis Cluster, global quota protection
  - L2 (Application Layer): Per-app SLA guarantees with burst & borrowing
  - L3 (Local Layer): Nginx local cache, <1ms response time

- **Key Technologies:**
  - OpenResty (Nginx + LuaJIT)
  - Redis Cluster with Lua scripts
  - Prometheus metrics & Grafana dashboards
  - Configuration management API

- **Performance Targets:**
  - P99 latency: <10ms
  - L3 cache hit rate: >95%
  - Throughput: 50k+ TPS
  - Availability: 99.99%

### 1.2 Testing Goals

| Goal | Target | Rationale |
|------|--------|-----------|
| **Code Coverage** | 90%+ for critical paths | Ensure reliability |
| **Test Reliability** | <0.1% flaky test rate | Maintain developer trust |
| **Test Execution Time** | <5 min for full suite | Enable rapid feedback |
| **Performance Regression** | <5% deviation allowed | Catch performance issues early |
| **Configuration Validation** | 100% coverage | Prevent production incidents |

### 1.3 Testing Pyramid

```
                   /\
                  /  \
                 / E2E \        5% (Critical user flows)
                /------\
               /        \
              / Integ.   \     25% (Component interactions)
             /------------\
            /              \
           /    Unit Tests  \  70% (Fast, isolated)
          /------------------\
```

---

## 2. Testing Philosophy & Approach

### 2.1 Core Principles

**1. Test Isolation**
- Each test must be independent and executable in any order
- No shared state between tests
- Clean up resources after each test

**2. Deterministic Results**
- No randomness in test data
- Mock external dependencies (time, network, Redis)
- Reproducible failures

**3. Fast Feedback**
- Unit tests: <100ms each
- Integration tests: <5s each
- E2E tests: <30s each

**4. Realistic Scenarios**
- Test with production-like data volumes
- Simulate real traffic patterns
- Cover edge cases discovered in production

**5. Comprehensive Coverage**
- Happy path: All success scenarios
- Sad path: All error conditions
- Edge cases: Boundary conditions, null/empty values
- Concurrent scenarios: Race conditions, deadlocks

### 2.2 Testing Levels

| Level | Focus | Tools | Execution |
|-------|-------|-------|-----------|
| **Unit** | Individual functions/modules | busted, luassert | Every commit |
| **Integration** | Component interactions | busted, test-redis | Every PR |
| **E2E** | Complete request flows | OpenResty, k6, wrk | Pre-production |
| **Performance** | Load, stress, benchmark | k6, wrk, locust | Daily/Nightly |
| **Chaos** | Failure scenarios | Chaos Mesh, Toxiproxy | Weekly |

### 2.3 Test Categories

```
┌─────────────────────────────────────────────────────────────┐
│                    Functional Testing                       │
├─────────────────┬───────────────────────────────────────────┤
│ • Cost Calculation Accuracy    │ • Token Bucket Operations   │
│ • Local Cache Consistency      │ • Redis Interactions        │
│ • API Endpoints                │ • Configuration Management  │
└─────────────────┴───────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Non-Functional Testing                   │
├─────────────────┬───────────────────────────────────────────┤
│ • Performance (Load/Stress)    │ • Reliability (Failover)    │
│ • Scalability (Throughput)     │ • Security (Rate limit      │
│ • Latency (P50/P95/P99)       │   bypass attempts)          │
└─────────────────┴───────────────────────────────────────────┘
```

---

## 3. Testing Tools & Frameworks

### 3.1 Unit Testing Tools

#### **busted** (Primary Lua Testing Framework)

**Why busted?**
- BDD-style syntax (describe/it)
- Async test support
- Mocking/stubbing built-in
- CI-friendly output formats
- Excellent OpenResty integration

```lua
-- Example busted test
describe("Cost Calculator", function()
  it("should calculate GET request cost correctly", function()
    local cost = cost_calculator.calculate("GET", 1024)
    assert.equals(2, cost)
  end)
end)
```

**Alternatives Considered:**
- **luaunit**: Too verbose, lacking BDD style
- **lustache**: Abandoned project
- **specl**: Less feature-rich than busted

#### **luassert** (Assertion Library)

**Why luassert?**
- Rich matchers (matches, same, equals)
- Custom assertion builders
- Clear error messages
- Extensible

```lua
-- Example assertions
assert.is_true(result)
assert.is.number(value)
assert.is_near(actual, expected, 0.01)
assert.matches(pattern, text)
```

### 3.2 Integration Testing Tools

#### **test-redis** (Redis Mocking)

**Why test-redis?**
- In-memory Redis server
- Fast startup/shutdown
- Redis protocol compatible
- Supports Redis Cluster simulation

```lua
local redis = require("test-redis")

describe("Redis Integration", function()
  local mock_redis

  before_each(function()
    mock_redis = redis:new({port = 6379})
    mock_redis:start()
  end)

  after_each(function()
    mock_redis:stop()
  end)
end)
```

#### **lua-resty-http** (HTTP Client Testing)

Used for testing Nginx integration and API endpoints.

### 3.3 End-to-End Testing Tools

#### **k6** (Load & E2E Testing)

**Why k6?**
- JavaScript-based (familiar to most devs)
- Built-in metrics & thresholds
- Cloud execution support
- Great Grafana integration

```javascript
// Example k6 test
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  vus: 100,
  duration: '30s',
  thresholds: {
    http_req_duration: ['p(95)<10'],  // 95% under 10ms
    http_req_failed: ['rate<0.01'],    // <1% errors
  },
};

export default function() {
  let res = http.get('http://localhost/api/v1/test', {
    headers: {'X-App-Id': 'test-app'},
  });
  check(res, {
    'status is 200': (r) => r.status === 200,
    'has rate limit headers': (r) => r.headers['X-RateLimit-Cost'],
  });
  sleep(1);
}
```

#### **wrk** (Benchmarking)

**Why wrk?**
- Extremely lightweight
- Multi-threaded
- Low overhead
- Perfect for microbenchmarks

```bash
# Example wrk command
wrk -t4 -c100 -d30s --latency \
  -H "X-App-Id: test-app" \
  http://localhost/api/v1/test
```

### 3.4 Configuration Validation Tools

#### **Gixy** (Nginx Configuration Linter)

**Why Gixy?**
- Detects security misconfigurations
- Validates lua blocks
- Checks for common pitfalls
- CI/CD friendly

```bash
# Example Gixy usage
gixy /etc/nginx/nginx.conf
```

**Alternative: nginx_config_test**
- Less feature-rich
- Simpler output

#### **OpenAPI Validator** (API Contract Testing)

```lua
-- Validate API responses against OpenAPI spec
local validator = require("spec_validator")

describe("API Contract Validation", function()
  it("should conform to OpenAPI spec", function()
    local response = call_api()
    assert.is_true(validator.validate(response, "/apps", "POST"))
  end)
end)
```

### 3.5 Chaos Testing Tools

#### **Chaos Mesh** (Kubernetes Chaos Engineering)

**Why Chaos Mesh?**
- Kubernetes native
- Network fault injection
- Pod failure simulation
- Easy to integrate with CI/CD

#### **Toxiproxy** (Network Fault Injection)

**Why Toxiproxy?**
- Simulate network latency
- Simulate connection drops
- Simulate Redis failures
- CLI & API control

```bash
# Example: Add 100ms latency to Redis
toxiproxy-cli create redis -l localhost:26379 -u localhost:6379
toxiproxy-cli toxic add redis -t latency -a latency=100
```

### 3.6 Monitoring & Metrics Testing

#### **Prometheus Test Framework**

```python
# Validate Prometheus metrics
from prometheus_client.parser import text_string_to_metric_families

def test_metrics_exposed():
    response = requests.get('http://localhost/metrics')
    metrics = text_string_to_metric_families(response.text)

    # Check critical metrics exist
    metric_names = [m.name for m in metrics]
    assert 'ratelimit_requests_total' in metric_names
    assert 'ratelimit_l2_tokens_available' in metric_names
```

### 3.7 Tool Summary Matrix

| Testing Level | Primary Tool | Backup Tool | Execution Speed |
|---------------|--------------|-------------|-----------------|
| Unit (Lua) | busted | luaunit | <100ms/test |
| Integration | test-redis | redmock | <5s/test |
| E2E | k6 | wrk | <30s/test |
| Config Validation | Gixy | nginx_config_test | <1s/test |
| Chaos | Chaos Mesh | Toxiproxy | Manual/Weekly |
| API Contract | OpenAPI Validator | schema-validator | <2s/test |

---

## 4. Test Architecture

### 4.1 Test Environment Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                      Production                             │
│  • Real traffic, real data                                  │
│  • Synthetic canary tests (1% traffic)                      │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│                      Staging                                │
│  • Production-like environment                              │
│  • Full E2E test suite                                      │
│  • Load testing (peak traffic simulation)                   │
│  • Configuration validation                                 │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│                      CI/CD Pipeline                         │
│  • Unit + Integration tests on every commit/PR              │
│  • Docker compose test environment                          │
│  • Automated performance regression detection               │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│                      Development                            │
│  • Local unit tests                                          │
│  • Mocked Redis and dependencies                            │
│  • Fast feedback loop                                       │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Test Data Strategy

#### **Test Data Sources**

| Source | Type | Usage |
|--------|------|-------|
| **Synthetic Data** | Generated | Unit & integration tests |
| **Anonymized Production Data** | Realistic | Performance tests |
| **Fixtures** | Predefined | Regression tests |
| **Factories** | Programmatic | Dynamic test scenarios |

#### **Data Volume Planning**

```lua
-- test/factories/cost_factory.lua
local cost_factory = {}

function cost_factory.small_request()
  return {
    method = "GET",
    body_size = math.random(1024, 10240)  -- 1-10 KB
  }
end

function cost_factory.large_request()
  return {
    method = "PUT",
    body_size = math.random(1048576, 10485760)  -- 1-10 MB
  }
end

function cost_factory.mixed_requests(count)
  local requests = {}
  for i = 1, count do
    if math.random() > 0.8 then
      table.insert(requests, cost_factory.large_request())
    else
      table.insert(requests, cost_factory.small_request())
    end
  end
  return requests
end

return cost_factory
```

### 4.3 Test Organization

```
tests/
├── unit/                           # Fast, isolated tests
│   ├── cost_calculator_spec.lua
│   ├── l3_bucket_spec.lua
│   └── token_bucket_spec.lua
│
├── integration/                    # Component interaction tests
│   ├── redis_integration_spec.lua
│   ├── nginx_integration_spec.lua
│   └── end_to_end_flow_spec.lua
│
├── e2e/                            # Full request flow tests
│   ├── rate_limiting_e2e_spec.lua
│   ├── emergency_mode_e2e_spec.lua
│   └── failover_e2e_spec.lua
│
├── performance/                    # Load & stress tests
│   ├── load_test_k6.js
│   ├── latency_bench.lua
│   └── soak_test.lua
│
├── chaos/                          # Failure scenario tests
│   ├── redis_failure_spec.lua
│   ├── network_partition_spec.lua
│   └── resource_exhaustion_spec.lua
│
├── config/                         # Configuration validation
│   ├── nginx_conf_spec.lua
│   ├── lua_syntax_spec.lua
│   └── openapi_spec_spec.lua
│
└── helpers/                        # Test utilities
    ├── redis_helper.lua
    ├── fixtures.lua
    ├── assertions.lua
    └── mocks.lua
```

---

## 5. Test Coverage Areas

### 5.1 Cost Calculation Accuracy

| Test Category | Scenarios | Priority |
|---------------|-----------|----------|
| **Basic Operations** | GET, HEAD, PUT, POST, PATCH, DELETE | P0 |
| **Complex Operations** | COPY, MULTIPART_* operations | P0 |
| **Size Calculations** | Small (<1KB), Medium (1KB-1MB), Large (>1MB) | P0 |
| **Edge Cases** | 0 bytes, max size, chunked transfer | P1 |
| **Bandwidth Profiles** | standard, iops_sensitive, bandwidth_sensitive | P1 |
| **Performance** | Cache hit/miss, batch calculations | P1 |

**Example Test Cases:**

```lua
describe("Cost Calculator - Basic Operations", function()
  it("should calculate GET request with 1KB body", function()
    local cost = cost_calculator.calculate("GET", 1024, 1)
    assert.equals(2, cost)  -- C_base=1 + ceil(1024/65536)=1
  end)

  it("should calculate PUT request with 10MB body", function()
    local cost = cost_calculator.calculate("PUT", 10485760, 1)
    assert.equals(165, cost)  -- C_base=5 + ceil(10485760/65536)=160
  end)

  it("should handle zero body size", function()
    local cost = cost_calculator.calculate("GET", 0, 1)
    assert.equals(1, cost)  -- Only C_base
  end)

  it("should cap at maximum cost", function()
    local cost = cost_calculator.calculate("PUT", 10000000000, 1)
    assert.equals(1000000, cost)  -- MAX_COST
  end)
end)

describe("Cost Calculator - Bandwidth Profiles", function()
  it("should use different C_bw coefficients", function()
    local standard = cost_calculator.calculate("GET", 65536, 1)
    local iops = cost_calculator.calculate("GET", 65536, 0.5)
    local bw = cost_calculator.calculate("GET", 65536, 2)

    assert.equals(2, standard)   -- 1 + 1*1
    assert.equals(1.5, iops)      -- 1 + 1*0.5
    assert.equals(3, bw)          -- 1 + 1*2
  end)
end)
```

### 5.2 Token Bucket Operations

| Test Category | Scenarios | Priority |
|---------------|-----------|----------|
| **Token Acquisition** | Success, insufficient tokens, exact match | P0 |
| **Token Refill** | Time-based refill, burst quota | P0 |
| **Token Borrowing** | Borrow success, borrow limit, debt calculation | P0 |
| **Token Repayment** | Full repayment, partial repayment | P1 |
| **Concurrent Access** | Race conditions, atomic operations | P0 |
| **Boundary Conditions** | Empty bucket, full bucket, overflow | P1 |

**Example Test Cases:**

```lua
describe("L2 Token Bucket - Acquisition", function()
  local app_id = "test-app"
  local redis_client

  before_each(function()
    redis_client = mock_redis:new()
    redis_client:init_app(app_id, {
      guaranteed_quota = 1000,
      burst_quota = 5000,
      current_tokens = 1000
    })
  end)

  it("should acquire tokens when sufficient", function()
    local result = l2_bucket.acquire(app_id, 100)
    assert.is_true(result.success)
    assert.equals(900, result.remaining)
  end)

  it("should fail when tokens insufficient", function()
    local result = l2_bucket.acquire(app_id, 2000)
    assert.is_false(result.success)
    assert.equals("insufficient_tokens", result.reason)
  end)

  it("should refill tokens over time", function()
    -- Start with 100 tokens
    redis_client.set_tokens(app_id, 100)

    -- Wait 2 seconds (refill rate: 1000 tokens/s)
    mock_time.advance(2)

    local result = l2_bucket.acquire(app_id, 1500)
    assert.is_true(result.success)
  end)
end)

describe("L2 Token Bucket - Borrowing", function()
  it("should borrow from L1 when L2 exhausted", function()
    -- Setup: L2 has 0 tokens, L1 has 10000
    local result = l2_bucket.acquire_with_borrow(app_id, 500, l1_bucket)
    assert.is_true(result.success)
    assert.equals("borrowed", result.source)
    assert.equals(600, result.debt)  -- 500 + 20% interest
  end)

  it("should enforce borrow limit", function()
    -- Already borrowed 10000, max is 10000
    local result = l2_bucket.borrow(app_id, 100, l1_bucket)
    assert.is_false(result.success)
    assert.equals("borrow_limit_exceeded", result.reason)
  end)
end)
```

### 5.3 Local Cache Consistency

| Test Category | Scenarios | Priority |
|---------------|-----------|----------|
| **Cache Hit** | Local tokens sufficient | P0 |
| **Cache Miss** | Local tokens depleted | P0 |
| **Cache Refresh** | Async refill from L2 | P0 |
| **Batch Sync** | Pending operations sync | P0 |
| **Consistency** | L3 vs L2 reconciliation | P0 |
| **Fail-Open** | Redis failure behavior | P0 |

**Example Test Cases:**

```lua
describe("L3 Local Bucket - Cache Consistency", function()
  it("should serve from local cache when tokens available", function()
    l3_bucket.set_tokens(app_id, 1000)
    local result = l3_bucket.acquire(app_id, 100)

    assert.is_true(result.success)
    assert.equals("local_hit", result.source)
    assert.equals(900, l3_bucket.get_tokens(app_id))
  end)

  it("should fetch from L2 when local cache depleted", function()
    l3_bucket.set_tokens(app_id, 50)
    mock_redis.expect_batch_acquire(1000, 1000)

    local result = l3_bucket.acquire(app_id, 100)
    assert.is_true(result.success)
    assert.equals("remote_fetch", result.source)
  end)

  it("should sync pending operations to L2", function()
    l3_bucket.set_tokens(app_id, 1000)

    -- Perform 100 operations locally
    for i = 1, 100 do
      l3_bucket.acquire(app_id, 10)
    end

    -- Trigger sync
    local synced = l3_bucket.sync_to_l2(app_id)
    assert.equals(1000, synced.total_cost)
    assert.equals(100, synced.request_count)
  end)

  it("should enter fail-open mode on Redis failure", function()
    mock_redis.simulate_failure()

    local result = l3_bucket.acquire(app_id, 10)
    assert.is_true(result.success)  -- Fail-open allows requests
    assert.equals("fail_open", result.source)
  end)
end)
```

### 5.4 Redis Failure Scenarios

| Test Category | Scenarios | Priority |
|---------------|-----------|----------|
| **Connection Failure** | Redis unavailable | P0 |
| **Timeout** | Slow Redis response | P0 |
| **Cluster Partition** | Partial cluster available | P1 |
| **Master Failover** | Master switch during request | P0 |
| **Script Execution Error** | Lua script failure | P1 |
| **Memory Exhaustion** | Redis OOM | P1 |

**Example Test Cases:**

```lua
describe("Redis Failure Handling", function()
  it("should degrade gracefully on connection failure", function()
    toxiproxy.disable_redis()

    local result = l3_bucket.acquire(app_id, 100)
    assert.is_true(result.success)
    assert.equals("fail_open", result.mode)

    toxiproxy.enable_redis()
  end)

  it("should timeout and retry on slow response", function()
    toxiproxy.add_latency("redis", 5000)  -- 5 second delay

    local start = os.time()
    local result = l3_bucket.acquire(app_id, 100)
    local elapsed = os.time() - start

    assert.is_true(result.success)
    assert.is_true(elapsed < 2)  -- Should timeout faster than 5s
  end)

  it("should handle Redis cluster reconfiguration", function()
    -- Remove master from cluster
    redis_cluster.kill_master()

    local result = l3_bucket.acquire(app_id, 100)
    assert.is_true(result.success)  -- Should use fail-open or new master
  end)
end)
```

### 5.5 Concurrent Request Handling

| Test Category | Scenarios | Priority |
|---------------|-----------|----------|
| **Race Conditions** | Concurrent token acquisition | P0 |
| **Atomic Operations** | Lua script atomicity | P0 |
| **Lock Contention** | High concurrency locking | P1 |
| **Batch Processing** | Concurrent batch operations | P1 |
| **Memory Safety** | Shared dict concurrent access | P0 |

**Example Test Cases:**

```lua
describe("Concurrent Request Handling", function()
  it("should handle 1000 concurrent requests safely", function()
    local threads = {}
    local errors = {}
    local success_count = 0

    for i = 1, 1000 do
      threads[i] = ngx.thread.spawn(function()
        local ok, result = pcall(function()
          return l3_bucket.acquire(app_id, 10)
        end)
        if not ok then
          table.insert(errors, result)
        elseif result.success then
          success_count = success_count + 1
        end
      end)
    end

    -- Wait for all threads
    for _, thread in ipairs(threads) do
      ngx.thread.wait(thread)
    end

    assert.equals(0, #errors)  -- No errors
    assert.equals(1000, success_count)  -- All succeeded
  end)

  it("should maintain atomicity with Lua scripts", function()
    local initial_tokens = redis_client.get_tokens(app_id)

    -- Spawn 100 threads each trying to acquire 10 tokens
    local threads = {}
    for i = 1, 100 do
      threads[i] = ngx.thread.spawn(function()
        return l2_bucket.acquire_atomic(app_id, 10)
      end)
    end

    -- Wait and sum results
    local total_acquired = 0
    for _, thread in ipairs(threads) do
      local ok, result = ngx.thread.wait(thread)
      if ok and result.success then
        total_acquired = total_acquired + 10
      end
    end

    local final_tokens = redis_client.get_tokens(app_id)
    assert.equals(initial_tokens - total_acquired, final_tokens)
  end)
end)
```

### 5.6 Configuration Validation

| Test Category | Scenarios | Priority |
|---------------|-----------|----------|
| **Nginx Syntax** | Configuration file validity | P0 |
| **Lua Syntax** | Script syntax errors | P0 |
| **Redis Scripts** | Lua script validation | P0 |
| **API Contracts** | OpenAPI spec compliance | P0 |
| **Security** | Gixy security checks | P0 |
| **Best Practices** | Performance and security patterns | P1 |

**Example Test Cases:**

```lua
describe("Configuration Validation", function()
  it("should validate nginx.conf syntax", function()
    local valid, err = nginx_helper.validate_config("/etc/nginx/nginx.conf")
    assert.is_true(valid, err)
  end)

  it("should detect security issues with Gixy", function()
    local issues = gixy.scan("/etc/nginx/nginx.conf")
    assert.is_true(#issues == 0, "Security issues found: " .. #issues)
  end)

  it("should validate all Lua scripts", function()
    local scripts = {
      "lua/ratelimit/cost.lua",
      "lua/ratelimit/l3_bucket.lua",
      "lua/ratelimit/redis.lua"
    }

    for _, script in ipairs(scripts) do
      local valid, err = lua_helper.validate_syntax(script)
      assert.is_true(valid, script .. " has syntax error: " .. err)
    end
  end)

  it("should validate Redis Lua scripts", function()
    local scripts = {
      "scripts/acquire_tokens.lua",
      "scripts/batch_acquire.lua",
      "scripts/three_layer_deduct.lua"
    }

    for _, script in ipairs(scripts) do
      local valid = redis_helper.validate_script(script)
      assert.is_true(valid, script .. " failed validation")
    end
  end)
end)
```

---

## 6. Test Directory Structure

```
rate-limiter/
├── tests/
│   ├── unit/                                    # Unit tests
│   │   ├── cost_calculator_spec.lua             # Cost calculation tests
│   │   ├── l3_bucket_spec.lua                   # Local bucket tests
│   │   ├── l2_bucket_spec.lua                   # App bucket tests
│   │   ├── l1_allocator_spec.lua                # Cluster allocator tests
│   │   ├── token_borrowing_spec.lua             # Borrowing mechanism tests
│   │   ├── metrics_spec.lua                     # Metrics collection tests
│   │   └── utils_spec.lua                       # Utility function tests
│   │
│   ├── integration/                             # Integration tests
│   │   ├── redis_integration_spec.lua           # Redis integration
│   │   ├── nginx_lua_integration_spec.lua       # Nginx+Lua integration
│   │   ├── three_layer_flow_spec.lua            # Full three-layer flow
│   │   ├── batch_sync_spec.lua                  # Batch synchronization
│   │   ├── reconcile_spec.lua                   # Reconciliation logic
│   │   └── pubsub_config_spec.lua               # Config update pub/sub
│   │
│   ├── e2e/                                     # End-to-end tests
│   │   ├── happy_path_e2e_spec.lua              # Normal request flow
│   │   ├── burst_traffic_e2e_spec.lua           # Burst handling
│   │   ├── emergency_mode_e2e_spec.lua          # Emergency mode
│   │   ├── failover_e2e_spec.lua                # Redis failover
│   │   ├── multi_app_e2e_spec.lua               # Multi-app isolation
│   │   └── cost_accuracy_e2e_spec.lua           # Cost calculation accuracy
│   │
│   ├── performance/                             # Performance tests
│   │   ├── load/                                # Load tests
│   │   │   ├── baseline_load_k6.js              # 50k TPS baseline
│   │   │   ├── peak_load_k6.js                  # Peak traffic simulation
│   │   │   └── sustained_load_k6.js             # 24-hour soak test
│   │   ├── latency/                             # Latency benchmarks
│   │   │   ├── p99_latency_bench.lua            # P99 <10ms validation
│   │   │   ├── local_cache_hit_bench.lua        # L3 cache hit latency
│   │   │   └── redis_latency_bench.lua          # Redis operation latency
│   │   └── stress/                              # Stress tests
│   │       ├── max_tps_stress_k6.js             # Max throughput finding
│   │       ├── redis_exhaustion_stress.lua       # Redis memory limit
│   │       └── connection_limit_stress_k6.js    # Connection limits
│   │
│   ├── chaos/                                   # Chaos tests
│   │   ├── redis_failure_chaos_spec.lua         # Redis failure
│   │   ├── network_partition_chaos_spec.lua     # Network partition
│   │   ├── pod_kill_chaos_spec.lua              # Nginx pod restart
│   │   └── resource_starvation_chaos_spec.lua   # CPU/memory limits
│   │
│   ├── config/                                  # Configuration tests
│   │   ├── nginx_conf_spec.lua                  # nginx.conf validation
│   │   ├── lua_scripts_syntax_spec.lua          # Lua syntax check
│   │   ├── redis_scripts_validation_spec.lua    # Redis script validation
│   │   ├── openapi_contract_spec.lua            # API contract testing
│   │   └── security_audit_spec.lua              # Gixy security scan
│   │
│   ├── fixtures/                                # Test fixtures
│   │   ├── app_configs.lua                      # Sample app configs
│   │   ├── cluster_configs.lua                  # Sample cluster configs
│   │   ├── cost_profiles.lua                    # Cost calculation profiles
│   │   └── test_data.lua                        # Synthetic test data
│   │
│   └── helpers/                                 # Test utilities
│       ├── redis_helper.lua                     # Redis test utilities
│       ├── nginx_helper.lua                     # Nginx test utilities
│       ├── mock_helper.lua                      # Mocking utilities
│       ├── assertion_helpers.lua                # Custom assertions
│       └── test_utils.lua                       # General utilities
│
├── scripts/                                     # Production Redis Lua scripts
│   ├── acquire_tokens.lua
│   ├── batch_acquire.lua
│   ├── three_layer_deduct.lua
│   ├── batch_report.lua
│   ├── reconcile.lua
│   ├── emergency_activate.lua
│   ├── emergency_deactivate.lua
│   ├── borrow_tokens.lua
│   └── repay_tokens.lua
│
├── lua/                                         # Production Nginx Lua modules
│   └── ratelimit/
│       ├── init.lua
│       ├── cost.lua
│       ├── l3_bucket.lua
│       ├── redis.lua
│       ├── metrics.lua
│       └── timer.lua
│
├── .busted.lua                                  # Busted configuration
├── .luacheckrc                                  # Lua linting configuration
├── docker-compose.test.yml                      # Test environment
├── Makefile                                     # Test commands
└── README.md
```

### 6.1 Test Configuration Files

#### **`.busted.lua` - Busted Configuration**

```lua
-- .busted.lua
return {
  _all = {
    -- Coverage configuration
    coverage = true,
    coverage_threshold = 90,

    -- Linting
    lint = true,
    linter = "luacheck",

    -- Exclude directories
    exclude = {
      "helpers",
      "fixtures"
    }
  },

  -- Unit tests: fast, no external dependencies
  unit = {
    _ = {
      roots = { "tests/unit" },
    },
    default = { "--seed", "1234" }  -- Reproducible randomness
  },

  -- Integration tests: require Redis
  integration = {
    _ = {
      roots = { "tests/integration" },
      require_redis = true
    }
  },

  -- E2E tests: require full Nginx stack
  e2e = {
    _ = {
      roots = { "tests/e2e" },
      require_nginx = true,
      require_redis = true
    }
  }
}
```

#### **`Makefile` - Test Commands**

```makefile
# Makefile
.PHONY: test unit-test integration-test e2e-test performance-test lint validate

# Run all tests
test: unit-test integration-test e2e-test validate

# Unit tests only (fast)
unit-test:
	@echo "Running unit tests..."
	busted tests/unit --coverage

# Integration tests
integration-test:
	@echo "Running integration tests..."
	docker-compose -f docker-compose.test.yml up -d redis
	busted tests/integration
	docker-compose -f docker-compose.test.yml down

# E2E tests
e2e-test:
	@echo "Running E2E tests..."
	docker-compose -f docker-compose.test.yml up -d
	busted tests/e2e
	docker-compose -f docker-compose.test.yml down

# Performance tests
performance-test:
	@echo "Running performance tests..."
	k6 run tests/performance/load/baseline_load_k6.js
	k6 run tests/performance/stress/max_tps_stress_k6.js

# Linting
lint:
	@echo "Running linters..."
	luacheck lua/ tests/ --no-unused
	gixy nginx.conf

# Configuration validation
validate:
	@echo "Validating configurations..."
	busted tests/config

# Coverage report
coverage:
	busted --coverage
	luacov

# CI pipeline
ci: lint unit-test integration-test
```

---

## 7. Test Data Management

### 7.1 Test Factories

**Purpose:** Generate realistic test data on-the-fly

```lua
-- tests/helpers/factory.lua
local factory = {}

function factory.app_config(overrides)
  local defaults = {
    app_id = "test-app-" .. math.random(1000, 9999),
    guaranteed_quota = 10000,
    burst_quota = 50000,
    priority = 2,
    max_borrow = 10000,
    cost_profile = "standard"
  }
  return merge(defaults, overrides or {})
end

function factory.request(overrides)
  local methods = {"GET", "PUT", "POST", "DELETE", "PATCH"}
  local defaults = {
    method = methods[math.random(1, #methods)],
    body_size = math.random(1024, 1048576),
    app_id = factory.app_config().app_id,
    user_id = "user-" .. math.random(1000, 9999)
  }
  return merge(defaults, overrides or {})
end

function factory.cost_calculation_test_cases()
  return {
    {method = "GET", body_size = 0, expected = 1, description = "GET with no body"},
    {method = "GET", body_size = 1024, expected = 2, description = "GET 1KB"},
    {method = "GET", body_size = 65536, expected = 2, description = "GET 64KB"},
    {method = "GET", body_size = 65537, expected = 3, description = "GET 64KB+1B"},
    {method = "PUT", body_size = 1048576, expected = 21, description = "PUT 1MB"},
    {method = "POST", body_size = 10485760, expected = 160, description = "POST 10MB"},
  }
end

return factory
```

### 7.2 Test Fixtures

**Purpose:** Predefined, reusable test data

```lua
-- tests/fixtures/app_configs.lua
local fixtures = {
  -- Standard web application
  web_app = {
    app_id = "web-app-01",
    guaranteed_quota = 20000,
    burst_quota = 80000,
    priority = 1,
    max_borrow = 20000
  },

  -- Video streaming service (bandwidth intensive)
  video_service = {
    app_id = "video-service",
    guaranteed_quota = 50000,
    burst_quota = 200000,
    priority = 0,
    max_borrow = 50000,
    cost_profile = "bandwidth_sensitive"
  },

  -- Internal monitoring (low priority)
  monitoring = {
    app_id = "internal-monitoring",
    guaranteed_quota = 1000,
    burst_quota = 5000,
    priority = 3,
    max_borrow = 1000
  },

  -- Storage service (IOPS intensive)
  storage_service = {
    app_id = "storage-backend",
    guaranteed_quota = 100000,
    burst_quota = 400000,
    priority = 0,
    max_borrow = 50000,
    cost_profile = "iops_sensitive"
  }
}

return fixtures
```

### 7.3 Test Scenarios

```lua
-- tests/fixtures/scenarios.lua
local scenarios = {}

-- Simulate normal day traffic
scenarios.normal_traffic = {
  duration = 3600,  -- 1 hour
  apps = {
    {app_id = "web-app-01", qps = 1000, cost_avg = 5},
    {app_id = "video-service", qps = 500, cost_avg = 500},
    {app_id = "storage-backend", qps = 2000, cost_avg = 10}
  }
}

-- Simulate flash crowd
scenarios.flash_crowd = {
  duration = 300,  -- 5 minutes
  apps = {
    {app_id = "web-app-01", qps = 10000, cost_avg = 5}  -- 10x normal
  }
}

-- Simulate DDoS attack
scenarios.ddos_attack = {
  duration = 600,  -- 10 minutes
  attacker = {
    app_id = "malicious-app",
    qps = 50000,  -- Very high QPS
    cost_avg = 1  -- Small requests
  }
}

return scenarios
```

### 7.4 Data Cleanup Strategies

```lua
-- tests/helpers/cleanup.lua
local cleanup = {}

function cleanup.redis_all()
  local redis = require("resty.redis"):new()
  redis:connect("127.0.0.1", 6379)

  -- Delete all test keys
  local keys = redis:keys("ratelimit:test:*")
  for _, key in ipairs(keys) do
    redis:del(key)
  end

  redis:set_keepalive()
end

function cleanup.nginx_shared_dict(dict_name)
  local dict = ngx.shared[dict_name]
  local keys = dict:get_keys(0)

  for _, key in ipairs(keys) do
    if key:match("^test:") then
      dict:delete(key)
    end
  end
end

function cleanup.isolate_test(test_name)
  return setmetatable({}, {
    __index = function(self, key)
      return "test:" .. test_name .. ":" .. key
    end
  })
end

return cleanup
```

---

## 8. Unit Testing Strategy

### 8.1 Test Organization

```
tests/unit/
├── cost_calculator_spec.lua      # Cost calculation tests
├── l3_bucket_spec.lua            # Local bucket tests
├── l2_bucket_spec.lua            # App bucket tests
├── l1_allocator_spec.lua         # Cluster allocator tests
├── borrowing_spec.lua            # Token borrowing tests
├── metrics_spec.lua              # Metrics collection tests
└── utils_spec.lua                # Utility function tests
```

### 8.2 Example Unit Tests

#### **Cost Calculator Tests**

```lua
-- tests/unit/cost_calculator_spec.lua
local cost_calculator = require("ratelimit.cost")

describe("Cost Calculator", function()
  describe("calculate", function()
    it("should calculate GET request cost correctly", function()
      local cost = cost_calculator.calculate("GET", 1024)
      assert.equals(2, cost)  -- C_base=1 + ceil(1024/65536)=1
    end)

    it("should calculate PUT request cost correctly", function()
      local cost = cost_calculator.calculate("PUT", 1048576)
      assert.equals(21, cost)  -- C_base=5 + ceil(1048576/65536)=16
    end)

    it("should handle zero body size", function()
      local cost = cost_calculator.calculate("GET", 0)
      assert.equals(1, cost)  -- Only C_base
    end)

    it("should cap at maximum cost", function()
      local cost = cost_calculator.calculate("PUT", 10000000000)
      assert.equals(1000000, cost)  -- MAX_COST
    end)

    it("should return cost details", function()
      local cost, details = cost_calculator.calculate("PUT", 65536)
      assert.equals(6, cost)  -- 5 + 1
      assert.equals("PUT", details.method)
      assert.equals(5, details.c_base)
      assert.equals(1, details.c_bandwidth)
    end)
  end)

  describe("calculate_batch", function()
    it("should calculate multiple requests", function()
      local requests = {
        {method = "GET", body_size = 1024, c_bw = 1},
        {method = "PUT", body_size = 1024, c_bw = 1},
        {method = "GET", body_size = 65536, c_bw = 1}
      }

      local total, results = cost_calculator.calculate_batch(requests)
      assert.equals(9, total)  -- 2 + 6 + 1
      assert.equals(3, #results)
    end)
  end)

  describe("bandwidth profiles", function()
    it("should use different C_bw coefficients", function()
      local standard = cost_calculator.calculate("GET", 65536, 1)
      local iops = cost_calculator.calculate("GET", 65536, 0.5)
      local bw = cost_calculator.calculate("GET", 65536, 2)

      assert.equals(2, standard)  -- 1 + 1*1
      assert.equals(1.5, iops)    -- 1 + 1*0.5
      assert.equals(3, bw)        -- 1 + 1*2
    end)
  end)
end)
```

#### **L3 Local Bucket Tests**

```lua
-- tests/unit/l3_bucket_spec.lua
local l3_bucket = require("ratelimit.l3_bucket")
local mock_redis = require("tests.helpers.mock_helper")

describe("L3 Local Bucket", function()
  local app_id = "test-app"

  before_each(function()
    -- Reset shared dict
    ngx.shared.ratelimit:flush_all()
    l3_bucket.set_tokens(app_id, 1000)
  end)

  describe("acquire", function()
    it("should acquire tokens when local cache has sufficient tokens", function()
      local result = l3_bucket.acquire(app_id, 100)

      assert.is_true(result.success)
      assert.equals("local_hit", result.source)
      assert.equals(900, l3_bucket.get_tokens(app_id))
    end)

    it("should fail when tokens insufficient and fetch fails", function()
      l3_bucket.set_tokens(app_id, 50)
      mock_redis.stub("batch_acquire", 0)  -- L2 returns 0 tokens

      local result = l3_bucket.acquire(app_id, 100)

      assert.is_false(result.success)
      assert.equals("quota_exhausted", result.reason)
    end)

    it("should trigger async refill when below threshold", function()
      l3_bucket.set_tokens(app_id, 150)  -- Below 20% threshold

      local spy_refill = spy.on(l3_bucket, "async_refill")
      l3_bucket.acquire(app_id, 10)

      assert.spy(spy_refill).was_called()
    end)

    it("should trigger sync when batch threshold reached", function()
      local spy_sync = spy.on(l3_bucket, "check_sync")

      for i = 1, 1001 do
        l3_bucket.acquire(app_id, 1)
      end

      assert.spy(spy_sync).was_called()
    end)
  end)

  describe("sync_to_l2", function()
    it("should report pending operations", function()
      -- Perform operations
      l3_bucket.acquire(app_id, 100)
      l3_bucket.acquire(app_id, 200)

      local synced = l3_bucket.sync_to_l2(app_id)

      assert.equals(300, synced.total_cost)
      assert.equals(2, synced.request_count)

      -- Pending should be reset
      assert.equals(0, l3_bucket.get_pending(app_id))
    end)

    it("should handle Redis sync failure gracefully", function()
      mock_redis.stub("report_consumption", nil, "connection error")

      l3_bucket.acquire(app_id, 100)

      -- Should not raise error
      local ok, err = pcall(l3_bucket.sync_to_l2, app_id)
      assert.is_true(ok)

      -- Pending should NOT be reset (will retry)
      assert.equals(100, l3_bucket.get_pending(app_id))
    end)
  end)

  describe("fail-open mode", function()
    it("should enter fail-open on Redis failure", function()
      mock_redis.simulate_failure()

      local result = l3_bucket.acquire(app_id, 100)

      assert.is_true(result.success)
      assert.equals("fail_open", result.mode)
    end)

    it("should exit fail-open when Redis recovers", function()
      mock_redis.simulate_failure()
      l3_bucket.acquire(app_id, 10)  -- Enter fail-open

      mock_redis.simulate_recovery()
      local result = l3_bucket.acquire(app_id, 100)

      assert.equals("local_hit", result.mode)  -- Back to normal
    end)

    it("should limit fail-open tokens", function()
      mock_redis.simulate_failure()

      -- Use all fail-open tokens (100)
      for i = 1, 10 do
        l3_bucket.acquire(app_id, 10)
      end

      local result = l3_bucket.acquire(app_id, 1)
      assert.is_false(result.success)
      assert.equals("fail_open_exhausted", result.reason)
    end)
  end)
end)
```

### 8.3 Mocking Strategy

```lua
-- tests/helpers/mock_helper.lua
local mock_helper = {}

function mock_helper.stub(module_name, method_name, return_value, error)
  local original = require(module_name)[method_name]

  require(module_name)[method_name] = function(...)
    if error then
      return nil, error
    end
    return return_value
  end

  return function()
    -- Restore original
    require(module_name)[method_name] = original
  end
end

function mock_helper.mock_time()
  local current_time = 1609459200  -- 2021-01-01 00:00:00

  return {
    advance = function(seconds)
      current_time = current_time + seconds
    end,
    get = function()
      return current_time
    end
  }
end

return mock_helper
```

---

## 9. Integration Testing Strategy

### 9.1 Test Environment

```yaml
# docker-compose.test.yml
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    command: redis-server --maxmemory 1gb --maxmemory-policy allkeys-lru
    ports:
      - "6379:6379"

  redis-cluster:
    image: redis:7-alpine
    command: redis-cli --cluster create 127.0.0.1:7001 127.0.0.1:7002 127.0.0.1:7003 --cluster-yes
    depends_on:
      - redis-node1
      - redis-node2
      - redis-node3

  redis-node1:
    image: redis:7-alpine
    command: redis-server --cluster-enabled yes --port 7001
    ports:
      - "7001:7001"

  redis-node2:
    image: redis:7-alpine
    command: redis-server --cluster-enabled yes --port 7002
    ports:
      - "7002:7002"

  redis-node3:
    image: redis:7-alpine
    command: redis-server --cluster-enabled yes --port 7003
    ports:
      - "7003:7003"

  nginx-gateway:
    build: .
    ports:
      - "8080:80"
      - "9145:9145"
    environment:
      - REDIS_HOST=redis
      - REDIS_PORT=6379
    volumes:
      - ./nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf:ro
      - ./lua:/etc/nginx/lua:ro
    depends_on:
      - redis

  toxiproxy:
    image: ghcr.io/shopify/toxiproxy:2.5.0
    ports:
      - "8474:8474"
      - "26379:26379"
    volumes:
      - ./tests/toxiproxy.json:/config/toxiproxy.json
    command: -host 0.0.0.0 -config /config/toxiproxy.json

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
```

### 9.2 Integration Test Examples

#### **Redis Integration Tests**

```lua
-- tests/integration/redis_integration_spec.lua
local redis_client = require("ratelimit.redis")
local l2_bucket = require("ratelimit.l2_bucket")

describe("Redis Integration", function()
  local redis
  local app_id = "integration-test-app"

  before_each(function()
    redis = require("resty.redis"):new()
    redis:connect("127.0.0.1", 6379)

    -- Setup test app
    redis:hset("ratelimit:l2:" .. app_id, "guaranteed_quota", 1000)
    redis:hset("ratelimit:l2:" .. app_id, "burst_quota", 5000)
    redis:hset("ratelimit:l2:" .. app_id, "current_tokens", 1000)
    redis:hset("ratelimit:l2:" .. app_id, "last_refill", ngx.now())
  end)

  after_each(function()
    -- Cleanup
    redis:del("ratelimit:l2:" .. app_id)
    redis:del("ratelimit:stats:" .. app_id)
    redis:set_keepalive()
  end)

  it("should acquire tokens atomically with Lua script", function()
    local script = [[
      local key = KEYS[1]
      local cost = tonumber(ARGV[1])
      local now = tonumber(ARGV[2])

      local current = tonumber(redis.call('HGET', key, 'current_tokens'))
      if current >= cost then
        redis.call('HINCRBY', key, 'current_tokens', -cost)
        return {1, current - cost}
      else
        return {0, current}
      end
    ]]

    local result = redis:eval(script, 1, "ratelimit:l2:" .. app_id, 100, ngx.now())

    assert.is_true(result[1] == 1)  -- Success
    assert.is_true(result[2] == 900)  -- Remaining
  end)

  it("should refill tokens over time", function()
    local initial_tokens = tonumber(redis:hget("ratelimit:l2:" .. app_id, "current_tokens"))

    -- Simulate time passing (2 seconds)
    ngx.sleep(2)

    -- Trigger refill by acquiring
    local cost = 100
    local result = l2_bucket.acquire(app_id, cost)

    assert.is_true(result.success)
    local final_tokens = tonumber(redis:hget("ratelimit:l2:" .. app_id, "current_tokens"))

    -- Tokens should have increased (refilled) then decreased (acquired)
    -- Initial 1000 + (2s * 1000/s) - 100 = 2900
    assert.is_true(final_tokens > initial_tokens)
  end)

  it("should handle concurrent token acquisitions", function()
    local threads = {}
    local acquired_count = 0

    -- Spawn 10 concurrent threads
    for i = 1, 10 do
      threads[i] = ngx.thread.spawn(function()
        local result = l2_bucket.acquire(app_id, 50)
        if result.success then
          acquired_count = acquired_count + 1
        end
      end)
    end

    -- Wait for all threads
    for _, thread in ipairs(threads) do
      ngx.thread.wait(thread)
    end

    -- All 10 should succeed (10 * 50 = 500 tokens)
    assert.equals(10, acquired_count)

    local remaining = tonumber(redis:hget("ratelimit:l2:" .. app_id, "current_tokens"))
    assert.equals(500, remaining)
  end)
end)
```

#### **Three-Layer Flow Integration**

```lua
-- tests/integration/three_layer_flow_spec.lua
describe("Three-Layer Integration", function()
  local app_id = "three-layer-test-app"

  before_each(function()
    -- Setup L1 cluster
    redis:set("ratelimit:l1:cluster:capacity", 1000000)
    redis:set("ratelimit:l1:cluster:available", 1000000)

    -- Setup L2 app
    redis:hset("ratelimit:l2:" .. app_id, "guaranteed_quota", 10000)
    redis:hset("ratelimit:l2:" .. app_id, "burst_quota", 50000)
    redis:hset("ratelimit:l2:" .. app_id, "current_tokens", 10000)
    redis:hset("ratelimit:l2:" .. app_id, "max_borrow", 5000)

    -- Setup L3 local cache
    ngx.shared.ratelimit:set("local:" .. app_id .. ":tokens", 1000)
  end)

  it("should flow from L3 to L2 to L1", function()
    local cost = 100

    -- L3 has 1000 tokens
    local result = l3_bucket.acquire(app_id, cost)
    assert.is_true(result.success)
    assert.equals("local_hit", result.source)
    assert.equals(900, ngx.shared.ratelimit:get("local:" .. app_id .. ":tokens"))

    -- Exhaust L3
    ngx.shared.ratelimit:set("local:" .. app_id .. ":tokens", 0)

    -- Should fetch from L2
    result = l3_bucket.acquire(app_id, cost)
    assert.is_true(result.success)
    assert.equals("remote_fetch", result.source)
    assert.equals(900, ngx.shared.ratelimit:get("local:" .. app_id .. ":tokens"))  -- Fetched 1000

    -- Verify L2 decreased
    local l2_tokens = tonumber(redis:hget("ratelimit:l2:" .. app_id, "current_tokens"))
    assert.is_true(l2_tokens < 10000)
  end)

  it("should borrow from L1 when L2 exhausted", function()
    -- Exhaust L2
    redis:hset("ratelimit:l2:" .. app_id, "current_tokens", 0)

    -- Acquire should borrow from L1
    local result = l2_bucket.acquire_with_borrow(app_id, 1000)
    assert.is_true(result.success)
    assert.equals("borrowed", result.source)

    -- Verify debt created
    local debt = tonumber(redis:hget("ratelimit:l2:" .. app_id, "debt"))
    assert.is_true(debt > 0)
  end)
end)
```

---

## 10. End-to-End Testing Strategy

### 10.1 E2E Test Scenarios

| Scenario | Description | Priority |
|----------|-------------|----------|
| **Happy Path** | Normal request flows through all layers | P0 |
| **Burst Traffic** | Sudden traffic spike handled gracefully | P0 |
| **Emergency Mode** | Emergency activation and behavior | P0 |
| **Failover** | Redis failure and recovery | P0 |
| **Multi-App Isolation** | Apps don't affect each other | P0 |
| **Cost Accuracy** | Cost calculation matches actual usage | P0 |

### 10.2 E2E Test Examples

#### **Happy Path E2E**

```lua
-- tests/e2e/happy_path_e2e_spec.lua
describe("Happy Path E2E", function()
  local http = require("resty.http")
  local httpc = http.new()

  it("should complete full request flow successfully", function()
    -- Step 1: Create app config via API
    local create_res = httpc:request_uri("http://localhost:8080/api/v1/apps", {
      method = "POST",
      body = cjson.encode({
        app_id = "e2e-test-app",
        guaranteed_quota = 10000,
        burst_quota = 50000
      }),
      headers = {["Content-Type"] = "application/json"}
    })
    assert.equals(201, create_res.status)

    -- Step 2: Send test request
    local req_res = httpc:request_uri("http://localhost:8080/api/v1/test", {
      method = "GET",
      headers = {
        ["X-App-Id"] = "e2e-test-app",
        ["Content-Length"] = "1024"
      }
    })
    assert.equals(200, req_res.status)
    assert.is_truthy(req_res.header["X-RateLimit-Cost"])
    assert.is_truthy(req_res.header["X-RateLimit-Remaining"])

    -- Step 3: Verify metrics
    local metrics_res = httpc:request_uri("http://localhost:9145/metrics")
    assert.is_true(metrics_res.body:match("ratelimit_requests_total"))

    -- Step 4: Verify L3 cache hit
    local second_req = httpc:request_uri("http://localhost:8080/api/v1/test", {
      method = "GET",
      headers = {
        ["X-App-Id"] = "e2e-test-app",
        ["Content-Length"] = "1024"
      }
    })
    assert.equals(200, second_req.status)

    -- Step 5: Verify app state
    local app_status = httpc:request_uri("http://localhost:8080/api/v1/apps/e2e-test-app")
    local status = cjson.decode(app_status.body)
    assert.is_true(status.current_tokens < 10000)  -- Tokens consumed
  end)
end)
```

#### **Burst Traffic E2E**

```lua
-- tests/e2e/burst_traffic_e2e_spec.lua
describe("Burst Traffic E2E", function()
  local http = require("resty.http")

  it("should handle burst traffic without dropping requests", function()
    local threads = {}
    local success_count = 0
    local reject_count = 0

    -- Send 1000 requests rapidly
    for i = 1, 1000 do
      threads[i] = ngx.thread.spawn(function()
        local httpc = http.new()
        local res = httpc:request_uri("http://localhost:8080/api/v1/test", {
          method = "GET",
          headers = {
            ["X-App-Id"] = "burst-test-app",
            ["Content-Length"] = "1024"
          }
        })

        if res.status == 200 then
          success_count = success_count + 1
        elseif res.status == 429 then
          reject_count = reject_count + 1
        end
      end)
    end

    -- Wait for all threads
    for _, thread in ipairs(threads) do
      ngx.thread.wait(thread)
    end

    -- Most should succeed (burst quota 50000, cost per request 2)
    -- 50000 / 2 = 25000 requests capacity, we only send 1000
    assert.is_true(success_count > 950)  -- >95% success
    assert.is_true(reject_count < 50)     -- <5% rejection
  end)
end)
```

---

## 11. Performance & Load Testing

### 11.1 Performance Testing Tools

| Tool | Use Case | Pros | Cons |
|------|----------|------|------|
| **k6** | Load testing, E2E | Modern JS, good metrics | Learning curve |
| **wrk** | Microbenchmarking | Fast, lightweight | Lua scripting only |
| **locust** | User simulation | Python, distributed | Heavy overhead |
| **ab** | Simple load tests | Simple, available | Limited features |

### 11.2 Load Testing Scenarios

#### **Baseline Load Test (k6)**

```javascript
// tests/performance/load/baseline_load_k6.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');

export let options = {
  stages: [
    { duration: '1m', target: 100 },   // Ramp up to 100 users
    { duration: '5m', target: 1000 },  // Ramp up to 1000 users
    { duration: '10m', target: 1000 }, // Stay at 1000 users for 10 min
    { duration: '2m', target: 0 },     // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<10', 'p(99)<50'],  // 95% <10ms, 99% <50ms
    http_req_failed: ['rate<0.01'],               // <1% errors
    errors: ['rate<0.01'],
  },
};

const BASE_URL = 'http://localhost:8080';
const APP_ID = 'load-test-app';

export default function() {
  let payload = JSON.stringify({
    key: `user-${__VU}-${__ITER}`,
    data: 'x'.repeat(1024)  // 1KB payload
  });

  let params = {
    headers: {
      'Content-Type': 'application/json',
      'X-App-Id': APP_ID,
    },
  };

  let res = http.post(`${BASE_URL}/api/v1/data`, payload, params);

  let success = check(res, {
    'status is 200': (r) => r.status === 200,
    'has rate limit headers': (r) =>
      r.headers['X-RateLimit-Cost'] !== undefined &&
      r.headers['X-RateLimit-Remaining'] !== undefined,
    'response time < 10ms': (r) => r.timings.duration < 10,
  });

  errorRate.add(!success);

  sleep(1);  // 1 request per second per user
}

export function teardown(data) {
  console.log('Test completed. Check Grafana dashboard for results.');
}
```

#### **Peak Load Test (k6)**

```javascript
// tests/performance/load/peak_load_k6.js
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 10000 },   // Spike to 10k users
    { duration: '5m', target: 10000 },   // Hold at 10k users
    { duration: '2m', target: 100 },     // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<50'],     // Relaxed threshold
    http_req_failed: ['rate<0.05'],      // Accept up to 5% errors
  },
};

export default function() {
  let res = http.get('http://localhost:8080/api/v1/data', {
    headers: {'X-App-Id': 'peak-test-app'},
  });

  check(res, {
    'status is 200 or 429': (r) => r.status === 200 || r.status === 429,
  });
}
```

#### **Soak Test (24-hour)**

```javascript
// tests/performance/load/soak_test_k6.js
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  stages: [
    { duration: '5m', target: 100 },
    { duration: '24h', target: 100 },    // 24-hour soak
    { duration: '5m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<20'],
    http_req_failed: ['rate<0.001'],     // Very strict error rate
  },
};

export default function() {
  let res = http.get('http://localhost:8080/api/v1/health', {
    headers: {'X-App-Id': 'soak-test-app'},
  });

  check(res, {
    'status is 200': (r) => r.status === 200,
  });
}
```

### 11.3 Latency Benchmarks

```lua
-- tests/performance/latency/p99_latency_bench.lua
local bench = require("benchmark")

describe("P99 Latency Benchmark", function()
  it("should achieve P99 <10ms for local cache hits", function()
    local latencies = {}
    local iterations = 1000

    for i = 1, iterations do
      local start = ngx.now()
      l3_bucket.acquire("bench-app", 10)
      table.insert(latencies, (ngx.now() - start) * 1000)  -- Convert to ms
    end

    table.sort(latencies)
    local p99_index = math.floor(iterations * 0.99)
    local p99 = latencies[p99_index]

    assert.is_true(p99 < 10, "P99 latency is " .. p99 .. "ms, expected <10ms")
  end)

  it("should achieve P99 <50ms for Redis calls", function()
    local latencies = {}
    local iterations = 100

    for i = 1, iterations do
      local start = ngx.now()
      l2_bucket.acquire("bench-app", 100)
      table.insert(latencies, (ngx.now() - start) * 1000)
    end

    table.sort(latencies)
    local p99_index = math.floor(iterations * 0.99)
    local p99 = latencies[p99_index]

    assert.is_true(p99 < 50, "P99 latency is " .. p99 .. "ms, expected <50ms")
  end)
end)
```

### 11.4 Performance Targets

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| **P50 Latency** | <1ms (L3 hit) | k6 histogram |
| **P95 Latency** | <10ms | k6 histogram |
| **P99 Latency** | <50ms | k6 histogram |
| **Throughput** | >50k TPS | wrk/k6 requests/s |
| **L3 Cache Hit Rate** | >95% | Prometheus metrics |
| **Redis Operations/s** | >10k | Redis INFO |
| **Memory Usage** | <2GB per Nginx instance | Docker stats |

---

## 12. Configuration Validation

### 12.1 Nginx Configuration Validation

```lua
-- tests/config/nginx_conf_spec.lua
describe("Nginx Configuration Validation", function()
  it("should have valid syntax", function()
    local handle = io.popen("nginx -t -c /etc/nginx/nginx.conf 2>&1")
    local result = handle:read("*a")
    handle:close()

    assert.is_true(result:match("successful"), "Nginx config validation failed:\n" .. result)
  end)

  it("should pass Gixy security scan", function()
    local handle = io.popen("gixy -c /etc/nginx/nginx.conf 2>&1")
    local result = handle:read("*a")
    handle:close()

    -- Parse Gixy output for issues
    local issue_count = 0
    for line in result:gmatch("[^\r\n]+") do
      if line:match("%[.*%]") then  -- Gixy issue format
        issue_count = issue_count + 1
      end
    end

    assert.equals(0, issue_count, "Gixy found " .. issue_count .. " security issues")
  end)

  it("should have all required shared dictionaries", function()
    local required_dicts = {"ratelimit", "ratelimit_locks", "ratelimit_metrics", "config_cache"}

    for _, dict_name in ipairs(required_dicts) do
      local dict = ngx.shared[dict_name]
      assert.is_not_nil(dict, "Missing shared dict: " .. dict_name)
    end
  end)

  it("should have correct lua_package_path", function()
    local config = io.open("/etc/nginx/nginx.conf"):read("*a")
    assert.is_true(config:match("lua_package_path"), "Missing lua_package_path")
    assert.is_true(config:match("ratelimit"), "lua_package_path doesn't include ratelimit")
  end)
end)
```

### 12.2 Lua Script Validation

```lua
-- tests/config/lua_scripts_syntax_spec.lua
describe("Lua Script Validation", function()
  local scripts = {
    "lua/ratelimit/init.lua",
    "lua/ratelimit/cost.lua",
    "lua/ratelimit/l3_bucket.lua",
    "lua/ratelimit/redis.lua",
    "lua/ratelimit/metrics.lua",
    "lua/ratelimit/timer.lua"
  }

  for _, script_path in ipairs(scripts) do
    it("should validate " .. script_path, function()
      local full_path = "/etc/nginx/" .. script_path
      local file = io.open(full_path, "r")
      local content = file:read("*a")
      file:close()

      -- Try to compile
      local ok, err = loadstring(content)
      assert.is_true(ok ~= nil, "Syntax error in " .. script_path .. ": " .. tostring(err))
    end)
  end

  it("should detect missing require() statements", function()
    local init_file = io.open("/etc/nginx/lua/ratelimit/init.lua"):read("*a")

    local required_modules = {
      "ratelimit.cost",
      "ratelimit.l3_bucket",
      "ratelimit.redis",
      "ratelimit.metrics"
    }

    for _, module in ipairs(required_modules) do
      assert.is_true(init_file:match('require%("' .. module .. '"') or
                              init_file:match('require\(' .. module .. '\)'),
                     "Missing require: " .. module)
    end
  end)
end)
```

### 12.3 Redis Lua Script Validation

```lua
-- tests/config/redis_scripts_validation_spec.lua
describe("Redis Script Validation", function()
  local scripts = {
    "scripts/acquire_tokens.lua",
    "scripts/batch_acquire.lua",
    "scripts/three_layer_deduct.lua",
    "scripts/borrow_tokens.lua",
    "scripts/repay_tokens.lua"
  }

  before_each(function()
    redis = require("resty.redis"):new()
    redis:connect("127.0.0.1", 6379)
  end)

  after_each(function()
    redis:set_keepalive()
  end)

  for _, script_path in ipairs(scripts) do
    it("should validate " .. script_path, function()
      local script = io.open(script_path):read("*a")

      -- Load script into Redis (validates syntax)
      local sha, err = redis:script("load", script)

      assert.is_not_nil(sha, "Script validation failed for " .. script_path .. ": " .. tostring(err))
      assert.is_string(sha, "Script load should return SHA")
    end)
  end

  it("should test acquire_tokens.lua logic", function()
    local script = io.open("scripts/acquire_tokens.lua"):read("*a")

    -- Setup test data
    redis:hset("ratelimit:l2:test-app", "guaranteed_quota", 1000)
    redis:hset("ratelimit:l2:test-app", "burst_quota", 5000)
    redis:hset("ratelimit:l2:test-app", "current_tokens", 1000)
    redis:hset("ratelimit:l2:test-app", "last_refill", ngx.now())

    -- Execute script
    local result = redis:eval(script, 1, "ratelimit:l2:test-app", 100, ngx.now())

    -- Result should be table: {1, remaining, burst_remaining}
    assert.equals(1, result[1])  -- Success
    assert.equals(900, result[2])  -- 1000 - 100

    -- Cleanup
    redis:del("ratelimit:l2:test-app")
  end)
end)
```

### 12.4 OpenAPI Contract Validation

```lua
-- tests/config/openapi_contract_spec.lua
describe("OpenAPI Contract Validation", function()
  local http = require("resty.http")
  local openapi_schema = require("tests.fixtures.openapi_spec")

  it("should validate GET /api/v1/apps/:app_id", function()
    local httpc = http.new()
    local res = httpc:request_uri("http://localhost:8080/api/v1/apps/video-service", {
      method = "GET"
    })

    assert.equals(200, res.status)

    local response = cjson.decode(res.body)
    local schema = openapi_schema.paths["/apps/{app_id}"].get.responses[200].content

    -- Validate required fields
    assert.is_not_nil(response.app_id)
    assert.is_not_nil(response.guaranteed_quota)
    assert.is_not_nil(response.burst_quota)
    assert.is_not_nil(response.current_tokens)

    -- Validate types
    assert.is_string(response.app_id)
    assert.is_number(response.guaranteed_quota)
  end)

  it("should validate POST /api/v1/apps", function()
    local httpc = http.new()
    local new_app = {
      app_id = "contract-test-app",
      guaranteed_quota = 5000,
      burst_quota = 25000
    }

    local res = httpc:request_uri("http://localhost:8080/api/v1/apps", {
      method = "POST",
      body = cjson.encode(new_app),
      headers = {["Content-Type"] = "application/json"}
    })

    assert.equals(201, res.status)

    local response = cjson.decode(res.body)
    assert.equals(new_app.app_id, response.app_id)
    assert.equals(new_app.guaranteed_quota, response.guaranteed_quota)
  end)
end)
```

---

## 13. Chaos Testing

### 13.1 Chaos Testing Strategy

| Scenario | Tool | Frequency | Success Criteria |
|----------|------|-----------|------------------|
| **Redis Failure** | Toxiproxy | Weekly | Fail-open activates |
| **Network Partition** | Chaos Mesh | Weekly | Graceful degradation |
| **Pod Kill** | Chaos Mesh | Weekly | Auto-recovery |
| **Resource Starvation** | Chaos Mesh | Weekly | SLOs maintained |
| **Redis Master Failover** | redis-cli | Monthly | <5s interruption |

### 13.2 Chaos Test Examples

#### **Redis Failure Test**

```lua
-- tests/chaos/redis_failure_chaos_spec.lua
describe("Redis Failure Chaos Test", function()
  local http = require("resty.http")

  it("should handle Redis connection failure gracefully", function()
    -- Disable Redis via Toxiproxy
    os.execute("toxiproxy-cli disable redis")

    -- Try to make request
    local httpc = http.new()
    local res = httpc:request_uri("http://localhost:8080/api/v1/test", {
      headers = {["X-App-Id"] = "chaos-test-app"}
    })

    -- Should still work (fail-open)
    assert.equals(200, res.status)

    -- Verify fail-open mode active
    local status_res = httpc:request_uri("http://localhost:8080/admin/ratelimit/status")
    local status = cjson.decode(status_res.body)
    assert.equals("fail_open", status.mode)

    -- Re-enable Redis
    os.execute("toxiproxy-cli enable redis")

    -- Wait for recovery
    ngx.sleep(2)

    -- Should return to normal
    res = httpc:request_uri("http://localhost:8080/api/v1/test", {
      headers = {["X-App-Id"] = "chaos-test-app"]}
    })
    assert.equals(200, res.status)

    status_res = httpc:request_uri("http://localhost:8080/admin/ratelimit/status")
    status = cjson.decode(status_res.body)
    assert.equals("normal", status.mode)
  end)
end)
```

#### **Network Partition Test**

```lua
-- tests/chaos/network_partition_chaos_spec.lua
describe("Network Partition Chaos Test", function()
  it("should handle partial network partition", function()
    -- Partition Nginx from Redis (allow 10% packet loss)
    os.execute("toxiproxy-cli toxic add redis -t slow_close -a delay=100")

    local httpc = http.new()
    local success_count = 0
    local timeout_count = 0

    -- Send 100 requests
    for i = 1, 100 do
      local res = httpc:request_uri("http://localhost:8080/api/v1/test", {
        headers = {["X-App-Id"] = "partition-test-app"},
        timeout = 1000  -- 1 second timeout
      })

      if res.status == 200 then
        success_count = success_count + 1
      elseif res.status == 504 or res.timed_out then
        timeout_count = timeout_count + 1
      end
    end

    -- Most should succeed (fail-open or retries)
    assert.is_true(success_count > 80, "Only " .. success_count .. "/100 succeeded")

    -- Cleanup
    os.execute("toxiproxy-cli toxic remove redis slow_close")
  end)
end)
```

---

## 14. CI/CD Integration

### 14.1 CI Pipeline Configuration

```yaml
# .github/workflows/test.yml
name: Test Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Lua
        uses: leafo/gh-actions-lua@v8

      - name: Lint Lua
        run: |
          luacheck lua/ tests/ --no-unused --globals ngx

      - name: Validate Nginx Config
        run: |
          docker run --rm -v $(pwd):/etc/nginx \
            openresty/openresty:alpine \
            nginx -t -c /etc/nginx/nginx.conf

      - name: Gixy Security Scan
        run: |
          pip install gixy
          gixy nginx.conf

  unit-test:
    name: Unit Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Lua
        uses: leafo/gh-actions-lua@v8

      - name: Install Dependencies
        run: |
          luarocks install busted
          luarocks install luacov
          luarocks install lua-resty-http

      - name: Run Unit Tests
        run: |
          busted tests/unit --coverage

      - name: Upload Coverage
        run: |
          luacov
          bash <(curl -s https://codecov.io/bash) -f luacov.report.out

  integration-test:
    name: Integration Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Start Redis
        run: |
          docker-compose -f docker-compose.test.yml up -d redis

      - name: Setup Lua
        uses: leafo/gh-actions-lua@v8

      - name: Install Dependencies
        run: |
          luarocks install busted
          luarocks install lua-resty-redis

      - name: Run Integration Tests
        run: |
          busted tests/integration
        env:
          REDIS_HOST: 127.0.0.1
          REDIS_PORT: 6379

      - name: Stop Redis
        run: |
          docker-compose -f docker-compose.test.yml down

  e2e-test:
    name: E2E Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Start Test Environment
        run: |
          docker-compose -f docker-compose.test.yml up -d

      - name: Wait for Services
        run: |
          sleep 10
          curl --retry 10 --retry-delay 1 --retry-connrefused \
            http://localhost/health

      - name: Setup Lua
        uses: leafo/gh-actions-lua@v8

      - name: Run E2E Tests
        run: |
          busted tests/e2e
        env:
          BASE_URL: http://localhost

      - name: Upload Logs
        if: failure()
        run: |
          docker-compose -f docker-compose.test.yml logs > logs.txt
          cat logs.txt

      - name: Stop Test Environment
        run: |
          docker-compose -f docker-compose.test.yml down

  performance-test:
    name: Performance Tests
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v3

      - name: Start Test Environment
        run: |
          docker-compose -f docker-compose.test.yml up -d

      - name: Wait for Services
        run: sleep 10

      - name: Install k6
        run: |
          sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 \
            --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
          echo "deb https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
          sudo apt-get update
          sudo apt-get install k6

      - name: Run Load Test
        run: |
          k6 run tests/performance/load/baseline_load_k6.js \
            --out json=results.json

      - name: Check Thresholds
        run: |
          # Parse results and check thresholds
          python tests/performance/check_thresholds.py results.json

      - name: Stop Test Environment
        run: |
          docker-compose -f docker-compose.test.yml down
```

### 14.2 Pre-commit Hook

```bash
# .git/hooks/pre-commit
#!/bin/bash

echo "Running pre-commit checks..."

# Lint Lua
echo "Linting Lua files..."
luacheck lua/ tests/ || exit 1

# Validate Nginx config
echo "Validating Nginx configuration..."
nginx -t -c nginx.conf || exit 1

# Run unit tests
echo "Running unit tests..."
busted tests/unit || exit 1

echo "Pre-commit checks passed!"
```

### 14.3 CD Pipeline Configuration

```yaml
# .github/workflows/deploy.yml
name: Deploy Pipeline

on:
  push:
    tags:
      - 'v*'

jobs:
  test:
    name: Test
    uses: ./.github/workflows/test.yml

  build-and-push:
    name: Build and Push Docker Image
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2

      - name: Login to Docker Hub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Build and Push
        uses: docker/build-push-action@v2
        with:
          context: .
          push: true
          tags: |
            yourorg/nginx-ratelimit:${{ github.ref_name }}
            yourorg/nginx-ratelimit:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy-staging:
    name: Deploy to Staging
    needs: build-and-push
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to Kubernetes
        run: |
          kubectl set image deployment/nginx-ratelimit \
            nginx=yourorg/nginx-ratelimit:${{ github.ref_name }} \
            -n ratelimit-staging

      - name: Wait for Rollout
        run: |
          kubectl rollout status deployment/nginx-ratelimit -n ratelimit-staging

      - name: Run Smoke Tests
        run: |
          k6 run tests/e2e/smoke_test_k6.js \
            --env URL=https://staging.example.com

  deploy-production:
    name: Deploy to Production
    needs: deploy-staging
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to Kubernetes (Canary)
        run: |
          kubectl apply -f k8s/canary.yaml -n ratelimit-prod

      - name: Monitor Canary
        run: |
          # Monitor metrics for 30 minutes
          python scripts/monitor_canary.py --duration 1800

      - name: Full Rollout
        run: |
          kubectl set image deployment/nginx-ratelimit \
            nginx=yourorg/nginx-ratelimit:${{ github.ref_name }} \
            -n ratelimit-prod
```

---

## 15. Sample Test Templates

### 15.1 Test Template for New Features

```lua
-- tests/unit/FEATURE_spec.lua
--[[
Feature Name: Brief description
Author: Your name
Date: YYYY-MM-DD
Description: Detailed description of what is being tested
]]

local feature_module = require("ratelimit.FEATURE")
local factory = require("tests.helpers.factory")
local cleanup = require("tests.helpers.cleanup")

describe("FEATURE_NAME", function()
  local test_context

  before_each(function()
    -- Setup test environment
    test_context = cleanup.isolate_test("feature")
  end)

  after_each(function()
    -- Cleanup
    cleanup.redis_all()
    cleanup.nginx_shared_dict("ratelimit")
  end)

  describe("happy path", function()
    it("should do X successfully", function()
      -- Arrange
      local input = factory.valid_input()

      -- Act
      local result = feature_module.do_something(input)

      -- Assert
      assert.is_true(result.success)
    end)
  end)

  describe("error cases", function()
    it("should handle invalid input", function()
      local result = feature_module.do_something(nil)
      assert.is_false(result.success)
      assert.equals("invalid_input", result.error_code)
    end)
  end)

  describe("edge cases", function()
    it("should handle boundary conditions", function()
      -- Test with max/min values
    end)
  end)
end)
```

### 15.2 Integration Test Template

```lua
-- tests/integration/FEATURE_integration_spec.lua
describe("FEATURE Integration", function()
  local redis
  local http

  before_each(function()
    redis = require("resty.redis"):new()
    redis:connect("127.0.0.1", 6379)

    http = require("resty.http").new()
  end)

  after_each(function()
    redis:flush_all()
    redis:set_keepalive()
  end)

  it("should integrate correctly with Redis", function()
    -- Setup
    redis:set("test:key", "value")

    -- Act
    local result = your_function()

    -- Assert
    assert.is_true(result.success)
  end)
end)
```

### 15.3 E2E Test Template

```javascript
// tests/e2e/FEATURE_e2e_k6.js
import http from 'k6/http';
import { check } from 'k6';

export let options = {
  stages: [
    { duration: '1m', target: 10 },
    { duration: '2m', target: 10 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<100'],
    http_req_failed: ['rate<0.01'],
  },
};

const BASE_URL = __ENV.URL || 'http://localhost:8080';

export default function() {
  let res = http.get(`${BASE_URL}/api/v1/endpoint`, {
    headers: {'X-App-Id': 'e2e-test-app'},
  });

  check(res, {
    'status is 200': (r) => r.status === 200,
    'has required headers': (r) => r.headers['X-Required-Header'] !== undefined,
  });
}
```

---

## 16. Performance Testing Scenarios

### 16.1 Scenario Definitions

| Scenario | Description | Duration | Target |
|----------|-------------|----------|--------|
| **Baseline** | Normal daily traffic | 10 min | P99 <10ms |
| **Peak** | Peak traffic (2x baseline) | 5 min | P99 <50ms |
| **Flash Crowd** | Sudden spike (10x baseline) | 2 min | <1% errors |
| **Soak Test** | Sustained load | 24 hours | No memory leaks |
| **Stress Test** | Find breaking point | Until failure | Record max TPS |

### 16.2 Performance Test Execution

```bash
#!/bin/bash
# run_performance_tests.sh

echo "=== Starting Performance Tests ==="

# Baseline test
echo "Running baseline test..."
k6 run tests/performance/load/baseline_load_k6.js \
  --out json=baseline_results.json

# Peak load test
echo "Running peak load test..."
k6 run tests/performance/load/peak_load_k6.js \
  --out json=peak_results.json

# Stress test (find breaking point)
echo "Running stress test..."
k6 run tests/performance/stress/max_tps_stress_k6.js \
  --out json=stress_results.json

# Generate report
echo "Generating performance report..."
python scripts/generate_perf_report.py \
  baseline_results.json \
  peak_results.json \
  stress_results.json \
  > performance_report.md

echo "=== Performance Tests Complete ==="
echo "Report: performance_report.md"
```

### 16.3 Performance Regression Detection

```python
# scripts/performance_regression.py
import json
import sys

THRESHOLDS = {
    'p99_latency_ms': 10,
    'p95_latency_ms': 5,
    'error_rate': 0.01
}

def check_regression(current_results, baseline_results):
    """Check for performance regression"""
    regressions = []

    # P99 latency check
    current_p99 = current_results['metrics']['http_req_duration']['p(99)']
    baseline_p99 = baseline_results['metrics']['http_req_duration']['p(99)']

    if current_p99 > THRESHOLDS['p99_latency_ms']:
        regressions.append(f"P99 latency {current_p99}ms exceeds threshold {THRESHOLDS['p99_latency_ms']}ms")

    if current_p99 > baseline_p99 * 1.2:  # 20% degradation
        regressions.append(f"P99 latency degraded by {((current_p99/baseline_p99 - 1) * 100):.1f}%")

    # Error rate check
    error_rate = current_results['metrics']['http_req_failed']['rate']
    if error_rate > THRESHOLDS['error_rate']:
        regressions.append(f"Error rate {error_rate} exceeds threshold {THRESHOLDS['error_rate']}")

    return regressions

if __name__ == '__main__':
    with open(sys.argv[1]) as f:
        current = json.load(f)

    with open(sys.argv[2]) as f:
        baseline = json.load(f)

    regressions = check_regression(current, baseline)

    if regressions:
        print("PERFORMANCE REGRESSION DETECTED:")
        for regression in regressions:
            print(f"  - {regression}")
        sys.exit(1)
    else:
        print("No performance regression detected")
        sys.exit(0)
```

---

## 17. Test Reporting & Metrics

### 17.1 Test Metrics Dashboard

```promql
# Test Success Rate
sum(rate(test_results_total{status="passed"}[24h])) /
sum(rate(test_results_total[24h])) * 100

# Test Execution Time
histogram_quantile(0.99, rate(test_duration_seconds_bucket[24h]))

# Flaky Test Rate
sum(rate(test_flaky_total[24h])) /
sum(rate(test_results_total[24h])) * 100

# Coverage Percentage
test_code_coverage / 100
```

### 17.2 Automated Test Report

```lua
-- scripts/generate_test_report.lua
local json = require("cjson")

local function generate_report()
  local report = {
    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    summary = {
      total_tests = 0,
      passed = 0,
      failed = 0,
      skipped = 0,
      duration = 0
    },
    suites = {}
  }

  -- Parse test results
  local test_files = {
    "tests/unit/results.json",
    "tests/integration/results.json",
    "tests/e2e/results.json"
  }

  for _, file in ipairs(test_files) do
    local f = io.open(file, "r")
    if f then
      local results = json.decode(f:read("*a"))
      f:close()

      table.insert(report.suites, results)
      report.summary.total_tests = report.summary.total_tests + results.total
      report.summary.passed = report.summary.passed + results.passed
      report.summary.failed = report.summary.failed + results.failed
      report.summary.duration = report.summary.duration + results.duration
    end
  end

  -- Generate markdown report
  local md = io.open("test_report.md", "w")
  md:write("# Test Report\n\n")
  md:write("**Generated:** " .. report.timestamp .. "\n\n")
  md:write("## Summary\n\n")
  md:write("| Metric | Value |\n")
  md:write("|--------|-------|\n")
  md:write("| Total Tests | " .. report.summary.total_tests .. " |\n")
  md:write("| Passed | " .. report.summary.passed .. " |\n")
  md:write("| Failed | " .. report.summary.failed .. " |\n")
  md:write("| Duration | " .. report.summary.duration .. "s |\n")
  md:write("| Success Rate | " .. string.format("%.2f%%", report.summary.passed / report.summary.total_tests * 100) .. " |\n\n")

  md:close()
end

generate_report()
```

---

## 18. Summary & Next Steps

### 18.1 Testing Framework Checklist

- [ ] Install testing tools (busted, luacheck, k6, Gixy)
- [ ] Set up test environment (docker-compose.test.yml)
- [ ] Configure CI/CD pipeline
- [ ] Write unit tests for all modules
- [ ] Write integration tests for Redis/Nginx
- [ ] Write E2E tests for critical paths
- [ ] Set up performance benchmarks
- [ ] Configure chaos testing
- [ ] Implement test reporting
- [ ] Train team on testing practices

### 18.2 Best Practices

1. **Write tests first** (TDD approach) when possible
2. **Keep tests simple** - one assertion per test when practical
3. **Use descriptive test names** - "should X when Y"
4. **Mock external dependencies** - Redis, time, network
5. **Clean up after tests** - reset state in after_each
6. **Run tests frequently** - on every commit/PR
7. **Monitor test execution time** - keep tests fast
8. **Review flaky tests** - fix or remove unreliable tests
9. **Maintain high coverage** - target 90%+ for critical code
10. **Document complex scenarios** - explain why, not just what

### 18.3 Resources

- **Busted Documentation:** https://olivinelabs.com/busted/
- **k6 Documentation:** https://k6.io/docs/
- **Gixy Documentation:** https://github.com/yandex/gixy
- **OpenResty Testing Guide:** https://openresty.org/en/testing.html
- **Lua Best Practices:** https://lua-users.org/wiki/LuaStyleGuide

---

**Document End**

This comprehensive testing framework design ensures reliability, performance, and confidence in your distributed rate limiting system. Implement it incrementally, starting with unit tests and gradually adding integration, E2E, and performance tests as your system matures.
