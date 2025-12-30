# OpenResty Distributed Storage QoS Rate Limiting System - OpenAPI 3.1 Specification

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Authentication & Authorization](#authentication--authorization)
4. [Common Components](#common-components)
5. [REST API Endpoints](#rest-api-endpoints)
6. [WebSocket API](#websocket-api)
7. [Error Handling](#error-handling)
8. [Rate Limiting](#rate-limiting)
9. [Versioning Strategy](#versioning-strategy)

---

## Overview

This API provides comprehensive management for a three-layer distributed token bucket rate limiting system designed for cloud storage QoS (Quality of Service). The system controls IOPS and bandwidth for storage operations using:

- **L1 (Cluster Level)**: Global cluster-wide rate limits
- **L2 (Application Level)**: Per-application quota management
- **L3 (Local Cache)**: OpenResty local shard-level caching for performance

### Base URL
```
Production: https://api.qos-system.example.com/v1
Staging: https://api.qos-system.staging.example.com/v1
Development: http://localhost:8080/v1
```

### Cost Model
```
Cost = C_base + (Size_body / Unit_quantum) × C_bw
```

Where:
- `C_base`: Base operation cost (depends on operation type: GET, PUT, DELETE, LIST)
- `Size_body`: Request/Response body size in bytes
- `Unit_quantum`: Quantum unit size (configurable, default: 4096 bytes)
- `C_bw`: Bandwidth cost factor

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     API Gateway (OpenResty)                  │
│  - L3 Local Token Cache (Shared Memory)                     │
│  - Rate Limit Enforcement                                   │
│  - WebSocket Proxy                                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Go Admin Backend                           │
│  - L2 Application Management                                │
│  - L1 Cluster Configuration                                 │
│  - Metrics Aggregation                                      │
│  - Alert Processing                                         │
│  - WebSocket Server                                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Storage Backend                            │
│  - Distributed Configuration Store (etcd/Consul)            │
│  - Time-Series Database (Prometheus/InfluxDB)               │
│  - Relational Database (PostgreSQL)                         │
└─────────────────────────────────────────────────────────────┘
```

---

## Authentication & Authorization

### Authentication Methods

#### 1. JWT Authentication (Recommended)
```yaml
Authorization: Bearer <jwt_token>
```

Token claims:
```json
{
  "sub": "user_id",
  "name": "user_name",
  "roles": ["admin", "operator"],
  "permissions": ["applications:read", "applications:write"],
  "exp": 1704067200,
  "iat": 1704063600
}
```

#### 2. API Key Authentication (For service accounts)
```yaml
X-API-Key: <api_key>
```

### Token Endpoint
```http
POST /api/v1/auth/token
```

### Authorization Model (RBAC)

| Role | Permissions |
|------|-------------|
| **Super Admin** | `*:*` (Full access) |
| **Cluster Admin** | `clusters:*`, `applications:*`, `monitoring:*` |
| **Operator** | `applications:read`, `applications:write`, `monitoring:read` |
| **Viewer** | `applications:read`, `monitoring:read` |
| **Service Account** | Specific permissions based on scope |

---

## Common Components

### OpenAPI 3.1 Specification (YAML)

```yaml
openapi: 3.1.0
info:
  title: OpenResty Distributed Storage QoS Rate Limiting System
  description: |
    Comprehensive API for managing a three-layer distributed token bucket
    rate limiting system designed for cloud storage QoS.

    ## Features
    - L1 Cluster-level rate limiting
    - L2 Application-level quota management
    - L3 Local cache optimization
    - Real-time monitoring and metrics
    - Alert management
    - Configuration versioning and rollback

    ## Cost Model
    Cost = C_base + (Size_body / Unit_quantum) × C_bw
  version: 1.0.0
  contact:
    name: API Support
    email: support@qos-system.example.com
    url: https://qos-system.example.com/support
  license:
    name: Apache 2.0
    url: https://www.apache.org/licenses/LICENSE-2.0.html

servers:
  - url: https://api.qos-system.example.com/v1
    description: Production server
  - url: https://api.qos-system.staging.example.com/v1
    description: Staging server
  - url: http://localhost:8080/v1
    description: Local development server

tags:
  - name: Authentication
    description: User authentication and token management
  - name: Clusters
    description: L1 cluster configuration and management
  - name: Applications
    description: L2 application CRUD and quota management
  - name: TokenBuckets
    description: Token bucket configuration and state management
  - name: CostRules
    description: Operation cost rules configuration
  - name: Monitoring
    description: Real-time metrics and historical data
  - name: Configuration
    description: Configuration versioning, deployment, and rollback
  - name: Alerts
    description: Alert rule management and notifications
  - name: Users
    description: User and role management
  - name: Health
    description: System health check endpoints
  - name: WebSocket
    description: Real-time WebSocket events

security:
  - BearerAuth: []
  - ApiKeyAuth: []

components:
  securitySchemes:
    BearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
      description: JWT token authentication
    ApiKeyAuth:
      type: apiKey
      in: header
      name: X-API-Key
      description: API key authentication for service accounts

  schemas:
    # Common Schemas
    Error:
      type: object
      required:
        - error
      properties:
        error:
          type: string
          description: Human-readable error message
        code:
          type: string
          description: Machine-readable error code
          example: "RATE_LIMIT_EXCEEDED"
        details:
          type: object
          description: Additional error details
          additionalProperties: true
        requestId:
          type: string
          format: uuid
          description: Unique request identifier for tracing
        timestamp:
          type: string
          format: date-time
          description: Error timestamp

    Pagination:
      type: object
      description: Pagination metadata
      properties:
        page:
          type: integer
          minimum: 1
          default: 1
          description: Current page number
        pageSize:
          type: integer
          minimum: 1
          maximum: 1000
          default: 50
          description: Number of items per page
        totalPages:
          type: integer
          minimum: 0
          readOnly: true
          description: Total number of pages
        totalItems:
          type: integer
          minimum: 0
          readOnly: true
          description: Total number of items

    SortOrder:
      type: string
      enum: [asc, desc]
      default: desc
      description: Sort order

    # Application Schemas
    Application:
      type: object
      required:
        - id
        - name
        - appId
        - clusterId
      properties:
        id:
          type: string
          format: uuid
          readOnly: true
          description: Unique application identifier
        name:
          type: string
          minLength: 1
          maxLength: 255
          description: Human-readable application name
        appId:
          type: string
          minLength: 1
          maxLength: 128
          pattern: '^[a-zA-Z0-9_-]+$'
          description: Unique application key (used in API requests)
        description:
          type: string
          maxLength: 1000
          description: Application description
        clusterId:
          type: string
          format: uuid
          description: Parent cluster identifier
        enabled:
          type: boolean
          default: true
          description: Whether the application is active
        priority:
          type: integer
          minimum: 1
          maximum: 10
          default: 5
          description: Application priority (1 = lowest, 10 = highest)
        tags:
          type: object
          additionalProperties:
            type: string
          description: Application tags for filtering and organization
        createdAt:
          type: string
          format: date-time
          readOnly: true
        updatedAt:
          type: string
          format: date-time
          readOnly: true
        createdBy:
          type: string
          readOnly: true
        updatedBy:
          type: string
          readOnly: true

    ApplicationQuota:
      type: object
      description: L2 application-level quota configuration
      required:
        - applicationId
      properties:
        applicationId:
          type: string
          format: uuid
          description: Application identifier
        iops:
          type: object
          description: IOPS (Input/Output Operations Per Second) quota
          required: [limit, burst]
          properties:
            limit:
              type: integer
              minimum: 1
              description: Sustained IOPS limit
              example: 10000
            burst:
              type: integer
              minimum: 1
              description: Peak/burst IOPS limit
              example: 15000
        bandwidth:
          type: object
          description: Bandwidth quota (bytes per second)
          required: [limit, burst]
          properties:
            limit:
              type: integer
              minimum: 1
              description: Sustained bandwidth limit (bytes/sec)
              example: 1073741824
            burst:
              type: integer
              minimum: 1
              description: Peak/burst bandwidth limit (bytes/sec)
              example: 2147483648
        storageSize:
          type: object
          description: Total storage size quota
          properties:
            limit:
              type: integer
              minimum: 0
              description: Maximum storage size in bytes (0 = unlimited)
              example: 1099511627776
        requestRate:
          type: object
          description: Request rate quota (requests per second)
          properties:
            limit:
              type: integer
              minimum: 1
              description: Request rate limit
              example: 1000
            burst:
              type: integer
              minimum: 1
              description: Burst request rate limit
              example: 1500
        connections:
          type: object
          description: Concurrent connections quota
          properties:
            limit:
              type: integer
              minimum: 1
              description: Maximum concurrent connections
              example: 100

    # Cluster Schemas
    Cluster:
      type: object
      required:
        - id
        - name
        - region
      properties:
        id:
          type: string
          format: uuid
          readOnly: true
          description: Unique cluster identifier
        name:
          type: string
          minLength: 1
          maxLength: 255
          description: Cluster name
        region:
          type: string
          minLength: 1
          maxLength: 100
          description: Geographic region
          example: "us-east-1"
        description:
          type: string
          maxLength: 1000
          description: Cluster description
        gatewayEndpoints:
          type: array
          description: OpenResty gateway endpoints for this cluster
          items:
            type: string
            format: uri
          example: ["https://gateway1.example.com", "https://gateway2.example.com"]
        enabled:
          type: boolean
          default: true
          description: Whether the cluster is active
        tags:
          type: object
          additionalProperties:
            type: string
        createdAt:
          type: string
          format: date-time
          readOnly: true
        updatedAt:
          type: string
          format: date-time
          readOnly: true

    ClusterConfiguration:
      type: object
      description: L1 cluster-level token bucket configuration
      required:
        - clusterId
      properties:
        clusterId:
          type: string
          format: uuid
          description: Cluster identifier
        globalIops:
          type: object
          description: Global cluster-wide IOPS limits
          required: [limit, burst]
          properties:
            limit:
              type: integer
              minimum: 1
              description: Sustained IOPS limit for entire cluster
              example: 1000000
            burst:
              type: integer
              minimum: 1
              description: Peak/burst IOPS limit for entire cluster
              example: 1500000
        globalBandwidth:
          type: object
          description: Global cluster-wide bandwidth limits
          required: [limit, burst]
          properties:
            limit:
              type: integer
              minimum: 1
              description: Sustained bandwidth limit (bytes/sec)
              example: 107374182400
            burst:
              type: integer
              minimum: 1
              description: Peak/burst bandwidth limit (bytes/sec)
              example: 214748364800
        defaultQuota:
          type: object
          description: Default quotas for new applications
          allOf:
            - $ref: '#/components/schemas/ApplicationQuota'
            - type: object
              properties:
                applicationId:
                  type: string
                  readOnly: true
        rateLimiting:
          type: object
          description: Rate limiting algorithm settings
          properties:
            algorithm:
              type: string
              enum: [token-bucket, leaky-bucket, sliding-window]
              default: token-bucket
              description: Rate limiting algorithm
            refillRate:
              type: number
              format: float
              minimum: 0
              description: Token refill rate (tokens per second)
            capacity:
              type: integer
              minimum: 1
              description: Maximum token capacity
        sharding:
          type: object
          description: L3 local cache sharding configuration
          properties:
            enabled:
              type: boolean
              default: true
            shardCount:
              type: integer
              minimum: 1
              maximum: 1024
              description: Number of local cache shards
              example: 16
            replicationFactor:
              type: integer
              minimum: 1
              maximum: 5
              description: Number of replicas per shard
              example: 2
            cacheSize:
              type: integer
              minimum: 1
              description: Local cache size in bytes per shard
              example: 10485760

    # Token Bucket State
    TokenBucketState:
      type: object
      description: Current state of a token bucket
      required:
        - bucketId
        - tokens
        - lastRefill
      properties:
        bucketId:
          type: string
          description: Unique bucket identifier
        level:
          type: string
          enum: [L1, L2, L3]
          description: Token bucket level
        tokens:
          type: number
          format: float
          minimum: 0
          description: Current available tokens
        capacity:
          type: integer
          minimum: 1
          description: Maximum token capacity
        refillRate:
          type: number
          format: float
          minimum: 0
          description: Token refill rate (tokens per second)
        lastRefill:
          type: string
          format: date-time
          description: Last refill timestamp
        lastConsume:
          type: string
          format: date-time
          description: Last consumption timestamp
        isBlocked:
          type: boolean
          description: Whether the bucket is currently blocked (no tokens)
        blockDuration:
          type: integer
          minimum: 0
          description: Duration of current block in milliseconds (0 if not blocked)

    # Cost Rule Schemas
    OperationType:
      type: string
      enum: [GET, PUT, DELETE, LIST, HEAD, POST, PATCH]
      description: Storage operation type

    CostRule:
      type: object
      required:
        - operationType
        - baseCost
        - bandwidthCostFactor
      properties:
        id:
          type: string
          format: uuid
          readOnly: true
        operationType:
          $ref: '#/components/schemas/OperationType'
        baseCost:
          type: number
          format: float
          minimum: 0
          description: Base operation cost (C_base)
          example: 1.0
        bandwidthCostFactor:
          type: number
          format: float
          minimum: 0
          description: Bandwidth cost factor (C_bw)
          example: 0.0001
        unitQuantum:
          type: integer
          minimum: 1
          default: 4096
          description: Quantum unit size in bytes
          example: 4096
        description:
          type: string
          description: Rule description
        enabled:
          type: boolean
          default: true
        priority:
          type: integer
          minimum: 1
          maximum: 100
          default: 50
          description: Rule priority (higher = evaluated first)

    # Monitoring Schemas
    MetricDataPoint:
      type: object
      required:
        - timestamp
        - value
      properties:
        timestamp:
          type: string
          format: date-time
          description: Metric timestamp
        value:
          type: number
          format: float
          description: Metric value
        labels:
          type: object
          additionalProperties:
            type: string
          description: Metric labels/dimensions

    MetricQuery:
      type: object
      required:
        - metric
        - timeRange
      properties:
        metric:
          type: string
          enum:
            - iops.usage
            - iops.limit
            - bandwidth.usage
            - bandwidth.limit
            - requests.total
            - requests.blocked
            - latency.p50
            - latency.p95
            - latency.p99
            - cache.hit_rate
            - tokens.available
          description: Metric name
        applicationId:
          type: string
          format: uuid
          description: Filter by application
        clusterId:
          type: string
          format: uuid
          description: Filter by cluster
        timeRange:
          type: object
          required: [start, end]
          properties:
            start:
              type: string
              format: date-time
            end:
              type: string
              format: date-time
        aggregation:
          type: string
          enum: [avg, sum, min, max, rate, p50, p95, p99]
          default: avg
          description: Aggregation function
        granularity:
          type: string
          enum: [1m, 5m, 15m, 1h, 1d]
          default: 5m
          description: Time granularity for aggregation
        groupBy:
          type: array
          items:
            type: string
          description: Group by these dimensions

    ApplicationMetrics:
      type: object
      required:
        - applicationId
        - timestamp
      properties:
        applicationId:
          type: string
          format: uuid
        clusterId:
          type: string
          format: uuid
        timestamp:
          type: string
          format: date-time
        iops:
          type: object
          properties:
            usage:
              type: number
              format: float
              description: Current IOPS usage
            limit:
              type: integer
              description: IOPS limit
            burstUsage:
              type: number
              format: float
            burstLimit:
              type: integer
        bandwidth:
          type: object
          properties:
            usage:
              type: number
              format: float
              description: Current bandwidth usage (bytes/sec)
            limit:
              type: integer
              description: Bandwidth limit (bytes/sec)
            burstUsage:
              type: number
              format: float
            burstLimit:
              type: integer
        requests:
          type: object
          properties:
            total:
              type: integer
              description: Total requests in current window
            blocked:
              type: integer
              description: Blocked requests in current window
            allowed:
              type: integer
              description: Allowed requests in current window
        tokens:
          type: object
          properties:
            available:
              type: number
              format: float
              description: Available tokens
            capacity:
              type: integer
              description: Maximum token capacity
        latency:
          type: object
          properties:
            p50:
              type: number
              format: float
              description: 50th percentile latency (ms)
            p95:
              type: number
              format: float
              description: 95th percentile latency (ms)
            p99:
              type: number
              format: float
              description: 99th percentile latency (ms)
        cache:
          type: object
          properties:
            hitRate:
              type: number
              format: float
              minimum: 0
              maximum: 1
              description: Cache hit rate (0-1)
            size:
              type: integer
              description: Current cache size (bytes)
            maxSize:
              type: integer
              description: Maximum cache size (bytes)

    ClusterMetrics:
      type: object
      required:
        - clusterId
        - timestamp
      properties:
        clusterId:
          type: string
          format: uuid
        timestamp:
          type: string
          format: date-time
        globalIops:
          type: object
          properties:
            usage:
              type: number
              format: float
            limit:
              type: integer
        globalBandwidth:
          type: object
          properties:
            usage:
              type: number
              format: float
            limit:
              type: integer
        applicationCount:
          type: integer
        activeConnections:
          type: integer
        gatewayStatus:
          type: array
          items:
            type: object
            properties:
              endpoint:
                type: string
                format: uri
              status:
                type: string
                enum: [healthy, degraded, down]
              connections:
                type: integer
              latency:
                type: number
                format: float

    # Alert Schemas
    AlertSeverity:
      type: string
      enum: [info, warning, critical, emergency]
      description: Alert severity level

    AlertRule:
      type: object
      required:
        - name
        - metric
        - condition
        - threshold
        - severity
      properties:
        id:
          type: string
          format: uuid
          readOnly: true
        name:
          type: string
          minLength: 1
          maxLength: 255
          description: Alert rule name
        description:
          type: string
          maxLength: 1000
        metric:
          type: string
          description: Metric to monitor
        condition:
          type: string
          enum: [gt, gte, lt, lte, eq, ne]
          description: Comparison condition
        threshold:
          type: number
          format: float
          description: Alert threshold value
        severity:
          $ref: '#/components/schemas/AlertSeverity'
        duration:
          type: integer
          minimum: 1
          description: Duration threshold must be breached (seconds)
          example: 300
        applicationId:
          type: string
          format: uuid
          description: Scope to specific application
        clusterId:
          type: string
          format: uuid
          description: Scope to specific cluster
        enabled:
          type: boolean
          default: true
        notificationChannels:
          type: array
          description: Notification channels
          items:
            type: object
            properties:
              type:
                type: string
                enum: [email, webhook, slack, pagerduty]
              config:
                type: object
                additionalProperties: true
        cooldown:
          type: integer
          minimum: 0
          default: 900
          description: Cooldown period between alerts (seconds)
        createdAt:
          type: string
          format: date-time
          readOnly: true

    Alert:
      type: object
      required:
        - ruleId
        - severity
        - message
        - timestamp
      properties:
        id:
          type: string
          format: uuid
          readOnly: true
        ruleId:
          type: string
          format: uuid
        severity:
          $ref: '#/components/schemas/AlertSeverity'
        message:
          type: string
          description: Alert message
        details:
          type: object
          additionalProperties: true
        timestamp:
          type: string
          format: date-time
        acknowledged:
          type: boolean
          default: false
        acknowledgedBy:
          type: string
        acknowledgedAt:
          type: string
          format: date-time
        resolvedAt:
          type: string
          format: date-time

    # Configuration Management
    ConfigurationVersion:
      type: object
      required:
        - version
        - timestamp
      properties:
        version:
          type: string
          description: Version identifier
        timestamp:
          type: string
          format: date-time
        description:
          type: string
          description: Version description
        createdBy:
          type: string
        changes:
          type: array
          items:
            type: object
            properties:
              type:
                type: string
                enum: [create, update, delete]
              resource:
                type: string
              resourceId:
                type: string
        status:
          type: string
          enum: [draft, deployed, rolled_back]
        isCurrent:
          type: boolean
          readOnly: true

    Deployment:
      type: object
      required:
        - version
        - targetClusters
      properties:
        id:
          type: string
          format: uuid
          readOnly: true
        version:
          type: string
          description: Configuration version to deploy
        targetClusters:
          type: array
          items:
            type: string
            format: uuid
          description: Cluster IDs to deploy to
        strategy:
          type: string
          enum: [rolling, blue-green, canary]
          default: rolling
          description: Deployment strategy
        rolloutPercent:
          type: integer
          minimum: 1
          maximum: 100
          default: 100
          description: For canary deployment, percentage of traffic
        status:
          type: string
          enum: [pending, in_progress, completed, failed, rolled_back]
          readOnly: true
        createdAt:
          type: string
          format: date-time
          readOnly: true
        startedAt:
          type: string
          format: date-time
          readOnly: true
        completedAt:
          type: string
          format: date-time
          readOnly: true
        createdBy:
          type: string
          readOnly: true

    # User Management
    User:
      type: object
      required:
        - username
        - email
        - roles
      properties:
        id:
          type: string
          format: uuid
          readOnly: true
        username:
          type: string
          minLength: 3
          maxLength: 64
          pattern: '^[a-zA-Z0-9_-]+$'
        email:
          type: string
          format: email
        fullName:
          type: string
          maxLength: 255
        roles:
          type: array
          items:
            type: string
          description: User roles
        permissions:
          type: array
          items:
            type: string
          readOnly: true
          description: Effective permissions (derived from roles)
        enabled:
          type: boolean
          default: true
        lastLogin:
          type: string
          format: date-time
          readOnly: true
        createdAt:
          type: string
          format: date-time
          readOnly: true

    Role:
      type: object
      required:
        - name
        - permissions
      properties:
        id:
          type: string
          format: uuid
          readOnly: true
        name:
          type: string
          minLength: 1
          maxLength: 64
          pattern: '^[a-zA-Z0-9_-]+$'
        description:
          type: string
          maxLength: 1000
        permissions:
          type: array
          items:
            type: string
          description: Permission list (format: resource:action)
          example: ["applications:read", "applications:write", "clusters:read"]
        isSystemRole:
          type: boolean
          readOnly: true
          description: System roles cannot be modified
        createdAt:
          type: string
          format: date-time
          readOnly: true

    # Health Check
    HealthStatus:
      type: string
      enum: [healthy, degraded, unhealthy]
      description: Health status

    HealthCheck:
      type: object
      required:
        - status
        - timestamp
      properties:
        status:
          $ref: '#/components/schemas/HealthStatus'
        timestamp:
          type: string
          format: date-time
        version:
          type: string
        components:
          type: object
          additionalProperties:
            type: object
            properties:
              status:
                $ref: '#/components/schemas/HealthStatus'
              message:
                type: string
              latency:
                type: number
                format: float
        uptime:
          type: integer
          description: Uptime in seconds
```

---

## REST API Endpoints

### 1. Authentication

#### Generate Token
```http
POST /api/v1/auth/token
```

**Description**: Generate JWT token for authentication

**Request Body**:
```json
{
  "username": "admin",
  "password": "securepassword",
  "mfaCode": "123456"
}
```

**Response** (200 OK):
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expiresIn": 3600,
  "user": {
    "id": "user_123",
    "username": "admin",
    "email": "admin@example.com",
    "roles": ["admin"]
  }
}
```

**Error Responses**:
- 401 Unauthorized - Invalid credentials
- 429 Too Many Requests - Rate limit exceeded

**Rate Limit**: 5 requests per minute per IP

---

#### Refresh Token
```http
POST /api/v1/auth/refresh
```

**Request Body**:
```json
{
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Response** (200 OK):
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expiresIn": 3600
}
```

---

#### Logout
```http
POST /api/v1/auth/logout
```

**Description**: Invalidate current token

**Response** (204 No Content)

---

### 2. Cluster Management (L1)

#### List Clusters
```http
GET /api/v1/clusters
```

**Query Parameters**:
- `page` (integer, default: 1) - Page number
- `pageSize` (integer, default: 50, max: 1000) - Items per page
- `sortBy` (string, enum: name,region,createdAt) - Sort field
- `sortOrder` (string, enum: asc,desc, default: desc) - Sort order
- `region` (string) - Filter by region
- `enabled` (boolean) - Filter by enabled status
- `search` (string) - Search in name/description

**Response** (200 OK):
```json
{
  "data": [
    {
      "id": "cluster_001",
      "name": "US-East Production",
      "region": "us-east-1",
      "description": "Primary production cluster",
      "gatewayEndpoints": [
        "https://gateway1.us-east.example.com",
        "https://gateway2.us-east.example.com"
      ],
      "enabled": true,
      "tags": {
        "environment": "production",
        "tier": "primary"
      },
      "createdAt": "2024-01-15T10:00:00Z",
      "updatedAt": "2024-01-20T15:30:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "pageSize": 50,
    "totalPages": 1,
    "totalItems": 1
  }
}
```

**Required Permissions**: `clusters:read`

---

#### Create Cluster
```http
POST /api/v1/clusters
```

**Request Body**:
```json
{
  "name": "US-West Production",
  "region": "us-west-2",
  "description": "West coast production cluster",
  "gatewayEndpoints": [
    "https://gateway1.us-west.example.com"
  ],
  "tags": {
    "environment": "production"
  }
}
```

**Response** (201 Created):
```json
{
  "id": "cluster_002",
  "name": "US-West Production",
  "region": "us-west-2",
  "description": "West coast production cluster",
  "gatewayEndpoints": [
    "https://gateway1.us-west.example.com"
  ],
  "enabled": true,
  "tags": {
    "environment": "production"
  },
  "createdAt": "2024-02-01T10:00:00Z",
  "updatedAt": "2024-02-01T10:00:00Z"
}
```

**Required Permissions**: `clusters:write`

---

#### Get Cluster
```http
GET /api/v1/clusters/{clusterId}
```

**Path Parameters**:
- `clusterId` (string, format: uuid) - Cluster identifier

**Response** (200 OK):
```json
{
  "id": "cluster_001",
  "name": "US-East Production",
  "region": "us-east-1",
  "description": "Primary production cluster",
  "gatewayEndpoints": [
    "https://gateway1.us-east.example.com",
    "https://gateway2.us-east.example.com"
  ],
  "enabled": true,
  "tags": {
    "environment": "production",
    "tier": "primary"
  },
  "createdAt": "2024-01-15T10:00:00Z",
  "updatedAt": "2024-01-20T15:30:00Z"
}
```

**Error Responses**:
- 404 Not Found - Cluster not found

**Required Permissions**: `clusters:read`

---

#### Update Cluster
```http
PATCH /api/v1/clusters/{clusterId}
```

**Request Body**:
```json
{
  "description": "Updated description",
  "gatewayEndpoints": [
    "https://gateway1.us-east.example.com",
    "https://gateway2.us-east.example.com",
    "https://gateway3.us-east.example.com"
  ]
}
```

**Response** (200 OK):
```json
{
  "id": "cluster_001",
  "name": "US-East Production",
  "region": "us-east-1",
  "description": "Updated description",
  "gatewayEndpoints": [
    "https://gateway1.us-east.example.com",
    "https://gateway2.us-east.example.com",
    "https://gateway3.us-east.example.com"
  ],
  "enabled": true,
  "tags": {
    "environment": "production",
    "tier": "primary"
  },
  "createdAt": "2024-01-15T10:00:00Z",
  "updatedAt": "2024-02-01T12:00:00Z"
}
```

**Required Permissions**: `clusters:write`

---

#### Delete Cluster
```http
DELETE /api/v1/clusters/{clusterId}
```

**Response** (204 No Content)

**Error Responses**:
- 409 Conflict - Cluster has applications

**Required Permissions**: `clusters:delete`

---

#### Get Cluster Configuration
```http
GET /api/v1/clusters/{clusterId}/configuration
```

**Response** (200 OK):
```json
{
  "clusterId": "cluster_001",
  "globalIops": {
    "limit": 1000000,
    "burst": 1500000
  },
  "globalBandwidth": {
    "limit": 107374182400,
    "burst": 214748364800
  },
  "defaultQuota": {
    "iops": {
      "limit": 10000,
      "burst": 15000
    },
    "bandwidth": {
      "limit": 1073741824,
      "burst": 2147483648
    }
  },
  "rateLimiting": {
    "algorithm": "token-bucket",
    "refillRate": 1000,
    "capacity": 10000
  },
  "sharding": {
    "enabled": true,
    "shardCount": 16,
    "replicationFactor": 2,
    "cacheSize": 10485760
  }
}
```

**Required Permissions**: `clusters:read`

---

#### Update Cluster Configuration
```http
PUT /api/v1/clusters/{clusterId}/configuration
```

**Request Body**:
```json
{
  "globalIops": {
    "limit": 2000000,
    "burst": 3000000
  },
  "globalBandwidth": {
    "limit": 214748364800,
    "burst": 429496729600
  },
  "rateLimiting": {
    "algorithm": "token-bucket",
    "refillRate": 2000,
    "capacity": 20000
  }
}
```

**Response** (200 OK):
```json
{
  "clusterId": "cluster_001",
  "globalIops": {
    "limit": 2000000,
    "burst": 3000000
  },
  "globalBandwidth": {
    "limit": 214748364800,
    "burst": 429496729600
  },
  "rateLimiting": {
    "algorithm": "token-bucket",
    "refillRate": 2000,
    "capacity": 20000
  }
}
```

**Required Permissions**: `clusters:write`

---

#### Get Cluster Metrics
```http
GET /api/v1/clusters/{clusterId}/metrics
```

**Query Parameters**:
- `timeRange` (string, format: ISO 8601 duration, default: PT1H) - Time range
- `granularity` (string, enum: 1m,5m,15m,1h,1d, default: 5m) - Aggregation granularity

**Response** (200 OK):
```json
{
  "clusterId": "cluster_001",
  "timestamp": "2024-02-01T12:00:00Z",
  "globalIops": {
    "usage": 850000,
    "limit": 2000000
  },
  "globalBandwidth": {
    "usage": 85899345920,
    "limit": 214748364800
  },
  "applicationCount": 150,
  "activeConnections": 5000,
  "gatewayStatus": [
    {
      "endpoint": "https://gateway1.us-east.example.com",
      "status": "healthy",
      "connections": 2500,
      "latency": 15.5
    },
    {
      "endpoint": "https://gateway2.us-east.example.com",
      "status": "healthy",
      "connections": 2500,
      "latency": 16.2
    }
  ]
}
```

**Required Permissions**: `clusters:read`, `monitoring:read`

---

### 3. Application Management (L2)

#### List Applications
```http
GET /api/v1/applications
```

**Query Parameters**:
- `page` (integer, default: 1)
- `pageSize` (integer, default: 50, max: 1000)
- `sortBy` (string, enum: name,priority,createdAt, usage)
- `sortOrder` (string, enum: asc,desc)
- `clusterId` (string, format: uuid) - Filter by cluster
- `enabled` (boolean) - Filter by enabled status
- `priority` (integer, min: 1, max: 10) - Filter by priority
- `search` (string) - Search in name/appId/description
- `tags` (string) - Filter by tags (format: key:value)

**Response** (200 OK):
```json
{
  "data": [
    {
      "id": "app_001",
      "name": "Storage Service A",
      "appId": "storage-service-a",
      "description": "Primary storage service",
      "clusterId": "cluster_001",
      "enabled": true,
      "priority": 8,
      "tags": {
        "team": "platform",
        "critical": "true"
      },
      "createdAt": "2024-01-15T10:00:00Z",
      "updatedAt": "2024-01-20T15:30:00Z",
      "createdBy": "admin",
      "updatedBy": "admin"
    }
  ],
  "pagination": {
    "page": 1,
    "pageSize": 50,
    "totalPages": 3,
    "totalItems": 150
  }
}
```

**Required Permissions**: `applications:read`

---

#### Create Application
```http
POST /api/v1/applications
```

**Request Body**:
```json
{
  "name": "Storage Service B",
  "appId": "storage-service-b",
  "description": "Secondary storage service",
  "clusterId": "cluster_001",
  "priority": 7,
  "tags": {
    "team": "platform"
  }
}
```

**Response** (201 Created):
```json
{
  "id": "app_002",
  "name": "Storage Service B",
  "appId": "storage-service-b",
  "description": "Secondary storage service",
  "clusterId": "cluster_001",
  "enabled": true,
  "priority": 7,
  "tags": {
    "team": "platform"
  },
  "createdAt": "2024-02-01T10:00:00Z",
  "updatedAt": "2024-02-01T10:00:00Z",
  "createdBy": "admin",
  "updatedBy": "admin"
}
```

**Error Responses**:
- 409 Conflict - appId already exists

**Required Permissions**: `applications:write`

---

#### Get Application
```http
GET /api/v1/applications/{applicationId}
```

**Response** (200 OK):
```json
{
  "id": "app_001",
  "name": "Storage Service A",
  "appId": "storage-service-a",
  "description": "Primary storage service",
  "clusterId": "cluster_001",
  "enabled": true,
  "priority": 8,
  "tags": {
    "team": "platform",
    "critical": "true"
  },
  "createdAt": "2024-01-15T10:00:00Z",
  "updatedAt": "2024-01-20T15:30:00Z",
  "createdBy": "admin",
  "updatedBy": "admin"
}
```

**Required Permissions**: `applications:read`

---

#### Update Application
```http
PATCH /api/v1/applications/{applicationId}
```

**Request Body**:
```json
{
  "name": "Storage Service A (Updated)",
  "priority": 9,
  "enabled": true
}
```

**Response** (200 OK):
```json
{
  "id": "app_001",
  "name": "Storage Service A (Updated)",
  "appId": "storage-service-a",
  "description": "Primary storage service",
  "clusterId": "cluster_001",
  "enabled": true,
  "priority": 9,
  "tags": {
    "team": "platform",
    "critical": "true"
  },
  "createdAt": "2024-01-15T10:00:00Z",
  "updatedAt": "2024-02-01T12:00:00Z",
  "createdBy": "admin",
  "updatedBy": "admin"
}
```

**Required Permissions**: `applications:write`

---

#### Delete Application
```http
DELETE /api/v1/applications/{applicationId}
```

**Response** (204 No Content)

**Required Permissions**: `applications:delete`

---

#### Get Application Quota
```http
GET /api/v1/applications/{applicationId}/quota
```

**Response** (200 OK):
```json
{
  "applicationId": "app_001",
  "iops": {
    "limit": 10000,
    "burst": 15000
  },
  "bandwidth": {
    "limit": 1073741824,
    "burst": 2147483648
  },
  "storageSize": {
    "limit": 1099511627776
  },
  "requestRate": {
    "limit": 1000,
    "burst": 1500
  },
  "connections": {
    "limit": 100
  }
}
```

**Required Permissions**: `applications:read`

---

#### Update Application Quota
```http
PUT /api/v1/applications/{applicationId}/quota
```

**Request Body**:
```json
{
  "iops": {
    "limit": 20000,
    "burst": 30000
  },
  "bandwidth": {
    "limit": 2147483648,
    "burst": 4294967296
  }
}
```

**Response** (200 OK):
```json
{
  "applicationId": "app_001",
  "iops": {
    "limit": 20000,
    "burst": 30000
  },
  "bandwidth": {
    "limit": 2147483648,
    "burst": 4294967296
  },
  "storageSize": {
    "limit": 1099511627776
  },
  "requestRate": {
    "limit": 1000,
    "burst": 1500
  },
  "connections": {
    "limit": 100
  }
}
```

**Required Permissions**: `applications:write`

---

#### Get Application Metrics
```http
GET /api/v1/applications/{applicationId}/metrics
```

**Query Parameters**:
- `timeRange` (string, default: PT1H)
- `includeHistorical` (boolean, default: false)
- `granularity` (string, enum: 1m,5m,15m,1h,1d)

**Response** (200 OK):
```json
{
  "applicationId": "app_001",
  "clusterId": "cluster_001",
  "timestamp": "2024-02-01T12:00:00Z",
  "iops": {
    "usage": 8500.5,
    "limit": 20000,
    "burstUsage": 0,
    "burstLimit": 30000
  },
  "bandwidth": {
    "usage": 1073741824,
    "limit": 2147483648,
    "burstUsage": 0,
    "burstLimit": 4294967296
  },
  "requests": {
    "total": 50000,
    "blocked": 125,
    "allowed": 49875
  },
  "tokens": {
    "available": 15000,
    "capacity": 20000
  },
  "latency": {
    "p50": 15.5,
    "p95": 45.2,
    "p99": 89.7
  },
  "cache": {
    "hitRate": 0.85,
    "size": 5242880,
    "maxSize": 10485760
  }
}
```

**Required Permissions**: `applications:read`, `monitoring:read`

---

#### Reset Application Tokens
```http
POST /api/v1/applications/{applicationId}/tokens/reset
```

**Description**: Manually reset token bucket to full capacity (emergency use)

**Request Body**:
```json
{
  "reason": "Emergency reset after incident",
  "bypassLimit": false
}
```

**Response** (200 OK):
```json
{
  "applicationId": "app_001",
  "tokens": 20000,
  "capacity": 20000,
  "resetAt": "2024-02-01T12:00:00Z",
  "resetBy": "admin"
}
```

**Required Permissions**: `applications:admin`

---

### 4. Token Bucket Configuration

#### List Token Buckets
```http
GET /api/v1/token-buckets
```

**Query Parameters**:
- `level` (string, enum: L1, L2, L3) - Filter by level
- `applicationId` (string, format: uuid) - Filter by application (L2/L3)
- `clusterId` (string, format: uuid) - Filter by cluster (L1/L2)
- `page` (integer)
- `pageSize` (integer)

**Response** (200 OK):
```json
{
  "data": [
    {
      "bucketId": "L2:app_001",
      "level": "L2",
      "tokens": 15000,
      "capacity": 20000,
      "refillRate": 1000,
      "lastRefill": "2024-02-01T12:00:00Z",
      "lastConsume": "2024-02-01T12:00:05Z",
      "isBlocked": false,
      "blockDuration": 0
    }
  ],
  "pagination": {
    "page": 1,
    "pageSize": 50,
    "totalPages": 1,
    "totalItems": 1
  }
}
```

**Required Permissions**: `tokenbuckets:read`

---

#### Get Token Bucket State
```http
GET /api/v1/token-buckets/{bucketId}
```

**Response** (200 OK):
```json
{
  "bucketId": "L2:app_001",
  "level": "L2",
  "tokens": 15000,
  "capacity": 20000,
  "refillRate": 1000,
  "lastRefill": "2024-02-01T12:00:00Z",
  "lastConsume": "2024-02-01T12:00:05Z",
  "isBlocked": false,
  "blockDuration": 0
}
```

**Required Permissions**: `tokenbuckets:read`

---

#### Update Token Bucket Configuration
```http
PATCH /api/v1/token-buckets/{bucketId}/configuration
```

**Request Body**:
```json
{
  "refillRate": 2000,
  "capacity": 30000
}
```

**Response** (200 OK):
```json
{
  "bucketId": "L2:app_001",
  "refillRate": 2000,
  "capacity": 30000,
  "updatedAt": "2024-02-01T12:00:00Z"
}
```

**Required Permissions**: `tokenbuckets:write`

---

#### Flush L3 Cache
```http
POST /api/v1/token-buckets/l3/cache/flush
```

**Description**: Flush L3 local cache across all gateways

**Request Body**:
```json
{
  "clusterId": "cluster_001",
  "gatewayIds": ["gateway_001", "gateway_002"]
}
```

**Response** (200 OK):
```json
{
  "status": "success",
  "flushedAt": "2024-02-01T12:00:00Z",
  "gatewayResults": [
    {
      "gatewayId": "gateway_001",
      "status": "success"
    },
    {
      "gatewayId": "gateway_002",
      "status": "success"
    }
  ]
}
```

**Required Permissions**: `tokenbuckets:admin`

---

### 5. Cost Rules

#### List Cost Rules
```http
GET /api/v1/cost-rules
```

**Query Parameters**:
- `operationType` (string, enum: GET,PUT,DELETE,LIST,HEAD,POST,PATCH)
- `enabled` (boolean)
- `sortBy` (string, enum: operationType,priority)
- `sortOrder` (string, enum: asc,desc)

**Response** (200 OK):
```json
{
  "data": [
    {
      "id": "rule_001",
      "operationType": "GET",
      "baseCost": 1.0,
      "bandwidthCostFactor": 0.0001,
      "unitQuantum": 4096,
      "description": "Standard GET operation",
      "enabled": true,
      "priority": 50
    },
    {
      "id": "rule_002",
      "operationType": "PUT",
      "baseCost": 2.0,
      "bandwidthCostFactor": 0.0002,
      "unitQuantum": 4096,
      "description": "Standard PUT operation",
      "enabled": true,
      "priority": 50
    },
    {
      "id": "rule_003",
      "operationType": "DELETE",
      "baseCost": 3.0,
      "bandwidthCostFactor": 0.0001,
      "unitQuantum": 4096,
      "description": "Standard DELETE operation",
      "enabled": true,
      "priority": 50
    },
    {
      "id": "rule_004",
      "operationType": "LIST",
      "baseCost": 5.0,
      "bandwidthCostFactor": 0.00005,
      "unitQuantum": 4096,
      "description": "LIST operation (more expensive)",
      "enabled": true,
      "priority": 50
    }
  ]
}
```

**Required Permissions**: "costrules:read`

---

#### Create Cost Rule
```http
POST /api/v1/cost-rules
```

**Request Body**:
```json
{
  "operationType": "POST",
  "baseCost": 2.5,
  "bandwidthCostFactor": 0.00015,
  "unitQuantum": 4096,
  "description": "Standard POST operation",
  "enabled": true,
  "priority": 50
}
```

**Response** (201 Created):
```json
{
  "id": "rule_005",
  "operationType": "POST",
  "baseCost": 2.5,
  "bandwidthCostFactor": 0.00015,
  "unitQuantum": 4096,
  "description": "Standard POST operation",
  "enabled": true,
  "priority": 50
}
```

**Error Responses**:
- 409 Conflict - Rule for operation type already exists

**Required Permissions**: `costrules:write`

---

#### Get Cost Rule
```http
GET /api/v1/cost-rules/{ruleId}
```

**Response** (200 OK):
```json
{
  "id": "rule_001",
  "operationType": "GET",
  "baseCost": 1.0,
  "bandwidthCostFactor": 0.0001,
  "unitQuantum": 4096,
  "description": "Standard GET operation",
  "enabled": true,
  "priority": 50
}
```

**Required Permissions**: `costrules:read`

---

#### Update Cost Rule
```http
PATCH /api/v1/cost-rules/{ruleId}
```

**Request Body**:
```json
{
  "baseCost": 1.5,
  "bandwidthCostFactor": 0.00012,
  "enabled": true
}
```

**Response** (200 OK):
```json
{
  "id": "rule_001",
  "operationType": "GET",
  "baseCost": 1.5,
  "bandwidthCostFactor": 0.00012,
  "unitQuantum": 4096,
  "description": "Standard GET operation",
  "enabled": true,
  "priority": 50
}
```

**Required Permissions**: `costrules:write`

---

#### Delete Cost Rule
```http
DELETE /api/v1/cost-rules/{ruleId}
```

**Response** (204 No Content)

**Required Permissions**: `costrules:delete`

---

#### Calculate Cost
```http
POST /api/v1/cost-rules/calculate
```

**Description**: Calculate operation cost for testing/estimation

**Request Body**:
```json
{
  "operationType": "PUT",
  "bodySize": 1048576,
  "applicationId": "app_001"
}
```

**Response** (200 OK):
```json
{
  "operationType": "PUT",
  "baseCost": 2.0,
  "bandwidthCostFactor": 0.0002,
  "bodySize": 1048576,
  "unitQuantum": 4096,
  "bandwidthCost": 51.2,
  "totalCost": 53.2,
  "applicationId": "app_001"
}
```

**Required Permissions**: `costrules:read`

---

### 6. Monitoring & Metrics

#### Query Metrics
```http
POST /api/v1/metrics/query
```

**Request Body**:
```json
{
  "metric": "iops.usage",
  "applicationId": "app_001",
  "timeRange": {
    "start": "2024-02-01T11:00:00Z",
    "end": "2024-02-01T12:00:00Z"
  },
  "aggregation": "avg",
  "granularity": "5m",
  "groupBy": ["clusterId"]
}
```

**Response** (200 OK):
```json
{
  "metric": "iops.usage",
  "data": [
    {
      "timestamp": "2024-02-01T11:00:00Z",
      "value": 8200.5,
      "labels": {
        "clusterId": "cluster_001",
        "applicationId": "app_001"
      }
    },
    {
      "timestamp": "2024-02-01T11:05:00Z",
      "value": 8500.2,
      "labels": {
        "clusterId": "cluster_001",
        "applicationId": "app_001"
      }
    }
  ],
  "aggregation": "avg",
  "granularity": "5m"
}
```

**Required Permissions**: `monitoring:read`

---

#### Get Real-time Metrics
```http
GET /api/v1/metrics/realtime
```

**Query Parameters**:
- `applicationId` (string, format: uuid) - Optional filter
- `clusterId` (string, format: uuid) - Optional filter
- `metrics` (string, comma-separated) - Metrics to retrieve (default: all)

**Response** (200 OK):
```json
{
  "timestamp": "2024-02-01T12:00:00Z",
  "applications": [
    {
      "applicationId": "app_001",
      "iops": {
        "usage": 8500.5,
        "limit": 20000
      },
      "bandwidth": {
        "usage": 1073741824,
        "limit": 2147483648
      },
      "tokens": {
        "available": 15000,
        "capacity": 20000
      }
    }
  ],
  "clusters": [
    {
      "clusterId": "cluster_001",
      "globalIops": {
        "usage": 850000,
        "limit": 2000000
      },
      "globalBandwidth": {
        "usage": 85899345920,
        "limit": 214748364800
      }
    }
  ]
}
```

**Required Permissions**: `monitoring:read`

---

#### Get Historical Metrics
```http
GET /api/v1/metrics/historical
```

**Query Parameters**:
- `metric` (string, required) - Metric name
- `applicationId` (string, format: uuid)
- `clusterId` (string, format: uuid)
- `start` (string, format: date-time, required)
- `end` (string, format: date-time, required)
- `aggregation` (string, enum: avg,sum,min,max,rate)
- `granularity` (string, enum: 1m,5m,15m,1h,1d)

**Response** (200 OK):
```json
{
  "metric": "iops.usage",
  "applicationId": "app_001",
  "timeRange": {
    "start": "2024-02-01T00:00:00Z",
    "end": "2024-02-01T12:00:00Z"
  },
  "aggregation": "avg",
  "granularity": "1h",
  "data": [
    {
      "timestamp": "2024-02-01T00:00:00Z",
      "value": 8100.5
    },
    {
      "timestamp": "2024-02-01T01:00:00Z",
      "value": 8300.2
    }
  ]
}
```

**Required Permissions**: `monitoring:read`

---

#### Get Top Consumers
```http
GET /api/v1/metrics/top-consumers
```

**Query Parameters**:
- `metric` (string, enum: iops,bandwidth,requests, default: iops)
- `clusterId` (string, format: uuid)
- `limit` (integer, min: 1, max: 100, default: 10)
- `timeRange` (string, format: ISO 8601 duration, default: PT1H)

**Response** (200 OK):
```json
{
  "metric": "iops",
  "timeRange": "PT1H",
  "topConsumers": [
    {
      "applicationId": "app_001",
      "applicationName": "Storage Service A",
      "value": 18500.5,
      "percentage": 18.5
    },
    {
      "applicationId": "app_002",
      "applicationName": "Storage Service B",
      "value": 15200.3,
      "percentage": 15.2
    }
  ]
}
```

**Required Permissions**: `monitoring:read`

---

#### Export Metrics
```http
POST /api/v1/metrics/export
```

**Description**: Export metrics in various formats (CSV, JSON, Prometheus)

**Request Body**:
```json
{
  "queries": [
    {
      "metric": "iops.usage",
      "applicationId": "app_001",
      "timeRange": {
        "start": "2024-02-01T00:00:00Z",
        "end": "2024-02-01T23:59:59Z"
      },
      "granularity": "1h"
    }
  ],
  "format": "csv",
  "includeHeaders": true
}
```

**Response** (200 OK):
```
timestamp,applicationId,clusterId,value
2024-02-01T00:00:00Z,app_001,cluster_001,8100.5
2024-02-01T01:00:00Z,app_001,cluster_001,8300.2
```

**Content-Type**: `text/csv` or `application/json` or `text/plain`

**Required Permissions**: `monitoring:read`, `monitoring:export`

---

### 7. Configuration Management

#### List Configuration Versions
```http
GET /api/v1/configurations/versions
```

**Query Parameters**:
- `page` (integer)
- `pageSize` (integer)
- `clusterId` (string, format: uuid)

**Response** (200 OK):
```json
{
  "data": [
    {
      "version": "v1.2.3",
      "timestamp": "2024-02-01T12:00:00Z",
      "description": "Updated cluster limits",
      "createdBy": "admin",
      "status": "deployed",
      "isCurrent": true,
      "changes": [
        {
          "type": "update",
          "resource": "cluster",
          "resourceId": "cluster_001"
        }
      ]
    },
    {
      "version": "v1.2.2",
      "timestamp": "2024-01-30T10:00:00Z",
      "description": "Added new application",
      "createdBy": "operator",
      "status": "rolled_back",
      "isCurrent": false
    }
  ],
  "pagination": {
    "page": 1,
    "pageSize": 50,
    "totalPages": 2,
    "totalItems": 75
  }
}
```

**Required Permissions**: `configurations:read`

---

#### Get Configuration Version
```http
GET /api/v1/configurations/versions/{version}
```

**Response** (200 OK):
```json
{
  "version": "v1.2.3",
  "timestamp": "2024-02-01T12:00:00Z",
  "description": "Updated cluster limits",
  "createdBy": "admin",
  "status": "deployed",
  "isCurrent": true,
  "changes": [
    {
      "type": "update",
      "resource": "cluster",
      "resourceId": "cluster_001",
      "details": {
        "before": {
          "globalIops": {
            "limit": 1000000
          }
        },
        "after": {
          "globalIops": {
            "limit": 2000000
          }
        }
      }
    }
  ],
  "configuration": {
    "clusters": [
      {
        "id": "cluster_001",
        "configuration": {
          "globalIops": {
            "limit": 2000000,
            "burst": 3000000
          }
        }
      }
    ],
    "applications": [
      {
        "id": "app_001",
        "quota": {
          "iops": {
            "limit": 20000
          }
        }
      }
    ]
  }
}
```

**Required Permissions**: `configurations:read`

---

#### Create Configuration Draft
```http
POST /api/v1/configurations/drafts
```

**Request Body**:
```json
{
  "description": "Increase quotas for peak season",
  "changes": [
    {
      "type": "update",
      "resource": "application",
      "resourceId": "app_001",
      "configuration": {
        "iops": {
          "limit": 30000,
          "burst": 45000
        }
      }
    }
  ]
}
```

**Response** (201 Created):
```json
{
  "version": "v1.2.4-draft",
  "timestamp": "2024-02-01T13:00:00Z",
  "description": "Increase quotas for peak season",
  "createdBy": "admin",
  "status": "draft",
  "isCurrent": false,
  "changes": [
    {
      "type": "update",
      "resource": "application",
      "resourceId": "app_001"
    }
  ]
}
```

**Required Permissions**: `configurations:write`

---

#### Deploy Configuration
```http
POST /api/v1/configurations/deployments
```

**Request Body**:
```json
{
  "version": "v1.2.4",
  "targetClusters": ["cluster_001", "cluster_002"],
  "strategy": "rolling",
  "rolloutPercent": 100
}
```

**Response** (202 Accepted):
```json
{
  "id": "deploy_001",
  "version": "v1.2.4",
  "targetClusters": ["cluster_001", "cluster_002"],
  "strategy": "rolling",
  "rolloutPercent": 100,
  "status": "pending",
  "createdAt": "2024-02-01T14:00:00Z",
  "createdBy": "admin"
}
```

**Required Permissions**: `configurations:deploy`

---

#### Get Deployment Status
```http
GET /api/v1/configurations/deployments/{deploymentId}
```

**Response** (200 OK):
```json
{
  "id": "deploy_001",
  "version": "v1.2.4",
  "targetClusters": ["cluster_001", "cluster_002"],
  "strategy": "rolling",
  "rolloutPercent": 100,
  "status": "in_progress",
  "createdAt": "2024-02-01T14:00:00Z",
  "startedAt": "2024-02-01T14:01:00Z",
  "createdBy": "admin",
  "progress": {
    "total": 2,
    "completed": 1,
    "failed": 0,
    "clusters": [
      {
        "clusterId": "cluster_001",
        "status": "completed",
        "completedAt": "2024-02-01T14:05:00Z"
      },
      {
        "clusterId": "cluster_002",
        "status": "in_progress",
        "startedAt": "2024-02-01T14:05:00Z"
      }
    ]
  }
}
```

**Required Permissions**: `configurations:read`

---

#### Rollback Configuration
```http
POST /api/v1/configurations/rollback
```

**Request Body**:
```json
{
  "version": "v1.2.3",
  "targetClusters": ["cluster_001", "cluster_002"],
  "reason": "Performance degradation detected"
}
```

**Response** (202 Accepted):
```json
{
  "id": "deploy_002",
  "version": "v1.2.3",
  "targetClusters": ["cluster_001", "cluster_002"],
  "strategy": "rolling",
  "status": "pending",
  "rollbackReason": "Performance degradation detected",
  "createdAt": "2024-02-01T15:00:00Z",
  "createdBy": "admin"
}
```

**Required Permissions**: `configurations:rollback`

---

### 8. Alert Management

#### List Alert Rules
```http
GET /api/v1/alerts/rules
```

**Query Parameters**:
- `enabled` (boolean)
- `severity` (string, enum: info,warning,critical,emergency)
- `applicationId` (string, format: uuid)
- `clusterId` (string, format: uuid)

**Response** (200 OK):
```json
{
  "data": [
    {
      "id": "rule_001",
      "name": "High IOPS Usage Alert",
      "description": "Alert when IOPS usage exceeds 90%",
      "metric": "iops.usage",
      "condition": "gte",
      "threshold": 18000,
      "severity": "warning",
      "duration": 300,
      "enabled": true,
      "notificationChannels": [
        {
          "type": "slack",
          "config": {
            "webhook": "https://hooks.slack.com/services/..."
          }
        }
      ],
      "cooldown": 900,
      "createdAt": "2024-01-15T10:00:00Z"
    }
  ]
}
```

**Required Permissions**: `alerts:read`

---

#### Create Alert Rule
```http
POST /api/v1/alerts/rules
```

**Request Body**:
```json
{
  "name": "Bandwidth Critical Alert",
  "description": "Alert when bandwidth exceeds 95% of limit",
  "metric": "bandwidth.usage",
  "condition": "gte",
  "threshold": 0.95,
  "severity": "critical",
  "duration": 60,
  "applicationId": "app_001",
  "enabled": true,
  "notificationChannels": [
    {
      "type": "pagerduty",
      "config": {
        "integrationKey": "...",
        "severity": "critical"
      }
    }
  ],
  "cooldown": 1800
}
```

**Response** (201 Created):
```json
{
  "id": "rule_002",
  "name": "Bandwidth Critical Alert",
  "description": "Alert when bandwidth exceeds 95% of limit",
  "metric": "bandwidth.usage",
  "condition": "gte",
  "threshold": 0.95,
  "severity": "critical",
  "duration": 60,
  "applicationId": "app_001",
  "enabled": true,
  "notificationChannels": [
    {
      "type": "pagerduty",
      "config": {
        "integrationKey": "...",
        "severity": "critical"
      }
    }
  ],
  "cooldown": 1800,
  "createdAt": "2024-02-01T10:00:00Z"
}
```

**Required Permissions**: `alerts:write`

---

#### Get Alert Rule
```http
GET /api/v1/alerts/rules/{ruleId}
```

**Response** (200 OK):
```json
{
  "id": "rule_001",
  "name": "High IOPS Usage Alert",
  "description": "Alert when IOPS usage exceeds 90%",
  "metric": "iops.usage",
  "condition": "gte",
  "threshold": 18000,
  "severity": "warning",
  "duration": 300,
  "enabled": true,
  "notificationChannels": [
    {
      "type": "slack",
      "config": {
        "webhook": "https://hooks.slack.com/services/..."
      }
    }
  ],
  "cooldown": 900,
  "createdAt": "2024-01-15T10:00:00Z"
}
```

**Required Permissions**: `alerts:read`

---

#### Update Alert Rule
```http
PATCH /api/v1/alerts/rules/{ruleId}
```

**Request Body**:
```json
{
  "threshold": 19000,
  "enabled": true
}
```

**Response** (200 OK):
```json
{
  "id": "rule_001",
  "name": "High IOPS Usage Alert",
  "description": "Alert when IOPS usage exceeds 90%",
  "metric": "iops.usage",
  "condition": "gte",
  "threshold": 19000,
  "severity": "warning",
  "duration": 300,
  "enabled": true,
  "notificationChannels": [
    {
      "type": "slack",
      "config": {
        "webhook": "https://hooks.slack.com/services/..."
      }
    }
  ],
  "cooldown": 900,
  "createdAt": "2024-01-15T10:00:00Z"
}
```

**Required Permissions**: `alerts:write`

---

#### Delete Alert Rule
```http
DELETE /api/v1/alerts/rules/{ruleId}
```

**Response** (204 No Content)

**Required Permissions**: `alerts:delete`

---

#### List Active Alerts
```http
GET /api/v1/alerts
```

**Query Parameters**:
- `severity` (string, enum: info,warning,critical,emergency)
- `acknowledged` (boolean)
- `applicationId` (string, format: uuid)
- `clusterId` (string, format: uuid)
- `startTime` (string, format: date-time)
- `endTime` (string, format: date-time)
- `page` (integer)
- `pageSize` (integer)

**Response** (200 OK):
```json
{
  "data": [
    {
      "id": "alert_001",
      "ruleId": "rule_001",
      "severity": "warning",
      "message": "IOPS usage exceeded 90% threshold for application app_001",
      "details": {
        "applicationId": "app_001",
        "currentValue": 18500,
        "threshold": 18000,
        "percentage": 92.5
      },
      "timestamp": "2024-02-01T12:00:00Z",
      "acknowledged": false,
      "acknowledgedBy": null,
      "acknowledgedAt": null,
      "resolvedAt": null
    }
  ],
  "pagination": {
    "page": 1,
    "pageSize": 50,
    "totalPages": 1,
    "totalItems": 5
  }
}
```

**Required Permissions**: `alerts:read`

---

#### Acknowledge Alert
```http
POST /api/v1/alerts/{alertId}/acknowledge
```

**Request Body**:
```json
{
  "note": "Investigating the issue"
}
```

**Response** (200 OK):
```json
{
  "id": "alert_001",
  "ruleId": "rule_001",
  "severity": "warning",
  "message": "IOPS usage exceeded 90% threshold for application app_001",
  "timestamp": "2024-02-01T12:00:00Z",
  "acknowledged": true,
  "acknowledgedBy": "admin",
  "acknowledgedAt": "2024-02-01T12:05:00Z",
  "resolvedAt": null
}
```

**Required Permissions**: `alerts:write`

---

#### Resolve Alert
```http
POST /api/v1/alerts/{alertId}/resolve
```

**Response** (200 OK):
```json
{
  "id": "alert_001",
  "ruleId": "rule_001",
  "severity": "warning",
  "message": "IOPS usage exceeded 90% threshold for application app_001",
  "timestamp": "2024-02-01T12:00:00Z",
  "acknowledged": true,
  "acknowledgedBy": "admin",
  "acknowledgedAt": "2024-02-01T12:05:00Z",
  "resolvedAt": "2024-02-01T12:30:00Z"
}
```

**Required Permissions**: `alerts:write`

---

### 9. User Management

#### List Users
```http
GET /api/v1/users
```

**Query Parameters**:
- `enabled` (boolean)
- `role` (string)
- `search` (string)
- `page` (integer)
- `pageSize` (integer)

**Response** (200 OK):
```json
{
  "data": [
    {
      "id": "user_001",
      "username": "admin",
      "email": "admin@example.com",
      "fullName": "System Administrator",
      "roles": ["Super Admin"],
      "permissions": [
        "*:*"
      ],
      "enabled": true,
      "lastLogin": "2024-02-01T10:00:00Z",
      "createdAt": "2024-01-01T00:00:00Z"
    },
    {
      "id": "user_002",
      "username": "operator",
      "email": "operator@example.com",
      "fullName": "System Operator",
      "roles": ["Operator"],
      "permissions": [
        "applications:read",
        "applications:write",
        "monitoring:read"
      ],
      "enabled": true,
      "lastLogin": "2024-02-01T09:30:00Z",
      "createdAt": "2024-01-05T00:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "pageSize": 50,
    "totalPages": 1,
    "totalItems": 10
  }
}
```

**Required Permissions**: `users:read`

---

#### Create User
```http
POST /api/v1/users
```

**Request Body**:
```json
{
  "username": "newuser",
  "email": "newuser@example.com",
  "fullName": "New User",
  "password": "SecurePassword123!",
  "roles": ["Viewer"]
}
```

**Response** (201 Created):
```json
{
  "id": "user_003",
  "username": "newuser",
  "email": "newuser@example.com",
  "fullName": "New User",
  "roles": ["Viewer"],
  "permissions": [
    "applications:read",
    "monitoring:read"
  ],
  "enabled": true,
  "lastLogin": null,
  "createdAt": "2024-02-01T10:00:00Z"
}
```

**Required Permissions**: `users:write`

---

#### Get User
```http
GET /api/v1/users/{userId}
```

**Response** (200 OK):
```json
{
  "id": "user_001",
  "username": "admin",
  "email": "admin@example.com",
  "fullName": "System Administrator",
  "roles": ["Super Admin"],
  "permissions": ["*:*"],
  "enabled": true,
  "lastLogin": "2024-02-01T10:00:00Z",
  "createdAt": "2024-01-01T00:00:00Z"
}
```

**Required Permissions**: `users:read`

---

#### Update User
```http
PATCH /api/v1/users/{userId}
```

**Request Body**:
```json
{
  "email": "updated@example.com",
  "roles": ["Operator"]
}
```

**Response** (200 OK):
```json
{
  "id": "user_002",
  "username": "operator",
  "email": "updated@example.com",
  "fullName": "System Operator",
  "roles": ["Operator"],
  "permissions": [
    "applications:read",
    "applications:write",
    "monitoring:read"
  ],
  "enabled": true,
  "lastLogin": "2024-02-01T09:30:00Z",
  "createdAt": "2024-01-05T00:00:00Z"
}
```

**Required Permissions**: `users:write`

---

#### Delete User
```http
DELETE /api/v1/users/{userId}
```

**Response** (204 No Content)

**Error Responses**:
- 403 Forbidden - Cannot delete last admin user

**Required Permissions**: `users:delete`

---

#### List Roles
```http
GET /api/v1/roles
```

**Response** (200 OK):
```json
{
  "data": [
    {
      "id": "role_001",
      "name": "Super Admin",
      "description": "Full system access",
      "permissions": ["*:*"],
      "isSystemRole": true,
      "createdAt": "2024-01-01T00:00:00Z"
    },
    {
      "id": "role_002",
      "name": "Cluster Admin",
      "description": "Cluster and application management",
      "permissions": [
        "clusters:*",
        "applications:*",
        "monitoring:*"
      ],
      "isSystemRole": true,
      "createdAt": "2024-01-01T00:00:00Z"
    },
    {
      "id": "role_003",
      "name": "Operator",
      "description": "Application operations and monitoring",
      "permissions": [
        "applications:read",
        "applications:write",
        "monitoring:read"
      ],
      "isSystemRole": true,
      "createdAt": "2024-01-01T00:00:00Z"
    },
    {
      "id": "role_004",
      "name": "Viewer",
      "description": "Read-only access",
      "permissions": [
        "applications:read",
        "monitoring:read"
      ],
      "isSystemRole": true,
      "createdAt": "2024-01-01T00:00:00Z"
    }
  ]
}
```

**Required Permissions**: `users:read`

---

#### Create Role
```http
POST /api/v1/roles
```

**Request Body**:
```json
{
  "name": "Custom Operator",
  "description": "Custom operator role with limited permissions",
  "permissions": [
    "applications:read",
    "monitoring:read"
  ]
}
```

**Response** (201 Created):
```json
{
  "id": "role_005",
  "name": "Custom Operator",
  "description": "Custom operator role with limited permissions",
  "permissions": [
    "applications:read",
    "monitoring:read"
  ],
  "isSystemRole": false,
  "createdAt": "2024-02-01T10:00:00Z"
}
```

**Required Permissions**: `users:write`

---

### 10. Health Check

#### System Health
```http
GET /api/v1/health
```

**Response** (200 OK):
```json
{
  "status": "healthy",
  "timestamp": "2024-02-01T12:00:00Z",
  "version": "1.0.0",
  "uptime": 86400,
  "components": {
    "api": {
      "status": "healthy",
      "latency": 5.2
    },
    "database": {
      "status": "healthy",
      "latency": 2.1
    },
    "cache": {
      "status": "healthy",
      "latency": 1.5
    },
    "messageQueue": {
      "status": "healthy",
      "latency": 3.8
    },
    "configurationStore": {
      "status": "healthy",
      "latency": 4.2
    },
    "metricsStore": {
      "status": "degraded",
      "message": "Elevated query latency",
      "latency": 250.5
    }
  }
}
```

**No Authentication Required**

---

#### Cluster Health
```http
GET /api/v1/health/clusters/{clusterId}
```

**Response** (200 OK):
```json
{
  "clusterId": "cluster_001",
  "status": "healthy",
  "timestamp": "2024-02-01T12:00:00Z",
  "components": {
    "gateways": [
      {
        "endpoint": "https://gateway1.us-east.example.com",
        "status": "healthy",
        "latency": 15.5
      },
      {
        "endpoint": "https://gateway2.us-east.example.com",
        "status": "healthy",
        "latency": 16.2
      }
    ],
    "l3Cache": {
      "status": "healthy",
      "cacheHitRate": 0.92
    },
    "tokenBuckets": {
      "status": "healthy",
      "totalBuckets": 150,
      "healthyBuckets": 150
    }
  }
}
```

**Required Permissions**: `clusters:read`

---

#### Application Health
```http
GET /api/v1/health/applications/{applicationId}
```

**Response** (200 OK):
```json
{
  "applicationId": "app_001",
  "status": "degraded",
  "timestamp": "2024-02-01T12:00:00Z",
  "components": {
    "tokenBucket": {
      "status": "degraded",
      "tokens": 1500,
      "capacity": 20000,
      "isBlocked": false
    },
    "quota": {
      "status": "healthy",
      "iopsUsage": 0.425,
      "bandwidthUsage": 0.50
    }
  },
  "alerts": [
    {
      "severity": "warning",
      "message": "Token bucket running low (7.5% remaining)"
    }
  ]
}
```

**Required Permissions**: `applications:read`

---

## WebSocket API

### Connection Endpoint

```
wss://api.qos-system.example.com/v1/ws?token=<jwt_token>
```

### Authentication

WebSocket connections must include a valid JWT token as a query parameter:

```javascript
const ws = new WebSocket('wss://api.qos-system.example.com/v1/ws?token=' + token);
```

### Connection Flow

1. **Connect** with JWT token
2. **Authenticate** event received on successful connection
3. **Subscribe** to desired channels
4. **Receive** real-time updates
5. **Heartbeat** every 30 seconds

### Client → Server Messages

#### Subscribe to Metrics
```json
{
  "action": "subscribe",
  "channel": "metrics",
  "filter": {
    "applicationId": "app_001",
    "metrics": ["iops.usage", "bandwidth.usage", "tokens.available"]
  },
  "interval": 5000
}
```

#### Subscribe to Alerts
```json
{
  "action": "subscribe",
  "channel": "alerts",
  "filter": {
    "severity": ["critical", "emergency"],
    "applicationId": "app_001"
  }
}
```

#### Subscribe to Configuration Changes
```json
{
  "action": "subscribe",
  "channel": "configurations",
  "filter": {
    "clusterId": "cluster_001"
  }
}
```

#### Unsubscribe
```json
{
  "action": "unsubscribe",
  "channel": "metrics"
}
```

#### Heartbeat (Ping)
```json
{
  "action": "ping"
}
```

### Server → Client Events

#### Authentication Success
```json
{
  "event": "authenticated",
  "timestamp": "2024-02-01T12:00:00Z",
  "userId": "user_001"
}
```

#### Metrics Update
```json
{
  "event": "metrics.update",
  "timestamp": "2024-02-01T12:00:00Z",
  "data": {
    "applicationId": "app_001",
    "clusterId": "cluster_001",
    "metrics": {
      "iops": {
        "usage": 8500.5,
        "limit": 20000
      },
      "bandwidth": {
        "usage": 1073741824,
        "limit": 2147483648
      },
      "tokens": {
        "available": 15000,
        "capacity": 20000
      }
    }
  }
}
```

#### Alert Triggered
```json
{
  "event": "alert.triggered",
  "timestamp": "2024-02-01T12:00:00Z",
  "data": {
    "alertId": "alert_001",
    "ruleId": "rule_001",
    "severity": "warning",
    "message": "IOPS usage exceeded 90% threshold",
    "applicationId": "app_001",
    "details": {
      "currentValue": 18500,
      "threshold": 18000,
      "percentage": 92.5
    }
  }
}
```

#### Alert Resolved
```json
{
  "event": "alert.resolved",
  "timestamp": "2024-02-01T12:30:00Z",
  "data": {
    "alertId": "alert_001",
    "resolvedAt": "2024-02-01T12:30:00Z"
  }
}
```

#### Configuration Changed
```json
{
  "event": "configuration.changed",
  "timestamp": "2024-02-01T12:00:00Z",
  "data": {
    "version": "v1.2.4",
    "clusterId": "cluster_001",
    "changeType": "update",
    "resource": "application",
    "resourceId": "app_001",
    "changes": {
      "iops": {
        "limit": {
          "from": 10000,
          "to": 20000
        }
      }
    }
  }
}
```

#### Configuration Deployed
```json
{
  "event": "configuration.deployed",
  "timestamp": "2024-02-01T14:00:00Z",
  "data": {
    "deploymentId": "deploy_001",
    "version": "v1.2.4",
    "status": "completed",
    "clusters": ["cluster_001", "cluster_002"],
    "completedAt": "2024-02-01T14:05:00Z"
  }
}
```

#### Token Bucket Blocked
```json
{
  "event": "tokenbucket.blocked",
  "timestamp": "2024-02-01T12:00:00Z",
  "data": {
    "bucketId": "L2:app_001",
    "level": "L2",
    "applicationId": "app_001",
    "blockDuration": 5000,
    "reason": "Token exhausted"
  }
}
```

#### Pong (Heartbeat Response)
```json
{
  "event": "pong",
  "timestamp": "2024-02-01T12:00:00Z"
}
```

#### Error
```json
{
  "event": "error",
  "timestamp": "2024-02-01T12:00:00Z",
  "data": {
    "code": "INVALID_SUBSCRIPTION",
    "message": "Invalid subscription parameters",
    "details": {
      "field": "metrics",
      "issue": "Invalid metric name"
    }
  }
}
```

### Available Channels

| Channel | Description | Filters |
|---------|-------------|----------|
| `metrics` | Real-time metric updates | applicationId, clusterId, metrics, interval |
| `alerts` | Alert notifications | severity, applicationId, clusterId |
| `configurations` | Configuration change events | clusterId, applicationId |
| `deployments` | Deployment status updates | deploymentId |
| `tokenbuckets` | Token bucket state changes | bucketId, level, applicationId |

---

## Error Handling

### Error Response Format

All error responses follow this structure:

```json
{
  "error": "Human-readable error message",
  "code": "ERROR_CODE",
  "details": {
    "field": "Additional context"
  },
  "requestId": "req_12345",
  "timestamp": "2024-02-01T12:00:00Z"
}
```

### Common HTTP Status Codes

| Status Code | Description | Error Code |
|-------------|-------------|------------|
| 200 OK | Request successful | - |
| 201 Created | Resource created | - |
| 204 No Content | Success, no content returned | - |
| 400 Bad Request | Invalid request parameters | `INVALID_REQUEST` |
| 401 Unauthorized | Authentication failed | `UNAUTHORIZED` |
| 403 Forbidden | Insufficient permissions | `FORBIDDEN` |
| 404 Not Found | Resource not found | `NOT_FOUND` |
| 409 Conflict | Resource conflict | `CONFLICT` |
| 422 Unprocessable Entity | Validation error | `VALIDATION_ERROR` |
| 429 Too Many Requests | Rate limit exceeded | `RATE_LIMIT_EXCEEDED` |
| 500 Internal Server Error | Server error | `INTERNAL_ERROR` |
| 503 Service Unavailable | Service unavailable | `SERVICE_UNAVAILABLE` |

### Specific Error Codes

#### Authentication Errors
- `UNAUTHORIZED`: Invalid or missing authentication
- `TOKEN_EXPIRED`: JWT token has expired
- `TOKEN_INVALID`: JWT token is malformed or invalid
- `CREDENTIALS_INVALID`: Invalid username/password

#### Authorization Errors
- `FORBIDDEN`: User lacks required permissions
- `INSUFFICIENT_PRIVILEGES`: Action requires higher privilege level

#### Validation Errors
- `VALIDATION_ERROR`: Request validation failed
- `INVALID_JSON`: Malformed JSON in request body
- `INVALID_PARAMETER`: Invalid query/path parameter
- `MISSING_REQUIRED_FIELD`: Required field is missing

#### Resource Errors
- `NOT_FOUND`: Requested resource does not exist
- `CONFLICT`: Resource already exists or state conflict
- `RESOURCE_LOCKED`: Resource is locked by another operation
- `VERSION_CONFLICT`: Update conflicts with current version

#### Rate Limiting Errors
- `RATE_LIMIT_EXCEEDED`: Request rate limit exceeded
- `QUOTA_EXCEEDED`: Quota limit exceeded
- `TOKEN_EXHAUSTED`: Token bucket exhausted

#### Configuration Errors
- `CONFIGURATION_INVALID`: Invalid configuration
- `DEPLOYMENT_FAILED`: Configuration deployment failed
- `ROLLBACK_FAILED`: Configuration rollback failed

#### System Errors
- `INTERNAL_ERROR`: Unexpected internal error
- `SERVICE_UNAVAILABLE`: Service temporarily unavailable
- `DATABASE_ERROR`: Database operation failed
- `CACHE_ERROR`: Cache operation failed

### Error Handling Best Practices

1. **Always include `requestId`** for tracing
2. **Use specific error codes** for programmatic handling
3. **Provide human-readable messages** for users
4. **Include relevant details** in the `details` object
5. **Log all errors** with full context server-side
6. **Retry on 5xx errors** with exponential backoff
7. **Don't retry on 4xx errors** (except 429 with rate limit handling)

---

## Rate Limiting

### Admin API Rate Limits

The admin API itself is rate limited to prevent abuse:

| User Role | Requests per Minute | Burst |
|-----------|---------------------|-------|
| Super Admin | 1000 | 100 |
| Cluster Admin | 500 | 50 |
| Operator | 200 | 20 |
| Viewer | 100 | 10 |

Rate limit headers are included in every response:

```
X-RateLimit-Limit: 500
X-RateLimit-Remaining: 495
X-RateLimit-Reset: 1706769600
X-RateLimit-Burst: 50
```

### Per-Endpoint Rate Limits

Some endpoints have additional rate limits:

| Endpoint | Limit | Purpose |
|----------|-------|---------|
| `POST /api/v1/auth/token` | 5 req/min | Prevent brute force |
| `POST /api/v1/applications` | 10 req/min | Prevent spam |
| `POST /api/v1/alerts/rules` | 20 req/min | Prevent alert spam |
| `POST /api/v1/configurations/deployments` | 5 req/min | Prevent rapid deployments |
| `DELETE /api/v1/*` | 50 req/min | Prevent mass deletions |

### Rate Limit Headers

- `X-RateLimit-Limit`: Maximum requests per window
- `X-RateLimit-Remaining`: Remaining requests in current window
- `X-RateLimit-Reset`: Unix timestamp when limit resets
- `X-RateLimit-Burst`: Burst capacity
- `Retry-After`: Seconds to wait before retry (429 response)

### Handling Rate Limits

When you receive a 429 Too Many Requests response:

```json
{
  "error": "Rate limit exceeded",
  "code": "RATE_LIMIT_EXCEEDED",
  "details": {
    "retryAfter": 60,
    "limit": 500,
    "window": "60s"
  },
  "requestId": "req_12345",
  "timestamp": "2024-02-01T12:00:00Z"
}
```

Use the `Retry-After` header to wait before retrying:

```python
import time
import requests

response = requests.post(url, json=data)
if response.status_code == 429:
    retry_after = int(response.headers.get('Retry-After', 60))
    time.sleep(retry_after)
    # Retry request
```

---

## Versioning Strategy

### API Versioning

The API uses **URL path versioning**:

```
/api/v1/...
/api/v2/...
```

### Version Support Policy

| Version | Status | Supported Until | Migration Guide |
|---------|--------|-----------------|-----------------|
| v1 | Current | Until v3 release | - |
| v2 | Beta | N/A | v1 → v2 Migration Guide |

### Breaking Changes

Breaking changes are reserved for major version increments (v1 → v2). Examples of breaking changes:

- Removing or renaming endpoints
- Changing request/response schema structure
- Modifying required fields
- Changing authentication mechanism
- Removing support for older features

### Non-Breaking Changes

The following changes are made within a major version (v1.x → v1.y):

- Adding new endpoints
- Adding new optional fields to responses
- Adding new query parameters
- Adding new request headers
- Fixing bugs without changing behavior

### Deprecation Process

1. **Announcement** - Deprecation announced 6 months in advance
2. **Warning Header** - Deprecated endpoints return `X-Deprecated: true`
3. **Documentation** - Marked as deprecated in API docs
4. **Sunset** - Endpoint removed after deprecation period

Example deprecation header:

```
X-Deprecated: true
X-Sunset: Fri, 01 Aug 2025 00:00:00 GMT
Link: </api/v2/new-endpoint>; rel="successor-version"
```

### Client Version Detection

Clients can detect API version using the `/api/v1/health` endpoint:

```json
{
  "version": "1.2.3",
  "apiVersion": "v1",
  "latestVersion": "1.2.3",
  "supportedVersions": ["v1"]
}
```

### Migration Guides

When v2 is released, a comprehensive migration guide will be provided including:

- Endpoint mapping (v1 → v2)
- Schema changes
- Code examples
- Breaking changes list
- Deprecation timeline

---

## Best Practices

### 1. Pagination

Always use pagination for list endpoints:

```http
GET /api/v1/applications?page=1&pageSize=50
```

Check the `pagination` object in responses to determine total pages.

### 2. Filtering

Use filter parameters to reduce response size:

```http
GET /api/v1/applications?clusterId=cluster_001&enabled=true
```

### 3. Field Selection (Future Enhancement)

Select only needed fields (to be implemented):

```http
GET /api/v1/applications?fields=id,name,appId
```

### 4. Conditional Requests

Use `If-Modified-Since` and `If-None-Match` headers:

```http
GET /api/v1/applications/app_001
If-Modified-Since: Wed, 01 Feb 2024 10:00:00 GMT
```

Returns `304 Not Modified` if resource hasn't changed.

### 5. Bulk Operations

For bulk operations, use dedicated endpoints:

```http
POST /api/v1/applications/bulk
```

### 6. Idempotency

All PUT and DELETE operations are idempotent. Use idempotency keys for POST:

```http
POST /api/v1/applications
Idempotency-Key: uuid-key-here
```

### 7. Request Tracing

Include a unique request ID for debugging:

```http
GET /api/v1/applications/app_001
X-Request-ID: my-custom-request-id
```

This ID will be returned in response headers and logs.

### 8. Async Operations

Long-running operations return 202 Accepted with a status URL:

```http
POST /api/v1/configurations/deployments
```

Response:
```json
{
  "deploymentId": "deploy_001",
  "status": "pending",
  "statusUrl": "/api/v1/configurations/deployments/deploy_001"
}
```

### 9. Webhooks (Future Enhancement)

Configure webhooks for event notifications:

```http
POST /api/v1/webhooks
```

### 10. Caching

Use `Cache-Control` headers:

```http
GET /api/v1/applications/app_001
Cache-Control: max-age=300
```

---

## SDK Examples

### cURL

```bash
# Get authentication token
curl -X POST https://api.qos-system.example.com/v1/auth/token \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"password"}'

# List applications
curl -X GET https://api.qos-system.example.com/v1/applications \
  -H "Authorization: Bearer <token>"

# Create application
curl -X POST https://api.qos-system.example.com/v1/applications \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Storage Service C",
    "appId": "storage-service-c",
    "clusterId": "cluster_001",
    "priority": 8
  }'
```

### Python (requests)

```python
import requests

BASE_URL = "https://api.qos-system.example.com/v1"

# Authenticate
response = requests.post(f"{BASE_URL}/auth/token", json={
    "username": "admin",
    "password": "password"
})
token = response.json()["token"]

# List applications
headers = {"Authorization": f"Bearer {token}"}
response = requests.get(f"{BASE_URL}/applications", headers=headers)
applications = response.json()["data"]

# Create application
response = requests.post(
    f"{BASE_URL}/applications",
    headers=headers,
    json={
        "name": "Storage Service C",
        "appId": "storage-service-c",
        "clusterId": "cluster_001",
        "priority": 8
    }
)
application = response.json()
```

### JavaScript (fetch)

```javascript
const BASE_URL = 'https://api.qos-system.example.com/v1';

// Authenticate
const authResponse = await fetch(`${BASE_URL}/auth/token`, {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({
    username: 'admin',
    password: 'password'
  })
});
const {token} = await authResponse.json();

// List applications
const appsResponse = await fetch(`${BASE_URL}/applications`, {
  headers: {'Authorization': `Bearer ${token}`}
});
const {data: applications} = await appsResponse.json();

// Create application
const createResponse = await fetch(`${BASE_URL}/applications`, {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    name: 'Storage Service C',
    appId: 'storage-service-c',
    clusterId: 'cluster_001',
    priority: 8
  })
});
const application = await createResponse.json();
```

### Go (net/http)

```go
package main

import (
    "bytes"
    "encoding/json"
    "net/http"
)

const BASE_URL = "https://api.qos-system.example.com/v1"

type TokenResponse struct {
    Token string `json:"token"`
}

func getToken() (string, error) {
    body, _ := json.Marshal(map[string]string{
        "username": "admin",
        "password": "password",
    })
    resp, err := http.Post(BASE_URL+"/auth/token", "application/json", bytes.NewBuffer(body))
    if err != nil {
        return "", err
    }
    defer resp.Body.Close()

    var tokenResp TokenResponse
    json.NewDecoder(resp.Body).Decode(&tokenResp)
    return tokenResp.Token, nil
}

func main() {
    token, _ := getToken()

    // List applications
    req, _ := http.NewRequest("GET", BASE_URL+"/applications", nil)
    req.Header.Set("Authorization", "Bearer "+token)
    client := &http.Client{}
    resp, _ := client.Do(req)
    defer resp.Body.Close()

    var result map[string]interface{}
    json.NewDecoder(resp.Body).Decode(&result)
    println(result)
}
```

---

## Appendix

### A. Complete OpenAPI 3.1 YAML File

The complete OpenAPI 3.1 specification in YAML format can be generated from this documentation. A tool can be created to parse this markdown and generate a valid `openapi.yaml` file.

### B. Postman Collection

A Postman collection can be auto-generated from this specification.

### C. SDK Generation

Client SDKs can be generated using:
- OpenAPI Generator: https://openapi-generator.tech
- Swagger Codegen: https://github.com/swagger-api/swagger-codegen

### D. API Gateway Configuration

Example OpenResty/Nginx configuration for API gateway:

```nginx
server {
    listen 443 ssl;
    server_name api.qos-system.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location /v1/ {
        proxy_pass http://backend_upstream;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Rate limiting
        limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
        limit_req zone=api_limit burst=20 nodelay;
    }

    location /v1/ws {
        proxy_pass http://websocket_upstream;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

### E. Monitoring Metrics

The system exposes Prometheus metrics at `/metrics`:

```
# API request metrics
http_requests_total{method="GET",endpoint="/applications",status="200"} 1234
http_request_duration_seconds{endpoint="/applications",quantile="0.5"} 0.05

# Rate limiting metrics
token_bucket_tokens{application_id="app_001",level="L2"} 15000
rate_limit_requests_blocked{application_id="app_001"} 125

# Alert metrics
alerts_active{severity="warning"} 5
alerts_triggered_total{rule_id="rule_001"} 42
```

### F. Database Schema

Key database tables:

```sql
-- Applications
CREATE TABLE applications (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    app_id VARCHAR(128) UNIQUE NOT NULL,
    cluster_id UUID NOT NULL,
    enabled BOOLEAN DEFAULT true,
    priority INT DEFAULT 5,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    created_by VARCHAR(255),
    updated_by VARCHAR(255)
);

-- Quotas
CREATE TABLE application_quotas (
    application_id UUID PRIMARY KEY REFERENCES applications(id),
    iops_limit INT,
    iops_burst INT,
    bandwidth_limit BIGINT,
    bandwidth_burst BIGINT,
    storage_size_limit BIGINT,
    request_rate_limit INT,
    connections_limit INT
);

-- Token Buckets
CREATE TABLE token_buckets (
    bucket_id VARCHAR(255) PRIMARY KEY,
    level VARCHAR(2) NOT NULL,
    tokens FLOAT NOT NULL,
    capacity INT NOT NULL,
    refill_rate FLOAT NOT NULL,
    last_refill TIMESTAMP,
    last_consume TIMESTAMP,
    is_blocked BOOLEAN DEFAULT false
);

-- Alert Rules
CREATE TABLE alert_rules (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    metric VARCHAR(255) NOT NULL,
    condition VARCHAR(10) NOT NULL,
    threshold FLOAT NOT NULL,
    severity VARCHAR(20) NOT NULL,
    duration INT,
    enabled BOOLEAN DEFAULT true,
    cooldown INT DEFAULT 900
);

-- Alerts
CREATE TABLE alerts (
    id UUID PRIMARY KEY,
    rule_id UUID REFERENCES alert_rules(id),
    severity VARCHAR(20) NOT NULL,
    message TEXT NOT NULL,
    details JSONB,
    timestamp TIMESTAMP DEFAULT NOW(),
    acknowledged BOOLEAN DEFAULT false,
    acknowledged_by VARCHAR(255),
    acknowledged_at TIMESTAMP,
    resolved_at TIMESTAMP
);
```

---

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024-02-01 | Initial release |

---

## Support

- Documentation: https://docs.qos-system.example.com
- GitHub: https://github.com/qos-system/api
- Issues: https://github.com/qos-system/api/issues
- Email: support@qos-system.example.com

---

**Document Version**: 1.0.0
**Last Updated**: 2024-02-01
**API Version**: v1
