# 配置管理 API 规范

## 一、API 概览

```
┌─────────────────────────────────────────────────────────────┐
│                    API 端点分类                              │
├─────────────────────────────────────────────────────────────┤
│  集群管理 API (/api/v1/clusters)                            │
│  • 集群配置、容量管理、紧急模式                              │
├─────────────────────────────────────────────────────────────┤
│  应用管理 API (/api/v1/apps)                                │
│  • 应用配额、优先级、借贷配置                                │
├─────────────────────────────────────────────────────────────┤
│  网关管理 API (/api/v1/gateways)                            │
│  • 网关状态、降级控制                                        │
├─────────────────────────────────────────────────────────────┤
│  监控 API (/api/v1/metrics)                                 │
│  • 实时指标、历史数据                                        │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、OpenAPI 规范

```yaml
openapi: 3.0.3
info:
  title: Rate Limiter Control API
  description: 分布式令牌桶限流系统配置管理 API
  version: 1.0.0
  contact:
    name: API Support
    email: support@example.com

servers:
  - url: https://ratelimit-api.example.com/api/v1
    description: Production
  - url: https://ratelimit-api-staging.example.com/api/v1
    description: Staging

tags:
  - name: clusters
    description: L1 集群管理
  - name: apps
    description: L2 应用管理
  - name: gateways
    description: L3 网关管理
  - name: metrics
    description: 监控指标
  - name: events
    description: 事件与告警

security:
  - bearerAuth: []
  - apiKeyAuth: []

components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
    apiKeyAuth:
      type: apiKey
      in: header
      name: X-API-Key

  schemas:
    # 集群配置
    ClusterConfig:
      type: object
      required:
        - cluster_id
        - capacity
      properties:
        cluster_id:
          type: string
          example: "cluster-01"
        capacity:
          type: integer
          description: 总容量 (tokens/s)
          example: 1000000
        reserved_ratio:
          type: number
          description: 预留比例
          default: 0.1
          example: 0.1
        burst_ratio:
          type: number
          description: 突发比例
          default: 1.2
          example: 1.2
        emergency_threshold:
          type: number
          description: 紧急模式触发阈值
          default: 0.95
          example: 0.95

    # 集群状态
    ClusterStatus:
      type: object
      properties:
        cluster_id:
          type: string
        capacity:
          type: integer
        available:
          type: integer
        usage_ratio:
          type: number
        emergency_mode:
          type: boolean
        app_count:
          type: integer
        last_updated:
          type: string
          format: date-time

    # 应用配置
    AppConfig:
      type: object
      required:
        - app_id
        - guaranteed_quota
      properties:
        app_id:
          type: string
          example: "video-service"
        guaranteed_quota:
          type: integer
          description: 保底配额 (tokens/s)
          example: 20000
        burst_quota:
          type: integer
          description: 突发配额上限
          example: 80000
        priority:
          type: integer
          description: 优先级 (0=最高)
          default: 2
          enum: [0, 1, 2, 3]
        max_borrow:
          type: integer
          description: 最大借用量
          example: 10000
        cost_profile:
          type: string
          description: Cost 计算配置
          enum: [standard, iops_sensitive, bandwidth_sensitive]
          default: standard

    # 应用状态
    AppStatus:
      type: object
      properties:
        app_id:
          type: string
        guaranteed_quota:
          type: integer
        burst_quota:
          type: integer
        current_tokens:
          type: integer
        borrowed:
          type: integer
        debt:
          type: integer
        usage_ratio:
          type: number
        request_rate:
          type: number
        rejection_rate:
          type: number
        last_updated:
          type: string
          format: date-time

    # 网关状态
    GatewayStatus:
      type: object
      properties:
        node_id:
          type: string
        status:
          type: string
          enum: [healthy, degraded, fail_open, offline]
        local_tokens:
          type: integer
        cache_hit_ratio:
          type: number
        pending_sync:
          type: integer
        degradation_level:
          type: integer
        last_seen:
          type: string
          format: date-time

    # 紧急模式请求
    EmergencyRequest:
      type: object
      required:
        - enable
        - reason
      properties:
        enable:
          type: boolean
        reason:
          type: string
          example: "Cluster usage at 96%"
        duration:
          type: integer
          description: 持续时间(秒)
          default: 300
        operator:
          type: string
          example: "sre-team"

    # 错误响应
    Error:
      type: object
      properties:
        code:
          type: string
        message:
          type: string
        details:
          type: object

paths:
  #==========================================
  # 集群管理 API
  #==========================================
  /clusters:
    get:
      tags: [clusters]
      summary: 获取所有集群列表
      responses:
        '200':
          description: 成功
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/ClusterStatus'

  /clusters/{cluster_id}:
    get:
      tags: [clusters]
      summary: 获取集群详情
      parameters:
        - name: cluster_id
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: 成功
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ClusterStatus'
        '404':
          description: 集群不存在

    put:
      tags: [clusters]
      summary: 更新集群配置
      parameters:
        - name: cluster_id
          in: path
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ClusterConfig'
      responses:
        '200':
          description: 更新成功
        '400':
          description: 参数错误

  /clusters/{cluster_id}/emergency:
    post:
      tags: [clusters]
      summary: 控制紧急模式
      parameters:
        - name: cluster_id
          in: path
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/EmergencyRequest'
      responses:
        '200':
          description: 操作成功
          content:
            application/json:
              schema:
                type: object
                properties:
                  status:
                    type: string
                  emergency_mode:
                    type: boolean
                  expires_at:
                    type: string
                    format: date-time

  #==========================================
  # 应用管理 API
  #==========================================
  /apps:
    get:
      tags: [apps]
      summary: 获取所有应用列表
      parameters:
        - name: cluster_id
          in: query
          schema:
            type: string
        - name: status
          in: query
          schema:
            type: string
            enum: [all, healthy, warning, critical]
      responses:
        '200':
          description: 成功
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/AppStatus'

    post:
      tags: [apps]
      summary: 创建应用配置
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/AppConfig'
      responses:
        '201':
          description: 创建成功
        '409':
          description: 应用已存在

  /apps/{app_id}:
    get:
      tags: [apps]
      summary: 获取应用详情
      parameters:
        - name: app_id
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: 成功
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/AppStatus'

    put:
      tags: [apps]
      summary: 更新应用配置
      parameters:
        - name: app_id
          in: path
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/AppConfig'
      responses:
        '200':
          description: 更新成功

    delete:
      tags: [apps]
      summary: 删除应用配置
      parameters:
        - name: app_id
          in: path
          required: true
          schema:
            type: string
      responses:
        '204':
          description: 删除成功

  /apps/{app_id}/quota:
    patch:
      tags: [apps]
      summary: 快速调整配额
      parameters:
        - name: app_id
          in: path
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                guaranteed_quota:
                  type: integer
                burst_quota:
                  type: integer
      responses:
        '200':
          description: 调整成功

  /apps/{app_id}/borrow:
    post:
      tags: [apps]
      summary: 申请借用令牌
      parameters:
        - name: app_id
          in: path
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required:
                - amount
              properties:
                amount:
                  type: integer
                  description: 借用数量
                reason:
                  type: string
      responses:
        '200':
          description: 借用成功
          content:
            application/json:
              schema:
                type: object
                properties:
                  granted:
                    type: integer
                  debt:
                    type: integer
                  expires_at:
                    type: string
                    format: date-time

  /apps/{app_id}/repay:
    post:
      tags: [apps]
      summary: 归还借用令牌
      parameters:
        - name: app_id
          in: path
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required:
                - amount
              properties:
                amount:
                  type: integer
      responses:
        '200':
          description: 归还成功
          content:
            application/json:
              schema:
                type: object
                properties:
                  repaid:
                    type: integer
                  remaining_debt:
                    type: integer


  #==========================================
  # 网关管理 API
  #==========================================
  /gateways:
    get:
      tags: [gateways]
      summary: 获取所有网关状态
      responses:
        '200':
          description: 成功
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/GatewayStatus'

  /gateways/{node_id}:
    get:
      tags: [gateways]
      summary: 获取网关详情
      parameters:
        - name: node_id
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: 成功
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/GatewayStatus'

  /gateways/{node_id}/degradation:
    post:
      tags: [gateways]
      summary: 设置降级级别
      parameters:
        - name: node_id
          in: path
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required:
                - level
              properties:
                level:
                  type: integer
                  enum: [0, 1, 2, 3]
                  description: "0=正常, 1=轻微, 2=显著, 3=完全"
                reason:
                  type: string
      responses:
        '200':
          description: 设置成功

  #==========================================
  # 监控 API
  #==========================================
  /metrics/realtime:
    get:
      tags: [metrics]
      summary: 获取实时指标
      parameters:
        - name: app_id
          in: query
          schema:
            type: string
        - name: metrics
          in: query
          schema:
            type: array
            items:
              type: string
          description: 指标名称列表
      responses:
        '200':
          description: 成功
          content:
            application/json:
              schema:
                type: object
                properties:
                  timestamp:
                    type: string
                    format: date-time
                  metrics:
                    type: object
                    additionalProperties:
                      type: number

  /metrics/history:
    get:
      tags: [metrics]
      summary: 获取历史指标
      parameters:
        - name: app_id
          in: query
          schema:
            type: string
        - name: metric
          in: query
          required: true
          schema:
            type: string
        - name: start
          in: query
          required: true
          schema:
            type: string
            format: date-time
        - name: end
          in: query
          required: true
          schema:
            type: string
            format: date-time
        - name: step
          in: query
          schema:
            type: string
            default: "1m"
      responses:
        '200':
          description: 成功
          content:
            application/json:
              schema:
                type: object
                properties:
                  metric:
                    type: string
                  data:
                    type: array
                    items:
                      type: object
                      properties:
                        timestamp:
                          type: string
                          format: date-time
                        value:
                          type: number

  #==========================================
  # 事件 API
  #==========================================
  /events:
    get:
      tags: [events]
      summary: 获取事件列表
      parameters:
        - name: type
          in: query
          schema:
            type: string
            enum: [all, emergency, config_change, quota_exhausted, borrow]
        - name: app_id
          in: query
          schema:
            type: string
        - name: start
          in: query
          schema:
            type: string
            format: date-time
        - name: end
          in: query
          schema:
            type: string
            format: date-time
        - name: limit
          in: query
          schema:
            type: integer
            default: 100
      responses:
        '200':
          description: 成功
          content:
            application/json:
              schema:
                type: array
                items:
                  type: object
                  properties:
                    id:
                      type: string
                    type:
                      type: string
                    app_id:
                      type: string
                    message:
                      type: string
                    details:
                      type: object
                    timestamp:
                      type: string
                      format: date-time
```

---

## 三、API 使用示例

### 3.1 创建应用配置

```bash
# 创建新应用
curl -X POST https://ratelimit-api.example.com/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "app_id": "video-service",
    "guaranteed_quota": 20000,
    "burst_quota": 80000,
    "priority": 1,
    "max_borrow": 10000,
    "cost_profile": "bandwidth_sensitive"
  }'

# 响应
{
  "app_id": "video-service",
  "status": "created",
  "effective_at": "2025-12-31T10:00:00Z"
}
```

### 3.2 调整配额

```bash
# 快速调整配额
curl -X PATCH https://ratelimit-api.example.com/api/v1/apps/video-service/quota \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "guaranteed_quota": 30000,
    "burst_quota": 100000
  }'

# 响应
{
  "app_id": "video-service",
  "previous": {
    "guaranteed_quota": 20000,
    "burst_quota": 80000
  },
  "current": {
    "guaranteed_quota": 30000,
    "burst_quota": 100000
  },
  "effective_at": "2025-12-31T10:05:00Z"
}
```

### 3.3 激活紧急模式

```bash
# 激活紧急模式
curl -X POST https://ratelimit-api.example.com/api/v1/clusters/cluster-01/emergency \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "enable": true,
    "reason": "Cluster usage at 96%, protecting system",
    "duration": 300,
    "operator": "sre-oncall"
  }'

# 响应
{
  "status": "emergency_activated",
  "emergency_mode": true,
  "expires_at": "2025-12-31T10:10:00Z",
  "affected_apps": ["app-a", "app-b", "app-c"]
}
```

### 3.4 借用令牌

```bash
# 申请借用
curl -X POST https://ratelimit-api.example.com/api/v1/apps/video-service/borrow \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "amount": 5000,
    "reason": "Traffic spike from marketing campaign"
  }'

# 响应
{
  "granted": 5000,
  "debt": 6000,
  "interest_rate": 0.2,
  "expires_at": "2025-12-31T11:00:00Z",
  "remaining_borrow_capacity": 5000
}
```

### 3.5 查询实时指标

```bash
# 获取实时指标
curl -X GET "https://ratelimit-api.example.com/api/v1/metrics/realtime?app_id=video-service&metrics=qps,rejection_rate,tokens_available" \
  -H "Authorization: Bearer $TOKEN"

# 响应
{
  "timestamp": "2025-12-31T10:00:00Z",
  "app_id": "video-service",
  "metrics": {
    "qps": 15234.5,
    "rejection_rate": 0.02,
    "tokens_available": 45000,
    "tokens_borrowed": 5000,
    "cache_hit_ratio": 0.97
  }
}
```

---

## 四、错误码定义

| 错误码 | HTTP 状态 | 描述 |
|--------|----------|------|
| CLUSTER_NOT_FOUND | 404 | 集群不存在 |
| APP_NOT_FOUND | 404 | 应用不存在 |
| APP_ALREADY_EXISTS | 409 | 应用已存在 |
| INVALID_QUOTA | 400 | 配额参数无效 |
| QUOTA_EXCEEDS_CLUSTER | 400 | 配额超过集群容量 |
| BORROW_LIMIT_EXCEEDED | 400 | 超过借用限制 |
| CLUSTER_INSUFFICIENT | 503 | 集群容量不足 |
| EMERGENCY_MODE_ACTIVE | 503 | 紧急模式已激活 |
| UNAUTHORIZED | 401 | 未授权 |
| FORBIDDEN | 403 | 权限不足 |
| RATE_LIMITED | 429 | API 请求过多 |

---

## 五、Webhook 通知

### 5.1 Webhook 配置

```yaml
# webhook 配置
webhooks:
  - name: "slack-alerts"
    url: "https://hooks.slack.com/services/xxx"
    events:
      - emergency_activated
      - emergency_deactivated
      - quota_exhausted
      - high_rejection_rate
    
  - name: "pagerduty"
    url: "https://events.pagerduty.com/v2/enqueue"
    events:
      - emergency_activated
      - cluster_near_exhaustion
    headers:
      Authorization: "Token token=xxx"
```

### 5.2 Webhook 事件格式

```json
{
  "event_type": "emergency_activated",
  "timestamp": "2025-12-31T10:00:00Z",
  "cluster_id": "cluster-01",
  "data": {
    "reason": "Cluster usage at 96%",
    "operator": "sre-oncall",
    "duration": 300,
    "usage_ratio": 0.96
  },
  "metadata": {
    "source": "ratelimit-api",
    "version": "1.0.0"
  }
}
```
