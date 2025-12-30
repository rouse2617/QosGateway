# 分布式令牌桶限流系统 - 技术文档

## 文档索引

| 文档 | 描述 | 状态 |
|------|------|------|
| [01-cost-algorithm.md](./01-cost-algorithm.md) | Cost 归一化算法详解 | ✅ 完成 |
| [02-layered-token-bucket.md](./02-layered-token-bucket.md) | 分层令牌桶架构详解 | ✅ 完成 |
| [03-lua-scripts.md](./03-lua-scripts.md) | Lua 脚本完整实现 | ✅ 完成 |
| [04-nginx-integration.md](./04-nginx-integration.md) | Nginx 集成方案 | ✅ 完成 |
| [05-monitoring-metrics.md](./05-monitoring-metrics.md) | 监控指标设计 | ✅ 完成 |
| [06-config-api.md](./06-config-api.md) | 配置管理 API 规范 | ✅ 完成 |
| [流控系统综合分析报告.md](./流控系统综合分析报告.md) | 系统综合分析报告 | ✅ 完成 |

---

## 系统概述

### 核心公式

```
Cost = C_base + (Size_body / Unit_quantum) × C_bw
```

### 三层架构

```
┌─────────────────────────────────────────┐
│  L1: 集群层 - 物理底线保护              │
│  Redis Cluster, 全局配额                │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  L2: 应用层 - 业务 SLA 保障             │
│  保底配额 + 突发配额 + 借贷机制         │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  L3: 本地层 - 边缘缓存                  │
│  Nginx 本地缓存, <1ms 响应              │
└─────────────────────────────────────────┘
```

### 性能目标

| 指标 | 目标 |
|------|------|
| P99 延迟 | < 10ms |
| L3 缓存命中率 | > 95% |
| 吞吐量 | 50k+ TPS |
| 可用性 | 99.99% |

---

## 快速开始

### 1. 部署 Redis Cluster

```bash
docker-compose up -d redis
```

### 2. 部署 Nginx 网关

```bash
docker-compose up -d nginx-gateway
```

### 3. 配置应用

```bash
curl -X POST http://localhost/api/v1/apps \
  -H "Content-Type: application/json" \
  -d '{
    "app_id": "my-app",
    "guaranteed_quota": 10000,
    "burst_quota": 50000
  }'
```

### 4. 验证限流

```bash
# 发送测试请求
curl -H "X-App-Id: my-app" http://localhost/api/v1/test

# 查看指标
curl http://localhost/metrics
```

---

## 文档更新日志

| 日期 | 版本 | 更新内容 |
|------|------|---------|
| 2025-12-31 | 1.0.0 | 初始版本，完成所有核心文档 |
