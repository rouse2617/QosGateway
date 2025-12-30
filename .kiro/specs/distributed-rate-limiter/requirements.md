# Requirements Document

## Introduction

本文档定义了基于 OpenResty 的分布式三层令牌桶限流系统的需求规范。该系统专为云存储平台设计，通过 Cost 归一化算法统一处理 IOPS 和带宽约束，实现公平、高效的流量控制。

## Glossary

- **Rate_Limiter**: 限流系统，负责控制请求速率
- **Token_Bucket**: 令牌桶，核心限流单元
- **Cost**: 请求成本，IOPS 和带宽的统一度量值
- **C_base**: 基础开销，按操作类型定义的 IOPS 当量值
- **C_bw**: 带宽开销系数
- **Unit_quantum**: 量子单位，默认 64KB (65536 bytes)
- **L1_Cluster_Layer**: 集群层，Redis Cluster 实现的全局配额管理
- **L2_Application_Layer**: 应用层，每个应用的保底配额和突发配额管理
- **L3_Local_Layer**: 本地层，Nginx 共享内存实现的边缘缓存
- **Guaranteed_Quota**: 保底配额，应用的最低保证配额
- **Burst_Quota**: 突发配额，允许短时间超出保底配额的上限
- **Emergency_Mode**: 紧急模式，集群过载时的保护机制
- **Fail_Open**: 故障开放模式，Redis 故障时的降级策略

## Requirements

### Requirement 1: Cost 归一化计算

**User Story:** As a 系统管理员, I want to 统一计算请求的资源消耗, so that 可以公平地对大小文件请求进行限流。

#### Acceptance Criteria

1. THE Cost_Calculator SHALL compute cost using formula: `Cost = C_base + ceil(Size_body / Unit_quantum) × C_bw`
2. WHEN a GET request is received, THE Cost_Calculator SHALL use C_base = 1
3. WHEN a PUT or POST request is received, THE Cost_Calculator SHALL use C_base = 5
4. WHEN a DELETE request is received, THE Cost_Calculator SHALL use C_base = 2
5. WHEN a LIST request is received, THE Cost_Calculator SHALL use C_base = 3
6. THE Cost_Calculator SHALL use Unit_quantum = 65536 (64KB) as the default bandwidth quantum
7. THE Cost_Calculator SHALL cap the maximum cost at 1,000,000 to prevent overflow
8. WHEN body_size is 0, THE Cost_Calculator SHALL return only C_base as the total cost

### Requirement 2: L3 本地令牌桶管理

**User Story:** As a 网关节点, I want to 在本地缓存令牌, so that 可以实现亚毫秒级的限流决策。

#### Acceptance Criteria

1. THE L3_Bucket SHALL store tokens in Nginx shared memory dictionary
2. WHEN a request arrives, THE L3_Bucket SHALL first check local token availability
3. WHEN local tokens are sufficient, THE L3_Bucket SHALL deduct tokens locally and return success within 1ms
4. WHEN local tokens fall below 20% of reserve target, THE L3_Bucket SHALL trigger async refill from L2
5. THE L3_Bucket SHALL batch sync consumption to L2 every 100ms or every 1000 requests
6. WHEN Redis is unavailable, THE L3_Bucket SHALL switch to Fail_Open mode with limited local tokens
7. THE L3_Bucket SHALL maintain pending_consumption counter for batch reporting
8. THE L3_Bucket SHALL achieve >95% local cache hit ratio under normal operation

### Requirement 3: L2 应用层令牌桶管理

**User Story:** As a 租户应用, I want to 拥有保底配额和突发配额, so that 可以获得 SLA 保障同时处理流量峰值。

#### Acceptance Criteria

1. THE L2_Bucket SHALL store application quota configuration in Redis Hash
2. THE L2_Bucket SHALL support guaranteed_quota (保底配额) per application
3. THE L2_Bucket SHALL support burst_quota (突发配额) per application
4. WHEN tokens are requested, THE L2_Bucket SHALL refill tokens based on elapsed time and refill_rate
5. THE L2_Bucket SHALL cap current_tokens at burst_quota maximum
6. WHEN guaranteed_quota is exhausted, THE L2_Bucket SHALL attempt to borrow from L1 with 20% interest
7. THE L2_Bucket SHALL use Redis Lua scripts for atomic token operations
8. THE L2_Bucket SHALL support priority levels (P0-P3) for emergency mode quota allocation

### Requirement 4: L1 集群层配额管理

**User Story:** As a 集群管理员, I want to 控制全局资源配额, so that 可以保护底层存储系统不被压垮。

#### Acceptance Criteria

1. THE L1_Cluster SHALL maintain global cluster capacity in Redis
2. THE L1_Cluster SHALL track current_used quota across all applications
3. THE L1_Cluster SHALL reserve 10% capacity for emergency operations
4. WHEN cluster usage exceeds 90%, THE L1_Cluster SHALL trigger quota reduction for low-priority apps
5. THE L1_Cluster SHALL support emergency_mode activation via API
6. WHEN emergency_mode is active, THE L1_Cluster SHALL only allow P0 priority requests at 100% quota
7. THE L1_Cluster SHALL perform global reconciliation every 60 seconds
8. IF L1 available tokens are insufficient, THEN THE L1_Cluster SHALL return cluster_exhausted error

### Requirement 5: 令牌借用机制

**User Story:** As a 应用, I want to 在配额不足时借用令牌, so that 可以处理突发流量而不被立即拒绝。

#### Acceptance Criteria

1. THE Borrow_Manager SHALL allow applications to borrow tokens from L1 cluster pool
2. THE Borrow_Manager SHALL apply 20% interest rate on borrowed tokens
3. THE Borrow_Manager SHALL enforce max_borrow limit per application
4. THE Borrow_Manager SHALL track borrowed amount and debt separately
5. WHEN repaying, THE Borrow_Manager SHALL apply repayment to debt first
6. THE Borrow_Manager SHALL record borrow/repay history for auditing
7. IF cluster available is below reserved ratio, THEN THE Borrow_Manager SHALL reject borrow requests

### Requirement 6: 紧急模式管理

**User Story:** As a SRE, I want to 在集群过载时激活紧急模式, so that 可以保护系统稳定性。

#### Acceptance Criteria

1. THE Emergency_Manager SHALL support manual activation via API
2. THE Emergency_Manager SHALL support automatic activation when usage > 95%
3. WHEN emergency_mode is active, THE Emergency_Manager SHALL apply priority-based quota ratios
4. THE Emergency_Manager SHALL allow P0 apps 100% quota, P1 apps 50%, P2 apps 10%, P3+ apps 0%
5. THE Emergency_Manager SHALL auto-expire after configured duration (default 300 seconds)
6. THE Emergency_Manager SHALL publish emergency events via Redis Pub/Sub
7. THE Emergency_Manager SHALL log all emergency activations and deactivations

### Requirement 7: 批量对账与同步

**User Story:** As a 系统, I want to 定期对账L3与L2的令牌状态, so that 可以修正累积的偏差。

#### Acceptance Criteria

1. THE Reconciler SHALL run every 60 seconds to check token drift
2. THE Reconciler SHALL correct tokens if drift exceeds 10% tolerance
3. THE Reconciler SHALL perform global reconciliation to ensure L1 = sum(L2)
4. THE Reconciler SHALL reset period consumption counters after reconciliation
5. THE Reconciler SHALL record correction count for monitoring
6. THE Reconciler SHALL handle node failures gracefully during reconciliation

### Requirement 8: Nginx 集成

**User Story:** As a 开发者, I want to 将限流系统集成到 OpenResty, so that 可以在网关层实现透明限流。

#### Acceptance Criteria

1. THE Nginx_Integration SHALL use access_by_lua_block for rate limit checking
2. THE Nginx_Integration SHALL use log_by_lua_block for consumption reporting
3. THE Nginx_Integration SHALL configure lua_shared_dict with 100MB for token cache
4. THE Nginx_Integration SHALL initialize rate limiter in init_worker_by_lua_block
5. THE Nginx_Integration SHALL set X-RateLimit-Cost and X-RateLimit-Remaining response headers
6. WHEN rate limit is exceeded, THE Nginx_Integration SHALL return HTTP 429 with Retry-After header
7. THE Nginx_Integration SHALL support health check endpoint without rate limiting
8. THE Nginx_Integration SHALL support metrics endpoint for Prometheus scraping

### Requirement 9: 监控指标

**User Story:** As a 运维人员, I want to 收集限流系统的监控指标, so that 可以监控系统健康状态。

#### Acceptance Criteria

1. THE Metrics_Collector SHALL expose Prometheus-compatible metrics endpoint
2. THE Metrics_Collector SHALL track requests_total by app_id, method, status
3. THE Metrics_Collector SHALL track request_cost histogram with configurable buckets
4. THE Metrics_Collector SHALL track l1/l2/l3 token availability gauges
5. THE Metrics_Collector SHALL track redis_latency histogram
6. THE Metrics_Collector SHALL track cache_hit_ratio per node
7. THE Metrics_Collector SHALL track emergency_mode status
8. THE Metrics_Collector SHALL track reconcile_corrections counter

### Requirement 10: 配置管理 API

**User Story:** As a 管理员, I want to 通过 API 管理限流配置, so that 可以动态调整配额而无需重启服务。

#### Acceptance Criteria

1. THE Config_API SHALL support CRUD operations for application quota configs
2. THE Config_API SHALL support cluster capacity configuration
3. THE Config_API SHALL support emergency mode control
4. THE Config_API SHALL support real-time metrics query
5. THE Config_API SHALL validate quota parameters before applying
6. THE Config_API SHALL publish config updates via Redis Pub/Sub
7. THE Config_API SHALL require authentication for all management endpoints
8. THE Config_API SHALL log all configuration changes for auditing

### Requirement 11: 降级策略

**User Story:** As a 系统, I want to 在 Redis 故障时优雅降级, so that 可以保持基本可用性。

#### Acceptance Criteria

1. WHEN Redis latency is 10-100ms, THE Degradation_Manager SHALL increase L3 cache size
2. WHEN Redis latency exceeds 100ms, THE Degradation_Manager SHALL switch to reserved mode
3. WHEN Redis is completely unavailable, THE Degradation_Manager SHALL activate Fail_Open mode
4. THE Degradation_Manager SHALL limit Fail_Open tokens to 100 per application
5. THE Degradation_Manager SHALL auto-recover when Redis becomes available
6. THE Degradation_Manager SHALL log all degradation level changes
7. THE Degradation_Manager SHALL expose degradation_level metric

### Requirement 12: Redis 连接管理

**User Story:** As a 系统, I want to 高效管理 Redis 连接, so that 可以支持高并发场景。

#### Acceptance Criteria

1. THE Redis_Client SHALL use connection pooling with keepalive
2. THE Redis_Client SHALL configure pool_size = 50 connections per worker
3. THE Redis_Client SHALL set connection timeout to 1000ms
4. THE Redis_Client SHALL use idle_timeout = 60000ms for keepalive
5. THE Redis_Client SHALL preload Lua scripts for better performance
6. THE Redis_Client SHALL handle connection failures with retry logic
7. THE Redis_Client SHALL support Redis Cluster topology

### Requirement 13: 请求取消时的令牌回滚

**User Story:** As a 系统, I want to 在请求取消时回滚已扣减的令牌, so that 可以避免令牌泄漏。

#### Acceptance Criteria

1. WHEN a request is cancelled before completion, THE Token_Rollback_Manager SHALL return the pre-deducted tokens to L3 bucket
2. WHEN a request timeout occurs, THE Token_Rollback_Manager SHALL trigger automatic token rollback
3. THE Token_Rollback_Manager SHALL track pending requests with their deducted cost
4. THE Token_Rollback_Manager SHALL complete rollback within 100ms of cancellation detection
5. THE Token_Rollback_Manager SHALL log all rollback events for auditing
6. IF rollback fails, THEN THE Token_Rollback_Manager SHALL queue the rollback for retry

### Requirement 14: 长时间操作的令牌预留与释放

**User Story:** As a 系统, I want to 为长时间操作预留令牌并在完成后释放, so that 可以准确计量大文件传输。

#### Acceptance Criteria

1. WHEN a multipart upload or large file transfer starts, THE Reservation_Manager SHALL pre-reserve estimated tokens
2. THE Reservation_Manager SHALL track reservation_id with estimated_cost and actual_cost
3. WHEN operation completes, THE Reservation_Manager SHALL reconcile actual vs estimated cost
4. IF actual_cost < estimated_cost, THEN THE Reservation_Manager SHALL return the difference
5. IF actual_cost > estimated_cost, THEN THE Reservation_Manager SHALL deduct additional tokens
6. THE Reservation_Manager SHALL auto-release reservations after timeout (default 3600 seconds)
7. THE Reservation_Manager SHALL expose reservation metrics for monitoring

### Requirement 15: 并发写入的一致性保障

**User Story:** As a 系统, I want to 保障并发令牌操作的一致性, so that 可以避免超发或漏扣。

#### Acceptance Criteria

1. THE Consistency_Manager SHALL use Redis Lua scripts for atomic token operations
2. THE Consistency_Manager SHALL implement optimistic locking for L3 shared dict updates
3. WHEN concurrent updates conflict, THE Consistency_Manager SHALL retry with exponential backoff
4. THE Consistency_Manager SHALL ensure L3 local tokens never go negative
5. THE Consistency_Manager SHALL detect and resolve token drift during reconciliation
6. THE Consistency_Manager SHALL maintain token drift metric below 5% tolerance

### Requirement 16: 配置热更新的预检查机制

**User Story:** As a 管理员, I want to 在配置更新前进行预检查, so that 可以避免错误配置导致系统故障。

#### Acceptance Criteria

1. WHEN a config update is submitted, THE Config_Validator SHALL validate all parameters before applying
2. THE Config_Validator SHALL check that sum(guaranteed_quotas) <= cluster_capacity * 0.9
3. THE Config_Validator SHALL verify burst_quota >= guaranteed_quota for each application
4. THE Config_Validator SHALL reject priority values outside valid range (0-3)
5. IF validation fails, THEN THE Config_Validator SHALL return detailed error messages
6. THE Config_Validator SHALL support dry-run mode for testing config changes
7. THE Config_Validator SHALL log all validation attempts and results

### Requirement 17: 连接并发数限制

**User Story:** As a 系统管理员, I want to 限制每个应用和集群的并发连接数, so that 可以防止单个应用耗尽系统资源。

#### Acceptance Criteria

1. THE Connection_Limiter SHALL support per-app connection limits
2. THE Connection_Limiter SHALL support per-cluster connection limits
3. WHEN a request arrives, THE Connection_Limiter SHALL check connection limits before token bucket check
4. WHEN app connections >= app_limit, THE Connection_Limiter SHALL return HTTP 429 with code "app_limit_exceeded"
5. WHEN cluster connections >= cluster_limit, THE Connection_Limiter SHALL return HTTP 429 with code "cluster_limit_exceeded"
6. THE Connection_Limiter SHALL track connection count in Nginx shared_dict for <0.5ms response
7. THE Connection_Limiter SHALL release connection count in log_by_lua phase
8. THE Connection_Limiter SHALL set X-Connection-Limit and X-Connection-Current response headers

### Requirement 18: 连接追踪与泄漏检测

**User Story:** As a 运维人员, I want to 追踪连接状态并检测泄漏, so that 可以防止连接计数器漂移。

#### Acceptance Criteria

1. THE Connection_Tracker SHALL record connection_id, app_id, cluster_id, created_at, client_ip for each connection
2. THE Connection_Tracker SHALL update last_seen timestamp for active connections
3. THE Connection_Tracker SHALL mark connections as "released" upon normal completion
4. WHEN (now - last_seen) > CONNECTION_TIMEOUT (default 300s), THE Connection_Tracker SHALL detect connection as leaked
5. THE Connection_Tracker SHALL force-release leaked connections and decrement counters
6. THE Connection_Tracker SHALL run cleanup every 30 seconds
7. THE Connection_Tracker SHALL log all leaked connections for investigation

### Requirement 19: 连接限制监控指标

**User Story:** As a 运维人员, I want to 监控连接限制相关指标, so that 可以及时发现连接问题。

#### Acceptance Criteria

1. THE Connection_Metrics SHALL expose connlimit_active_connections gauge by app_id, cluster_id
2. THE Connection_Metrics SHALL expose connlimit_peak_connections gauge by app_id, cluster_id
3. THE Connection_Metrics SHALL expose connlimit_rejected_total counter by app_id, cluster_id, reason
4. THE Connection_Metrics SHALL expose connlimit_leaked_total counter by app_id, cluster_id
5. THE Connection_Metrics SHALL expose connlimit_duration_seconds histogram
6. THE Connection_Metrics SHALL report statistics to Redis every 10 seconds
7. THE Connection_Metrics SHALL support aggregation across multiple nodes

### Requirement 20: 连接限制配置管理

**User Story:** As a 管理员, I want to 动态配置连接限制, so that 可以根据业务需求调整限制值。

#### Acceptance Criteria

1. THE Connection_Config SHALL support CRUD operations for app connection limits via API
2. THE Connection_Config SHALL support cluster connection limit configuration
3. THE Connection_Config SHALL store configuration in Redis for cross-node consistency
4. THE Connection_Config SHALL publish config updates via Redis Pub/Sub
5. THE Connection_Config SHALL cache configuration locally with 60s TTL
6. THE Connection_Config SHALL validate max_connections > 0 before applying
7. THE Connection_Config SHALL support burst_connections >= max_connections


### Requirement 21: 管理控制台后端 API

**User Story:** As a 管理员, I want to 通过 Web 控制台管理限流系统, so that 可以可视化地监控和配置限流策略。

#### Acceptance Criteria

1. THE Admin_Backend SHALL provide RESTful API for all management operations
2. THE Admin_Backend SHALL support JWT-based authentication
3. THE Admin_Backend SHALL expose /api/v1/apps endpoint for application CRUD
4. THE Admin_Backend SHALL expose /api/v1/clusters endpoint for cluster management
5. THE Admin_Backend SHALL expose /api/v1/metrics endpoint for real-time metrics
6. THE Admin_Backend SHALL expose /api/v1/emergency endpoint for emergency mode control
7. THE Admin_Backend SHALL expose /api/v1/connections endpoint for connection limit management
8. THE Admin_Backend SHALL support WebSocket for real-time metrics push
9. THE Admin_Backend SHALL implement rate limiting on API endpoints
10. THE Admin_Backend SHALL log all API access for auditing

### Requirement 22: 管理控制台前端

**User Story:** As a 管理员, I want to 使用图形界面管理限流系统, so that 可以直观地查看系统状态和进行配置。

#### Acceptance Criteria

1. THE Admin_Frontend SHALL provide dashboard showing system overview
2. THE Admin_Frontend SHALL display real-time metrics charts (requests/s, tokens, connections)
3. THE Admin_Frontend SHALL provide application management interface (list, create, edit, delete)
4. THE Admin_Frontend SHALL provide cluster configuration interface
5. THE Admin_Frontend SHALL provide connection limit configuration interface
6. THE Admin_Frontend SHALL provide emergency mode control panel
7. THE Admin_Frontend SHALL display alert notifications for system events
8. THE Admin_Frontend SHALL support responsive design for mobile access
9. THE Admin_Frontend SHALL implement role-based access control UI
10. THE Admin_Frontend SHALL provide configuration diff preview before applying changes

### Requirement 23: 实时监控仪表盘

**User Story:** As a 运维人员, I want to 实时查看系统运行状态, so that 可以及时发现和处理问题。

#### Acceptance Criteria

1. THE Dashboard SHALL display L1/L2/L3 token availability in real-time
2. THE Dashboard SHALL display per-app request rate and cost distribution
3. THE Dashboard SHALL display connection count by app and cluster
4. THE Dashboard SHALL display Redis latency and health status
5. THE Dashboard SHALL display emergency mode status and history
6. THE Dashboard SHALL display top-N apps by consumption
7. THE Dashboard SHALL support time range selection (1h, 6h, 24h, 7d)
8. THE Dashboard SHALL auto-refresh metrics every 5 seconds
9. THE Dashboard SHALL highlight anomalies and threshold breaches
10. THE Dashboard SHALL support drill-down from overview to app details
