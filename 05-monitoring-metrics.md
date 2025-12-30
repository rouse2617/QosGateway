# 监控指标设计文档

## 一、指标体系概览

```
┌─────────────────────────────────────────────────────────────┐
│                      监控指标层次                            │
├─────────────────────────────────────────────────────────────┤
│  业务层指标                                                  │
│  • 请求成功率、拒绝率                                        │
│  • 应用配额使用率                                            │
│  • Cost 分布统计                                             │
├─────────────────────────────────────────────────────────────┤
│  系统层指标                                                  │
│  • L1/L2/L3 令牌状态                                        │
│  • Redis 延迟、连接数                                        │
│  • Nginx 性能指标                                            │
├─────────────────────────────────────────────────────────────┤
│  基础设施指标                                                │
│  • CPU、内存、网络                                           │
│  • 磁盘 IO                                                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、Prometheus 指标定义

### 2.1 请求指标

```lua
-- nginx/lua/ratelimit/metrics.lua
local prometheus = require("prometheus")

local _M = {}

-- 初始化指标
local metrics = {}

function _M.init()
    metrics.requests_total = prometheus:counter(
        "ratelimit_requests_total",
        "Total number of requests",
        {"app_id", "method", "status"}
    )
    
    metrics.requests_allowed = prometheus:counter(
        "ratelimit_requests_allowed_total",
        "Total number of allowed requests",
        {"app_id", "method"}
    )
    
    metrics.requests_rejected = prometheus:counter(
        "ratelimit_requests_rejected_total",
        "Total number of rejected requests",
        {"app_id", "method", "reason"}
    )
    
    metrics.request_cost = prometheus:histogram(
        "ratelimit_request_cost",
        "Request cost distribution",
        {"app_id", "method"},
        {1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 5000, 10000}
    )
    
    metrics.request_latency = prometheus:histogram(
        "ratelimit_check_latency_seconds",
        "Rate limit check latency",
        {"app_id", "source"},
        {0.0001, 0.0005, 0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1}
    )
end
```


### 2.2 令牌桶指标

```lua
-- 令牌桶状态指标
function _M.init_bucket_metrics()
    -- L1 集群层
    metrics.l1_tokens_available = prometheus:gauge(
        "ratelimit_l1_tokens_available",
        "L1 cluster available tokens",
        {"cluster_id"}
    )
    
    metrics.l1_tokens_capacity = prometheus:gauge(
        "ratelimit_l1_tokens_capacity",
        "L1 cluster total capacity",
        {"cluster_id"}
    )
    
    metrics.l1_usage_ratio = prometheus:gauge(
        "ratelimit_l1_usage_ratio",
        "L1 cluster usage ratio",
        {"cluster_id"}
    )
    
    -- L2 应用层
    metrics.l2_tokens_available = prometheus:gauge(
        "ratelimit_l2_tokens_available",
        "L2 application available tokens",
        {"app_id"}
    )
    
    metrics.l2_tokens_guaranteed = prometheus:gauge(
        "ratelimit_l2_tokens_guaranteed",
        "L2 application guaranteed quota",
        {"app_id"}
    )
    
    metrics.l2_tokens_burst = prometheus:gauge(
        "ratelimit_l2_tokens_burst",
        "L2 application burst quota",
        {"app_id"}
    )
    
    metrics.l2_tokens_borrowed = prometheus:gauge(
        "ratelimit_l2_tokens_borrowed",
        "L2 application borrowed tokens",
        {"app_id"}
    )
    
    metrics.l2_tokens_debt = prometheus:gauge(
        "ratelimit_l2_tokens_debt",
        "L2 application debt",
        {"app_id"}
    )
    
    -- L3 本地层
    metrics.l3_tokens_local = prometheus:gauge(
        "ratelimit_l3_tokens_local",
        "L3 local cached tokens",
        {"app_id", "node_id"}
    )
    
    metrics.l3_cache_hit_ratio = prometheus:gauge(
        "ratelimit_l3_cache_hit_ratio",
        "L3 local cache hit ratio",
        {"app_id", "node_id"}
    )
    
    metrics.l3_pending_sync = prometheus:gauge(
        "ratelimit_l3_pending_sync",
        "L3 pending sync count",
        {"app_id", "node_id"}
    )
end

### 2.3 Redis 指标

```lua
function _M.init_redis_metrics()
    metrics.redis_commands_total = prometheus:counter(
        "ratelimit_redis_commands_total",
        "Total Redis commands executed",
        {"command", "status"}
    )
    
    metrics.redis_latency = prometheus:histogram(
        "ratelimit_redis_latency_seconds",
        "Redis command latency",
        {"command"},
        {0.0001, 0.0005, 0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1}
    )
    
    metrics.redis_connections = prometheus:gauge(
        "ratelimit_redis_connections",
        "Redis connection pool size",
        {"state"}  -- active, idle
    )
    
    metrics.redis_errors_total = prometheus:counter(
        "ratelimit_redis_errors_total",
        "Total Redis errors",
        {"error_type"}
    )
end
```

### 2.4 系统状态指标

```lua
function _M.init_system_metrics()
    metrics.emergency_mode = prometheus:gauge(
        "ratelimit_emergency_mode",
        "Emergency mode status (1=active, 0=inactive)",
        {"cluster_id"}
    )
    
    metrics.degradation_level = prometheus:gauge(
        "ratelimit_degradation_level",
        "Current degradation level (0-3)",
        {"node_id"}
    )
    
    metrics.fail_open_active = prometheus:gauge(
        "ratelimit_fail_open_active",
        "Fail-open mode status",
        {"node_id"}
    )
    
    metrics.reconcile_corrections = prometheus:counter(
        "ratelimit_reconcile_corrections_total",
        "Total reconciliation corrections",
        {"app_id", "type"}
    )
    
    metrics.config_updates = prometheus:counter(
        "ratelimit_config_updates_total",
        "Total configuration updates",
        {"app_id", "source"}
    )
end
```

### 2.5 指标记录函数

```lua
-- 记录请求
function _M.record_request(app_id, method, cost, allowed, reason, latency)
    local status = allowed and "allowed" or "rejected"
    
    metrics.requests_total:inc(1, {app_id, method, status})
    metrics.request_cost:observe(cost, {app_id, method})
    metrics.request_latency:observe(latency, {app_id, allowed and "local" or "remote"})
    
    if allowed then
        metrics.requests_allowed:inc(1, {app_id, method})
    else
        metrics.requests_rejected:inc(1, {app_id, method, reason or "unknown"})
    end
end

-- 更新令牌桶状态
function _M.update_bucket_metrics(level, data)
    if level == "l1" then
        metrics.l1_tokens_available:set(data.available, {data.cluster_id})
        metrics.l1_tokens_capacity:set(data.capacity, {data.cluster_id})
        metrics.l1_usage_ratio:set(1 - data.available / data.capacity, {data.cluster_id})
    elseif level == "l2" then
        metrics.l2_tokens_available:set(data.available, {data.app_id})
        metrics.l2_tokens_guaranteed:set(data.guaranteed, {data.app_id})
        metrics.l2_tokens_burst:set(data.burst, {data.app_id})
        metrics.l2_tokens_borrowed:set(data.borrowed or 0, {data.app_id})
        metrics.l2_tokens_debt:set(data.debt or 0, {data.app_id})
    elseif level == "l3" then
        metrics.l3_tokens_local:set(data.local_tokens, {data.app_id, data.node_id})
        metrics.l3_cache_hit_ratio:set(data.hit_ratio, {data.app_id, data.node_id})
        metrics.l3_pending_sync:set(data.pending, {data.app_id, data.node_id})
    end
end

-- 导出 Prometheus 格式
function _M.export_prometheus()
    return prometheus:collect()
end

return _M
```

---

## 三、Prometheus 配置

### 3.1 prometheus.yml

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  # Nginx 网关指标
  - job_name: 'nginx-ratelimit'
    static_configs:
      - targets: ['nginx-gateway:9145']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '([^:]+):\d+'
        replacement: '${1}'

  # Redis 指标
  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']

  # Kubernetes 服务发现
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
```

### 3.2 告警规则

```yaml
# /etc/prometheus/rules/ratelimit.yml
groups:
  - name: ratelimit_alerts
    rules:
      # 高拒绝率告警
      - alert: HighRejectionRate
        expr: |
          sum(rate(ratelimit_requests_rejected_total[5m])) by (app_id)
          /
          sum(rate(ratelimit_requests_total[5m])) by (app_id)
          > 0.1
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High rejection rate for {{ $labels.app_id }}"
          description: "Rejection rate is {{ $value | humanizePercentage }} for app {{ $labels.app_id }}"

      # L1 配额即将耗尽
      - alert: L1QuotaNearExhaustion
        expr: ratelimit_l1_usage_ratio > 0.9
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "L1 cluster quota near exhaustion"
          description: "L1 usage is at {{ $value | humanizePercentage }}"

      # L2 应用配额耗尽
      - alert: L2AppQuotaExhausted
        expr: |
          ratelimit_l2_tokens_available / ratelimit_l2_tokens_guaranteed < 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "L2 quota low for {{ $labels.app_id }}"
          description: "Available tokens below 10% of guaranteed quota"

      # Redis 延迟过高
      - alert: RedisHighLatency
        expr: |
          histogram_quantile(0.99, rate(ratelimit_redis_latency_seconds_bucket[5m])) > 0.1
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Redis latency is high"
          description: "P99 latency is {{ $value | humanizeDuration }}"

      # 紧急模式激活
      - alert: EmergencyModeActive
        expr: ratelimit_emergency_mode == 1
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: "Emergency mode is active"
          description: "Rate limiting emergency mode has been activated"

      # Fail-Open 模式
      - alert: FailOpenModeActive
        expr: ratelimit_fail_open_active == 1
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Fail-open mode is active on {{ $labels.node_id }}"
          description: "Redis connection failed, running in fail-open mode"

      # L3 缓存命中率低
      - alert: LowCacheHitRatio
        expr: ratelimit_l3_cache_hit_ratio < 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low L3 cache hit ratio for {{ $labels.app_id }}"
          description: "Cache hit ratio is {{ $value | humanizePercentage }}"

      # 借贷过多
      - alert: HighBorrowedTokens
        expr: |
          ratelimit_l2_tokens_borrowed / ratelimit_l2_tokens_guaranteed > 0.5
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High borrowed tokens for {{ $labels.app_id }}"
          description: "Borrowed tokens exceed 50% of guaranteed quota"
```


---

## 四、Grafana 仪表板

### 4.1 总览仪表板 JSON

```json
{
  "dashboard": {
    "title": "Rate Limiter Overview",
    "uid": "ratelimit-overview",
    "tags": ["ratelimit", "overview"],
    "timezone": "browser",
    "panels": [
      {
        "title": "System Health Score",
        "type": "gauge",
        "gridPos": {"h": 6, "w": 6, "x": 0, "y": 0},
        "targets": [
          {
            "expr": "100 - (sum(rate(ratelimit_requests_rejected_total[5m])) / sum(rate(ratelimit_requests_total[5m])) * 100)",
            "legendFormat": "Health Score"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "thresholds": {
              "steps": [
                {"color": "red", "value": 0},
                {"color": "yellow", "value": 80},
                {"color": "green", "value": 95}
              ]
            },
            "unit": "percent",
            "min": 0,
            "max": 100
          }
        }
      },
      {
        "title": "Total QPS",
        "type": "stat",
        "gridPos": {"h": 6, "w": 6, "x": 6, "y": 0},
        "targets": [
          {
            "expr": "sum(rate(ratelimit_requests_total[1m]))",
            "legendFormat": "QPS"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "reqps"
          }
        }
      },
      {
        "title": "Rejection Rate",
        "type": "stat",
        "gridPos": {"h": 6, "w": 6, "x": 12, "y": 0},
        "targets": [
          {
            "expr": "sum(rate(ratelimit_requests_rejected_total[5m])) / sum(rate(ratelimit_requests_total[5m])) * 100",
            "legendFormat": "Rejection %"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "thresholds": {
              "steps": [
                {"color": "green", "value": 0},
                {"color": "yellow", "value": 5},
                {"color": "red", "value": 10}
              ]
            }
          }
        }
      },
      {
        "title": "Emergency Mode",
        "type": "stat",
        "gridPos": {"h": 6, "w": 6, "x": 18, "y": 0},
        "targets": [
          {
            "expr": "max(ratelimit_emergency_mode)",
            "legendFormat": "Emergency"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "mappings": [
              {"type": "value", "options": {"0": {"text": "Normal", "color": "green"}}},
              {"type": "value", "options": {"1": {"text": "EMERGENCY", "color": "red"}}}
            ]
          }
        }
      },
      {
        "title": "Request Rate by App",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 6},
        "targets": [
          {
            "expr": "sum(rate(ratelimit_requests_total[1m])) by (app_id)",
            "legendFormat": "{{app_id}}"
          }
        ]
      },
      {
        "title": "Rejection Rate by App",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 6},
        "targets": [
          {
            "expr": "sum(rate(ratelimit_requests_rejected_total[5m])) by (app_id) / sum(rate(ratelimit_requests_total[5m])) by (app_id) * 100",
            "legendFormat": "{{app_id}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent"
          }
        }
      },
      {
        "title": "L1 Cluster Usage",
        "type": "gauge",
        "gridPos": {"h": 6, "w": 8, "x": 0, "y": 14},
        "targets": [
          {
            "expr": "ratelimit_l1_usage_ratio * 100",
            "legendFormat": "Usage"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "min": 0,
            "max": 100,
            "thresholds": {
              "steps": [
                {"color": "green", "value": 0},
                {"color": "yellow", "value": 70},
                {"color": "red", "value": 90}
              ]
            }
          }
        }
      },
      {
        "title": "L2 App Quota Usage",
        "type": "bargauge",
        "gridPos": {"h": 6, "w": 8, "x": 8, "y": 14},
        "targets": [
          {
            "expr": "(1 - ratelimit_l2_tokens_available / ratelimit_l2_tokens_burst) * 100",
            "legendFormat": "{{app_id}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "min": 0,
            "max": 100
          }
        }
      },
      {
        "title": "L3 Cache Hit Ratio",
        "type": "bargauge",
        "gridPos": {"h": 6, "w": 8, "x": 16, "y": 14},
        "targets": [
          {
            "expr": "ratelimit_l3_cache_hit_ratio * 100",
            "legendFormat": "{{node_id}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "min": 0,
            "max": 100,
            "thresholds": {
              "steps": [
                {"color": "red", "value": 0},
                {"color": "yellow", "value": 80},
                {"color": "green", "value": 95}
              ]
            }
          }
        }
      },
      {
        "title": "Cost Distribution",
        "type": "heatmap",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 20},
        "targets": [
          {
            "expr": "sum(rate(ratelimit_request_cost_bucket[5m])) by (le)",
            "legendFormat": "{{le}}"
          }
        ]
      },
      {
        "title": "Redis Latency P99",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 20},
        "targets": [
          {
            "expr": "histogram_quantile(0.99, rate(ratelimit_redis_latency_seconds_bucket[5m]))",
            "legendFormat": "P99"
          },
          {
            "expr": "histogram_quantile(0.95, rate(ratelimit_redis_latency_seconds_bucket[5m]))",
            "legendFormat": "P95"
          },
          {
            "expr": "histogram_quantile(0.50, rate(ratelimit_redis_latency_seconds_bucket[5m]))",
            "legendFormat": "P50"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "s"
          }
        }
      }
    ]
  }
}
```

### 4.2 应用详情仪表板

```json
{
  "dashboard": {
    "title": "Rate Limiter - App Detail",
    "uid": "ratelimit-app-detail",
    "templating": {
      "list": [
        {
          "name": "app_id",
          "type": "query",
          "query": "label_values(ratelimit_requests_total, app_id)",
          "refresh": 2
        }
      ]
    },
    "panels": [
      {
        "title": "App QPS",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "targets": [
          {
            "expr": "sum(rate(ratelimit_requests_total{app_id=\"$app_id\"}[1m])) by (method)",
            "legendFormat": "{{method}}"
          }
        ]
      },
      {
        "title": "Token Bucket Status",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
        "targets": [
          {
            "expr": "ratelimit_l2_tokens_available{app_id=\"$app_id\"}",
            "legendFormat": "Available"
          },
          {
            "expr": "ratelimit_l2_tokens_guaranteed{app_id=\"$app_id\"}",
            "legendFormat": "Guaranteed"
          },
          {
            "expr": "ratelimit_l2_tokens_burst{app_id=\"$app_id\"}",
            "legendFormat": "Burst Limit"
          }
        ]
      },
      {
        "title": "Rejection Reasons",
        "type": "piechart",
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 8},
        "targets": [
          {
            "expr": "sum(rate(ratelimit_requests_rejected_total{app_id=\"$app_id\"}[5m])) by (reason)",
            "legendFormat": "{{reason}}"
          }
        ]
      },
      {
        "title": "Cost by Method",
        "type": "bargauge",
        "gridPos": {"h": 8, "w": 8, "x": 8, "y": 8},
        "targets": [
          {
            "expr": "sum(rate(ratelimit_request_cost_sum{app_id=\"$app_id\"}[5m])) by (method) / sum(rate(ratelimit_request_cost_count{app_id=\"$app_id\"}[5m])) by (method)",
            "legendFormat": "{{method}}"
          }
        ]
      },
      {
        "title": "Borrowed vs Debt",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 8, "x": 16, "y": 8},
        "targets": [
          {
            "expr": "ratelimit_l2_tokens_borrowed{app_id=\"$app_id\"}",
            "legendFormat": "Borrowed"
          },
          {
            "expr": "ratelimit_l2_tokens_debt{app_id=\"$app_id\"}",
            "legendFormat": "Debt"
          }
        ]
      }
    ]
  }
}
```

---

## 五、关键指标查询

### 5.1 常用 PromQL 查询

```promql
# 1. 总体 QPS
sum(rate(ratelimit_requests_total[1m]))

# 2. 按应用的 QPS
sum(rate(ratelimit_requests_total[1m])) by (app_id)

# 3. 拒绝率
sum(rate(ratelimit_requests_rejected_total[5m])) 
/ sum(rate(ratelimit_requests_total[5m])) * 100

# 4. 按应用的拒绝率
sum(rate(ratelimit_requests_rejected_total[5m])) by (app_id)
/ sum(rate(ratelimit_requests_total[5m])) by (app_id) * 100

# 5. L1 使用率
ratelimit_l1_usage_ratio * 100

# 6. L2 配额使用率
(1 - ratelimit_l2_tokens_available / ratelimit_l2_tokens_burst) * 100

# 7. L3 缓存命中率
avg(ratelimit_l3_cache_hit_ratio) by (app_id) * 100

# 8. Redis P99 延迟
histogram_quantile(0.99, rate(ratelimit_redis_latency_seconds_bucket[5m]))

# 9. 平均 Cost
sum(rate(ratelimit_request_cost_sum[5m])) / sum(rate(ratelimit_request_cost_count[5m]))

# 10. 按方法的平均 Cost
sum(rate(ratelimit_request_cost_sum[5m])) by (method) 
/ sum(rate(ratelimit_request_cost_count[5m])) by (method)

# 11. 限流检查延迟 P99
histogram_quantile(0.99, rate(ratelimit_check_latency_seconds_bucket[5m]))

# 12. 借贷比例
ratelimit_l2_tokens_borrowed / ratelimit_l2_tokens_guaranteed * 100

# 13. 紧急模式状态
max(ratelimit_emergency_mode)

# 14. Fail-Open 节点数
count(ratelimit_fail_open_active == 1)

# 15. 对账修正次数
sum(rate(ratelimit_reconcile_corrections_total[1h])) by (app_id)
```

### 5.2 SLO 定义

```yaml
# SLO 配置
slos:
  - name: "Request Success Rate"
    target: 99.9%
    query: |
      1 - (
        sum(rate(ratelimit_requests_rejected_total{reason!="quota_exhausted"}[30d]))
        / sum(rate(ratelimit_requests_total[30d]))
      )
    
  - name: "Rate Limit Check Latency P99"
    target: 10ms
    query: |
      histogram_quantile(0.99, rate(ratelimit_check_latency_seconds_bucket[30d]))
    
  - name: "L3 Cache Hit Rate"
    target: 95%
    query: |
      avg(ratelimit_l3_cache_hit_ratio)
    
  - name: "Redis Availability"
    target: 99.99%
    query: |
      1 - (
        sum(rate(ratelimit_redis_errors_total[30d]))
        / sum(rate(ratelimit_redis_commands_total[30d]))
      )
```
