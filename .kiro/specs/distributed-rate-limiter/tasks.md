# Implementation Plan: 分布式三层令牌桶限流系统

## Overview

本实现计划将分布式三层令牌桶限流系统分为多个阶段，从核心功能开始逐步构建完整系统。每个任务都包含具体的实现目标和对应的需求引用。

## Tasks

- [x] 1. 项目初始化与基础设施
  - [x] 1.1 创建项目目录结构
    - 创建 `nginx/lua/ratelimit/` 目录
    - 创建 `nginx/conf/` 配置目录
    - 创建 `nginx/tests/` 测试目录
    - _Requirements: 8.1, 8.3_

  - [x] 1.2 配置 OpenResty 基础环境
    - 配置 `lua_shared_dict ratelimit_dict 100m`
    - 配置 `lua_shared_dict connlimit_dict 10m`
    - 配置 `lua_shared_dict config_dict 5m`
    - 配置 `lua_package_path`
    - _Requirements: 8.3, 8.4_

  - [ ]* 1.3 设置测试框架
    - 配置 busted 单元测试框架
    - 配置 lua-quickcheck 属性测试框架
    - 创建测试辅助函数
    - _Requirements: Testing Strategy_

- [x] 2. Cost Calculator 实现
  - [x] 2.1 实现 Cost 计算核心模块
    - 创建 `ratelimit/cost.lua`
    - 实现 `calculate(method, body_size, c_bw)` 函数
    - 实现 HTTP 方法到 C_base 的映射
    - 实现 Cost 上限检查 (MAX_COST = 1,000,000)
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8_

  - [ ]* 2.2 编写 Cost Calculator 属性测试
    - **Property 1: Cost Calculation Correctness**
    - 验证公式 `Cost = C_base + ceil(body_size / 65536) × C_bw`
    - 验证结果不超过 1,000,000
    - **Validates: Requirements 1.1, 1.7**

- [x] 3. Checkpoint - Cost Calculator 验证
  - 确保所有 Cost Calculator 测试通过
  - 验证各 HTTP 方法的 C_base 值正确

- [x] 4. L3 本地令牌桶实现
  - [x] 4.1 实现 L3 Bucket 核心模块
    - 创建 `ratelimit/l3_bucket.lua`
    - 实现 `acquire(app_id, cost)` 函数
    - 实现本地令牌扣减逻辑
    - 实现 pending_consumption 计数器
    - _Requirements: 2.1, 2.2, 2.3, 2.7_

  - [x] 4.2 实现异步补充机制
    - 实现 `async_refill(app_id)` 函数
    - 实现 20% 阈值触发逻辑
    - 实现批量同步 (100ms / 1000 requests)
    - _Requirements: 2.4, 2.5_

  - [x] 4.3 实现 Fail-Open 模式
    - 实现 `handle_fail_open(app_id, cost)` 函数
    - 限制 Fail-Open 令牌数为 100
    - _Requirements: 2.6, 11.3, 11.4_

  - [x] 4.4 实现令牌回滚功能
    - 实现 `rollback(app_id, cost)` 函数
    - 实现回滚计数器
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5_

  - [ ]* 4.5 编写 L3 Bucket 属性测试
    - **Property 2: Token Deduction Consistency**
    - **Property 10: Local Tokens Non-Negative Invariant**
    - **Property 12: Refill Threshold Trigger**
    - **Validates: Requirements 2.3, 2.4, 2.7, 15.4**

- [x] 5. Checkpoint - L3 Bucket 验证
  - 确保所有 L3 Bucket 测试通过
  - 验证本地令牌扣减和回滚正确

- [x] 6. Redis 客户端实现
  - [x] 6.1 实现 Redis 连接池
    - 创建 `ratelimit/redis.lua`
    - 实现连接池管理 (pool_size = 50)
    - 实现 keepalive 配置 (idle_timeout = 60000ms)
    - 实现连接超时 (timeout = 1000ms)
    - _Requirements: 12.1, 12.2, 12.3, 12.4_

  - [x] 6.2 实现 Lua 脚本预加载
    - 预加载 ACQUIRE_SCRIPT
    - 预加载 BORROW_SCRIPT
    - 实现脚本缓存机制
    - _Requirements: 12.5_

  - [x] 6.3 实现连接失败重试逻辑
    - 实现指数退避重试
    - 实现 Redis Cluster 支持
    - _Requirements: 12.6, 12.7_

- [x] 7. L2 应用层令牌桶实现
  - [x] 7.1 实现 L2 Bucket 核心模块
    - 创建 `ratelimit/l2_bucket.lua`
    - 实现 Redis Lua 脚本 ACQUIRE_SCRIPT
    - 实现令牌补充逻辑 (基于 elapsed time × refill_rate)
    - 实现 burst_quota 上限检查
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.7_

  - [x] 7.2 实现批量获取功能
    - 实现 `acquire_batch(app_id, amount)` 函数
    - 供 L3 预取使用
    - _Requirements: 3.7_

  - [ ]* 7.3 编写 L2 Bucket 属性测试
    - **Property 3: Token Refill Correctness**
    - **Property 4: Burst Quota Invariant**
    - **Validates: Requirements 3.4, 3.5**

- [x] 8. Checkpoint - L2 Bucket 验证
  - 确保所有 L2 Bucket 测试通过
  - 验证 Redis Lua 脚本原子性

- [x] 9. L1 集群层实现
  - [x] 9.1 实现 L1 Cluster 核心模块
    - 创建 `ratelimit/l1_cluster.lua`
    - 实现全局配额管理
    - 实现 10% 预留容量
    - 实现 90% 使用率触发配额削减
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [x] 9.2 实现紧急模式支持
    - 实现 emergency_mode 激活
    - 实现 P0 优先级 100% 配额
    - _Requirements: 4.5, 4.6_

  - [x] 9.3 实现全局对账
    - 实现 60 秒周期对账
    - 实现 cluster_exhausted 错误返回
    - _Requirements: 4.7, 4.8_

- [x] 10. 借用管理器实现
  - [x] 10.1 实现 Borrow Manager 核心模块
    - 创建 `ratelimit/borrow.lua`
    - 实现 Redis Lua 脚本 BORROW_SCRIPT
    - 实现 20% 利息计算
    - 实现 max_borrow 限制
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x] 10.2 实现还款逻辑
    - 实现债务优先还款
    - 实现借用/还款历史记录
    - _Requirements: 5.5, 5.6_

  - [x] 10.3 实现集群可用量检查
    - 实现 reserved_ratio 检查
    - 拒绝低于预留比例的借用
    - _Requirements: 5.7_

  - [ ]* 10.4 编写 Borrow Manager 属性测试
    - **Property 5: Borrowing Correctness**
    - **Property 13: Repayment Order**
    - **Validates: Requirements 5.2, 5.3, 5.5, 5.7**

- [x] 11. Checkpoint - 借用机制验证
  - 确保所有借用相关测试通过
  - 验证利息计算和还款顺序

- [x] 12. 紧急模式管理器实现
  - [x] 12.1 实现 Emergency Manager 核心模块
    - 创建 `ratelimit/emergency.lua`
    - 实现手动激活 API
    - 实现自动激活 (usage > 95%)
    - _Requirements: 6.1, 6.2_

  - [x] 12.2 实现优先级配额分配
    - 实现 P0=100%, P1=50%, P2=10%, P3+=0%
    - 实现 `check_emergency_request(app_id, cost)` 函数
    - _Requirements: 6.3, 6.4_

  - [x] 12.3 实现紧急模式生命周期
    - 实现自动过期 (default 300s)
    - 实现 Redis Pub/Sub 事件发布
    - 实现日志记录
    - _Requirements: 6.5, 6.6, 6.7_

  - [ ]* 12.4 编写 Emergency Manager 属性测试
    - **Property 6: Emergency Mode Quota Ratios**
    - **Validates: Requirements 4.6, 6.3, 6.4**

- [x] 13. 对账器实现
  - [x] 13.1 实现 Reconciler 核心模块
    - 创建 `ratelimit/reconciler.lua`
    - 实现 60 秒周期检查
    - 实现 10% 漂移容忍度
    - _Requirements: 7.1, 7.2_

  - [x] 13.2 实现全局对账
    - 实现 L1 = sum(L2) 验证
    - 实现周期消耗计数器重置
    - _Requirements: 7.3, 7.4_

  - [x] 13.3 实现修正记录
    - 实现 correction_count 计数器
    - 实现节点故障处理
    - _Requirements: 7.5, 7.6_

  - [ ]* 13.4 编写 Reconciler 属性测试
    - **Property 7: Global Reconciliation Invariant**
    - **Property 14: Drift Tolerance Correction**
    - **Validates: Requirements 7.2, 7.3, 15.5, 15.6**

- [x] 14. Checkpoint - 核心限流功能验证
  - 确保 L1/L2/L3 三层协同工作
  - 验证紧急模式和对账功能

- [x] 15. 连接限制器实现
  - [x] 15.1 实现 Connection Limiter 核心模块
    - 创建 `ratelimit/connection_limiter.lua`
    - 实现 `init()` 初始化函数
    - 实现输入验证函数 `validate_input(app_id, cluster_id)`
    - 实现 `get_or_init_data(key, default_limit)` 函数
    - _Requirements: 17.1, 17.2_

  - [x] 15.2 实现原子计数操作
    - 实现 `atomic_increment(key, default_limit)` 函数（CAS 模式）
    - 实现 `atomic_decrement(key)` 函数
    - 实现重试逻辑 (RETRY_MAX = 3)
    - 确保多 Worker 环境下的原子性
    - _Requirements: 17.6, 15.2_

  - [x] 15.3 实现连接获取功能
    - 实现 `acquire(app_id, cluster_id)` 函数
    - 实现 per-app 和 per-cluster 两级限制检查
    - 实现 Cluster 检查失败时的 App 计数回滚
    - 实现 `generate_conn_id()` 唯一 ID 生成（微秒精度 + 随机数）
    - _Requirements: 17.3, 17.4, 17.5_

  - [x] 15.4 实现连接释放
    - 实现 `release()` 函数
    - 在 log_by_lua 阶段调用
    - 实现幂等性检查（防止重复释放）
    - 实现 `set_response_headers()` 响应头设置
    - _Requirements: 17.7, 17.8_

  - [x] 15.5 实现连接追踪
    - 实现连接追踪表记录
    - 记录 connection_id, app_id, cluster_id, created_at, last_seen, client_ip
    - 实现 `heartbeat()` 函数更新 last_seen（用于长连接）
    - _Requirements: 18.1, 18.2, 18.3_

  - [x] 15.6 实现泄漏检测与清理
    - 实现 `cleanup_leaked_connections()` 函数
    - 限制每次扫描键数量 (MAX_CLEANUP_KEYS = 1000)
    - 实现 30 秒周期清理定时器
    - 实现 300 秒超时检测
    - 实现 `force_release_connection()` 强制释放
    - 实现详细泄漏日志记录
    - _Requirements: 18.4, 18.5, 18.6, 18.7_

  - [x] 15.7 实现降级策略
    - 实现连接限制器降级级别定义
    - 实现 normal/mild/significant/fail_open 四级降级
    - 实现降级时的清理频率调整
    - _Requirements: 11.1, 11.2, 11.3_

  - [x] 15.8 实现拒绝事件记录
    - 实现 `record_rejection()` 函数
    - 记录拒绝原因、app_id、cluster_id、client_ip
    - _Requirements: 17.4, 17.5_

  - [ ]* 15.9 编写 Connection Limiter 属性测试
    - **Property 15: Connection Acquire-Release Consistency**
    - **Property 16: Connection Limit Enforcement**
    - **Property 17: Connection Counter Non-Negative Invariant**
    - **Property 18: Connection Leak Detection Correctness**
    - **Property 19: Connection Peak Tracking**
    - **Property 20: Connection Release Idempotency**
    - **Validates: Requirements 17, 18**

- [x] 16. Checkpoint - 连接限制器验证
  - 确保连接限制器测试通过
  - 验证泄漏检测和清理功能

- [x] 17. 预留管理器实现
  - [x] 17.1 实现 Reservation Manager 核心模块
    - 创建 `ratelimit/reservation.lua`
    - 实现 `create(app_id, estimated_cost)` 函数
    - 实现预留 ID 生成和追踪
    - _Requirements: 14.1, 14.2_

  - [x] 17.2 实现预留完成与对账
    - 实现 `complete(reservation_id, actual_cost)` 函数
    - 实现差额退还/补扣逻辑
    - _Requirements: 14.3, 14.4, 14.5_

  - [x] 17.3 实现预留超时处理
    - 实现自动释放 (default 3600s)
    - 实现预留指标暴露
    - _Requirements: 14.6, 14.7_

  - [ ]* 17.4 编写 Reservation Manager 属性测试
    - **Property 8: Token Rollback Correctness**
    - **Property 9: Reservation Round-Trip**
    - **Validates: Requirements 13.1, 14.3, 14.4, 14.5**

- [x] 18. 配置验证器实现
  - [x] 18.1 实现 Config Validator 核心模块
    - 创建 `ratelimit/config_validator.lua`
    - 实现 `validate_app_config(config)` 函数
    - 实现 `validate_cluster_capacity(capacity, quotas)` 函数
    - _Requirements: 16.1, 16.2, 16.3, 16.4_

  - [x] 18.2 实现验证规则
    - 验证 sum(guaranteed_quotas) <= cluster_capacity × 0.9
    - 验证 burst_quota >= guaranteed_quota
    - 验证 priority 范围 [0, 3]
    - _Requirements: 16.2, 16.3, 16.4_

  - [x] 18.3 实现 dry-run 模式
    - 实现配置预检查
    - 实现详细错误消息返回
    - 实现验证日志记录
    - _Requirements: 16.5, 16.6, 16.7_

  - [ ]* 18.4 编写 Config Validator 属性测试
    - **Property 11: Config Validation Correctness**
    - **Validates: Requirements 16.2, 16.3, 16.4**

- [x] 19. Checkpoint - 高级功能验证
  - 确保预留管理和配置验证测试通过
  - 验证端到端配置更新流程

- [x] 20. Nginx 集成实现
  - [x] 20.1 实现主入口模块
    - 创建 `ratelimit/init.lua`
    - 实现 `init()` 初始化函数
    - 实现 `check(app_id, user_id, cluster_id)` 函数
    - 实现 `log()` 日志阶段处理
    - _Requirements: 8.1, 8.2, 8.4_

  - [x] 20.2 实现响应头设置
    - 设置 X-RateLimit-Cost
    - 设置 X-RateLimit-Remaining
    - 设置 X-Connection-Limit
    - 设置 X-Connection-Current
    - _Requirements: 8.5, 17.8_

  - [x] 20.3 实现限流拒绝响应
    - 返回 HTTP 429
    - 设置 Retry-After 头
    - 返回 JSON 错误详情
    - _Requirements: 8.6_

  - [x] 20.4 实现健康检查端点
    - 实现 /health 端点 (跳过限流)
    - _Requirements: 8.7_

- [x] 21. 降级管理器实现
  - [x] 21.1 实现 Degradation Manager 核心模块
    - 创建 `ratelimit/degradation.lua`
    - 实现降级级别定义 (normal, mild, significant, fail_open)
    - 实现 Redis 延迟检测
    - _Requirements: 11.1, 11.2, 11.3_

  - [x] 21.2 实现降级策略
    - 10-100ms 延迟: 增加 L3 缓存
    - >100ms 延迟: 切换 reserved 模式
    - 不可用: 激活 Fail-Open
    - _Requirements: 11.1, 11.2, 11.3, 11.4_

  - [x] 21.3 实现自动恢复
    - 实现 Redis 可用性检测
    - 实现自动恢复逻辑
    - 实现降级日志和指标
    - _Requirements: 11.5, 11.6, 11.7_

- [x] 22. 监控指标实现
  - [x] 22.1 实现 Metrics Collector 核心模块
    - 创建 `ratelimit/metrics.lua`
    - 实现 Prometheus 兼容格式
    - _Requirements: 9.1_

  - [x] 22.2 实现请求指标
    - 实现 requests_total (by app_id, method, status)
    - 实现 request_cost histogram
    - _Requirements: 9.2, 9.3_

  - [x] 22.3 实现令牌指标
    - 实现 l1/l2/l3 token availability gauges
    - 实现 cache_hit_ratio
    - _Requirements: 9.4, 9.6_

  - [x] 22.4 实现系统指标
    - 实现 redis_latency histogram
    - 实现 emergency_mode status
    - 实现 reconcile_corrections counter
    - _Requirements: 9.5, 9.7, 9.8_

  - [x] 22.5 实现连接限制指标
    - 实现 connlimit_active_connections gauge
    - 实现 connlimit_peak_connections gauge
    - 实现 connlimit_rejected_total counter
    - 实现 connlimit_leaked_total counter
    - 实现 connlimit_duration_seconds histogram
    - _Requirements: 19.1, 19.2, 19.3, 19.4, 19.5_

  - [x] 22.6 实现指标端点
    - 实现 /metrics Prometheus 端点
    - 实现 Redis 统计上报 (10s 周期)
    - _Requirements: 8.8, 19.6, 19.7_

- [x] 23. 配置管理 API 实现
  - [x] 23.1 实现 Config API 核心模块
    - 创建 `ratelimit/config_api.lua`
    - 实现应用配额 CRUD
    - 实现集群容量配置
    - _Requirements: 10.1, 10.2_

  - [x] 23.2 实现紧急模式控制
    - 实现紧急模式激活/停用 API
    - 实现实时指标查询
    - _Requirements: 10.3, 10.4_

  - [x] 23.3 实现配置验证与发布
    - 集成 Config Validator
    - 实现 Redis Pub/Sub 配置发布
    - _Requirements: 10.5, 10.6_

  - [x] 23.4 实现安全与审计
    - 实现 API 认证
    - 实现配置变更日志
    - _Requirements: 10.7, 10.8_

  - [x] 23.5 实现连接限制配置 API
    - 实现应用连接限制 CRUD
    - 实现集群连接限制配置
    - 实现配置缓存 (60s TTL)
    - _Requirements: 20.1, 20.2, 20.3, 20.4, 20.5, 20.6, 20.7_

- [x] 24. Checkpoint - 完整系统验证
  - 确保所有模块集成正确
  - 验证监控指标和配置 API

- [x] 25. Nginx 配置文件
  - [x] 25.1 创建生产环境 nginx.conf
    - 配置 worker_processes
    - 配置 shared_dict
    - 配置 lua_package_path
    - 配置 init_by_lua_block
    - 配置 init_worker_by_lua_block
    - _Requirements: 8.3, 8.4_

  - [x] 25.2 配置 API 路由
    - 配置 access_by_lua_block
    - 配置 log_by_lua_block
    - 配置 /health 端点
    - 配置 /metrics 端点
    - 配置 /admin API 路由
    - _Requirements: 8.1, 8.2, 8.7, 8.8_

- [ ] 26. Final Checkpoint - 系统完整性验证
  - 确保所有测试通过
  - 验证端到端限流流程
  - 验证配置热更新
  - 验证故障降级和恢复
  - 如有问题请咨询用户

- [ ] 27. 管理控制台后端实现 (Go)
  - [ ] 27.1 初始化 Go 项目
    - 创建 `admin-backend/` 目录
    - 初始化 Go module (`go mod init`)
    - 添加依赖: gin, go-redis, golang-jwt, gorilla/websocket
    - _Requirements: 21.1_

  - [ ] 27.2 实现 API 服务器核心
    - 创建 `main.go` 入口文件
    - 实现 Gin 路由配置
    - 实现 CORS 中间件
    - 实现健康检查端点
    - _Requirements: 21.1, 21.2_

  - [ ] 27.3 实现 JWT 认证中间件
    - 实现 `AuthMiddleware()` 函数
    - 实现 Token 验证逻辑
    - 实现用户上下文注入
    - _Requirements: 21.2_

  - [ ] 27.4 实现应用管理 API
    - 实现 GET/POST/PUT/DELETE /api/v1/apps
    - 实现配置验证逻辑
    - 实现 Redis 配置存储
    - 实现配置发布 (Redis Pub/Sub)
    - _Requirements: 21.3_

  - [ ] 27.5 实现集群管理 API
    - 实现 GET/PUT /api/v1/clusters
    - 实现集群容量配置
    - _Requirements: 21.4_

  - [ ] 27.6 实现连接限制管理 API
    - 实现 GET/PUT /api/v1/connections
    - 实现连接限制配置 CRUD
    - _Requirements: 21.7_

  - [ ] 27.7 实现紧急模式控制 API
    - 实现 GET /api/v1/emergency
    - 实现 POST /api/v1/emergency/activate
    - 实现 POST /api/v1/emergency/deactivate
    - _Requirements: 21.6_

  - [ ] 27.8 实现实时指标 API
    - 实现 GET /api/v1/metrics
    - 实现 GET /api/v1/metrics/apps/:id
    - 实现 GET /api/v1/metrics/connections
    - _Requirements: 21.5_

  - [ ] 27.9 实现 WebSocket 实时推送
    - 实现 WebSocket 连接管理 (gorilla/websocket)
    - 实现指标实时推送 (5s 间隔)
    - 实现告警事件推送
    - _Requirements: 21.8_

  - [ ] 27.10 实现安全与审计
    - 实现 API 速率限制中间件
    - 实现审计日志记录
    - _Requirements: 21.9, 21.10_

- [ ] 28. 管理控制台前端实现 (Vue 3 + TypeScript)
  - [ ] 28.1 初始化前端项目
    - 使用 Vite 创建 Vue 3 + TypeScript 项目
    - 配置 Vue Router
    - 配置 Pinia 状态管理
    - 安装 Element Plus UI 组件库
    - 安装 ECharts 图表库
    - 配置 Axios API 客户端
    - _Requirements: 22.1_

  - [ ] 28.2 实现 TypeScript 类型定义
    - 创建 `src/types/app.ts` 应用类型
    - 创建 `src/types/metrics.ts` 指标类型
    - 创建 `src/types/api.ts` API 响应类型
    - _Requirements: 22.1_

  - [ ] 28.3 实现 API 层
    - 创建 `src/api/client.ts` Axios 配置
    - 创建 `src/api/apps.ts` 应用 API
    - 创建 `src/api/metrics.ts` 指标 API
    - 创建 `src/api/emergency.ts` 紧急模式 API
    - _Requirements: 22.1_

  - [ ] 28.4 实现 Pinia 状态管理
    - 创建 `src/stores/auth.ts` 认证状态
    - 创建 `src/stores/apps.ts` 应用状态
    - 创建 `src/stores/metrics.ts` 指标状态
    - _Requirements: 22.1_

  - [ ] 28.5 实现 WebSocket 组合式函数
    - 创建 `src/composables/useWebSocket.ts`
    - 实现自动重连逻辑
    - 实现实时数据更新
    - _Requirements: 22.2_

  - [ ] 28.6 实现 Dashboard 仪表盘
    - 实现 OverviewCard.vue 概览卡片
    - 实现 MetricsChart.vue 指标图表 (ECharts)
    - 实现 TopAppsTable.vue Top 应用表格
    - 实现 AlertPanel.vue 告警面板
    - 实现 TokenFlowChart.vue L1/L2/L3 令牌流动图
    - _Requirements: 22.1, 22.2, 23.1, 23.2, 23.6_

  - [ ] 28.7 实现应用管理界面
    - 实现 AppList.vue 应用列表页面
    - 实现 AppForm.vue 应用创建/编辑表单
    - 实现 QuotaEditor.vue 配额编辑器
    - 实现配置 diff 预览
    - _Requirements: 22.3, 22.10_

  - [ ] 28.8 实现集群配置界面
    - 实现集群列表和配置
    - 实现容量配置表单
    - _Requirements: 22.4_

  - [ ] 28.9 实现连接限制配置界面
    - 实现 ConnectionList.vue 连接限制列表
    - 实现 ConnectionForm.vue 连接限制配置表单
    - 实现 ConnectionStats.vue 连接统计展示
    - _Requirements: 22.5, 23.3_

  - [ ] 28.10 实现紧急模式控制面板
    - 实现 EmergencyPanel.vue 紧急模式状态展示
    - 实现激活/停用按钮
    - 实现 EmergencyHistory.vue 紧急模式历史记录
    - _Requirements: 22.6, 23.5_

  - [ ] 28.11 实现告警通知
    - 实现告警通知组件
    - 实现告警列表和确认
    - 实现阈值突破高亮
    - _Requirements: 22.7, 23.9_

  - [ ] 28.12 实现响应式设计
    - 实现移动端适配
    - 实现侧边栏折叠
    - _Requirements: 22.8_

  - [ ] 28.13 实现权限控制 UI
    - 实现登录页面
    - 实现角色权限展示
    - 实现操作权限控制
    - _Requirements: 22.9_

- [ ] 29. 实时监控仪表盘增强
  - [ ] 29.1 实现 L1/L2/L3 令牌可视化
    - 实现三层令牌仪表盘
    - 实现令牌流动动画
    - _Requirements: 23.1_

  - [ ] 29.2 实现请求分析
    - 实现请求速率图表
    - 实现 Cost 分布直方图
    - _Requirements: 23.2_

  - [ ] 29.3 实现 Redis 健康监控
    - 实现 Redis 延迟图表
    - 实现连接池状态
    - _Requirements: 23.4_

  - [ ] 29.4 实现时间范围选择
    - 实现 1h/6h/24h/7d 切换
    - 实现自定义时间范围
    - _Requirements: 23.7_

  - [ ] 29.5 实现自动刷新
    - 实现 5 秒自动刷新
    - 实现刷新间隔配置
    - _Requirements: 23.8_

  - [ ] 29.6 实现下钻功能
    - 实现从概览到应用详情的下钻
    - 实现从应用到连接详情的下钻
    - _Requirements: 23.10_

- [ ] 30. Final Checkpoint - 完整系统验证
  - 确保所有模块集成正确
  - 验证管理控制台功能完整
  - 验证实时监控准确性
  - 验证权限控制有效性
  - 如有问题请咨询用户

## Notes

- 标记 `*` 的任务为可选测试任务，可跳过以加快 MVP 开发
- 每个 Checkpoint 用于验证阶段性成果
- 属性测试使用 lua-quickcheck，每个测试至少运行 100 次迭代
- 所有 Redis 操作使用 Lua 脚本保证原子性
- 核心限流系统实现语言: Lua (OpenResty)
- 管理控制台后端: Go (Gin framework, go-redis, golang-jwt, gorilla/websocket)
- 管理控制台前端: Vue 3 + TypeScript + Vite (Element Plus, ECharts, Pinia, Axios)
