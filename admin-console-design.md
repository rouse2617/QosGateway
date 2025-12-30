# OpenResty Distributed Rate Limiter - Admin Console Design

**Version:** 1.0
**Date:** 2025-12-31
**Author:** System Architecture Team

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Research & Competitive Analysis](#research--competitive-analysis)
3. [Recommended Technology Stack](#recommended-technology-stack)
4. [System Architecture](#system-architecture)
5. [Backend API Design](#backend-api-design)
6. [Frontend Architecture](#frontend-architecture)
7. [Database Schema](#database-schema)
8. [Key Features & Modules](#key-features--modules)
9. [Authentication & Authorization](#authentication--authorization)
10. [OpenResty Integration](#openresty-integration)
11. [Deployment Architecture](#deployment-architecture)
12. [Security Considerations](#security-considerations)
13. [Development Roadmap](#development-roadmap)

---

## Executive Summary

This document outlines the design for a modern, scalable admin console for managing OpenResty-based distributed rate limiting. The system draws inspiration from industry-leading tools like **nginx-ui** and **Nginx Proxy Manager** while specializing in rate limiting management, Redis cluster monitoring, and real-time metrics visualization.

### Key Objectives

- **Unified Management**: Single pane of glass for configuration, monitoring, and operations
- **Real-time Visibility**: Live dashboard for rate limiting metrics, token usage, and system health
- **Developer-Friendly**: API-first design with comprehensive TypeScript support
- **Operational Excellence**: Configuration versioning, rollback, and audit trails
- **Scalability**: Support for multi-region deployments and high-availability configurations

---

## Research & Competitive Analysis

### 1. nginx-ui ([GitHub](https://github.com/0xJacky/nginx-ui))

**Technology Stack:**
- **Backend:** Go 1.23+ (single binary distribution)
- **Frontend:** Vue.js with Tailwind CSS
- **Architecture:** Self-hosted executable with embedded web server

**Strengths:**
- ✅ Single executable binary deployment (cross-platform: Linux, macOS, Windows, BSD)
- ✅ Modern Vue.js UI with dark mode support
- ✅ Real-time server metrics (CPU, memory, load, disk)
- ✅ Configuration versioning with diff comparison and rollback
- ✅ Cluster management with mirroring to multiple nodes
- ✅ Encrypted configuration export for deployment/recovery
- ✅ Built-in NgxConfigEditor (block-based) + Ace Code Editor (with LLM completion)
- ✅ ChatGPT integration for configuration assistance
- ✅ MCP (Model Context Protocol) for AI agent automation
- ✅ Let's Encrypt SSL automation
- ✅ Web terminal integration
- ✅ Multi-language support (English, Chinese)

**Weaknesses:**
- ❌ Not specialized for rate limiting (generic nginx management)
- ❌ Limited Redis cluster monitoring
- ❌ No per-application quota management
- ❌ No advanced rate limiting analytics

**Key Takeaways for Our Design:**
1. Adopt Go backend for single-binary distribution and performance
2. Use Vue.js + Tailwind CSS for modern, responsive UI
3. Implement configuration versioning and rollback
4. Add AI assistant integration for configuration help
5. Provide cluster management capabilities

### 2. Nginx Proxy Manager ([Official Site](https://nginxproxymanager.com/))

**Technology Stack:**
- **Backend:** Node.js + Express
- **Frontend:** Vue.js (based on Tabler UI)
- **Database:** SQLite (default) or MySQL/PostgreSQL
- **Deployment:** Docker container

**Strengths:**
- ✅ Beautiful, user-friendly Tabler-based UI
- ✅ Docker-native deployment
- ✅ Multi-user support with permissions
- ✅ Let's Encrypt SSL automation
- ✅ Proxy host management with visual interface
- ✅ Access lists and IP whitelisting
- ✅ Stream (TCP/UDP) proxy support
- ✅ Certificate management
- ✅ Dead-simple setup (database-only requirement)

**Weaknesses:**
- ❌ Node.js backend (higher resource usage vs Go)
- ❌ Less granular configuration control
- ❌ Limited nginx configuration editing (focuses on proxies)
- ❌ No advanced rate limiting features
- ❌ SQLite performance issues at scale

**Key Takeaways for Our Design:**
1. Prioritize UX/UI design excellence (Tabler or similar)
2. Implement role-based access control (RBAC)
3. Support Docker deployment
4. Provide visual configuration builders for complex setups
5. Choose production-grade database (PostgreSQL recommended)

### 3. API Gateway Monitoring Best Practices (2025)

Based on research from [API7's API Monitoring Metrics Guide](https://api7.ai/blog/top-10-api-monitoring-metrics) and [Gravitee's Rate Limiting Blog](https://www.gravitee.io/blog/rate-limiting-throttling-with-an-api-gateway-why-it-matters):

**Critical Metrics to Monitor:**
1. **Request Rate & Throughput** (requests/sec per route/app)
2. **Rate Limit Violations** (429 responses, rejected requests)
3. **Token Bucket Usage** (remaining capacity per app/key)
4. **Latency** (p50, p95, p99 response times)
5. **Redis Cluster Health** (memory, connections, hit rate, fragmentation)
6. **OpenResty Worker Status** (CPU, memory, connections per worker)
7. **Error Rates** (5xx errors, upstream failures)
8. **Geo-distribution** (requests by region/country)
9. **Top Consumers** (apps/keys using most quota)
10. **Configuration Changes** (audit trail, deployment status)

---

## Recommended Technology Stack

### Backend: Go 1.23+ ⭐ Recommended

**Justification:**
1. **Performance**: Compiled binary, low memory footprint (~10-20MB vs Node.js ~100MB+)
2. **Deployment**: Single executable, cross-platform builds (like nginx-ui)
3. **Concurrency**: Goroutines perfect for handling multiple OpenResty nodes
4. **Ecosystem**: Excellent Redis client (`go-redis/redis`), OpenResty integration via HTTP API
5. **Type Safety**: Strong typing reduces runtime errors vs JavaScript/Node.js
6. **Maintenance**: Easier long-term maintenance vs Node.js dependency hell

**Alternative**: Node.js + TypeScript (only if team has zero Go experience)

### Frontend: Vue 3 + TypeScript + Vite

**Justification:**
1. **Modern & Fast**: Vue 3 Composition API, Vite for instant HMR
2. **Type Safety**: TypeScript for component props, API contracts
3. **UI Libraries**: Element Plus, Ant Design Vue, or Naive UI (all excellent)
4. **State Management**: Pinia (official Vue 3 store)
5. **Proven**: Used by nginx-ui, Nginx Proxy Manager
6. **Learning Curve**: Gentler than React for new developers

**Alternative**: React 18 + TypeScript (equally valid, choose based on team preference)

### Database: PostgreSQL 15+

**Justification:**
1. **Production-Grade**: ACID compliance, reliable at scale
2. **JSON Support**: Store nginx configs as JSONB for querying
3. **Full-Text Search**: Search configurations, logs
4. **Extensions**: TimescaleDB for metrics time-series data
5. **Backup/Restore**: Mature tooling (pg_dump, WAL archiving)
6. **Free & Open Source**: No licensing costs

**Time-Series Data**: Consider TimescaleDB extension (PostgreSQL-based) or InfluxDB for high-cardinality metrics

### Real-Time Communication: WebSocket (Go) + Server-Sent Events

**Justification:**
1. **Metrics Streaming**: Push Redis/OpenResty metrics to dashboard
2. **Log Tailing**: Real-time nginx error/access log streaming
3. **Configuration Changes**: Notify users of deployments, reloads
4. **Bi-directional**: WebSocket for interactive terminal (like nginx-ui)

### Authentication: JWT + RBAC

**Justification:**
1. **Stateless**: JWT tokens for API authentication
2. **Scalability**: No session storage required
3. **Roles**: Admin, Operator, Viewer, App Owner (custom per-app access)
4. **Integration**: Easy SSO integration via OAuth2/OIDC

### Additional Technologies

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **API Client** | Axios (TS) | HTTP requests with interceptors |
| **UI Framework** | Naive UI / Element Plus | Vue 3 component library |
| **Charts** | ECharts / Chart.js | Metrics visualization |
| **Code Editor** | Monaco Editor | Nginx/Lua config editing (VS Code engine) |
| **Diff Viewer** | monaco-diff / diff2html | Config version comparison |
| **Terminal** | xterm.js | Web terminal (SSH to OpenResty nodes) |
| **WebSocket** | Socket.IO / native WS | Real-time metrics streaming |
| **Monitoring** | Prometheus Exporter | Expose metrics for Grafana |
| **Validation** | OpenResty config test API | Validate nginx -t logic |
| **Logging** | Winston / Zap | Structured logging backend |

---

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Admin Console                            │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Frontend (Vue 3 + TypeScript)               │   │
│  │  - Dashboard      - Config Editor   - App Management     │   │
│  │  - Monitoring     - Redis Health    - Users/RBAC         │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              ▲                                   │
│                              │ HTTP/WS                           │
│  ┌───────────────────────────┴───────────────────────────────┐  │
│  │              Backend (Go + Gin/Echo Framework)            │  │
│  │  - REST API      - WebSocket Hub   - Auth Service        │  │
│  │  - Config Store  - Metrics Collector - Job Scheduler      │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│   PostgreSQL    │  │  Redis Cluster  │  │  OpenResty Nodes │
│  (Config DB)    │  │  (Rate Limit)   │  │  (Gateway)       │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

### Component Overview

#### 1. Frontend (Vue 3 + TypeScript)

**Core Modules:**
- **Dashboard**: Real-time metrics, alerts, system health
- **Configuration Manager**: Nginx/Lua config editor with validation
- **Application Management**: Per-app rate limit quotas, API keys
- **Monitoring**: Time-series charts, log viewer, topology map
- **Redis Cluster**: Node status, memory, keys, failover events
- **User Management**: RBAC, audit logs, SSO integration
- **Settings**: Global config, notifications, integrations

#### 2. Backend (Go)

**Core Services:**
- **API Gateway**: RESTful API, middleware (auth, logging, rate limiting)
- **Config Service**: CRUD for nginx/Lua configs, versioning, validation
- **Metrics Collector**: Poll OpenResty/Redis, aggregate, store in DB
- **WebSocket Hub**: Broadcast real-time updates to connected clients
- **Job Scheduler**: Config deployment, SSL renewal, cleanup tasks
- **Notification Service**: Alerting (Email, Slack, PagerDuty, Webhooks)
- **Auth Service**: JWT tokens, RBAC enforcement, SSO

#### 3. Integration Layer

**OpenResty Gateway:**
- HTTP API endpoints (Lua) for:
  - Metrics exposure (shared memory zones)
  - Configuration reload (nginx -s reload)
  - Log streaming (access/error logs via tail)
  - Certificate management (Let's Encrypt hooks)

**Redis Cluster:**
- Rate limit data (token buckets)
- Distributed locks (leader election)
- Pub/Sub (real-time events)

---

## Backend API Design

### API Structure

```
/api/v1/
├── auth/                    # Authentication
│   ├── POST   /login
│   ├── POST  /logout
│   ├── POST  /refresh
│   └── GET   /me
├── config/                  # Configuration Management
│   ├── GET    /             # List all configs
│   ├── POST   /             # Create config
│   ├── GET    /:id          # Get config details
│   ├── PUT    /:id          # Update config
│   ├── DELETE /:id          # Delete config
│   ├── POST   /:id/validate # Validate config syntax
│   ├── POST   /:id/deploy   # Deploy to OpenResty
│   ├── GET    /:id/versions # List versions
│   ├── GET    /:id/versions/:version_id
│   ├── POST   /:id/rollback # Rollback to version
│   └── GET    /:id/diff/:from/:to  # Compare versions
├── applications/            # Application Management
│   ├── GET    /             # List apps
│   ├── POST   /             # Create app
│   ├── GET    /:id          # Get app details
│   ├── PUT    /:id          # Update app
│   ├── DELETE /:id          # Delete app
│   ├── POST   /:id/keys     # Generate API key
│   ├── DELETE /:id/keys/:key_id
│   ├── GET    /:id/quota    # Get quota config
│   ├── PUT    /:id/quota    # Update quota
│   ├── GET    /:id/metrics  # App-specific metrics
│   └── GET    /:id/usage    # Token usage history
├── routes/                  # Route Configuration
│   ├── GET    /             # List routes
│   ├── POST   /             # Create route
│   ├── GET    /:id
│   ├── PUT    /:id
│   ├── DELETE /:id
│   ├── PUT    /:id/rate-limit  # Configure rate limit
│   └── GET    /:id/metrics
├── redis/                   # Redis Cluster Management
│   ├── GET    /clusters     # List clusters
│   ├── GET    /clusters/:id # Cluster details
│   ├── GET    /clusters/:id/nodes  # Node status
│   ├── GET    /clusters/:id/metrics
│   ├── POST   /clusters/:id/failover
│   ├── GET    /keys         # List keys (pattern search)
│   ├── GET    /keys/:key    # Get key value
│   ├── DELETE /keys/:key    # Delete key
│   └── POST   /flush        # Flush database (dangerous!)
├── openresty/               # OpenResty Node Management
│   ├── GET    /nodes        # List nodes
│   ├── POST   /nodes        # Add node
│   ├── GET    /nodes/:id    # Node details
│   ├── PUT    /nodes/:id    # Update node
│   ├── DELETE /nodes/:id
│   ├── POST   /nodes/:id/reload   # Reload nginx
│   ├── POST   /nodes/:id/restart  # Restart nginx
│   ├── GET    /nodes/:id/logs/access
│   ├── GET    /nodes/:id/logs/error
│   └── GET    /nodes/:id/metrics
├── monitoring/              # Metrics & Monitoring
│   ├── GET    /dashboard    # Dashboard metrics (aggregate)
│   ├── GET    /rate-limit   # Rate limiting metrics
│   ├── GET    /top-consumers
│   ├── GET    /geo-stats
│   ├── GET    /alerts       # Active alerts
│   ├── POST   /alerts/:id/acknowledge
│   └── GET    /history      # Metrics history (time-range)
├── users/                   # User Management
│   ├── GET    /             # List users
│   ├── POST   /             # Create user
│   ├── GET    /:id
│   ├── PUT    /:id
│   ├── DELETE /:id
│   ├── POST   /:id/roles    # Assign roles
│   └── GET    /me/activity  # Current user activity
├── roles/                   # RBAC
│   ├── GET    /             # List roles
│   ├── POST   /             # Create role
│   ├── GET    /:id
│   ├── PUT    /:id
│   ├── DELETE /:id
│   └── GET    /:id/permissions
└── system/                  # System Settings
    ├── GET    /info         # System info (version, uptime)
    ├── GET    /health       # Health check
    ├── GET    /settings     # Global settings
    ├── PUT    /settings     # Update settings
    └── POST   /backup       # Trigger backup
```

### API Specification Examples

#### POST /api/v1/auth/login
```http
POST /api/v1/auth/login HTTP/1.1
Content-Type: application/json

{
  "username": "admin",
  "password": "securepassword"
}

Response:
{
  "success": true,
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "expires_in": 3600,
    "user": {
      "id": "usr_123abc",
      "username": "admin",
      "email": "admin@example.com",
      "roles": ["admin"],
      "created_at": "2025-01-01T00:00:00Z"
    }
  }
}
```

#### POST /api/v1/config/:id/validate
```http
POST /api/v1/config/conf_123/validate HTTP/1.1
Authorization: Bearer <token>
Content-Type: application/json

{
  "content": "user nginx;\nworker_processes auto;\n..."
}

Response:
{
  "success": true,
  "data": {
    "valid": true,
    "warnings": [
      "worker_processes should not exceed number of CPU cores"
    ],
    "errors": [],
    "nginx_test_output": "nginx: configuration file /etc/nginx/nginx.conf test is successful"
  }
}
```

#### GET /api/v1/applications/:id/metrics
```http
GET /api/v1/applications/app_456/metrics?from=2025-12-31T00:00:00Z&to=2025-12-31T23:59:59Z&interval=5m
Authorization: Bearer <token>

Response:
{
  "success": true,
  "data": {
    "application_id": "app_456",
    "name": "Mobile API",
    "metrics": {
      "total_requests": 1500000,
      "rate_limit_violations": 234,
      "average_tokens_used": 75.5,
      "peak_rps": 450,
      "p95_latency_ms": 120,
      "p99_latency_ms": 340,
      "time_series": [
        {
          "timestamp": "2025-12-31T00:00:00Z",
          "requests": 1200,
          "tokens_used": 65,
          "violations": 5
        },
        ...
      ]
    }
  }
}
```

#### WebSocket Events

```javascript
// Client connects to: wss://admin-console.example.com/api/v1/stream

// Server -> Client events
{
  "type": "metrics_update",
  "data": {
    "timestamp": "2025-12-31T12:00:00Z",
    "rps": 1250,
    "rate_limit_violations": 12,
    "redis_memory_mb": 2048,
    "active_connections": 450
  }
}

{
  "type": "config_deployment",
  "data": {
    "config_id": "conf_123",
    "status": "success",
    "deployed_at": "2025-12-31T12:05:00Z",
    "nodes": ["node1", "node2", "node3"]
  }
}

{
  "type": "alert",
  "data": {
    "severity": "critical",
    "title": "Redis High Memory Usage",
    "message": "Redis node redis-01 using 92% memory",
    "timestamp": "2025-12-31T12:10:00Z"
  }
}

{
  "type": "log_entry",
  "data": {
    "node_id": "node1",
    "level": "error",
    "message": "upstream timed out (110: Connection timed out)",
    "timestamp": "2025-12-31T12:15:00Z"
  }
}
```

---

## Frontend Architecture

### Directory Structure

```
frontend/
├── src/
│   ├── assets/              # Static assets (images, fonts)
│   ├── components/          # Reusable components
│   │   ├── common/          # Generic components
│   │   │   ├── Button.vue
│   │   │   ├── Card.vue
│   │   │   ├── Modal.vue
│   │   │   ├── Table.vue
│   │   │   └── StatusBadge.vue
│   │   ├── config/          # Config-related components
│   │   │   ├── ConfigEditor.vue      # Monaco-based editor
│   │   │   ├── ConfigDiffViewer.vue  # Version comparison
│   │   │   ├── ConfigValidator.vue   # Validation status
│   │   │   └── ConfigHistory.vue     # Version timeline
│   │   ├── monitoring/      # Monitoring components
│   │   │   ├── MetricsChart.vue      # ECharts wrapper
│   │   │   ├── RealtimeGauge.vue     # Live metrics gauges
│   │   │   ├── LogViewer.vue         # Log stream viewer
│   │   │   └── AlertList.vue         # Alerts panel
│   │   ├── redis/          # Redis components
│   │   │   ├── ClusterMap.vue        # Cluster topology
│   │   │   ├── NodeStatus.vue        # Node health cards
│   │   │   └── KeyBrowser.vue        # Key explorer
│   │   └── auth/           # Auth components
│   │       ├── LoginForm.vue
│   │       └── ProtectedRoute.vue
│   ├── composables/        # Vue composition functions
│   │   ├── useAuth.ts      # Authentication logic
│   │   ├── useApi.ts       # API client
│   │   ├── useWebSocket.ts # WebSocket connection
│   │   ├── useMetrics.ts   # Metrics polling/streaming
│   │   └── useNotification.ts # Toast notifications
│   ├── layouts/            # Layout components
│   │   ├── DefaultLayout.vue    # Main layout with sidebar
│   │   ├── AuthLayout.vue       # Login page layout
│   │   └── EmptyLayout.vue      # Full-screen layout
│   ├── pages/              # Page components
│   │   ├── Dashboard.vue
│   │   ├── ConfigList.vue
│   │   ├── ConfigEdit.vue
│   │   ├── Applications.vue
│   │   ├── ApplicationDetail.vue
│   │   ├── Routes.vue
│   │   ├── RedisClusters.vue
│   │   ├── RedisKeys.vue
│   │   ├── OpenRestyNodes.vue
│   │   ├── Monitoring.vue
│   │   ├── Alerts.vue
│   │   ├── Logs.vue
│   │   ├── Users.vue
│   │   ├── Roles.vue
│   │   ├── Settings.vue
│   │   └── Login.vue
│   ├── router/             # Vue Router config
│   │   └── index.ts
│   ├── stores/             # Pinia stores
│   │   ├── auth.ts         # Auth state
│   │   ├── config.ts       # Config state
│   │   ├── metrics.ts      # Metrics cache
│   │   ├── notifications.ts # Toast queue
│   │   └── settings.ts     # User settings
│   ├── types/              # TypeScript types
│   │   ├── api.ts          # API response types
│   │   ├── config.ts       # Config types
│   │   ├── metrics.ts      # Metrics types
│   │   └── auth.ts         # Auth types
│   ├── utils/              # Utility functions
│   │   ├── formatters.ts   # Date, number formatters
│   │   ├── validators.ts   # Form validators
│   │   └── constants.ts    # App constants
│   ├── App.vue
│   └── main.ts
├── public/
├── package.json
├── vite.config.ts
├── tsconfig.json
└── tailwind.config.js
```

### Component Hierarchy

#### Dashboard Page (Dashboard.vue)

```vue
<template>
  <div class="dashboard">
    <!-- Page Header -->
    <DashboardHeader
      :time-range="timeRange"
      @update:time-range="handleTimeRangeChange"
    />

    <!-- Summary Cards -->
    <div class="summary-cards grid grid-cols-4 gap-4">
      <SummaryCard
        title="Total Requests"
        :value="metrics.totalRequests"
        :trend="metrics.requestsTrend"
        icon="requests"
      />
      <SummaryCard
        title="Rate Limit Violations"
        :value="metrics.violations"
        :trend="metrics.violationsTrend"
        icon="warning"
        :threshold="100"
      />
      <SummaryCard
        title="Active Applications"
        :value="metrics.activeApps"
        icon="apps"
      />
      <SummaryCard
        title="Redis Memory"
        :value="`${metrics.redisMemory}%`"
        :trend="metrics.redisMemoryTrend"
        icon="database"
        :threshold="80"
      />
    </div>

    <!-- Charts Row -->
    <div class="charts-row grid grid-cols-2 gap-4">
      <MetricsChart
        title="Requests per Second"
        :data="metrics.rpsTimeSeries"
        :time-range="timeRange"
        type="line"
      />
      <MetricsChart
        title="Token Bucket Usage (Top 5 Apps)"
        :data="metrics.tokenUsage"
        type="bar"
      />
    </div>

    <!-- Real-time Section -->
    <div class="realtime-section grid grid-cols-3 gap-4">
      <!-- Live Requests Stream -->
      <LiveRequestStream :requests="liveRequests" />

      <!-- Active Alerts -->
      <AlertPanel :alerts="activeAlerts" @acknowledge="handleAckAlert" />

      <!-- System Status -->
      <SystemStatus
        :openresty-nodes="openrestyNodes"
        :redis-cluster="redisCluster"
      />
    </div>

    <!-- Top Consumers Table -->
    <TopConsumersTable :consumers="topConsumers" />
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useMetrics } from '@/composables/useMetrics'
import { useWebSocket } from '@/composables/useWebSocket'

const { metrics, fetchMetrics, timeRange } = useMetrics()
const { connect, disconnect, liveRequests, activeAlerts } = useWebSocket()

onMounted(() => {
  fetchMetrics()
  connect()
})

onUnmounted(() => {
  disconnect()
})
</script>
```

#### Configuration Editor (ConfigEdit.vue)

```vue
<template>
  <div class="config-editor">
    <!-- Header -->
    <ConfigEditorHeader
      :config="config"
      :has-unsaved-changes="hasUnsavedChanges"
      @save="handleSave"
      @deploy="handleDeploy"
      @validate="handleValidate"
    />

    <div class="editor-layout flex">
      <!-- Main Editor -->
      <div class="editor-main flex-1">
        <MonacoEditor
          v-model="configContent"
          language="nginx"
          :options="editorOptions"
          @change="handleEditorChange"
        />

        <!-- Validation Panel -->
        <ValidationPanel
          :validation-result="validationResult"
          :is-validating="isValidating"
        />
      </div>

      <!-- Sidebar -->
      <div class="editor-sidebar w-80">
        <!-- Config Info -->
        <ConfigInfoCard :config="config" />

        <!-- Versions History -->
        <ConfigVersions
          :versions="versions"
          @select-version="handleSelectVersion"
        />

        <!-- AI Assistant -->
        <AIAssistant
          :context="configContent"
          @suggestion="handleAISuggestion"
        />

        <!-- Variables -->
        <ConfigVariables
          v-model="config.variables"
        />
      </div>
    </div>

    <!-- Diff Modal (for version comparison) -->
    <DiffViewerModal
      v-if="showDiffModal"
      :from-content="originalContent"
      :to-content="configContent"
      @close="showDiffModal = false"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { useRoute } from 'vue-router'
import { useConfigApi } from '@/composables/useApi'

const route = useRoute()
const { fetchConfig, saveConfig, validateConfig, deployConfig } = useConfigApi()

const config = ref(null)
const configContent = ref('')
const originalContent = ref('')
const versions = ref([])
const validationResult = ref(null)
const isValidating = ref(false)

const hasUnsavedChanges = computed(() => {
  return configContent.value !== originalContent.value
})

onMounted(async () => {
  const configId = route.params.id
  config.value = await fetchConfig(configId)
  configContent.value = config.value.content
  originalContent.value = config.value.content
  versions.value = await fetchVersions(configId)
})

const handleValidate = async () => {
  isValidating.value = true
  validationResult.value = await validateConfig(config.value.id, configContent.value)
  isValidating.value = false
}

const handleSave = async () => {
  await saveConfig(config.value.id, {
    content: configContent.value,
    message: 'Manual save'
  })
  originalContent.value = configContent.value
}

const handleDeploy = async () => {
  await handleValidate()
  if (validationResult.value.valid) {
    await deployConfig(config.value.id)
  }
}
</script>
```

### Key Composables

#### useApi.ts (API Client)

```typescript
// src/composables/useApi.ts
import axios, { AxiosInstance } from 'axios'
import { useAuthStore } from '@/stores/auth'
import { useNotificationStore } from '@/stores/notifications'

export function useApi() {
  const authStore = useAuthStore()
  const notificationStore = useNotificationStore()

  const apiClient: AxiosInstance = axios.create({
    baseURL: import.meta.env.VITE_API_URL || 'http://localhost:8080/api/v1',
    timeout: 30000,
    headers: {
      'Content-Type': 'application/json'
    }
  })

  // Request interceptor (add auth token)
  apiClient.interceptors.request.use(
    (config) => {
      if (authStore.token) {
        config.headers.Authorization = `Bearer ${authStore.token}`
      }
      return config
    },
    (error) => Promise.reject(error)
  )

  // Response interceptor (handle errors, token refresh)
  apiClient.interceptors.response.use(
    (response) => response.data,
    async (error) => {
      const originalRequest = error.config

      // Token expired, try refresh
      if (error.response?.status === 401 && !originalRequest._retry) {
        originalRequest._retry = true
        try {
          await authStore.refreshToken()
          apiClient.defaults.headers.Authorization = `Bearer ${authStore.token}`
          return apiClient(originalRequest)
        } catch (refreshError) {
          authStore.logout()
          window.location.href = '/login'
          return Promise.reject(refreshError)
        }
      }

      // Show error notification
      const message = error.response?.data?.message || 'An error occurred'
      notificationStore.error(message)

      return Promise.reject(error)
    }
  )

  return {
    client: apiClient,
    // Config API
    fetchConfigs: () => apiClient.get('/config'),
    fetchConfig: (id: string) => apiClient.get(`/config/${id}`),
    saveConfig: (id: string, data: any) => apiClient.put(`/config/${id}`, data),
    validateConfig: (id: string, content: string) =>
      apiClient.post(`/config/${id}/validate`, { content }),
    deployConfig: (id: string) => apiClient.post(`/config/${id}/deploy`),
    // ... other API methods
  }
}
```

#### useWebSocket.ts (Real-time Updates)

```typescript
// src/composables/useWebSocket.ts
import { ref, onUnmounted } from 'vue'
import { useAuthStore } from '@/stores/auth'

export function useWebSocket() {
  const authStore = useAuthStore()
  const ws = ref<WebSocket | null>(null)
  const connected = ref(false)
  const liveRequests = ref([])
  const activeAlerts = ref([])
  const metricsUpdates = ref({})

  const connect = () => {
    const wsUrl = `${import.meta.env.VITE_WS_URL}/api/v1/stream?token=${authStore.token}`
    ws.value = new WebSocket(wsUrl)

    ws.value.onopen = () => {
      connected.value = true
      console.log('WebSocket connected')
    }

    ws.value.onmessage = (event) => {
      const message = JSON.parse(event.data)

      switch (message.type) {
        case 'metrics_update':
          metricsUpdates.value = message.data
          break
        case 'request_stream':
          liveRequests.value.unshift(message.data)
          if (liveRequests.value.length > 100) {
            liveRequests.value.pop()
          }
          break
        case 'alert':
          activeAlerts.value.unshift(message.data)
          break
        case 'log_entry':
          // Handle log streaming
          break
      }
    }

    ws.value.onerror = (error) => {
      console.error('WebSocket error:', error)
    }

    ws.value.onclose = () => {
      connected.value = false
      // Auto-reconnect after 5 seconds
      setTimeout(connect, 5000)
    }
  }

  const disconnect = () => {
    if (ws.value) {
      ws.value.close()
      ws.value = null
    }
  }

  const send = (type: string, data: any) => {
    if (ws.value && connected.value) {
      ws.value.send(JSON.stringify({ type, data }))
    }
  }

  onUnmounted(() => {
    disconnect()
  })

  return {
    connected,
    connect,
    disconnect,
    send,
    liveRequests,
    activeAlerts,
    metricsUpdates
  }
}
```

---

## Database Schema

### PostgreSQL Schema

```sql
-- ============================================
-- Users & Authentication
-- ============================================

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_login_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT true,
    mfa_enabled BOOLEAN DEFAULT false,
    mfa_secret VARCHAR(255)
);

CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    permissions JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE user_roles (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID REFERENCES roles(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    assigned_by UUID REFERENCES users(id),
    PRIMARY KEY (user_id, role_id)
);

-- ============================================
-- OpenResty Nodes
-- ============================================

CREATE TABLE openresty_nodes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    host VARCHAR(255) NOT NULL,
    port INTEGER DEFAULT 80,
    ssl_port INTEGER DEFAULT 443,
    api_port INTEGER DEFAULT 9000,
    status VARCHAR(20) DEFAULT 'unknown', -- online, offline, degraded
    version VARCHAR(50),
    worker_processes INTEGER,
    worker_connections INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_health_check_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB DEFAULT '{}'
);

CREATE INDEX idx_openresty_nodes_status ON openresty_nodes(status);

-- ============================================
-- Configurations
-- ============================================

CREATE TABLE configurations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    type VARCHAR(20) NOT NULL, -- 'nginx' or 'lua'
    description TEXT,
    content TEXT NOT NULL,
    checksum VARCHAR(64), -- SHA-256 hash
    node_id UUID REFERENCES openresty_nodes(id),
    status VARCHAR(20) DEFAULT 'draft', -- draft, active, archived
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deployed_at TIMESTAMP WITH TIME ZONE,
    variables JSONB DEFAULT '{}',
    metadata JSONB DEFAULT '{}'
);

CREATE TABLE configuration_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    config_id UUID REFERENCES configurations(id) ON DELETE CASCADE,
    version INTEGER NOT NULL,
    content TEXT NOT NULL,
    change_description TEXT,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (config_id, version)
);

CREATE INDEX idx_config_versions_config_id ON configuration_versions(config_id, version DESC);

CREATE TABLE configuration_deployments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    config_id UUID REFERENCES configurations(id),
    version_id UUID REFERENCES configuration_versions(id),
    node_id UUID REFERENCES openresty_nodes(id),
    status VARCHAR(20) DEFAULT 'pending', -- pending, success, failed
    deployed_by UUID REFERENCES users(id),
    deployed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,
    output TEXT,
    error_message TEXT
);

CREATE INDEX idx_config_deployments_config_id ON configuration_deployments(config_id, deployed_at DESC);

-- ============================================
-- Applications & API Keys
-- ============================================

CREATE TABLE applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    owner_id UUID REFERENCES users(id),
    status VARCHAR(20) DEFAULT 'active', -- active, disabled, archived
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'
);

CREATE TABLE api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID REFERENCES applications(id) ON DELETE CASCADE,
    key_hash VARCHAR(255) UNIQUE NOT NULL, -- SHA-256 hash
    prefix VARCHAR(20) NOT NULL, -- First 8 chars for display
    name VARCHAR(100),
    rate_limit_quota INTEGER, -- requests per minute
    burst_quota INTEGER, -- burst capacity
    status VARCHAR(20) DEFAULT 'active',
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE,
    last_used_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB DEFAULT '{}'
);

CREATE INDEX idx_api_keys_application_id ON api_keys(application_id);
CREATE INDEX idx_api_keys_prefix ON api_keys(prefix);

-- ============================================
-- Routes & Rate Limiting
-- ============================================

CREATE TABLE routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID REFERENCES applications(id),
    path VARCHAR(500) NOT NULL,
    methods JSONB NOT NULL DEFAULT '[]', -- ['GET', 'POST', ...]
    upstream_url VARCHAR(500) NOT NULL,
    strip_prefix BOOLEAN DEFAULT false,
    rate_limit_enabled BOOLEAN DEFAULT true,
    rate_limit_policy JSONB DEFAULT '{}', -- {limit: 100, window: 60, algorithm: "token-bucket"}
    auth_required BOOLEAN DEFAULT true,
    status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'
);

CREATE INDEX idx_routes_application_id ON routes(application_id);
CREATE INDEX idx_routes_path ON routes(path);

-- ============================================
-- Redis Clusters
-- ============================================

CREATE TABLE redis_clusters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    type VARCHAR(20) DEFAULT 'standalone', -- standalone, sentinel, cluster
    nodes JSONB NOT NULL DEFAULT '[]', -- [{host, port, role}, ...]
    status VARCHAR(20) DEFAULT 'unknown',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    connection_params JSONB DEFAULT '{}'
);

-- ============================================
-- Metrics (Time-Series Data)
-- Option 1: Native PostgreSQL with partitioning
-- Option 2: TimescaleDB extension for better performance
-- ============================================

-- Native PostgreSQL with partitioning
CREATE TABLE metrics (
    id BIGSERIAL,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    metric_name VARCHAR(100) NOT NULL,
    metric_value DOUBLE PRECISION NOT NULL,
    tags JSONB DEFAULT '{}',
    node_id UUID REFERENCES openresty_nodes(id),
    application_id UUID REFERENCES applications(id),
    PRIMARY KEY (id, timestamp)
);

-- Create indexes for common queries
CREATE INDEX idx_metrics_name_timestamp ON metrics(metric_name, timestamp DESC);
CREATE INDEX idx_metrics_node_id ON metrics(node_id, timestamp DESC) WHERE node_id IS NOT NULL;
CREATE INDEX idx_metrics_application_id ON metrics(application_id, timestamp DESC) WHERE application_id IS NOT NULL;

-- Partition by month (optional, for very large datasets)
-- CREATE TABLE metrics_2025_01 PARTITION OF metrics
--     FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

-- ============================================
-- Alerts & Incidents
-- ============================================

CREATE TABLE alert_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    metric_name VARCHAR(100) NOT NULL,
    condition VARCHAR(20) NOT NULL, -- gt, lt, eq, gte, lte
    threshold DOUBLE PRECISION NOT NULL,
    duration_seconds INTEGER DEFAULT 300, -- Alert if condition for X seconds
    severity VARCHAR(20) DEFAULT 'warning', -- info, warning, critical
    enabled BOOLEAN DEFAULT true,
    notification_channels JSONB DEFAULT '[]', -- ['email', 'slack', 'webhook']
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id UUID REFERENCES alert_rules(id),
    status VARCHAR(20) DEFAULT 'firing', -- firing, resolved, acknowledged
    severity VARCHAR(20) DEFAULT 'warning',
    message TEXT NOT NULL,
    details JSONB DEFAULT '{}',
    fired_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    resolved_at TIMESTAMP WITH TIME ZONE,
    acknowledged_by UUID REFERENCES users(id),
    acknowledged_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_alerts_status ON alerts(status, fired_at DESC);

-- ============================================
-- Audit Logs
-- ============================================

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    action VARCHAR(100) NOT NULL, -- config.created, config.deployed, user.login, etc.
    resource_type VARCHAR(50), -- configuration, application, api_key, etc.
    resource_id UUID,
    details JSONB DEFAULT '{}',
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id, created_at DESC);
CREATE INDEX idx_audit_logs_resource ON audit_logs(resource_type, resource_id, created_at DESC);
CREATE INDEX idx_audit_logs_action ON audit_logs(action, created_at DESC);

-- ============================================
-- System Settings
-- ============================================

CREATE TABLE system_settings (
    key VARCHAR(100) PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_by UUID REFERENCES users(id),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert default settings
INSERT INTO system_settings (key, value, description) VALUES
    ('smtp', '{"host": "", "port": 587, "from": "noreply@example.com"}', 'SMTP configuration'),
    ('slack', '{"webhook_url": "", "channel": "#alerts"}', 'Slack integration'),
    ('retention', '{"metrics_days": 30, "logs_days": 7, "audit_logs_days": 90}', 'Data retention policy'),
    ('security', '{"session_timeout_minutes": 60, "max_login_attempts": 5, "password_min_length": 12}', 'Security policies');

-- ============================================
-- Functions & Triggers
-- ============================================

-- Update updated_at timestamp automatically
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to tables with updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_configurations_updated_at BEFORE UPDATE ON configurations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_applications_updated_at BEFORE UPDATE ON applications
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- Initial Data
-- ============================================

-- Create default admin user (password: admin123 - CHANGE THIS!)
INSERT INTO users (username, email, password_hash) VALUES
    ('admin', 'admin@example.com', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzpLaEmc9q');

-- Create default roles
INSERT INTO roles (name, description, permissions) VALUES
    ('admin', 'Full system access', '{"*": true}'),
    ('operator', 'Can manage configs and view metrics', '{"configs": ["read", "write", "deploy"], "metrics": ["read"], "applications": ["read"]}'),
    ('viewer', 'Read-only access', '{"configs": ["read"], "metrics": ["read"], "applications": ["read"]}');

-- Assign admin role to admin user
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id FROM users u, roles r
WHERE u.username = 'admin' AND r.name = 'admin';
```

### Database Diagram

```
┌─────────────┐         ┌──────────────┐
│    users    │◄────────│  user_roles  │
└─────────────┘         └──────┬───────┘
     │                           │
     │                           │
     ▼                           ▼
┌─────────────────────────────────────┐
│             roles                   │
└─────────────────────────────────────┘

┌──────────────────┐         ┌──────────────────────┐
│ openresty_nodes  │─────────┤ configurations       │
└──────────────────┘         ├──────────────────────┤
                             │ configuration_versions│
                             ├──────────────────────┤
                             │ configuration_deploy │
                             └──────────┬───────────┘
                                        │
                                        │
┌──────────────────┐         ┌──────────▼───────────┐
│  applications    │◄────────│       routes         │
├──────────────────┤         └──────────────────────┘
│  api_keys        │
└──────────────────┘

┌──────────────────┐         ┌──────────────────────┐
│  redis_clusters  │         │      metrics         │
└──────────────────┘         │   (time-series)      │
                             └──────────────────────┘

┌──────────────────┐         ┌──────────────────────┐
│  alert_rules     │─────────│       alerts         │
└──────────────────┘         └──────────────────────┘

┌─────────────────────────────────────────┐
│           audit_logs                    │
│  (all user actions tracked)             │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│        system_settings                  │
│  (key-value configuration store)        │
└─────────────────────────────────────────┘
```

---

## Key Features & Modules

### 1. Configuration Management

**Overview:**
Create, edit, validate, and deploy Nginx and Lua configurations for OpenResty gateways.

**Features:**
- **Monaco Editor**: VS Code-powered editor with syntax highlighting for Nginx/Lua
- **Validation**: Real-time config validation using `nginx -t` and `lua syntax check`
- **Versioning**: Git-like version history with diff viewer
- **Rollback**: One-click rollback to any previous version
- **Variables**: Template variables for dynamic configs (e.g., `${upstream_host}`, `${rate_limit}`)
- **AI Assistant**: ChatGPT/Deepseek integration for config suggestions and explanations
- **Cluster Deployment**: Deploy configs to multiple OpenResty nodes simultaneously
- **Dry Run**: Test deployment without applying changes
- **Diff Preview**: Show exact changes before deploying

**User Flow:**
1. User opens Config Editor
2. Selects config or creates new one
3. Edits content with Monaco Editor
4. Clicks "Validate" → Backend runs `nginx -t`
5. If valid, clicks "Deploy" → Shows diff preview
6. Confirms deployment → Config pushed to nodes
7. Nginx reload triggered automatically
8. Status shown in real-time (success/failure)

**API Endpoints:**
- `GET /api/v1/config` - List configs
- `POST /api/v1/config` - Create config
- `PUT /api/v1/config/:id` - Update config
- `POST /api/v1/config/:id/validate` - Validate config
- `POST /api/v1/config/:id/deploy` - Deploy to nodes
- `GET /api/v1/config/:id/versions` - View history
- `POST /api/v1/config/:id/rollback` - Rollback

### 2. Application Management

**Overview:**
Manage applications, API keys, and rate limiting quotas per application.

**Features:**
- **Application CRUD**: Create, view, update, delete applications
- **API Key Management**:
  - Generate secure API keys (UUID-based)
  - Set expiration dates
  - Revoke compromised keys
  - View key usage stats
- **Quota Configuration**:
  - Requests per minute/hour/day
  - Burst capacity
  - Per-route quotas
- **Usage Analytics**:
  - Token consumption charts
  - Rate limit violation counts
  - Top endpoints by traffic
- **Access Control**:
  - Assign application owners
  - Per-application user permissions
- **Export**: Export application config as JSON/YAML

**UI Components:**
- `Applications.vue` - List all apps with search/filter
- `ApplicationDetail.vue` - App overview with metrics
- `ApiKeyManager.vue` - Key CRUD and usage stats
- `QuotaEditor.vue` - Visual quota configuration
- `UsageChart.vue` - Time-series usage visualization

**API Endpoints:**
- `GET /api/v1/applications` - List apps
- `POST /api/v1/applications` - Create app
- `GET /api/v1/applications/:id` - Get details
- `PUT /api/v1/applications/:id/quota` - Update quota
- `POST /api/v1/applications/:id/keys` - Generate API key
- `DELETE /api/v1/applications/:id/keys/:key_id` - Revoke key
- `GET /api/v1/applications/:id/metrics` - Get usage metrics

### 3. Real-time Monitoring Dashboard

**Overview:**
Live dashboard showing rate limiting metrics, system health, and alerts.

**Features:**
- **Summary Cards**:
  - Total RPS (requests per second)
  - Rate limit violations (with trend)
  - Active applications
  - Redis memory usage
- **Live Charts**:
  - Request rate over time
  - Token bucket usage (per app)
  - Latency percentiles (p50, p95, p99)
  - Error rates
- **Top Consumers**: List of top applications/keys by request count
- **Live Request Stream**: Real-time stream of incoming requests (WebSocket)
- **Alert Panel**: Active alerts with acknowledge button
- **System Status**: OpenResty nodes and Redis cluster health

**Data Sources:**
- **OpenResty Shared Memory**: Read from `lua_shared_dict` metrics
- **Redis INFO**: Memory, connections, keys, hit rate
- **PostgreSQL**: Historical metrics, aggregated stats
- **WebSocket**: Real-time event streaming

**Refresh Strategy:**
- **Real-time**: WebSocket push for live metrics (RPS, violations)
- **Polling**: Every 30s for historical charts
- **On-demand**: User-initiated refresh

### 4. Redis Cluster Monitoring

**Overview:**
Monitor Redis cluster health, memory usage, and rate limit data.

**Features:**
- **Cluster Topology Map**: Visual representation of master/replica nodes
- **Node Status Cards**:
  - CPU, memory, network I/O
  - Connections, commands/sec
  - Hit rate, fragmentation ratio
  - Role (master/slave), master link status
- **Key Browser**:
  - Search keys by pattern
  - View key values (with format detection)
  - Delete keys (with confirmation)
  - Export keys as JSON
- **Slow Log**: View slow queries (from Redis SLOWLOG)
- **Failover Management**: Manual failover triggers
- **Memory Analysis**:
  - Top keys by memory usage
  - Encoding types distribution
  - Expiration stats

**Redis Info Parsing:**
```go
// Example: Parse Redis INFO command output
func ParseRedisInfo(infoRaw string) RedisInfo {
    info := RedisInfo{}
    lines := strings.Split(infoRaw, "\n")

    for _, line := range lines {
        if strings.HasPrefix(line, "#") || line == "" {
            continue
        }

        parts := strings.SplitN(line, ":", 2)
        if len(parts) != 2 {
            continue
        }

        key := strings.TrimSpace(parts[0])
        value := strings.TrimSpace(parts[1])

        switch key {
        case "used_memory_human":
            info.UsedMemory = value
        case "connected_clients":
            info.ConnectedClients = parseInt(value)
        case "instantaneous_ops_per_sec":
            info.OpsPerSec = parseInt(value)
        // ... more fields
        }
    }

    return info
}
```

**API Endpoints:**
- `GET /api/v1/redis/clusters` - List clusters
- `GET /api/v1/redis/clusters/:id` - Cluster details
- `GET /api/v1/redis/clusters/:id/nodes` - Node status
- `GET /api/v1/redis/clusters/:id/metrics` - Cluster metrics
- `GET /api/v1/redis/keys?pattern=*` - Search keys
- `DELETE /api/v1/redis/keys/:key` - Delete key

### 5. Route Configuration

**Overview:**
Configure routes, upstream servers, and rate limiting policies per route.

**Features:**
- **Visual Route Builder**: Form-based route creation (path, methods, upstream)
- **Nginx Config Generator**: Auto-generate Nginx location blocks
- **Rate Limit Policies**:
  - Set limits per route
  - Choose algorithm (token bucket, leaky bucket, fixed window)
  - Configure burst capacity
- **Middleware Configuration**:
  - Auth enabled/disabled
  - CORS settings
  - Request/response transformations
- **Route Testing**: Test route before deploying
- **Import/Export**: Bulk import routes from CSV/JSON

**Route Configuration Example:**
```json
{
  "id": "route_123",
  "path": "/api/v1/users/*",
  "methods": ["GET", "POST"],
  "upstream_url": "http://user-service:8080",
  "strip_prefix": true,
  "rate_limit": {
    "enabled": true,
    "limit": 100,
    "window": 60,
    "burst": 20,
    "algorithm": "token-bucket"
  },
  "auth": {
    "required": true,
    "methods": ["jwt", "api-key"]
  },
  "cors": {
    "enabled": true,
    "origins": ["https://example.com"],
    "methods": ["GET", "POST", "PUT", "DELETE"],
    "headers": ["Content-Type", "Authorization"]
  }
}
```

**Generated Nginx Config:**
```nginx
location /api/v1/users/ {
    set $upstream_uri $request_uri;
    if ($uri ~ ^/api/v1/users/(.*)$) {
        set $upstream_uri /$1;
    }

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=users_limit:10m rate=100r/m;
    limit_req zone=users_limit burst=20 nodelay;

    # Proxy settings
    proxy_pass http://user-service:8080$upstream_uri;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```

### 6. OpenResty Node Management

**Overview:**
Manage multiple OpenResty gateway nodes from a single interface.

**Features:**
- **Node Discovery**: Auto-discover nodes via API
- **Health Checks**: Periodic health checks (HTTP, TCP)
- **Bulk Operations**:
  - Deploy config to all nodes
  - Reload nginx on all nodes
  - Roll out updates with canary deployment
- **Log Streaming**: Tail access/error logs from nodes
- **Terminal**: Web-based SSH terminal to nodes
- **Status Dashboard**:
  - Node status (online/offline/degraded)
  - Worker processes status
  - Active connections
  - Requests per second

**Health Check Logic:**
```go
func (s *NodeService) HealthCheck(node *OpenRestyNode) error {
    client := &http.Client{Timeout: 5 * time.Second}

    // Check API endpoint
    resp, err := client.Get(fmt.Sprintf("http://%s:%d/health", node.Host, node.APIPort))
    if err != nil {
        node.Status = "offline"
        return err
    }
    defer resp.Body.Close()

    if resp.StatusCode != 200 {
        node.Status = "degraded"
        return fmt.Errorf("health check failed: status %d", resp.StatusCode)
    }

    // Parse health response
    var health HealthResponse
    json.NewDecoder(resp.Body).Decode(&health)

    node.Status = "online"
    node.Version = health.Version
    node.WorkerProcesses = health.WorkerProcesses
    node.LastHealthCheckAt = time.Now()

    return nil
}
```

**API Endpoints:**
- `GET /api/v1/openresty/nodes` - List nodes
- `POST /api/v1/openresty/nodes` - Add node
- `GET /api/v1/openresty/nodes/:id` - Node details
- `POST /api/v1/openresty/nodes/:id/reload` - Reload nginx
- `GET /api/v1/openresty/nodes/:id/logs/access` - Tail access logs
- `GET /api/v1/openresty/nodes/:id/logs/error` - Tail error logs

### 7. User Management & RBAC

**Overview:**
Manage users, roles, and permissions with fine-grained access control.

**Features:**
- **User CRUD**: Create, view, update, deactivate users
- **Role Management**: Define roles with custom permissions
- **Permission Matrix**:
  - `configs:read`, `configs:write`, `configs:deploy`
  - `applications:read`, `applications:write`
  - `metrics:read`
  - `users:manage`
  - `settings:manage`
- **SSO Integration**: OAuth2/OIDC support (Google, Azure AD, Okta)
- **Audit Trail**: Log all user actions
- **MFA Support**: Optional TOTP-based 2FA

**Default Roles:**
- **Admin**: Full access to all features
- **Operator**: Can manage configs, deploy, view metrics
- **Viewer**: Read-only access
- **App Owner**: Can manage assigned applications only

**API Endpoints:**
- `GET /api/v1/users` - List users
- `POST /api/v1/users` - Create user
- `PUT /api/v1/users/:id/roles` - Assign roles
- `GET /api/v1/roles` - List roles
- `POST /api/v1/roles` - Create role
- `GET /api/v1/me/activity` - Current user activity

### 8. Alerts & Notifications

**Overview:**
Configure alert rules and receive notifications for critical events.

**Alert Types:**
- **Rate Limit Violations**: High 429 rate
- **Redis High Memory**: Memory usage above threshold
- **Node Offline**: OpenResty node unreachable
- **High Latency**: p95 latency above threshold
- **Config Deployment Failed**: Deployment error
- **API Key Expiring**: Keys near expiration

**Notification Channels:**
- **Email**: SMTP integration
- **Slack**: Webhook to Slack channel
- **PagerDuty**: Trigger incidents
- **Webhook**: Custom webhook URLs
- **In-App**: Toast notifications in UI

**Alert Rule Example:**
```json
{
  "name": "Redis High Memory Alert",
  "metric_name": "redis.memory_usage_percent",
  "condition": "gt",
  "threshold": 85,
  "duration_seconds": 300,
  "severity": "warning",
  "enabled": true,
  "notification_channels": ["email", "slack"]
}
```

**API Endpoints:**
- `GET /api/v1/monitoring/alerts` - List active alerts
- `GET /api/v1/monitoring/alert-rules` - List rules
- `POST /api/v1/monitoring/alert-rules` - Create rule
- `POST /api/v1/monitoring/alerts/:id/acknowledge` - Acknowledge alert

---

## Authentication & Authorization

### JWT-Based Authentication

**Token Structure:**
```json
{
  "sub": "usr_123abc",
  "username": "admin",
  "email": "admin@example.com",
  "roles": ["admin"],
  "permissions": {"*": true},
  "iat": 1704067200,
  "exp": 1704070800
}
```

**Authentication Flow:**
1. User submits login form (`POST /api/v1/auth/login`)
2. Backend validates credentials (bcrypt hash comparison)
3. Backend generates JWT access token (15 min expiry) + refresh token (7 days)
4. Frontend stores tokens in localStorage/memory
5. Frontend sends access token in `Authorization: Bearer <token>` header
6. Backend validates token on each request
7. When access token expires, frontend uses refresh token to get new access token

**RBAC Implementation:**
```go
// Go middleware example
func AuthMiddleware(requiredPermission string) gin.HandlerFunc {
    return func(c *gin.Context) {
        token := c.GetHeader("Authorization")
        if token == "" {
            c.JSON(401, gin.H{"error": "Missing authorization header"})
            c.Abort()
            return
        }

        // Validate JWT
        claims, err := ValidateJWT(token)
        if err != nil {
            c.JSON(401, gin.H{"error": "Invalid token"})
            c.Abort()
            return
        }

        // Check permissions
        if !hasPermission(claims.Permissions, requiredPermission) {
            c.JSON(403, gin.H{"error": "Insufficient permissions"})
            c.Abort()
            return
        }

        // Set user context
        c.Set("user", claims)
        c.Next()
    }
}

func hasPermission(permissions map[string]interface{}, required string) bool {
    // Admin wildcard
    if _, ok := permissions["*"]; ok {
        return true
    }

    // Check specific permission (e.g., "configs:deploy")
    resource, action := parsePermission(required)
    resourcePerms, ok := permissions[resource]
    if !ok {
        return false
    }

    actions := resourcePerms.([]interface{})
    for _, a := range actions {
        if a == action || a == "*" {
            return true
        }
    }

    return false
}
```

### Password Security

- **Hashing**: bcrypt with cost factor 12
- **Requirements**: Min 12 chars, uppercase, lowercase, number, special char
- **MFA**: TOTP (Time-based One-Time Password) support

### Session Management

- **Access Token**: 15 minutes expiry
- **Refresh Token**: 7 days expiry (stored in HTTP-only cookie or DB)
- **Session Timeout**: Configurable (default 60 min inactivity)

---

## OpenResty Integration

### OpenResty Side API (Lua)

The admin console communicates with OpenResty gateways via a Lua-based HTTP API.

**Nginx Config Snippet:**
```nginx
# Admin API endpoint (internal access only)
location /admin/api/ {
    internal;  # Only accessible from internal calls
    allow 127.0.0.1;
    allow 10.0.0.0/8;  # Private network
    deny all;

    content_by_lua_block {
        local action = ngx.var.request_uri:match("/admin/api/(%w+)")

        if action == "metrics" then
            -- Return shared memory metrics
            local metrics = ngx.shared.rate_limit:get_keys()
            ngx.say(ngx.encode_json(metrics))
        elseif action == "reload" then
            -- Trigger nginx reload
            ngx.exec("/admin/reload")
        elseif action == "health" then
            -- Health check response
            ngx.say(ngx.encode_json({
                status = "ok",
                version = ngx.config.nginx_version,
                worker_processes = ngx.worker.count(),
                timestamp = ngx.time()
            }))
        else
            ngx.status = 404
            ngx.say("Not found")
        end
    }
}

# Reload endpoint (with validation)
location = /admin/reload {
    internal;
    allow 127.0.0.1;
    deny all;

    content_by_lua_block {
        -- Test config first
        local handle = io.popen("nginx -t 2>&1")
        local result = handle:read("*a")
        handle:close()

        if result:match("successful") then
            -- Reload nginx
            os.execute("nginx -s reload 2>&1")
            ngx.say(ngx.encode_json({
                status = "success",
                message = "Nginx reloaded successfully"
            }))
        else
            ngx.status = 400
            ngx.say(ngx.encode_json({
                status = "error",
                message = "Config validation failed",
                output = result
            }))
        end
    }
}

# Metrics streaming endpoint
location /admin/stream/metrics {
    internal;
    allow 127.0.0.1;
    deny all;

    content_by_lua_block {
        -- Stream metrics in Server-Sent Events format
        local interval = 1  -- 1 second

        ngx.header["Content-Type"] = "text/event-stream"
        ngx.header["Cache-Control"] = "no-cache"
        ngx.header["Connection"] = "keep-alive"

        while true do
            local metrics = {
                timestamp = ngx.time(),
                rps = ngx.shared.metrics:get("rps") or 0,
                active_connections = ngx.var.connections_active,
                violations = ngx.shared.metrics:get("violations") or 0
            }

            ngx.say("data: " .. ngx.encode_json(metrics) .. "\n\n")
            ngx.flush()

            ngx.sleep(interval)
        end
    }
}
```

### Rate Limiting Data Collection

**Shared Memory Zones:**
```nginx
# Define shared memory zone for metrics
lua_shared_dict rate_limit 100m;
lua_shared_dict metrics 10m;
lua_shared_dict api_keys 10m;

# Update metrics on each request
log_by_lua_block {
    local metrics = ngx.shared.metrics

    -- Increment request counter
    metrics:incr("total_requests", 1, 0)

    -- Update RPS (requests per second)
    local current_rps = metrics:get("rps") or 0
    metrics:set("rps", current_rps + 1)

    -- Log rate limit violations
    if ngx.status == 429 then
        metrics:incr("violations", 1, 0)
    end

    -- Update per-app metrics
    local app_id = ngx.var.http_x_app_id
    if app_id then
        local key = "app:" .. app_id .. ":requests"
        metrics:incr(key, 1, 0)
    end
}
```

### Log Streaming

**Access Log Streaming:**
```go
// Go backend: Tail access logs from OpenResty nodes
func (s *NodeService) StreamAccessLogs(nodeID string, ws *websocket.Conn) {
    node := s.GetNode(nodeID)

    // SSH to node and tail log file
    cmd := exec.Command("ssh", node.Host, "tail -f /var/log/nginx/access.log")
    stdout, _ := cmd.StdoutPipe()

    cmd.Start()

    scanner := bufio.NewScanner(stdout)
    for scanner.Scan() {
        line := scanner.Text()

        // Parse log line (Nginx combined format)
        logEntry := parseAccessLog(line)

        // Send to WebSocket client
        ws.WriteJSON(logEntry)
    }
}

func parseAccessLog(line string) AccessLogEntry {
    // Parse: $remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"
    // ...
    return AccessLogEntry{
        Timestamp: time.Now(),
        IP:        "192.168.1.100",
        Method:    "GET",
        Path:      "/api/v1/users",
        Status:    200,
        Latency:   45 * time.Millisecond,
    }
}
```

---

## Deployment Architecture

### Docker Deployment

**docker-compose.yml:**
```yaml
version: '3.8'

services:
  # PostgreSQL Database
  postgres:
    image: postgres:15-alpine
    container_name: openresty-admin-db
    environment:
      POSTGRES_DB: openresty_admin
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: securepassword
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    networks:
      - openresty-admin

  # Admin Console Backend (Go)
  backend:
    image: openresty-admin-backend:latest
    container_name: openresty-admin-backend
    build:
      context: ./backend
      dockerfile: Dockerfile
    environment:
      DATABASE_URL: postgres://admin:securepassword@postgres:5432/openresty_admin?sslmode=disable
      JWT_SECRET: your-secret-key
      REDIS_URL: redis://redis:6379
    ports:
      - "8080:8080"
    depends_on:
      - postgres
      - redis
    networks:
      - openresty-admin

  # Admin Console Frontend (Vue.js)
  frontend:
    image: openresty-admin-frontend:latest
    container_name: openresty-admin-frontend
    build:
      context: ./frontend
      dockerfile: Dockerfile
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      - backend
    networks:
      - openresty-admin

  # Redis (for caching, sessions)
  redis:
    image: redis:7-alpine
    container_name: openresty-admin-redis
    ports:
      - "6379:6379"
    networks:
      - openresty-admin

volumes:
  postgres_data:

networks:
  openresty-admin:
    driver: bridge
```

### Kubernetes Deployment

**backend-deployment.yaml:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openresty-admin-backend
  namespace: openresty-admin
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: openresty-admin-backend:latest
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: jwt-secret
              key: secret
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5

---
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  namespace: openresty-admin
spec:
  selector:
    app: backend
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
  type: ClusterIP
```

### High-Level Deployment Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Load Balancer (Nginx)                     │
│                      SSL Termination                         │
└─────────────────────────────┬───────────────────────────────┘
                              │
                ┌─────────────┴─────────────┐
                ▼                           ▼
┌───────────────────────────┐   ┌─────────────────────────────┐
│  Admin Console Frontend   │   │  OpenResty Gateway Nodes    │
│  (Vue.js + Nginx)         │   │  (Rate Limiting Gateway)    │
└─────────────┬─────────────┘   └───────────┬─────────────────┘
              │                             │
              │                             │
              ▼                             ▼
┌─────────────────────────────┐   ┌─────────────────────────────┐
│  Admin Console Backend      │   │  Redis Cluster              │
│  (Go API)                   │   │  (Token Bucket Storage)     │
│  - 2 replicas               │   │  - 3 master + 3 replica     │
│  - HPA enabled              │   │  - Sentinel for HA          │
└─────────────┬───────────────┘   └─────────────────────────────┘
              │
              ▼
┌─────────────────────────────┐
│  PostgreSQL                 │
│  (Config & Metrics DB)      │
│  - Primary + 2 replicas     │
│  - TimescaleDB extension    │
└─────────────────────────────┘
```

---

## Security Considerations

### 1. API Security

- **HTTPS Only**: Enforce TLS 1.3 for all API communication
- **Rate Limiting**: Apply rate limiting to admin API itself
- **Input Validation**: Validate all user inputs (SQL injection, XSS prevention)
- **CORS**: Restrict CORS to trusted origins only
- **Secrets Management**: Use HashiCorp Vault or AWS Secrets Manager for secrets

### 2. Authentication & Authorization

- **Strong Passwords**: Enforce password complexity (min 12 chars, mixed case, numbers, symbols)
- **MFA**: Enable TOTP-based 2FA for admin accounts
- **JWT Expiry**: Short-lived access tokens (15 min)
- **Refresh Tokens**: Securely stored in HTTP-only cookies
- **RBAC**: Least privilege principle (no wildcard permissions for operators)

### 3. Network Security

- **Internal API**: OpenResty admin API accessible only from private network
- **Firewall Rules**: Restrict access to admin console (IP whitelisting)
- **VPN**: Require VPN for remote admin access
- **Bastion Host**: Use jump host for SSH access to OpenResty nodes

### 4. Data Protection

- **Encryption at Rest**: Encrypt PostgreSQL data volumes (LUKS, EBS encryption)
- **Encryption in Transit**: TLS for all connections
- **Backup Encryption**: Encrypt backups before storing
- **Audit Logging**: Log all sensitive actions (config changes, user access)

### 5. Secrets Storage

**Never commit secrets to git!** Use environment variables or secret managers:

```yaml
# Kubernetes Secret example
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
stringData:
  url: postgres://admin:securepassword@postgres:5432/openresty_admin
---
apiVersion: v1
kind: Secret
metadata:
  name: jwt-secret
type: Opaque
stringData:
  secret: your-super-secret-jwt-key-min-32-chars
```

---

## Development Roadmap

### Phase 1: MVP (Months 1-3)

**Goal**: Basic configuration management and monitoring

- [ ] Backend API scaffold (Go + Gin/Echo)
- [ ] PostgreSQL schema implementation
- [ ] Basic authentication (JWT)
- [ ] Frontend setup (Vue 3 + TypeScript + Vite)
- [ ] Configuration CRUD operations
- [ ] Config validation (nginx -t integration)
- [ ] Basic dashboard with summary cards
- [ ] Redis cluster monitoring (basic)
- [ ] OpenResty node management (add/list/health check)

**Deliverables**:
- Working admin console with basic config editing
- Deploy to test environment
- User documentation

### Phase 2: Advanced Features (Months 4-6)

**Goal**: Application management, advanced monitoring

- [ ] Application & API key management
- [ ] Rate limiting quota configuration
- [ ] Real-time metrics dashboard (WebSocket)
- [ ] Route configuration UI
- [ ] Config versioning and rollback
- [ ] Alerts & notifications (email + Slack)
- [ ] User management & RBAC
- [ ] Audit logging
- [ ] Web terminal (SSH to nodes)

**Deliverables**:
- Production-ready admin console
- Monitoring and alerting functional
- Multi-user support

### Phase 3: Polish & Scale (Months 7-9)

**Goal**: Performance optimization, integrations

- [ ] AI assistant integration (ChatGPT/Deepseek)
- [ ] Configuration templates
- [ ] Bulk operations (deploy to multiple nodes)
- [ ] Export/import configurations
- [ ] SSO integration (OAuth2/OIDC)
- [ ] Metrics retention policies
- [ ] Performance optimization (caching, DB indexing)
- [ ] Load testing and benchmarking
- [ ] Security audit and hardening

**Deliverables**:
- Scalable architecture (10k+ configurations)
- Enterprise features (SSO, advanced RBAC)
- Security audit passed

### Phase 4: Maintenance & Iteration (Ongoing)

- [ ] Bug fixes and patch releases
- [ ] User feedback-driven improvements
- [ ] New OpenResty feature support
- [ ] Documentation updates
- [ ] Community support (if open source)

---

## Conclusion

This design document provides a comprehensive blueprint for building a modern, scalable admin console for OpenResty-based distributed rate limiting. By drawing inspiration from successful tools like **nginx-ui** and **Nginx Proxy Manager** while specializing in rate limiting management, this system will provide:

1. **Unified Management**: Single interface for configs, apps, routes, monitoring
2. **Real-time Visibility**: Live dashboards with WebSocket streaming
3. **Operational Excellence**: Versioning, rollback, audit trails, alerts
4. **Scalability**: Support for multi-region, multi-cluster deployments
5. **Developer-Friendly**: Modern tech stack (Go + Vue 3 + TypeScript)

The recommended technology stack prioritizes:
- **Performance**: Go backend (low resource usage)
- **UX Excellence**: Vue 3 with modern component libraries
- **Reliability**: PostgreSQL with TimescaleDB for metrics
- **Security**: JWT auth, RBAC, encryption at rest/transit

This architecture is designed to scale from single-node deployments to enterprise-grade, multi-region gateway clusters serving millions of requests per day.

---

## References & Resources

### Tools & Libraries
- [nginx-ui GitHub](https://github.com/0xJacky/nginx-ui) - Inspiration for Go backend + Vue frontend
- [Nginx Proxy Manager](https://nginxproxymanager.com/) - UI/UX reference
- [Naive UI](https://www.naiveui.com/) - Vue 3 component library
- [Monaco Editor](https://microsoft.github.io/monaco-editor/) - Code editor
- [ECharts](https://echarts.apache.org/) - Charting library
- [xterm.js](https://xtermjs.org/) - Web terminal

### Documentation
- [OpenResty Documentation](https://openresty.org/en/documentation.html)
- [Nginx Documentation](https://nginx.org/en/docs/)
- [Redis Best Practices](https://redis.io/docs/manual/admin/)
- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)

### Articles
- [API Gateway Monitoring Metrics (API7)](https://api7.ai/blog/top-10-api-monitoring-metrics)
- [Rate Limiting Best Practices 2025](https://zuplo.com/learning-center/10-best-practices-for-api-rate-limiting-in-2025)
- [Building Real-time Dashboards with React + GraphQL + Redis](https://medium.com/@nowke/building-a-real-time-dashboard-using-react-graphql-subscriptions-and-redis-pubsub-49f5e391a4f9)
- [Monitoring OpenResty Edge](https://doc.openresty.com/en/edge/edge-ops/monitoring-edge/)

---

**Document Version:** 1.0
**Last Updated:** 2025-12-31
**Next Review:** 2025-06-30
