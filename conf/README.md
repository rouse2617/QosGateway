# Nginx 配置文件说明

本目录包含分布式三层令牌桶限流系统的 Nginx/OpenResty 配置文件。

## 配置文件

### nginx.conf (生产环境)

完整的生产环境配置，包含：

- **Worker 配置**: 自动检测 CPU 核心数，优化连接数
- **共享内存**: 
  - `ratelimit_dict` (100MB) - 令牌桶缓存
  - `connlimit_dict` (10MB) - 连接限制
  - `config_dict` (5MB) - 配置缓存
  - `metrics_dict` (10MB) - 指标收集
  - `locks_dict` (1MB) - 分布式锁
- **API 端点**:
  - `/health` - 健康检查（跳过限流）
  - `/metrics` - Prometheus 指标
  - `/admin/*` - 管理 API
  - `/api/v1/*` - 代理到 Go Admin Backend
  - `/ws/*` - WebSocket 支持
  - `/console/*` - 管理前端静态文件
  - `/` - 主业务路由（带限流）

### nginx.dev.conf (开发环境)

简化的开发环境配置，特点：

- 单 Worker 进程
- 关闭 Lua 代码缓存（支持热更新）
- Debug 级别日志
- 前台运行模式
- 内置模拟后端服务
- 额外测试端点：
  - `/test/cost` - Cost 计算测试
  - `/test/status` - 限流状态查看

## 使用方法

### 生产环境

```bash
# 启动
openresty -p /path/to/nginx -c conf/nginx.conf

# 重载配置
openresty -p /path/to/nginx -s reload

# 停止
openresty -p /path/to/nginx -s stop

# 测试配置
openresty -p /path/to/nginx -t
```

### 开发环境

```bash
# 前台启动（便于调试）
openresty -p /path/to/nginx -c conf/nginx.dev.conf

# 或使用 Docker
docker run -it --rm \
  -v $(pwd):/app \
  -p 80:80 \
  openresty/openresty:alpine \
  openresty -p /app -c conf/nginx.dev.conf
```

## 配置说明

### 限流检查流程

1. **连接限制检查** - 检查 per-app 和 per-cluster 并发连接数
2. **Cost 计算** - 根据 HTTP 方法和请求体大小计算 Cost
3. **紧急模式检查** - 如果紧急模式激活，检查优先级配额
4. **L3 本地令牌检查** - 检查本地缓存令牌
5. **L2 应用层获取** - 从 Redis 获取应用配额
6. **借用尝试** - 尝试从集群池借用令牌
7. **拒绝响应** - 返回 HTTP 429

### 响应头

限流系统会设置以下响应头：

| 响应头 | 说明 |
|--------|------|
| `X-RateLimit-Cost` | 请求消耗的 Cost |
| `X-RateLimit-Remaining` | 剩余可用令牌 |
| `X-Connection-Limit` | 连接限制值 |
| `X-Connection-Current` | 当前连接数 |
| `Retry-After` | 建议重试等待时间（仅 429 响应）|

### 请求头

客户端可以通过以下请求头标识身份：

| 请求头 | 说明 | 默认值 |
|--------|------|--------|
| `X-App-Id` | 应用标识 | `default` |
| `X-Cluster-Id` | 集群标识 | `default` |
| `X-User-Id` | 用户标识（可选）| - |

### 环境变量

可以通过环境变量配置 Redis 连接：

```bash
export REDIS_HOST=127.0.0.1
export REDIS_PORT=6379
export REDIS_PASSWORD=your_password
export REDIS_DB=0
```

## 性能调优

### 生产环境建议

1. **Worker 数量**: 设置为 CPU 核心数
2. **连接数**: `worker_connections` 根据预期并发调整
3. **共享内存**: 根据应用数量和流量调整大小
4. **Keepalive**: 启用后端连接池
5. **Gzip**: 启用压缩减少带宽

### 监控指标

访问 `/metrics` 端点获取 Prometheus 格式指标：

```bash
curl http://localhost/metrics
```

主要指标：
- `ratelimit_requests_total` - 请求总数
- `ratelimit_rejected_total` - 拒绝请求数
- `ratelimit_tokens_available` - 可用令牌数
- `connlimit_active_connections` - 活跃连接数
- `ratelimit_redis_latency_seconds` - Redis 延迟
- `ratelimit_emergency_mode` - 紧急模式状态
- `ratelimit_degradation_level` - 降级级别

## 故障排查

### 常见问题

1. **模块加载失败**
   - 检查 `lua_package_path` 配置
   - 确认 Lua 文件存在且语法正确

2. **共享内存不足**
   - 增加 `lua_shared_dict` 大小
   - 检查是否有内存泄漏

3. **Redis 连接失败**
   - 检查 Redis 服务状态
   - 验证连接配置
   - 查看降级状态 `/test/status`

4. **限流不生效**
   - 检查应用配置是否存在
   - 验证请求头是否正确传递
   - 查看错误日志

### 日志位置

- 错误日志: `logs/error.log`
- 访问日志: `logs/access.log`
- 审计日志: Redis `ratelimit:audit_log`
