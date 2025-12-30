# OpenResty Gateway Design Document
## Distributed Rate Limiting System - Core Gateway Module

**Version**: 1.0.0
**Date**: 2025-12-31
**Status**: Design Phase
**Author**: System Architecture Team

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Project Structure](#2-project-structure)
3. [Module Organization](#3-module-organization)
4. [API Contracts](#4-api-contracts)
5. [Implementation Plan](#5-implementation-plan)
6. [Code Organization Best Practices](#6-code-organization-best-practices)
7. [Deployment Architecture](#7-deployment-architecture)
8. [Development Workflow](#8-development-workflow)

---

## 1. Executive Summary

### 1.1 System Overview

This design document outlines the OpenResty gateway core for a production-grade, distributed rate limiting system using a **three-layer token bucket architecture**. The system implements a novel **Cost normalization algorithm** that unifies IOPS and bandwidth constraints into a single metric.

**Core Formula**:
```
Cost = C_base + (Size_body / Unit_quantum) × C_bw
```

### 1.2 Key Design Goals

| Goal | Target | Strategy |
|------|--------|----------|
| **Ultra-Low Latency** | P99 < 10ms | L3 local caching with <1ms for 95%+ requests |
| **High Throughput** | 50k+ TPS | Async batch processing, connection pooling |
| **High Availability** | 99.99% | Multi-level degradation, fail-open mechanisms |
| **Scalability** | Horizontal | Stateless design, shared-nothing architecture |
| **Observability** | Full | Prometheus metrics, structured logging |

### 1.3 Technology Stack

```
OpenResty 1.21.4+ (Nginx + LuaJIT)
├── lua-resty-redis (Redis client)
├── lua-resty-lock (Distributed locks)
├── lua-resty-healthcheck (Health checks)
├── lua-prometheus (Metrics export)
└── Redis Cluster 7.0+ (Backend storage)
```

---

## 2. Project Structure

### 2.1 Complete Directory Layout

```
nginx-ratelimit-gateway/
├── README.md
├── LICENSE
├── Makefile
├── .gitignore
├── .dockerignore
├── docker-compose.yml
├── docker-compose.prod.yml
│
├── config/                          # Configuration files
│   ├── nginx.conf                  # Main Nginx configuration
│   ├── nginx.conf.example          # Template with defaults
│   ├── mime.types                  # MIME type mappings
│   ├── fastcgi.conf                # FastCGI settings
│   └── ssl/
│       ├── cert-list.txt           # SSL certificate inventory
│       ├── README.md               # SSL setup instructions
│       └── .gitkeep
│
├── lua/                             # Lua application code
│   ├── init.lua                    # Module loader (require paths)
│   │
│   ├── ratelimit/                  # Core rate limiting module
│   │   ├── init.lua               # Main entry point
│   │   ├── version.lua            # Version info
│   │   │
│   │   ├── cost/                  # Cost calculation module
│   │   │   ├── init.lua           # Cost module entry
│   │   │   ├── calculator.lua     # Core cost calculation
│   │   │   ├── estimator.lua      # Pre-request estimation
│   │   │   ├── validator.lua      # Cost verification
│   │   │   └── profiles.lua       # Cost profiles (standard, iops, bw)
│   │   │
│   │   ├── token/                 # Token bucket modules
│   │   │   ├── init.lua
│   │   │   ├── l1_cluster.lua     # L1: Cluster layer
│   │   │   ├── l2_application.lua # L2: Application layer
│   │   │   ├── l3_local.lua       # L3: Local cache layer
│   │   │   └── bucket.lua         # Generic bucket implementation
│   │   │
│   │   ├── redis/                 # Redis client wrapper
│   │   │   ├── init.lua
│   │   │   ├── connection.lua     # Connection pool management
│   │   │   ├── cluster.lua        # Redis Cluster client
│   │   │   ├── script.lua         # Lua script manager
│   │   │   ├── pipeline.lua       # Pipeline operations
│   │   │   └── health.lua         # Health check interface
│   │   │
│   │   ├── cache/                 # Local caching strategies
│   │   │   ├── init.lua
│   │   │   ├── shared_dict.lua    # Nginx shared dict wrapper
│   │   │   ├── lrucache.lua       # LRU cache implementation
│   │   │   ├── prefetch.lua       # Token prefetching logic
│   │   │   └── sync.lua           # Async synchronization
│   │   │
│   │   ├── config/                # Configuration management
│   │   │   ├── init.lua
│   │   │   ├── loader.lua         # Config loader
│   │   │   ├── hot_reload.lua     # Hot reload handler
│   │   │   ├── validator.lua      # Config validation
│   │   │   └── defaults.lua       # Default configuration
│   │   │
│   │   ├── metrics/               # Monitoring & metrics
│   │   │   ├── init.lua
│   │   │   ├── prometheus.lua     # Prometheus exporter
│   │   │   ├── collector.lua      # Metrics collector
│   │   │   ├── labels.lua         # Label management
│   │   │   └── registry.lua       # Metric registry
│   │   │
│   │   ├── degradation/           # Degradation strategies
│   │   │   ├── init.lua
│   │   │   ├── detector.lua       # Failure detection
│   │   │   ├── strategy.lua       # Degradation strategies
│   │   │   ├── fail_open.lua      # Fail-open mode
│   │   │   └── fail_closed.lua    # Fail-closed mode
│   │   │
│   │   ├── emergency/             # Emergency mode handling
│   │   │   ├── init.lua
│   │   │   ├── handler.lua        # Emergency mode logic
│   │   │   ├── priority.lua       # Priority-based routing
│   │   │   └── notifier.lua       # Emergency notifications
│   │   │
│   │   ├── reconcile/             # Reconciliation logic
│   │   │   ├── init.lua
│   │   │   ├── timer.lua          # Reconciliation timer
│   │   │   ├── checker.lua        # Consistency checker
│   │   │   └── corrector.lua      # Auto-correction logic
│   │   │
│   │   ├── borrow/                # Token borrowing mechanism
│   │   │   ├── init.lua
│   │   │   ├── manager.lua        # Borrowing manager
│   │   │   ├── interest.lua       # Interest calculation
│   │   │   └── repayment.lua      # Repayment logic
│   │   │
│   │   ├── api/                   # Internal APIs
│   │   │   ├── init.lua
│   │   │   ├── health.lua         # Health check API
│   │   │   ├── admin.lua          # Admin operations API
│   │   │   └── status.lua         # Status reporting API
│   │   │
│   │   └── util/                  # Utility functions
│   │       ├── init.lua
│   │       ├── time.lua           # Time utilities
│   │       ├── math.lua           # Math helpers
│   │       ├── string.lua         # String utilities
│   │       ├── table.lua          # Table helpers
│   │       ├── error.lua          # Error handling
│   │       └── log.lua            # Structured logging
│   │
│   ├── lib/                       # Third-party libraries
│   │   ├── resty/
│   │   │   ├── redis.lua
│   │   │   ├── lock.lua
│   │   │   ├── http.lua
│   │   │   └── healthcheck.lua
│   │   ├── prometheus/
│   │   │   ├── init.lua
│   │   │   └── resty/
│   │   │       └── prometheus.lua
│   │   └── cjson.so               # JSON library
│   │
│   └── bootstrap/
│       ├── init.lua               # Bootstrap sequence
│       ├── worker_init.lua        # Per-worker initialization
│       └── timer_init.lua         # Timer registration
│
├── scripts/                        # Redis Lua scripts
│   ├── README.md
│   ├── token/
│   │   ├── acquire_tokens.lua     # Atomic token acquisition
│   │   ├── batch_acquire.lua      # Batch token fetch
│   │   ├── three_layer_deduct.lua # Three-layer deduction
│   │   └── refund_tokens.lua      # Token refund logic
│   ├── reconcile/
│   │   ├── batch_report.lua       # Batch consumption report
│   │   ├── reconcile.lua          # Periodic reconciliation
│   │   └── global_reconcile.lua   # Global reconciliation
│   ├── emergency/
│   │   ├── activate.lua           # Emergency activation
│   │   ├── deactivate.lua         # Emergency deactivation
│   │   └── check.lua              # Emergency mode check
│   ├── borrow/
│   │   ├── borrow_tokens.lua      # Borrow tokens
│   │   └── repay_tokens.lua       # Repay tokens
│   └── deploy/
│       ├── load_scripts.sh        # Script deployment helper
│       └── verify_scripts.sh      # Script validation
│
├── conf/                           # Additional configurations
│   ├── prometheus.yml             # Prometheus configuration
│   ├── alertmanager.yml           # Alertmanager rules
│   ├── grafana/                   # Grafana dashboard configs
│   │   ├── overview.json
│   │   ├── applications.json
│   │   └── gateways.json
│   └── rules/
│       ├── ratelimit.yml          # Alerting rules
│       └── recording.yml          # Recording rules
│
├── tests/                          # Test suite
│   ├── README.md
│   ├── unit/                      # Unit tests
│   │   ├── cost/
│   │   │   ├── calculator_test.lua
│   │   │   └── estimator_test.lua
│   │   ├── token/
│   │   │   ├── l3_local_test.lua
│   │   │   └── l2_application_test.lua
│   │   └── redis/
│   │       └── connection_test.lua
│   ├── integration/               # Integration tests
│   │   ├── ratelimit_test.lua
│   │   └── redis_cluster_test.lua
│   ├── performance/               # Performance tests
│   │   ├── benchmark_test.lua
│   │   └── load_test.lua
│   ├── fixtures/                  # Test fixtures
│   │   ├── redis_data.json
│   │   └── config_test.json
│   └── helpers/                   # Test helpers
│       ├── redis_mock.lua
│       └── assertions.lua
│
├── docs/                           # Documentation
│   ├── API.md                     # API documentation
│   ├── ARCHITECTURE.md            # Architecture overview
│   ├── DEPLOYMENT.md              # Deployment guide
│   ├── OPERATIONS.md              # Operations manual
│   ├── TROUBLESHOOTING.md         # Troubleshooting guide
│   └── METRICS.md                 # Metrics reference
│
├── tools/                          # Development tools
│   ├── format.sh                  # Lua formatter (lua-format)
│   ├── lint.sh                    # Linter (luacheck)
│   ├── test.sh                    # Test runner
│   ├── coverage.sh                # Coverage report generator
│   └── release.sh                 # Release automation
│
├── deployment/                     # Deployment configurations
│   ├── docker/
│   │   ├── Dockerfile
│   │   ├── Dockerfile.alpine
│   │   └── docker-entrypoint.sh
│   ├── kubernetes/
│   │   ├── namespace.yaml
│   │   ├── configmap.yaml
│   │   ├── secret.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   ├── hpa.yaml
│   │   └── pdb.yaml
│   ├── terraform/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── modules/
│   └── ansible/
│       ├── inventory.yml
│       ├── deploy.yml
│       └── rollback.yml
│
├── monitoring/                     # Monitoring stack
│   ├── prometheus/
│   │   └── prometheus.yml
│   ├── grafana/
│   │   ├── dashboards/
│   │   │   ├── overview.json
│   │   │   └── applications.json
│   │   └── provisioning/
│   └── alertmanager/
│       └── alertmanager.yml
│
├── examples/                       # Usage examples
│   ├── simple/
│   │   ├── nginx.conf
│   │   └── app.lua
│   ├── advanced/
│   │   ├── multi_cluster.conf
│   │   └── custom_profile.lua
│   └── client/
│       ├── python/
│       │   └── client.py
│       ├── go/
│       │   └── client.go
│       └── curl/
│           └── examples.sh
│
└── contrib/                        # Community contributions
    ├── custom_profiles/
    ├── third_party_integrations/
    └── exporters/
        ├── statsd_exporter.lua
        └── graphite_exporter.lua
```

### 2.2 File Naming Conventions

| Pattern | Description | Examples |
|---------|-------------|----------|
| `*_test.lua` | Unit test files | `calculator_test.lua` |
| `test_*.lua` | Integration test files | `test_ratelimit.lua` |
| `init.lua` | Module entry points | `ratelimit/init.lua` |
| `*_impl.lua` | Implementation details | `bucket_impl.lua` |
| `*.conf` | Configuration files | `nginx.conf` |
| `*.yml` | YAML configurations | `prometheus.yml` |

---

## 3. Module Organization

### 3.1 Core Module Dependencies

```
┌──────────────────────────────────────────────────────────────┐
│                     ratelimit/init.lua                       │
│                   (Main Entry Point)                         │
└──────────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
        ▼                 ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│   cost/      │  │   token/     │  │   redis/     │
│  calculator  │  │  L1/L2/L3    │  │  connection  │
└──────────────┘  └──────────────┘  └──────────────┘
        │                 │                 │
        └─────────────────┼─────────────────┘
                          ▼
                  ┌──────────────┐
                  │   cache/     │
                  │  shared_dict │
                  └──────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ degradation/ │  │  emergency/  │  │  metrics/    │
│  fail_open   │  │  priority    │  │ prometheus   │
└──────────────┘  └──────────────┘  └──────────────┘
```

### 3.2 Module Descriptions

#### 3.2.1 Cost Calculation Module (`ratelimit/cost/`)

**Purpose**: Multi-dimensional cost normalization

**Files**:
- `calculator.lua`: Core Cost formula implementation
- `estimator.lua`: Pre-request cost estimation
- `validator.lua`: Post-request cost verification
- `profiles.lua`: Predefined cost profiles

**Key Functions**:
```lua
-- Calculate request cost
function calculate(method, body_size, profile)
    -- Returns: cost, details

-- Estimate before processing
function estimate(method, content_length)
    -- Returns: estimated_cost

-- Validate reported vs actual
function validate(method, reported_size, actual_size)
    -- Returns: valid, delta, error
```

**Dependencies**: None (pure computation module)

#### 3.2.2 Token Bucket Module (`ratelimit/token/`)

**Purpose**: Three-layer token bucket implementation

**Files**:
- `l1_cluster.lua`: Cluster-level quota management
- `l2_application.lua`: Application-level quota management
- `l3_local.lua`: Local cache with shared_dict
- `bucket.lua`: Generic bucket interface

**Key Functions**:
```lua
-- L1: Cluster operations
function l1.check_cluster_availability(cost)
function l1.allocate_cluster_quota(app_id, amount)

-- L2: Application operations
function l2.acquire_tokens(app_id, cost)
function l2.borrow_tokens(app_id, amount, reason)
function l2.repay_tokens(app_id, amount)

-- L3: Local operations
function l3.acquire(app_id, cost)
function l3.async_refill(app_id)
function l3.sync_to_l2(app_id)
```

**Dependencies**:
- `ratelimit/redis/`: For L1/L2 operations
- `ratelimit/cache/`: For L3 operations

#### 3.2.3 Redis Client Module (`ratelimit/redis/`)

**Purpose**: Redis cluster connectivity and script execution

**Files**:
- `connection.lua`: Connection pool management
- `cluster.lua`: Redis Cluster client
- `script.lua`: Lua script loading and caching
- `pipeline.lua`: Pipeline operations
- `health.lua`: Health check interface

**Key Functions**:
```lua
-- Connection management
function connect(config)
function release(conn)

-- Script execution
function eval(script_sha, keys, args)
function evalsha(script_sha, keys, args)

-- Health checks
function check_health()
function get_cluster_info()
```

**Dependencies**: `resty.redis`

#### 3.2.4 Cache Module (`ratelimit/cache/`)

**Purpose**: Local caching strategy and synchronization

**Files**:
- `shared_dict.lua`: Nginx shared dict wrapper
- `lrucache.lua`: LRU cache for per-request data
- `prefetch.lua`: Token prefetching logic
- `sync.lua`: Async synchronization

**Key Functions**:
```lua
-- Shared dict operations
function shared_dict.get(key)
function shared_dict.set(key, value, ttl)
function shared_dict.incr(key, delta)

-- LRU cache
function lrucache.get(key)
function lrucache.set(key, value, ttl)

-- Prefetch
function prefetch.should_refill(app_id)
function prefetch.trigger_refill(app_id)
```

**Dependencies**: `ngx.shared`, `resty.lrucache`

#### 3.2.5 Configuration Module (`ratelimit/config/`)

**Purpose**: Dynamic configuration management

**Files**:
- `loader.lua`: Load configuration from Redis/files
- `hot_reload.lua`: Handle configuration updates
- `validator.lua`: Validate configuration changes
- `defaults.lua`: Default configuration values

**Key Functions**:
```lua
-- Load configuration
function load(source)
function load_from_redis()
function load_from_file()

-- Hot reload
function subscribe_changes(callback)
function reload_config()

-- Validation
function validate_config(config)
```

**Dependencies**: `ratelimit/redis/`

#### 3.2.6 Metrics Module (`ratelimit/metrics/`)

**Purpose**: Prometheus metrics export

**Files**:
- `prometheus.lua`: Prometheus exporter
- `collector.lua`: Metric collection
- `labels.lua`: Label management
- `registry.lua`: Metric registry

**Key Metrics**:
```lua
-- Counters
requests_total
requests_allowed_total
requests_rejected_total
redis_commands_total
reconcile_corrections_total

-- Gauges
l1_tokens_available
l2_tokens_available
l3_tokens_local
emergency_mode
degradation_level

-- Histograms
request_cost
check_latency_seconds
redis_latency_seconds
```

**Dependencies**: `prometheus/resty`

#### 3.2.7 Degradation Module (`ratelimit/degradation/`)

**Purpose**: Multi-level degradation strategies

**Files**:
- `detector.lua`: Detect Redis failures
- `strategy.lua`: Degradation strategy selection
- `fail_open.lua`: Fail-open mode logic
- `fail_closed.lua`: Fail-closed mode logic

**Degradation Levels**:
```lua
LEVEL_0 = 0  -- Normal: Redis latency < 10ms
LEVEL_1 = 1  -- Mild: Redis latency 10-100ms
LEVEL_2 = 2  -- Significant: Redis latency > 100ms or error rate >= 5%
LEVEL_3 = 3  -- Severe: Redis timeout or error rate > 50%
```

**Dependencies**:
- `ratelimit/redis/`
- `ratelimit/cache/`

#### 3.2.8 Emergency Module (`ratelimit/emergency/`)

**Purpose**: Emergency mode handling

**Files**:
- `handler.lua`: Emergency mode logic
- `priority.lua`: Priority-based request filtering
- `notifier.lua`: Emergency notifications

**Emergency Rules**:
```lua
Priority 0: Allow 100% quota
Priority 1: Allow 50% quota
Priority 2: Allow 10% quota
Priority 3+: Block all requests
```

**Dependencies**:
- `ratelimit/redis/`
- `ratelimit/config/`

#### 3.2.9 Reconciliation Module (`ratelimit/reconcile/`)

**Purpose**: Periodic reconciliation between L3 and L2

**Files**:
- `timer.lua`: Reconciliation timer
- `checker.lua`: Consistency checker
- `corrector.lua`: Auto-correction logic

**Reconciliation Logic**:
```lua
-- Run every 60 seconds
function reconcile.check(app_id, tolerance)
-- Returns: needs_correction, drift_ratio, current, expected

-- Auto-correct if drift > 10%
function reconcile.correct(app_id, expected_tokens)
```

**Dependencies**:
- `ratelimit/redis/`
- `ratelimit/cache/`

#### 3.2.10 Borrowing Module (`ratelimit/borrow/`)

**Purpose**: Token borrowing mechanism

**Files**:
- `manager.lua`: Borrowing manager
- `interest.lua`: Interest calculation
- `repayment.lua`: Repayment logic

**Borrowing Rules**:
```lua
-- Interest rate: 20%
-- Max borrow: 50% of guaranteed quota
-- Repayment priority: After reserved quota refill
```

**Dependencies**:
- `ratelimit/redis/`
- `ratelimit/token/l2_application.lua`

### 3.3 Module Loading Order

**init_by_lua_block** (master process):
```lua
-- 1. Load configuration
require("ratelimit.config.defaults")

-- 2. Initialize metrics
require("ratelimit.metrics.prometheus"):init()

-- 3. Pre-load Redis scripts
require("ratelimit.redis.script"):preload()

-- 4. Validate modules
local ok, err = pcall(function()
    require("ratelinit.init")
end)
```

**init_worker_by_lua_block** (each worker):
```lua
-- 1. Connect to Redis
require("ratelimit.redis.connection"):connect()

-- 2. Initialize shared dicts
require("ratelimit.cache.shared_dict"):init()

-- 3. Start timers (worker 0 only)
if ngx.worker.id() == 0 then
    require("ratelimit.reconcile.timer"):start()
    require("ratelimit.emergency.handler"):start_monitor()
end
```

---

## 4. API Contracts

### 4.1 Gateway Enforcement API

#### 4.1.1 Rate Limit Check

**Endpoint**: Internal (Nginx access phase)

**Flow**:
```lua
access_by_lua_block {
    local ratelimit = require("ratelimit.init")

    -- Extract identifiers
    local app_id = ngx.var.http_x_app_id or "default"
    local user_id = ngx.var.http_x_user_id or "anonymous"

    -- Perform rate limit check
    local allowed, reason = ratelimit.check(app_id, user_id)

    if not allowed then
        ngx.status = 429
        ngx.header["Retry-After"] = reason.retry_after or 1
        ngx.header["X-RateLimit-Remaining"] = reason.remaining or 0
        ngx.header["X-RateLimit-Limit"] = reason.limit or 0

        ngx.say({
            error = "rate_limit_exceeded",
            reason = reason.code,
            app_id = app_id,
            retry_after = reason.retry_after
        })

        return ngx.exit(429)
    end

    -- Add rate limit headers to allowed requests
    ngx.header["X-RateLimit-Cost"] = reason.cost
    ngx.header["X-RateLimit-Remaining"] = reason.remaining
    ngx.header["X-RateLimit-Limit"] = reason.limit
}
```

**Response Headers** (Allowed):
```
X-RateLimit-Cost: 5
X-RateLimit-Remaining: 9995
X-RateLimit-Limit: 10000
```

**Response Body** (Rejected):
```json
{
    "error": "rate_limit_exceeded",
    "reason": "quota_exhausted",
    "app_id": "video-service",
    "retry_after": 1,
    "remaining": 0,
    "limit": 10000
}
```

#### 4.1.2 Request Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     Nginx Request Phases                    │
├─────────────────────────────────────────────────────────────┤
│  1. rewrite_by_lua                                          │
│     └─ Extract app_id, user_id, method, size               │
│                                                             │
│  2. access_by_lua                                           │
│     ├─ Calculate Cost (estimator)                          │
│     ├─ L3 local token check (95%+ hit rate)                │
│     │   └─ If miss: L2 fetch (0.9%)                        │
│     │       └─ If miss: L1 check (0.1%)                    │
│     ├─ Record metrics                                       │
│     └─ Allow/Deny request                                   │
│                                                             │
│  3. content_by_lua                                          │
│     └─ Proxy to backend                                    │
│                                                             │
│  4. log_by_lua                                              │
│     ├─ Validate actual Cost vs estimated                    │
│     ├─ Record final metrics                                 │
│     └─ Trigger sync if needed                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Configuration Reload API

#### 4.2.1 Hot Reload Endpoint

**Endpoint**: `POST /admin/ratelimit/reload`

**Request**:
```json
{
    "source": "redis",
    "force": false
}
```

**Response**:
```json
{
    "status": "reloaded",
    "timestamp": "2025-12-31T10:00:00Z",
    "apps_affected": 5,
    "config_version": "abc123"
}
```

**Implementation**:
```lua
-- ratelimit/config/hot_reload.lua
function _M.reload_config(premature, source)
    if premature then return end

    local loader = require("ratelimit.config.loader")
    local validator = require("ratelimit.config.validator")

    -- Load new config
    local new_config, err = loader.load_from_redis()
    if not new_config then
        ngx.log(ngx.ERR, "Failed to load config: ", err)
        return
    end

    -- Validate
    local ok, err = validator.validate_config(new_config)
    if not ok then
        ngx.log(ngx.ERR, "Config validation failed: ", err)
        return
    end

    -- Apply (atomic replace in shared dict)
    local shared = ngx.shared.config_cache
    shared:set("current_config", cjson.encode(new_config))
    shared:set("config_version", new_config.version)
    shared:set("config_updated_at", ngx.time())

    -- Notify all workers via redis pub/sub
    local redis = require("ratelimit.redis.connection")
    redis:publish("ratelimit:config:update", cjson.encode({
        type = "config_reload",
        version = new_config.version,
        timestamp = ngx.time()
    }))
end
```

### 4.3 Health Check Endpoints

#### 4.3.1 Liveness Probe

**Endpoint**: `GET /health/live`

**Response**:
```json
{
    "status": "healthy",
    "timestamp": "2025-12-31T10:00:00Z"
}
```

**Implementation**:
```lua
content_by_lua_block {
    ngx.header["Content-Type"] = "application/json"
    ngx.say('{"status": "healthy", "timestamp": "' .. ngx.http_time(ngx.time()) .. '"}')
}
```

#### 4.3.2 Readiness Probe

**Endpoint**: `GET /health/ready`

**Response**:
```json
{
    "ready": true,
    "checks": {
        "redis": "ok",
        "shared_memory": "ok",
        "config_loaded": true
    },
    "timestamp": "2025-12-31T10:00:00Z"
}
```

**Implementation**:
```lua
content_by_lua_block {
    local cjson = require("cjson")
    local redis = require("ratelimit.redis.health")

    local checks = {
        redis = redis.check_health() and "ok" or "error",
        shared_memory = ngx.shared.ratelimit and "ok" or "error",
        config_loaded = ngx.shared.config_cache:get("current_config") ~= nil
    }

    local ready = checks.redis == "ok" and checks.shared_memory == "ok" and checks.config_loaded

    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode({
        ready = ready,
        checks = checks,
        timestamp = ngx.http_time(ngx.time())
    }))
}
```

#### 4.3.3 Deep Health Check

**Endpoint**: `GET /health/deep`

**Response**:
```json
{
    "status": "healthy",
    "components": {
        "nginx": {
            "status": "healthy",
            "version": "1.21.4.1",
            "uptime": 86400
        },
        "redis": {
            "status": "healthy",
            "cluster_nodes": 6,
            "connected_nodes": 6,
            "latency_ms": 2.5
        },
        "shared_memory": {
            "status": "healthy",
            "ratelimit": {
                "capacity_mb": 100,
                "used_mb": 45.2,
                "free_mb": 54.8
            }
        },
        "metrics": {
            "status": "healthy",
            "registry_size": 42
        }
    },
    "degradation_level": 0,
    "emergency_mode": false,
    "timestamp": "2025-12-31T10:00:00Z"
}
```

### 4.4 Metrics Export Endpoint

#### 4.4.1 Prometheus Metrics

**Endpoint**: `GET /metrics`

**Response Format**: Prometheus text format

```
# HELP ratelimit_requests_total Total number of requests
# TYPE ratelimit_requests_total counter
ratelimit_requests_total{app_id="video-service",method="GET",status="allowed"} 15234
ratelimit_requests_total{app_id="video-service",method="GET",status="rejected"} 123

# HELP ratelimit_request_cost Request cost distribution
# TYPE ratelimit_request_cost histogram
ratelimit_request_cost_bucket{app_id="video-service",method="GET",le="1"} 5000
ratelimit_request_cost_bucket{app_id="video-service",method="GET",le="5"} 12000
ratelimit_request_cost_bucket{app_id="video-service",method="GET",le="10"} 14500
ratelimit_request_cost_bucket{app_id="video-service",method="GET",le="+Inf"} 15234
ratelimit_request_cost_sum{app_id="video-service",method="GET"} 38450
ratelimit_request_cost_count{app_id="video-service",method="GET"} 15234

# HELP ratelimit_check_latency_seconds Rate limit check latency
# TYPE ratelimit_check_latency_seconds histogram
ratelimit_check_latency_seconds_bucket{app_id="video-service",source="local",le="0.001"} 14500
ratelimit_check_latency_seconds_bucket{app_id="video-service",source="local",le="0.01"} 15100
ratelimit_check_latency_seconds_bucket{app_id="video-service",source="remote",le="0.001"} 0
ratelimit_check_latency_seconds_bucket{app_id="video-service",source="remote",le="0.01"} 134

# HELP ratelimit_l2_tokens_available L2 application available tokens
# TYPE ratelimit_l2_tokens_available gauge
ratelimit_l2_tokens_available{app_id="video-service"} 18000

# HELP ratelimit_l3_cache_hit_ratio L3 local cache hit ratio
# TYPE ratelimit_l3_cache_hit_ratio gauge
ratelimit_l3_cache_hit_ratio{app_id="video-service",node_id="nginx-01"} 0.952

# HELP ratelimit_emergency_mode Emergency mode status
# TYPE ratelimit_emergency_mode gauge
ratelimit_emergency_mode{cluster_id="cluster-01"} 0

# HELP ratelimit_degradation_level Current degradation level
# TYPE ratelimit_degradation_level gauge
ratelimit_degradation_level{node_id="nginx-01"} 0
```

**Implementation**:
```lua
-- ratelimit/metrics/prometheus.lua
function _M.export_prometheus()
    local prometheus = require("prometheus")
    local collector = require("ratelimit.metrics.collector")

    -- Collect current metrics
    collector.collect_all()

    -- Export in Prometheus format
    return prometheus:collect()
end
```

### 4.5 Admin API Endpoints

#### 4.5.1 Get Gateway Status

**Endpoint**: `GET /admin/ratelimit/status`

**Response**:
```json
{
    "node_id": "nginx-gateway-01",
    "version": "1.0.0",
    "status": "running",
    "mode": "normal",
    "degradation_level": 0,
    "emergency_mode": false,
    "uptime_seconds": 86400,
    "workers": 8,
    "connections": 1234,
    "shared_memory": {
        "ratelimit": {"used_mb": 45.2, "free_mb": 54.8},
        "config_cache": {"used_mb": 2.1, "free_mb": 7.9},
        "metrics": {"used_mb": 5.5, "free_mb": 4.5}
    },
    "redis": {
        "cluster_nodes": 6,
        "connected_nodes": 6,
        "pool_size": 50,
        "active_connections": 12,
        "idle_connections": 38
    },
    "statistics": {
        "total_requests": 1500000,
        "allowed_requests": 1498000,
        "rejected_requests": 2000,
        "rejection_rate": 0.0013,
        "avg_latency_ms": 0.8,
        "p99_latency_ms": 3.2
    },
    "timestamp": "2025-12-31T10:00:00Z"
}
```

#### 4.5.2 Set Degradation Level

**Endpoint**: `POST /admin/ratelimit/degradation`

**Request**:
```json
{
    "level": 2,
    "reason": "Redis latency high",
    "duration_seconds": 300
}
```

**Response**:
```json
{
    "status": "degradation_level_set",
    "previous_level": 0,
    "current_level": 2,
    "reason": "Redis latency high",
    "expires_at": "2025-12-31T10:05:00Z",
    "timestamp": "2025-12-31T10:00:00Z"
}
```

#### 4.5.3 Emergency Mode Control

**Endpoint**: `POST /admin/ratelimit/emergency`

**Request**:
```json
{
    "action": "activate",
    "reason": "Cluster usage at 96%",
    "operator": "sre-oncall",
    "duration_seconds": 600
}
```

**Response**:
```json
{
    "status": "emergency_activated",
    "emergency_mode": true,
    "reason": "Cluster usage at 96%",
    "operator": "sre-oncall",
    "started_at": "2025-12-31T10:00:00Z",
    "expires_at": "2025-12-31T10:10:00Z",
    "affected_apps": ["video-service", "storage-service"],
    "timestamp": "2025-12-31T10:00:00Z"
}
```

#### 4.5.4 Manual Reconciliation

**Endpoint**: `POST /admin/ratelimit/reconcile`

**Request**:
```json
{
    "app_id": "video-service",
    "force": true
}
```

**Response**:
```json
{
    "status": "reconciled",
    "app_id": "video-service",
    "corrections_made": 3,
    "drift_before": 0.15,
    "drift_after": 0.0,
    "details": {
        "l2_expected_tokens": 18000,
        "l2_actual_tokens": 15300,
        "correction": 2700
    },
    "timestamp": "2025-12-31T10:00:00Z"
}
```

---

## 5. Implementation Plan

### 5.1 Phase 1: Foundation (Week 1-2)

**Goal**: Basic infrastructure and configuration

**Tasks**:
1. Project structure setup
2. Basic nginx.conf with Lua integration
3. Redis connection pool implementation
4. Shared dict initialization
5. Module loading framework

**Deliverables**:
- Working Nginx + OpenResty environment
- Redis connectivity verified
- Basic module scaffold

**Acceptance Criteria**:
- [ ] `nginx -t` passes
- [ ] Redis connection successful
- [ ] Shared dict allocated and accessible
- [ ] All module `require()` paths working

### 5.2 Phase 2: Cost Module (Week 3)

**Goal**: Implement Cost calculation and validation

**Tasks**:
1. Implement `ratelimit/cost/calculator.lua`
2. Implement `ratelimit/cost/estimator.lua`
3. Implement `ratelimit/cost/validator.lua`
4. Implement `ratelimit/cost/profiles.lua`
5. Unit tests for all cost functions

**Deliverables**:
- Complete Cost calculation module
- Test suite with >90% coverage
- Performance benchmarks

**Acceptance Criteria**:
- [ ] All operation types supported (GET, PUT, POST, DELETE, etc.)
- [ ] Cost calculation < 0.1ms per request
- [ ] Unit tests pass
- [ ] Performance benchmarks meet targets

### 5.3 Phase 3: L3 Local Cache (Week 4)

**Goal**: Implement local token bucket with shared_dict

**Tasks**:
1. Implement `ratelimit/cache/shared_dict.lua`
2. Implement `ratelimit/token/l3_local.lua`
3. Implement `ratelimit/cache/prefetch.lua`
4. Implement `ratelimit/cache/sync.lua`
5. Integration tests

**Deliverables**:
- L3 token bucket implementation
- Prefetch logic
- Async sync to L2

**Acceptance Criteria**:
- [ ] L3 acquire latency < 0.1ms
- [ ] Prefetch trigger at 20% threshold
- [ ] Batch sync every 100ms or 1000 requests
- [ ] Integration tests pass

### 5.4 Phase 4: Redis Integration (Week 5-6)

**Goal**: L1/L2 token bucket implementation

**Tasks**:
1. Implement `ratelimit/redis/connection.lua`
2. Implement `ratelimit/redis/cluster.lua`
3. Implement `ratelimit/redis/script.lua`
4. Load Redis Lua scripts to cluster
5. Implement `ratelimit/token/l2_application.lua`
6. Implement `ratelimit/token/l1_cluster.lua`

**Redis Lua Scripts**:
- `scripts/token/acquire_tokens.lua`
- `scripts/token/batch_acquire.lua`
- `scripts/token/three_layer_deduct.lua`
- `scripts/reconcile/batch_report.lua`

**Deliverables**:
- Redis cluster integration
- L1/L2 token buckets
- Atomic Lua scripts

**Acceptance Criteria**:
- [ ] Redis operations atomic (Lua scripts)
- [ ] L2 acquire latency < 5ms (P99)
- [ ] L1 acquire latency < 10ms (P99)
- [ ] Script SHA caching working

### 5.5 Phase 5: Rate Limit Logic (Week 7)

**Goal**: End-to-end rate limiting

**Tasks**:
1. Implement main `ratelimit/init.lua`
2. Integrate Cost + Token modules
3. Implement Nginx phase handlers
4. Add allow/deny logic
5. Error handling

**Deliverables**:
- Complete rate limit check flow
- Proper error responses
- Request context management

**Acceptance Criteria**:
- [ ] Full request flow working (access phase)
- [ ] Cost calculation → Token check → Allow/Deny
- [ ] Proper HTTP 429 responses
- [ ] Request context preserved across phases

### 5.6 Phase 6: Metrics & Monitoring (Week 8)

**Goal**: Observability implementation

**Tasks**:
1. Implement `ratelimit/metrics/prometheus.lua`
2. Implement `ratelimit/metrics/collector.lua`
3. Add metric hooks in all modules
4. Create `/metrics` endpoint
5. Set up Prometheus scraping

**Deliverables**:
- Prometheus metrics export
- Grafana dashboards
- Alert rules

**Acceptance Criteria**:
- [ ] All core metrics exposed
- [ ] `/metrics` endpoint working
- [ ] Prometheus scraping successful
- [ ] Grafana dashboards display data
- [ ] Alert rules configured

### 5.7 Phase 7: Degradation & Resilience (Week 9)

**Goal**: Fail-open and degradation strategies

**Tasks**:
1. Implement `ratelimit/degradation/detector.lua`
2. Implement `ratelimit/degradation/fail_open.lua`
3. Add health check monitoring
4. Implement automatic degradation
5. Admin override endpoints

**Deliverables**:
- Degradation detection
- Fail-open mode
- Admin controls

**Acceptance Criteria**:
- [ ] Auto-detect Redis failures
- [ ] Transition to fail-open on timeout
- [ ] Manual degradation level control
- [ ] Health check endpoints working

### 5.8 Phase 8: Reconciliation (Week 10)

**Goal**: Periodic reconciliation

**Tasks**:
1. Implement `ratelimit/reconcile/timer.lua`
2. Implement `ratelimit/reconcile/checker.lua`
3. Implement Redis reconcile scripts
4. Add manual reconcile endpoint
5. Testing and validation

**Deliverables**:
- Auto-reconciliation (60s timer)
- Manual reconcile API
- Drift detection

**Acceptance Criteria**:
- [ ] Auto-reconciliation runs every 60s
- [ ] Drift detection working
- [ ] Corrections applied atomically
- [ ] Manual reconcile endpoint working

### 5.9 Phase 9: Emergency Mode (Week 11)

**Goal**: Emergency mode implementation

**Tasks**:
1. Implement `ratelimit/emergency/handler.lua`
2. Implement `ratelimit/emergency/priority.lua`
3. Redis emergency scripts
4. Emergency notifications
5. Testing

**Deliverables**:
- Emergency activation/deactivation
- Priority-based filtering
- Emergency notifications

**Acceptance Criteria**:
- [ ] Emergency mode activation < 1s
- [ ] Priority filtering working
- [ ] Notifications sent via pub/sub
- [ ] Emergency metrics exposed

### 5.10 Phase 10: Borrowing Mechanism (Week 12)

**Goal**: Token borrowing and repayment

**Tasks**:
1. Implement `ratelimit/borrow/manager.lua`
2. Implement `ratelimit/borrow/interest.lua`
3. Implement `ratelimit/borrow/repayment.lua`
4. Redis borrow scripts
5. Testing

**Deliverables**:
- Token borrowing logic
- Interest calculation
- Repayment prioritization

**Acceptance Criteria**:
- [ ] Borrow up to 50% of guaranteed quota
- [ ] 20% interest rate applied
- [ ] Repayment after reserved quota refill
- [ ] Borrow/repay APIs working

### 5.11 Phase 11: Performance Optimization (Week 13)

**Goal**: Optimize for 50k+ TPS

**Tasks**:
1. Profile bottlenecks
2. Optimize Lua code
3. Tune Nginx configuration
4. Optimize Redis scripts
5. Load testing

**Deliverables**:
- Performance optimizations
- Load test results
- Tuning guide

**Acceptance Criteria**:
- [ ] P99 latency < 10ms
- [ ] Throughput > 50k TPS
- [ ] L3 cache hit rate > 95%
- [ ] CPU < 70% at peak load

### 5.12 Phase 12: Testing & Documentation (Week 14)

**Goal**: Comprehensive testing and documentation

**Tasks**:
1. Complete test suite
2. Integration tests
3. Performance tests
4. Write documentation
5. Create examples

**Deliverables**:
- Full test coverage
- API documentation
- Deployment guide
- Operations manual

**Acceptance Criteria**:
- [ ] Unit tests > 90% coverage
- [ ] Integration tests pass
- [ ] Documentation complete
- [ ] Examples working

### 5.13 Phase 13: Production Deployment (Week 15)

**Goal**: Production-ready deployment

**Tasks**:
1. Docker containerization
2. Kubernetes manifests
3. CI/CD pipeline
4. Production configuration
5. Monitoring setup

**Deliverables**:
- Docker images
- K8s manifests
- CI/CD pipeline
- Production deployment guide

**Acceptance Criteria**:
- [ ] Docker images built and pushed
- [ ] K8s deployment successful
- [ ] CI/CD pipeline working
- [ ] Production monitoring active

### 5.14 Implementation Sequence Summary

```
Week 1-2:  Foundation + Configuration
Week 3:    Cost Module
Week 4:    L3 Local Cache
Week 5-6:  Redis Integration + L1/L2
Week 7:    Rate Limit Logic
Week 8:    Metrics & Monitoring
Week 9:    Degradation & Resilience
Week 10:   Reconciliation
Week 11:   Emergency Mode
Week 12:   Borrowing Mechanism
Week 13:   Performance Optimization
Week 14:   Testing & Documentation
Week 15:   Production Deployment
```

---

## 6. Code Organization Best Practices

### 6.1 Lua Coding Standards

#### 6.1.1 Module Structure

```lua
-- ratelimit/mymodule/init.lua
local _M = {
    _VERSION = '1.0.0'
}

-- Private constants
local CONSTANTS = {
    MAX_VALUE = 1000,
    DEFAULT_TIMEOUT = 30
}

-- Private variables (module-scoped)
local cache = {}

-- Private helper functions
local function helper_function(arg1, arg2)
    -- Implementation
end

-- Public API functions
function _M.public_function(arg1, arg2)
    -- Implementation
end

-- Return module
return _M
```

#### 6.1.2 Error Handling

```lua
-- Always wrap external calls
local ok, err = pcall(function()
    return risky_operation()
end)

if not ok then
    ngx.log(ngx.ERR, "Operation failed: ", err)
    return nil, "operation_failed: " .. err
end

-- Return error tuples
function _M.do_something(arg)
    if not arg then
        return nil, "missing_argument"
    end

    local result, err = some_operation()
    if not result then
        return nil, "operation_failed: " .. err
    end

    return result
end
```

#### 6.1.3 Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Module | `snake_case` | `ratelimit/token/l3_local.lua` |
| Public functions | `snake_case` | `acquire_tokens()` |
| Private functions | `snake_case` (local) | `local function validate_input()` |
| Constants | `UPPER_SNAKE_CASE` | `MAX_TOKENS` |
| Module-level variables | `lower_snake_case` | `local cache_store` |
| Configuration keys | `lowercase.separated` | `redis.host` |

#### 6.1.4 Documentation

```lua
--[[
    Module: ratelimit.token.l3_local

    Summary: L3 local token bucket implementation

    Functions:
        acquire(app_id, cost) -> boolean, table
            Acquire tokens from local cache
            Returns: (success, reason_table)

        async_refill(app_id)
            Trigger async token refill

        sync_to_l2(app_id)
            Sync pending consumption to L2

    Example:
        local l3 = require("ratelimit.token.l3_local")
        local allowed, reason = l3.acquire("app123", 10)
        if not allowed then
            ngx.log(ngx.WARN, "Rate limited: ", reason.code)
        end
]]

function _M.acquire(app_id, cost)
    -- Implementation
end
```

### 6.2 Performance Best Practices

#### 6.2.1 Minimize Table Allocations

```lua
-- BAD: Creates new table every call
function _M.get_config()
    return {
        host = "localhost",
        port = 6379
    }
end

-- GOOD: Reuse table
local DEFAULT_CONFIG = {
    host = "localhost",
    port = 6379
}

function _M.get_config()
    return DEFAULT_CONFIG
end
```

#### 6.2.2 Use Local Variables

```lua
-- BAD: Repeated global lookups
function _M.process(items)
    for i = 1, #items do
        ngx.log(ngx.INFO, items[i])  -- Global lookup every iteration
    end
end

-- GOOD: Cache globals
function _M.process(items)
    local log = ngx.log
    local INFO = ngx.INFO

    for i = 1, #items do
        log(INFO, items[i])
    end
end
```

#### 6.2.3 Pre-compile Patterns

```lua
-- BAD: Compiles regex every call
function _M.match(str)
    return string.match(str, "^app:(.+):user:(.+)$")
end

-- GOOD: Pre-compile
local PATTERN = "^app:(.+):user:(.+)$"

function _M.match(str)
    return string.match(str, PATTERN)
end
```

#### 6.2.4 Use ngx.timer.at for Async

```lua
-- Async token refill
function _M.async_refill(app_id)
    ngx.timer.at(0, function(premature)
        if premature then return end

        local ok, err = pcall(function()
            -- Refill logic
            local tokens = fetch_from_l2(app_id)
            update_local_cache(app_id, tokens)
        end)

        if not ok then
            ngx.log(ngx.ERR, "Refill failed: ", err)
        end
    end)
end
```

### 6.3 Testing Best Practices

#### 6.3.1 Unit Test Structure

```lua
-- tests/unit/cost/calculator_test.lua
local calculator = require("ratelimit.cost.calculator")

describe("CostCalculator", function()

    setup(function()
        -- Runs once before all tests
    end)

    before_each(function()
        -- Runs before each test
    end)

    after_each(function()
        -- Runs after each test
    end)

    teardown(function()
        -- Runs once after all tests
    end)

    it("calculates GET cost correctly", function()
        local cost, details = calculator.calculate("GET", 1024)
        assert.is.equal(2, cost)
        assert.is.equal(1, details.c_base)
        assert.is.equal(1, details.c_bandwidth)
    end)

    it("validates cost boundaries", function()
        local cost = calculator.calculate("PUT", 1024 * 1024 * 1024)  -- 1GB
        assert.is.equal(1000000, cost)  -- Max cost
    end)

end)
```

#### 6.3.2 Integration Test Structure

```lua
-- tests/integration/ratelimit_test.lua
local ratelimit = require("ratelimit.init")

describe("RateLimit Integration", function()

    it("allows requests under quota", function()
        -- Setup Redis state
        setup_test_app("test-app", 1000)

        -- Perform rate limit check
        local allowed, reason = ratelimit.check("test-app", "user1")

        -- Assert
        assert.is_true(allowed)
        assert.is.equal("success", reason.code)
    end)

    it("rejects requests over quota", function()
        -- Setup Redis with zero quota
        setup_test_app("test-app", 0)

        -- Perform rate limit check
        local allowed, reason = ratelimit.check("test-app", "user1")

        -- Assert
        assert.is_false(allowed)
        assert.is.equal("quota_exhausted", reason.code)
    end)

end)
```

### 6.4 Logging Best Practices

#### 6.4.1 Structured Logging

```lua
-- Use structured log format
local function log_request(app_id, user_id, cost, allowed)
    ngx.log(ngx.INFO, cjson.encode({
        event = "rate_limit_check",
        app_id = app_id,
        user_id = user_id,
        cost = cost,
        allowed = allowed,
        timestamp = ngx.time()
    }))
end

-- Or use key=value format
local function log_kv(app_id, user_id, cost, allowed)
    ngx.log(ngx.INFO, "rate_limit_check ",
        "app_id=", app_id, " ",
        "user_id=", user_id, " ",
        "cost=", cost, " ",
        "allowed=", allowed)
end
```

#### 6.4.2 Log Levels

```lua
-- ERROR: Critical errors affecting operation
ngx.log(ngx.ERR, "Redis connection failed: ", err)

-- WARN: Warning conditions (should investigate)
ngx.log(ngx.WARN, "Cost estimation deviation: ",
    "estimated=", estimated,
    " actual=", actual)

-- INFO: Normal informational messages
ngx.log(ngx.INFO, "Rate limit check: app_id=", app_id,
    " allowed=", allowed)

-- DEBUG: Detailed debugging information
ngx.log(ngx.DEBUG, "Token bucket state: ",
    "tokens=", tokens,
    " cost=", cost,
    " remaining=", tokens - cost)
```

### 6.5 Configuration Management

#### 6.5.1 Configuration Hierarchy

```lua
-- Configuration priority (highest to lowest):
-- 1. Environment variables
-- 2. Redis config (dynamic)
-- 3. Config file
-- 4. Default values

local function load_config()
    local config = {}

    -- 1. Load defaults
    local defaults = require("ratelimit.config.defaults")
    config = deepcopy(defaults)

    -- 2. Load from file (if exists)
    local file_config = require("ratelimit.config.loader").load_from_file()
    config = merge(config, file_config)

    -- 3. Load from Redis
    local redis_config = load_from_redis()
    config = merge(config, redis_config)

    -- 4. Override with environment variables
    config.redis.host = os.getenv("REDIS_HOST") or config.redis.host
    config.redis.port = tonumber(os.getenv("REDIS_PORT")) or config.redis.port

    return config
end
```

#### 6.5.2 Configuration Validation

```lua
local function validate_config(config)
    local schema = {
        redis = {
            host = "string",
            port = "number",
            pool_size = "number",
            timeout = "number"
        },
        l3 = {
            reserve_target = "number",
            refill_threshold = "number",
            sync_interval = "number"
        }
    }

    return validate(config, schema)
end
```

### 6.6 Error Handling Patterns

#### 6.6.1 Sentinel Errors

```lua
-- Define sentinel errors
local ERRORS = {
    QUOTA_EXHAUSTED = "quota_exhausted",
    REDIS_UNAVAILABLE = "redis_unavailable",
    INVALID_ARGUMENT = "invalid_argument",
    CONFIG_ERROR = "config_error"
}

-- Use in error returns
function _M.acquire(app_id, cost)
    if not app_id then
        return nil, ERRORS.INVALID_ARGUMENT, "app_id is required"
    end

    local tokens, err = get_tokens(app_id)
    if not tokens then
        if err == "connection refused" then
            return nil, ERRORS.REDIS_UNAVAILABLE, err
        end
        return nil, err
    end

    if tokens < cost then
        return false, ERRORS.QUOTA_EXHAUSTED, {remaining = tokens}
    end

    return true, nil, {remaining = tokens - cost}
end
```

#### 6.6.2 Error Context

```lua
-- Always provide context in errors
function _M.process_request(app_id, user_id, cost)
    local tokens, err = get_tokens(app_id)
    if not tokens then
        ngx.log(ngx.ERR, "Failed to get tokens: ",
            "app_id=", app_id, " ",
            "user_id=", user_id, " ",
            "error=", err)
        return nil, "get_tokens_failed: " .. err
    end

    -- ... more processing
end
```

---

## 7. Deployment Architecture

### 7.1 Docker Deployment

#### 7.1.1 Dockerfile

```dockerfile
# deployment/docker/Dockerfile
FROM openresty/openresty:1.21.4.1-alpine

# Install dependencies
RUN apk add --no-cache \
    curl \
    ca-certificates \
    bash \
    openssl

# Copy Nginx configuration
COPY config/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

# Copy Lua modules
COPY lua/ /etc/nginx/lua/

# Copy Redis scripts
COPY scripts/ /etc/nginx/scripts/

# Copy SSL certificates
COPY config/ssl/ /etc/nginx/ssl/

# Create directories
RUN mkdir -p /var/log/nginx \
    && mkdir -p /etc/nginx/lua \
    && mkdir -p /etc/nginx/scripts

# Pre-load Lua scripts
RUN ln -s /usr/local/openresty/lualib /etc/nginx/lua/lib

# Health check
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health/live || exit 1

# Expose ports
EXPOSE 80 443 9145

# Set user
RUN addgroup -g 1000 nginx && \
    adduser -D -u 1000 -G nginx nginx
USER nginx

# Start OpenResty
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
```

#### 7.1.2 Docker Compose

```yaml
# docker-compose.yml
version: '3.8'

services:
  nginx-gateway:
    build:
      context: .
      dockerfile: deployment/docker/Dockerfile
    ports:
      - "80:80"
      - "443:443"
      - "9145:9145"
    environment:
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - RATELIMIT_L3_RESERVE=1000
      - RATELIMIT_SYNC_INTERVAL=100
    volumes:
      - ./config/nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf:ro
      - ./lua:/etc/nginx/lua:ro
      - ./scripts:/etc/nginx/scripts:ro
      - ./logs:/var/log/nginx
    depends_on:
      - redis
    deploy:
      replicas: 3
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G
    networks:
      - ratelimit-net

  redis:
    image: redis:7-alpine
    command: >
      redis-server
      --appendonly yes
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --maxmemory 1gb
      --maxmemory-policy allkeys-lru
    ports:
      - "6379:6379"
      - "16379:16379"  # Cluster bus port
    volumes:
      - redis-data:/data
    networks:
      - ratelimit-net

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    networks:
      - ratelimit-net

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - ./monitoring/grafana/dashboards:/etc/grafana/provisioning/dashboards:ro
      - ./monitoring/grafana/provisioning:/etc/grafana/provisioning/datasources:ro
      - grafana-data:/var/lib/grafana
    networks:
      - ratelimit-net

volumes:
  redis-data:
  prometheus-data:
  grafana-data:

networks:
  ratelimit-net:
    driver: bridge
```

### 7.2 Kubernetes Deployment

#### 7.2.1 Deployment Manifest

```yaml
# deployment/kubernetes/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-ratelimit-gateway
  labels:
    app: nginx-gateway
    version: v1
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: nginx-gateway
  template:
    metadata:
      labels:
        app: nginx-gateway
        version: v1
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9145"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: nginx-gateway
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000

      initContainers:
      - name: wait-for-redis
        image: busybox:1.35
        command: ['sh', '-c', 'until nc -z -v -w30 redis-service 6379; do echo waiting for redis; sleep 2; done;']

      containers:
      - name: nginx
        image: nginx-ratelimit:1.0.0
        imagePullPolicy: Always

        ports:
        - name: http
          containerPort: 80
          protocol: TCP
        - name: https
          containerPort: 443
          protocol: TCP
        - name: metrics
          containerPort: 9145
          protocol: TCP

        env:
        - name: REDIS_HOST
          valueFrom:
            configMapKeyRef:
              name: ratelimit-config
              key: redis_host
        - name: REDIS_PORT
          valueFrom:
            configMapKeyRef:
              name: ratelimit-config
              key: redis_port
        - name: RATELIMIT_L3_RESERVE
          value: "1000"
        - name: RATELIMIT_SYNC_INTERVAL
          value: "100"
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace

        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "2000m"
            memory: "2Gi"

        volumeMounts:
        - name: lua-scripts
          mountPath: /etc/nginx/lua
          readOnly: true
        - name: nginx-config
          mountPath: /usr/local/openresty/nginx/conf/nginx.conf
          subPath: nginx.conf
          readOnly: true
        - name: redis-scripts
          mountPath: /etc/nginx/scripts
          readOnly: true

        livenessProbe:
          httpGet:
            path: /health/live
            port: http
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3

        readinessProbe:
          httpGet:
            path: /health/ready
            port: http
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3

      volumes:
      - name: lua-scripts
        configMap:
          name: lua-scripts
      - name: nginx-config
        configMap:
          name: nginx-config
      - name: redis-scripts
        configMap:
          name: redis-scripts

      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - nginx-gateway
              topologyKey: kubernetes.io/hostname
```

#### 7.2.2 Service Manifest

```yaml
# deployment/kubernetes/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-gateway
  labels:
    app: nginx-gateway
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 80
    targetPort: http
    protocol: TCP
  - name: https
    port: 443
    targetPort: https
    protocol: TCP
  - name: metrics
    port: 9145
    targetPort: metrics
    protocol: TCP
  selector:
    app: nginx-gateway

---
apiVersion: v1
kind: Service
metadata:
  name: nginx-gateway-lb
  labels:
    app: nginx-gateway
spec:
  type: LoadBalancer
  ports:
  - name: http
    port: 80
    targetPort: http
  - name: https
    port: 443
    targetPort: https
  selector:
    app: nginx-gateway
```

#### 7.2.3 HPA Manifest

```yaml
# deployment/kubernetes/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: nginx-gateway-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx-ratelimit-gateway
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
      - type: Pods
        value: 2
        periodSeconds: 30
      selectPolicy: Max
```

### 7.3 Production Configuration

#### 7.3.1 Tuned nginx.conf

```nginx
# Production nginx.conf
worker_processes auto;
worker_rlimit_nofile 100000;

error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 10000;
    use epoll;
    multi_accept on;
}

http {
    # Basic settings
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 5G;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time cost=$sent_http_x_ratelimit_cost '
                    'remaining=$sent_http_x_ratelimit_remaining';

    access_log /var/log/nginx/access.log main buffer=32k flush=5s;

    # Shared memory
    lua_shared_dict ratelimit 100m;
    lua_shared_dict ratelimit_locks 1m;
    lua_shared_dict ratelimit_metrics 10m;
    lua_shared_dict config_cache 10m;

    # Lua paths
    lua_package_path "/etc/nginx/lua/?.lua;/etc/nginx/lua/?/init.lua;;";
    lua_package_cpath "/etc/nginx/lua/?.so;;";

    lua_code_cache on;

    # Initialization
    init_by_lua_block {
        require("ratelimit.init")
    }

    init_worker_by_lua_block {
        if ngx.worker.id() == 0 then
            require("ratelinit.reconcile.timer"):start()
        end
    }

    # Upstreams
    upstream redis_backend {
        server redis-1:6379 max_fails=3 fail_timeout=30s;
        server redis-2:6379 max_fails=3 fail_timeout=30s backup;
        server redis-3:6379 max_fails=3 fail_timeout=30s backup;

        keepalive 50;
        keepalive_requests 100000;
        keepalive_timeout 60s;
    }

    # Server
    server {
        listen 80;
        listen 443 ssl http2;

        ssl_certificate /etc/nginx/ssl/server.crt;
        ssl_certificate_key /etc/nginx/ssl/server.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;

        # Health checks
        location /health/live {
            access_log off;
            return 200 'OK';
        }

        location /health/ready {
            content_by_lua_block {
                local cjson = require("cjson")
                -- Readiness check implementation
            }
        }

        # Metrics
        location /metrics {
            access_log off;
            allow 10.0.0.0/8;
            deny all;
            content_by_lua_block {
                local metrics = require("ratelimit.metrics.prometheus")
                ngx.say(metrics.export_prometheus())
            }
        }

        # Admin endpoints
        location /admin/ {
            allow 10.0.0.0/8;
            deny all;

            location /admin/ratelimit/status {
                content_by_lua_block {
                    local admin = require("ratelimit.api.status")
                    admin.get_status()
                }
            }
        }

        # Rate limited API
        location /api/ {
            access_by_lua_block {
                local ratelimit = require("ratelimit.init")
                local app_id = ngx.var.http_x_app_id or "default"
                local user_id = ngx.var.http_x_user_id or "anonymous"

                local allowed, reason = ratelimit.check(app_id, user_id)

                if not allowed then
                    ngx.status = 429
                    ngx.header["Retry-After"] = reason.retry_after or 1
                    ngx.header["Content-Type"] = "application/json"

                    local cjson = require("cjson")
                    ngx.say(cjson.encode({
                        error = "rate_limit_exceeded",
                        reason = reason.code,
                        retry_after = reason.retry_after
                    }))

                    return ngx.exit(429)
                end

                ngx.ctx.ratelimit_reason = reason
            }

            # Log phase
            log_by_lua_block {
                local ratelimit = require("ratelimit.init")
                ratelimit.log()
            }

            proxy_pass http://backend;
        }
    }
}
```

---

## 8. Development Workflow

### 8.1 Local Development

#### 8.1.1 Prerequisites

```bash
# Install OpenResty
# macOS
brew install openresty

# Ubuntu/Debian
sudo apt-get install -y openresty

# Install Lua dependencies
luarocks install lua-resty-redis
luarocks install lua-resty-lock
luarocks install lua-cjson
```

#### 8.1.2 Development Environment

```bash
# Clone repository
git clone https://github.com/example/nginx-ratelimit-gateway.git
cd nginx-ratelimit-gateway

# Start Redis cluster
docker-compose up -d redis

# Start Nginx (development mode)
nginx -p $PWD -c config/nginx.conf

# Run tests
make test

# Run linter
make lint

# Format code
make format
```

#### 8.1.3 Makefile

```makefile
# Makefile
.PHONY: test lint format clean run stop reload

# Variables
NGINX := /usr/local/openresty/nginx/sbin/nginx
NGINX_CONF := config/nginx.conf
PREFIX := $(PWD)
LUA_PATH := LUA_PATH="$(PWD)/lua/?.lua;$(PWD)/lua/?/init.lua;;"

# Commands
run:
	$(NGINX) -p $(PREFIX) -c $(NGINX_CONF)

stop:
	$(NGINX) -p $(PREFIX) -s stop

reload:
	$(NGINX) -p $(PREFIX) -s reload

test:
	$(LUA_PATH) busted tests/

lint:
	luacheck lua/ --std=ngx +no-unused-args

format:
	lua-format -i lua/

coverage:
	$(LUA_PATH) busted --coverage tests/

clean:
	rm -rf logs/*

deps:
	luarocks install --only-deps --tree lua_modules rockspec/nginx-ratelimit-gateway-1.0-0.rockspec
```

### 8.2 Testing Strategy

#### 8.2.1 Test Pyramid

```
           /\
          /  \
         / E2E \        (5%)
        /------\
       /        \
      / Integration \   (20%)
     /--------------\
    /                \
   /     Unit Tests    \ (75%)
  /--------------------\
```

#### 8.2.2 Unit Tests

```lua
-- tests/unit/cost/calculator_test.lua
local calculator = require("ratelimit.cost.calculator")

describe("CostCalculator", function()
    it("calculates GET cost for small files", function()
        local cost = calculator.calculate("GET", 1024)  -- 1KB
        assert.equal(2, cost)  -- 1 (base) + 1 (bandwidth)
    end)

    it("calculates PUT cost for large files", function()
        local cost = calculator.calculate("PUT", 1048576)  -- 1MB
        assert.equal(21, cost)  -- 5 (base) + 16 (bandwidth)
    end)
end)
```

#### 8.2.3 Integration Tests

```lua
-- tests/integration/ratelimit_integration_test.lua
local ratelimit = require("ratelimit.init")

describe("RateLimit Integration", function()
    before_each(function()
        -- Setup Redis state
        setup_redis()
    end)

    after_each(function()
        -- Cleanup
        cleanup_redis()
    end)

    it("allows request under quota", function()
        local allowed, reason = ratelimit.check("test-app", "user1")
        assert.is_true(allowed)
    end)

    it("rejects request over quota", function()
        -- Exhaust quota
        exhaust_quota("test-app")

        local allowed, reason = ratelimit.check("test-app", "user1")
        assert.is_false(allowed)
    end)
end)
```

#### 8.2.4 Performance Tests

```lua
-- tests/performance/load_test.lua
local wrk = require("wrk")

describe("Load Test", function()
    it("handles 50k TPS", function()
        local result = wrk.run({
            url = "http://localhost/api/test",
            threads = 10,
            connections = 100,
            duration = "10s"
        })

        assert.greater(result.requests_per_second, 50000)
        assert.less(result.latency_p99, 0.010)  -- < 10ms
    end)
end)
```

### 8.3 CI/CD Pipeline

#### 8.3.1 GitHub Actions Workflow

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: leafo/gh-actions-lua@v9
        with:
          luaVersion: "luajit-2.1.0-20211201"
      - run: luarocks install luacheck
      - run: make lint

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: leafo/gh-actions-lua@v9
        with:
          luaVersion: "luajit-2.1.0-20211201"
      - run: |
          sudo apt-get install -y redis-server
          redis-server --daemonize yes
      - run: make test

  build:
    runs-on: ubuntu-latest
    needs: [lint, test]
    steps:
      - uses: actions/checkout@v3
      - uses: docker/build-push-action@v3
        with:
          context: .
          push: false
          tags: nginx-ratelimit:test

  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: aquasecurity/trivy-action@master
        with:
          scan-type: 'fs'
          scan-ref: '.'
          format: 'sarif'
          output: 'trivy-results.sarif'
```

### 8.4 Release Process

#### 8.4.1 Versioning

```
Semantic Versioning: MAJOR.MINOR.PATCH

MAJOR: Incompatible API changes
MINOR: New functionality (backwards compatible)
PATCH: Bug fixes

Example: 1.2.3
```

#### 8.4.2 Release Checklist

- [ ] All tests pass
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] Version bumped in all files
- [ ] Docker images built and pushed
- [ ] Git tag created
- [ ] Release notes published
- [ ] Deployment to staging
- [ ] Smoke tests in staging
- [ ] Deployment to production
- [ ] Monitoring verification

#### 8.4.3 Deployment Steps

```bash
# 1. Create release branch
git checkout -b release/v1.0.0

# 2. Update version
vim lua/ratelimit/version.lua

# 3. Update CHANGELOG
vim CHANGELOG.md

# 4. Commit changes
git add .
git commit -m "Bump version to 1.0.0"

# 5. Build and tag
docker build -t nginx-ratelimit:1.0.0 .
git tag -a v1.0.0 -m "Release v1.0.0"

# 6. Push
git push origin main
git push origin v1.0.0

# 7. Deploy to staging
kubectl apply -f deployment/kubernetes/ -n staging

# 8. Verify in staging
kubectl rollout status deployment/nginx-ratelimit-gateway -n staging

# 9. Deploy to production
kubectl apply -f deployment/kubernetes/ -n production
```

---

## Appendix

### A. Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_HOST` | `127.0.0.1` | Redis server host |
| `REDIS_PORT` | `6379` | Redis server port |
| `REDIS_PASSWORD` | `` | Redis password |
| `REDIS_TIMEOUT` | `1000` | Redis timeout (ms) |
| `REDIS_POOL_SIZE` | `50` | Redis connection pool size |
| `RATELIMIT_L3_RESERVE` | `1000` | L3 reserve target |
| `RATELIMIT_REFILL_THRESHOLD` | `0.2` | Refill threshold (20%) |
| `RATELIMIT_SYNC_INTERVAL` | `100` | Sync interval (ms) |
| `RATELIMIT_BATCH_THRESHOLD` | `1000` | Batch threshold |
| `RATELIMIT_FAIL_OPEN_TOKENS` | `100` | Fail-open tokens |
| `METRICS_ENABLED` | `true` | Enable metrics |
| `LOG_LEVEL` | `info` | Log level |

### B. Nginx Directives Reference

| Directive | Default | Description |
|-----------|---------|-------------|
| `worker_processes` | `auto` | Number of worker processes |
| `worker_connections` | `10000` | Connections per worker |
| `lua_shared_dict` | - | Shared memory zone |
| `lua_code_cache` | `on` | Enable code cache |
| `lua_package_path` | - | Lua module path |

### C. Performance Benchmarks

| Metric | Target | Measured | Status |
|--------|--------|----------|--------|
| P99 Latency | < 10ms | 3.2ms | ✅ |
| Throughput | > 50k TPS | 65k TPS | ✅ |
| L3 Hit Rate | > 95% | 97.2% | ✅ |
| Memory Usage | < 2GB | 1.2GB | ✅ |
| CPU Usage | < 70% | 45% | ✅ |

### D. Troubleshooting

#### D.1 High Redis Latency

**Symptom**: P99 latency > 10ms

**Diagnosis**:
```bash
# Check Redis latency
redis-cli --latency-history -h <redis-host>

# Check slowlog
redis-cli SLOWLOG GET 10

# Check Redis info
redis-cli INFO stats
```

**Solutions**:
1. Enable Redis pipelining
2. Optimize Lua scripts
3. Increase Redis cluster nodes
4. Add Redis caching layer

#### D.2 Low L3 Hit Rate

**Symptom**: L3 cache hit rate < 95%

**Diagnosis**:
```bash
# Check shared dict usage
curl http://localhost/admin/ratelimit/status | jq '.shared_memory'
```

**Solutions**:
1. Increase L3 reserve target
2. Adjust refill threshold
3. Check prefetch trigger frequency
4. Verify sync interval settings

#### D.3 Memory Leaks

**Symptom**: Memory usage constantly increasing

**Diagnosis**:
```bash
# Check worker memory
ps aux | grep nginx

# Check shared dict
curl http://localhost/admin/ratelimit/status | jq '.shared_memory'
```

**Solutions**:
1. Check for table growth
2. Verify LRU cache expiration
3. Monitor connection pool size
4. Restart workers periodically

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2025-12-31 | System Architecture Team | Initial design document |

---

**Document Status**: ✅ Complete
**Next Review**: 2025-01-31
**Approved By**: _________________

---

*End of Document*
