# Frontend Architecture Design Document
## OpenResty Distributed Rate Limiting System - Storage QoS Admin Console

**Technology Stack:**
- Vue 3.5+ (Composition API + `<script setup>`)
- TypeScript 5.3+
- Vite 5.0+
- Naive UI (preferred) or Element Plus
- ECharts 5.4+ for visualization
- Monaco Editor 0.45+ for config editing
- Pinia 2.1+ for state management
- Vue Router 4.2+
- WebSocket + SSE for real-time updates

---

## Table of Contents
1. [Project Structure](#project-structure)
2. [Component Hierarchy](#component-hierarchy)
3. [State Management Architecture](#state-management-architecture)
4. [Routing Design](#routing-design)
5. [Major Feature Areas](#major-feature-areas)
6. [Reusable UI Components](#reusable-ui-components)
7. [API Layer Design](#api-layer-design)
8. [Real-time Communication](#real-time-communication)
9. [TypeScript Type Definitions](#typescript-type-definitions)
10. [Key UI Patterns](#key-ui-patterns)

---

## 1. Project Structure

```
frontend/
├── src/
│   ├── main.ts                          # Application entry point
│   ├── App.vue                          # Root component
│   │
│   ├── assets/                          # Static assets
│   │   ├── styles/
│   │   │   ├── main.scss                # Global styles
│   │   │   ├── variables.scss           # SCSS variables
│   │   │   └── themes/                  # Theme files
│   │   ├── icons/
│   │   └── images/
│   │
│   ├── components/                      # Reusable components
│   │   ├── layout/
│   │   │   ├── AppLayout.vue            # Main layout wrapper
│   │   │   ├── AppSidebar.vue           # Navigation sidebar
│   │   │   ├── AppHeader.vue            # Top header bar
│   │   │   ├── AppBreadcrumb.vue        # Breadcrumb navigation
│   │   │   └── AppFooter.vue            # Footer
│   │   │
│   │   ├── common/
│   │   │   ├── BaseButton.vue
│   │   │   ├── BaseInput.vue
│   │   │   ├── BaseSelect.vue
│   │   │   ├── BaseTable.vue
│   │   │   ├── BaseModal.vue
│   │   │   ├── BaseTooltip.vue
│   │   │   ├── BaseConfirm.vue
│   │   │   └── BaseLoading.vue
│   │   │
│   │   ├── charts/
│   │   │   ├── MetricChart.vue          # Generic metric chart wrapper
│   │   │   ├── TokenUsageChart.vue      # Token bucket usage
│   │   │   ├── IOPSChart.vue            # IOPS over time
│   │   │   ├── BandwidthChart.vue       # Bandwidth over time
│   │   │   ├── RequestRateChart.vue     # Request rate tracking
│   │   │   ├── LatencyChart.vue         # Latency distribution
│   │   │   └── ClusterHealthChart.vue   # Cluster status visualization
│   │   │
│   │   ├── editors/
│   │   │   ├── MonacoEditor.vue         # Monaco editor wrapper
│   │   │   ├── JsonValidator.vue        # JSON validation helper
│   │   │   ├── ConfigDiffViewer.vue     # Configuration diff viewer
│   │   │   └── TokenBucketEditor.vue    # Token bucket config editor
│   │   │
│   │   ├── monitoring/
│   │   │   ├── MetricCard.vue           # Single metric display card
│   │   │   ├── MetricsGrid.vue          # Grid of metric cards
│   │   │   ├── RealtimeCounter.vue      # Real-time updating counter
│   │   │   ├── TokenBucketDisplay.vue   # Token bucket state display
│   │   │   ├── AlertBadge.vue           # Alert indicator badge
│   │   │   └── StatusIndicator.vue      # Status dot/indicator
│   │   │
│   │   ├── tables/
│   │   │   ├── DataTable.vue            # Enhanced data table
│   │   │   ├── SortableTable.vue        # Sortable table wrapper
│   │   │   ├── FilterableTable.vue      # Filterable table wrapper
│   │   │   └── ActionCell.vue           # Action buttons cell
│   │   │
│   │   └── forms/
│   │       ├── FormField.vue            # Form field wrapper
│   │       ├── FormSection.vue          # Form section with title
│   │       ├── ValidationMessage.vue    # Validation error display
│   │       └── ConfigForm.vue           # Configuration form base
│   │
│   ├── views/                           # Page-level components
│   │   ├── Dashboard/
│   │   │   ├── Dashboard.vue            # Main dashboard view
│   │   │   ├── components/
│   │   │   │   ├── ClusterOverview.vue   # Cluster summary cards
│   │   │   │   ├── MetricsOverview.vue   # Key metrics grid
│   │   │   │   ├── RecentAlerts.vue      # Recent alerts list
│   │   │   │   ├── TopApplications.vue   # Top consumers
│   │   │   │   └── SystemHealth.vue      # Health status panel
│   │   │
│   │   ├── Cluster/
│   │   │   ├── ClusterList.vue          # L1 cluster list
│   │   │   ├── ClusterDetail.vue        # Cluster detail view
│   │   │   ├── ClusterForm.vue          # Add/Edit cluster
│   │   │   └── components/
│   │   │       ├── ClusterNodeList.vue   # Node listing
│   │   │       ├── ClusterMetrics.vue    # Cluster-specific metrics
│   │   │       └── ClusterStatus.vue     # Status indicator
│   │   │
│   │   ├── Application/
│   │   │   ├── ApplicationList.vue      # L2 application list
│   │   │   ├── ApplicationDetail.vue    # Application detail view
│   │   │   ├── ApplicationForm.vue      # Add/Edit application
│   │   │   └── components/
│   │   │       ├── ApplicationQuota.vue  # Quota configuration
│   │   │       ├── UsageStats.vue        # Usage statistics
│   │   │       └── TokenBuckets.vue      # Token bucket overview
│   │   │
│   │   ├── TokenBucket/
│   │   │   ├── TokenBucketList.vue      # Token bucket configurations
│   │   │   ├── TokenBucketEditor.vue    # Create/Edit token bucket
│   │   │   ├── TokenBucketViewer.vue    # View token bucket config
│   │   │   └── components/
│   │   │       ├── L1Config.vue          # L1 configuration form
│   │   │       ├── L2Config.vue          # L2 configuration form
│   │   │       ├── L3Config.vue          # L3 configuration form
│   │   │       └── ConfigPreview.vue     # Config JSON preview
│   │   │
│   │   ├── CostRules/
│   │   │   ├── CostRulesList.vue        # Cost rules listing
│   │   │   ├── CostRuleEditor.vue       # Add/Edit cost rule
│   │   │   ├── OperationTypeForm.vue    # Operation type config
│   │   │   └── components/
│   │   │       ├── CostMatrix.vue        # Cost matrix display
│   │   │       └── CostPreview.vue       # Cost calculation preview
│   │   │
│   │   ├── Configuration/
│   │   │   ├── ConfigList.vue           # Configuration versions list
│   │   │   ├── ConfigDetail.vue         # Configuration detail view
│   │   │   ├── ConfigDiff.vue           # Diff viewer for versions
│   │   │   ├── ConfigDeploy.vue         # Deploy configuration
│   │   │   └── components/
│   │   │       ├── VersionHistory.vue    # Version timeline
│   │   │       ├── DiffPanel.vue         # Side-by-side diff
│   │   │       └── DeployStatus.vue      # Deployment progress
│   │   │
│   │   ├── Monitoring/
│   │   │   ├── RealtimeMonitor.vue      # Real-time monitoring dashboard
│   │   │   ├── HistoricalMetrics.vue    # Historical metrics viewer
│   │   │   ├── TokenUsage.vue           # Token usage tracking
│   │   │   ├── RequestAnalytics.vue     # Request analytics
│   │   │   └── components/
│   │   │       ├── LiveMetrics.vue       # Live updating metrics
│   │   │       ├── TimeRangeSelector.vue # Time range picker
│   │   │       └── MetricsExporter.vue   # Export functionality
│   │   │
│   │   ├── RedisCluster/
│   │   │   ├── RedisList.vue            # Redis cluster list
│   │   │   ├── RedisDetail.vue          # Redis cluster detail
│   │   │   ├── RedisNodeMonitor.vue     # Node monitoring
│   │   │   └── components/
│   │   │       ├── NodeHealth.vue        # Node health status
│   │   │       ├── MemoryUsage.vue       # Memory usage display
│   │   │       ├── KeyDistribution.vue   # Key distribution chart
│   │   │       └── ReplicationStatus.vue # Replication info
│   │   │
│   │   ├── Alerts/
│   │   │   ├── AlertList.vue            # Alert listing with filters
│   │   │   ├── AlertDetail.vue          # Alert detail view
│   │   │   ├── AlertRules.vue           # Alert rule management
│   │   │   ├── AlertNotifications.vue   # Notification settings
│   │   │   └── components/
│   │   │       ├── AlertRuleForm.vue     # Rule configuration form
│   │   │       ├── AlertTimeline.vue     # Alert timeline view
│   │   │       └── NotificationConfig.vue # Notification channels
│   │   │
│   │   ├── Users/
│   │   │   ├── UserList.vue             # User listing
│   │   │   ├── UserDetail.vue           # User detail view
│   │   │   ├── UserForm.vue             # Create/Edit user
│   │   │   ├── RoleList.vue             # Role management
│   │   │   ├── RoleForm.vue             # Create/Edit role
│   │   │   └── components/
│   │   │       ├── PermissionTree.vue    # Permission tree selector
│   │   │       └── RoleAssignment.vue    # Role assignment interface
│   │   │
│   │   ├── AuditLogs/
│   │   │   ├── AuditLogList.vue         # Audit log listing
│   │   │   ├── AuditLogDetail.vue       # Log detail view
│   │   │   ├── AuditFilters.vue         # Advanced filter panel
│   │   │   └── components/
│   │   │       ├── LogEntry.vue          # Single log entry
│   │   │       ├── ChangeSummary.vue     # Change summary display
│   │   │       └── ExportLogs.vue        # Log export functionality
│   │   │
│   │   └── Settings/
│   │       ├── SystemSettings.vue       # System-wide settings
│   │       ├── NotificationSettings.vue # Notification preferences
│   │       └── APISettings.vue          # API configuration
│   │
│   ├── stores/                          # Pinia stores
│   │   ├── index.ts                     # Store exports
│   │   ├── modules/
│   │   │   ├── auth.ts                  # Authentication state
│   │   │   ├── user.ts                  # User profile state
│   │   │   ├── cluster.ts               # Cluster state
│   │   │   ├── application.ts           # Application state
│   │   │   ├── tokenBucket.ts           # Token bucket state
│   │   │   ├── costRule.ts              # Cost rule state
│   │   │   ├── configuration.ts         # Configuration state
│   │   │   ├── monitoring.ts            # Monitoring data state
│   │   │   ├── redis.ts                 # Redis cluster state
│   │   │   ├── alert.ts                 # Alert state
│   │   │   ├── notification.ts          # Notification state
│   │   │   └── settings.ts              # Settings state
│   │   └── composables/
│   │       ├── useAuth.ts               # Auth composable
│   │       ├── usePagination.ts         # Pagination helper
│   │       ├── useTable.ts              # Table helper
│   │       ├── useWebSocket.ts          # WebSocket connection
│   │       ├── useNotifications.ts      # Notification system
│   │       └── useExport.ts             # Export functionality
│   │
│   ├── api/                             # API layer
│   │   ├── index.ts                     # Axios instance setup
│   │   ├── endpoints.ts                 # API endpoint definitions
│   │   ├── types.ts                     # API response types
│   │   ├── modules/
│   │   │   ├── auth.ts                  # Authentication APIs
│   │   │   ├── cluster.ts               # Cluster APIs
│   │   │   ├── application.ts           # Application APIs
│   │   │   ├── tokenBucket.ts           # Token bucket APIs
│   │   │   ├── costRule.ts              # Cost rule APIs
│   │   │   ├── configuration.ts         # Configuration APIs
│   │   │   ├── monitoring.ts            # Monitoring APIs
│   │   │   ├── redis.ts                 # Redis APIs
│   │   │   ├── alert.ts                 # Alert APIs
│   │   │   ├── user.ts                  # User management APIs
│   │   │   └── audit.ts                 # Audit log APIs
│   │   └── interceptors/
│   │       ├── request.ts               # Request interceptor
│   │       └── response.ts              # Response interceptor
│   │
│   ├── types/                           # TypeScript type definitions
│   │   ├── index.ts                     # Type exports
│   │   ├── models/
│   │   │   ├── cluster.ts               # Cluster types
│   │   │   ├── application.ts           # Application types
│   │   │   ├── tokenBucket.ts           # Token bucket types
│   │   │   ├── costRule.ts              # Cost rule types
│   │   │   ├── configuration.ts         # Configuration types
│   │   │   ├── monitoring.ts            # Monitoring types
│   │   │   ├── redis.ts                 # Redis types
│   │   │   ├── alert.ts                 # Alert types
│   │   │   ├── user.ts                  # User types
│   │   │   └── audit.ts                 # Audit log types
│   │   ├── api/
│   │   │   ├── request.ts               # API request/response types
│   │   │   └── pagination.ts            # Pagination types
│   │   └── ui/
│   │       ├── table.ts                 # Table UI types
│   │       ├── form.ts                  # Form UI types
│   │       └── chart.ts                 # Chart UI types
│   │
│   ├── utils/                           # Utility functions
│   │   ├── formatters.ts                # Data formatters
│   │   ├── validators.ts                # Form validators
│   │   ├── calculators.ts               # Metric calculations
│   │   ├── chartHelpers.ts              # Chart helpers
│   │   ├── dateHelpers.ts               # Date manipulation
│   │   ├── storage.ts                   # Local storage helpers
│   │   ├── download.ts                  # File download helpers
│   │   └── constants.ts                 # Application constants
│   │
│   ├── composables/                     # Global composables
│   │   ├── useBreakpoints.ts            # Responsive breakpoints
│   │   ├── useDebounce.ts               # Debounce helper
│   │   ├── useThrottle.ts               # Throttle helper
│   │   └── useClipboard.ts              # Clipboard helper
│   │
│   ├── router/                          # Vue Router configuration
│   │   ├── index.ts                     # Router setup
│   │   ├── routes.ts                    # Route definitions
│   │   ├── guards.ts                    # Navigation guards
│   │   └── middleware/
│   │       ├── auth.ts                  # Authentication middleware
│   │       ├── permission.ts            # Permission middleware
│   │       └── telemetry.ts             # Telemetry middleware
│   │
│   ├── directives/                      # Custom directives
│   │   ├── permission.ts                # Permission-based rendering
│   │   ├── loading.ts                   # Loading indicator
│   │   └── clickOutside.ts              # Click outside handler
│   │
│   ├── plugins/                         # Vue plugins
│   │   ├── naive-ui.ts                  # Naive UI setup
│   │   ├── echarts.ts                   # ECharts setup
│   │   └── dayjs.ts                     # Day.js setup
│   │
│   └── config/                          # Application configuration
│       ├── app.ts                       # App config
│       ├── chart.ts                     # Chart config
│       └── api.ts                       # API config
│
├── public/                              # Public assets
│   ├── favicon.ico
│   └── index.html
│
├── tests/                               # Test files
│   ├── unit/
│   ├── integration/
│   └── e2e/
│
├── .env.example                         # Environment variables template
├── .env.development                     # Development environment
├── .env.production                      # Production environment
├── .eslintrc.js                         # ESLint configuration
├── .prettierrc.js                       # Prettier configuration
├── tsconfig.json                        # TypeScript configuration
├── tsconfig.node.json                   # TypeScript config for Node
├── vite.config.ts                       # Vite configuration
├── package.json                         # Dependencies
└── README.md                            # Project documentation
```

---

## 2. Component Hierarchy

### 2.1 Root Components

```
App.vue (Root)
└── AppLayout.vue
    ├── AppSidebar.vue
    ├── AppHeader.vue
    ├── AppBreadcrumb.vue
    └── Router View
        └── [View Components]
```

### 2.2 Layout Components

#### AppLayout.vue
**Purpose:** Main application layout wrapper with responsive design

**Props:**
- None

**State:**
- `sidebarCollapsed: Ref<boolean>` - Sidebar collapse state
- `isMobile: Ref<boolean>` - Mobile device detection

**Child Components:**
- `AppSidebar`
- `AppHeader`
- `AppBreadcrumb`

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useBreakpoints } from '@/composables/useBreakpoints'
import AppSidebar from './AppSidebar.vue'
import AppHeader from './AppHeader.vue'
import AppBreadcrumb from './AppBreadcrumb.vue'

const { isMobile } = useBreakpoints()
const sidebarCollapsed = ref(false)

const layoutClass = computed(() => ({
  'layout--collapsed': sidebarCollapsed.value,
  'layout--mobile': isMobile.value
}))

const toggleSidebar = () => {
  sidebarCollapsed.value = !sidebarCollapsed.value
}

defineExpose({
  toggleSidebar
})
</script>

<template>
  <div class="app-layout" :class="layoutClass">
    <AppSidebar :collapsed="sidebarCollapsed" @toggle="toggleSidebar" />
    <div class="app-layout__main">
      <AppHeader @toggle-sidebar="toggleSidebar" />
      <div class="app-layout__content">
        <AppBreadcrumb />
        <main class="app-layout__view">
          <router-view v-slot="{ Component }">
            <transition name="fade" mode="out-in">
              <component :is="Component" />
            </transition>
          </router-view>
        </main>
      </div>
    </div>
  </div>
</template>
```

#### AppSidebar.vue
**Purpose:** Navigation sidebar with menu items

**Props:**
- `collapsed: boolean` - Collapse state

**Events:**
- `toggle` - Toggle sidebar collapse

**State:**
- Uses `useAuthStore` for user info
- Uses `useRoute` for active route highlighting

**Sample Code:**
```vue
<script setup lang="ts">
import { computed } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { NMenu } from 'naive-ui'
import { useAuthStore } from '@/stores/modules/auth'
import { menuOptions } from '@/config/menu'

interface Props {
  collapsed: boolean
}

const props = defineProps<Props>()
const emit = defineEmits<{
  toggle: []
}>()

const router = useRouter()
const route = useRoute()
const authStore = useAuthStore()

const activeKey = computed(() => route.name as string)
const userPermissions = computed(() => authStore.permissions)

const filteredMenuOptions = computed(() => {
  return menuOptions.filter(item => {
    if (item.permissions) {
      return item.permissions.some(p => userPermissions.value.includes(p))
    }
    return true
  })
})

const handleMenuSelect = (key: string) => {
  router.push({ name: key })
}
</script>

<template>
  <aside class="app-sidebar" :class="{ 'app-sidebar--collapsed': collapsed }">
    <div class="app-sidebar__logo">
      <h1 v-if="!collapsed">Storage QoS</h1>
      <h1 v-else>QoS</h1>
    </div>
    <NMenu
      :collapsed="collapsed"
      :collapsed-width="64"
      :collapsed-icon-size="22"
      :options="filteredMenuOptions"
      :value="activeKey"
      @update:value="handleMenuSelect"
    />
  </aside>
</template>
```

#### AppHeader.vue
**Purpose:** Top header with user info, notifications, settings

**Props:** None

**Events:**
- `toggle-sidebar` - Toggle sidebar

**State:**
- Uses `useAuthStore` for user info
- Uses `useNotificationStore` for notifications

**Child Components:**
- Notification dropdown
- User dropdown
- Theme toggle

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { NButton, NDropdown, NAvatar, NBadge } from 'naive-ui'
import { useAuthStore } from '@/stores/modules/auth'
import { useNotificationStore } from '@/stores/modules/notification'

interface Emits {
  toggleSidebar: []
}

const emit = defineEmits<Emits>()
const router = useRouter()
const authStore = useAuthStore()
const notificationStore = useNotificationStore()

const unreadCount = computed(() => notificationStore.unreadCount)
const userName = computed(() => authStore.user?.name || 'Admin')

const handleLogout = async () => {
  await authStore.logout()
  router.push('/login')
}

const notificationOptions = [
  {
    label: 'Mark all as read',
    key: 'mark-read'
  },
  {
    label: 'Notification settings',
    key: 'settings'
  }
]

const userOptions = [
  {
    label: 'Profile',
    key: 'profile'
  },
  {
    label: 'Settings',
    key: 'settings'
  },
  {
    type: 'divider',
    key: 'd1'
  },
  {
    label: 'Logout',
    key: 'logout'
  }
]

const handleUserSelect = (key: string) => {
  if (key === 'logout') {
    handleLogout()
  } else if (key === 'profile') {
    router.push({ name: 'UserDetail', params: { id: authStore.user?.id } })
  } else if (key === 'settings') {
    router.push({ name: 'Settings' })
  }
}
</script>

<template>
  <header class="app-header">
    <div class="app-header__left">
      <NButton quaternary circle @click="emit('toggle-sidebar')">
        <template #icon>
          <icon-mdi-menu />
        </template>
      </NButton>
    </div>

    <div class="app-header__right">
      <!-- Notifications -->
      <NDropdown :options="notificationOptions" trigger="click">
        <NButton quaternary circle>
          <template #icon>
            <NBadge :value="unreadCount" :max="99">
              <icon-mdi-bell />
            </NBadge>
          </template>
        </NButton>
      </NDropdown>

      <!-- User Menu -->
      <NDropdown :options="userOptions" trigger="click" @select="handleUserSelect">
        <div class="app-header__user">
          <NAvatar round size="small">
            {{ userName.charAt(0) }}
          </NAvatar>
          <span class="app-header__username">{{ userName }}</span>
        </div>
      </NDropdown>
    </div>
  </header>
</template>
```

### 2.3 Dashboard Components

#### Dashboard.vue
**Purpose:** Main dashboard view aggregating all key metrics

**Props:** None

**State:**
- `useDashboardStore` - Dashboard metrics state
- `useClusterStore` - Cluster health state
- `useAlertStore` - Recent alerts state

**Child Components:**
- `ClusterOverview`
- `MetricsOverview`
- `RecentAlerts`
- `TopApplications`
- `SystemHealth`

**API Calls:**
- `GET /api/v1/dashboard/summary` - Dashboard summary data
- `GET /api/v1/dashboard/metrics` - Key metrics
- `GET /api/v1/alerts/recent` - Recent alerts
- `GET /api/v1/applications/top` - Top applications by usage

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, onMounted, computed, watch } from 'vue'
import { useDashboardStore } from '@/stores/modules/dashboard'
import { useClusterStore } from '@/stores/modules/cluster'
import { useAlertStore } from '@/stores/modules/alert'
import { useWebSocket } from '@/stores/composables/useWebSocket'
import ClusterOverview from './components/ClusterOverview.vue'
import MetricsOverview from './components/MetricsOverview.vue'
import RecentAlerts from './components/RecentAlerts.vue'
import TopApplications from './components/TopApplications.vue'
import SystemHealth from './components/SystemHealth.vue'

const dashboardStore = useDashboardStore()
const clusterStore = useClusterStore()
const alertStore = useAlertStore()

const loading = ref(true)
const refreshing = ref(false)

const timeRange = ref('1h') // 15m, 1h, 6h, 24h, 7d

const fetchData = async (showRefreshLoading = false) => {
  try {
    if (showRefreshLoading) refreshing.value = true
    await Promise.all([
      dashboardStore.fetchSummary(),
      dashboardStore.fetchMetrics(timeRange.value),
      alertStore.fetchRecentAlerts(),
      clusterStore.fetchClustersHealth()
    ])
  } finally {
    loading.value = false
    refreshing.value = false
  }
}

onMounted(() => {
  fetchData()

  // Subscribe to WebSocket updates
  const ws = useWebSocket()
  ws.subscribe('dashboard:update', handleDashboardUpdate)
})

const handleDashboardUpdate = (data: any) => {
  dashboardStore.updateMetrics(data)
}

watch(timeRange, () => {
  fetchData(true)
})

defineExpose({
  refresh: () => fetchData(true)
})
</script>

<template>
  <div class="dashboard">
    <div class="dashboard__header">
      <h2>Dashboard</h2>
      <NSelect
        v-model:value="timeRange"
        :options="[
          { label: 'Last 15 minutes', value: '15m' },
          { label: 'Last 1 hour', value: '1h' },
          { label: 'Last 6 hours', value: '6h' },
          { label: 'Last 24 hours', value: '24h' },
          { label: 'Last 7 days', value: '7d' }
        ]"
        style="width: 200px"
      />
    </div>

    <NSpin :show="loading">
      <div class="dashboard__content">
        <!-- Cluster Overview -->
        <ClusterOverview />

        <!-- Key Metrics Grid -->
        <MetricsOverview :time-range="timeRange" />

        <!-- Two Column Layout -->
        <div class="dashboard__row">
          <div class="dashboard__col">
            <!-- Top Applications by Usage -->
            <TopApplications />
          </div>
          <div class="dashboard__col">
            <!-- Recent Alerts -->
            <RecentAlerts />
          </div>
        </div>

        <!-- System Health Panel -->
        <SystemHealth />
      </div>
    </NSpin>
  </div>
</template>
```

#### ClusterOverview.vue
**Purpose:** Display cluster summary cards with health status

**Props:**
- None

**State:**
- `useClusterStore` - Cluster data

**Child Components:**
- `MetricCard` (reused)

**Sample Code:**
```vue
<script setup lang="ts">
import { computed } from 'vue'
import { useClusterStore } from '@/stores/modules/cluster'
import { NGrid, NGridItem } from 'naive-ui'
import MetricCard from '@/components/monitoring/MetricCard.vue'

const clusterStore = useClusterStore()

const stats = computed(() => [
  {
    title: 'Total Clusters',
    value: clusterStore.totalClusters,
    icon: 'mdi-server-network',
    color: '#18a058'
  },
  {
    title: 'Healthy Clusters',
    value: clusterStore.healthyClusters,
    icon: 'mdi-check-circle',
    color: '#18a058'
  },
  {
    title: 'Degraded Clusters',
    value: clusterStore.degradedClusters,
    icon: 'mdi-alert',
    color: '#f0a020'
  },
  {
    title: 'Critical Clusters',
    value: clusterStore.criticalClusters,
    icon: 'mdi-alert-circle',
    color: '#d03050'
  }
])
</script>

<template>
  <div class="cluster-overview">
    <h3>Cluster Overview</h3>
    <NGrid :cols="4" :x-gap="16">
      <NGridItem v-for="stat in stats" :key="stat.title">
        <MetricCard
          :title="stat.title"
          :value="stat.value"
          :icon="stat.icon"
          :color="stat.color"
        />
      </NGridItem>
    </NGrid>
  </div>
</template>
```

#### MetricsOverview.vue
**Purpose:** Display key system metrics in a grid

**Props:**
- `timeRange: string` - Time range for metrics

**State:**
- `useDashboardStore` - Dashboard metrics

**Child Components:**
- `MetricCard`

**Sample Code:**
```vue
<script setup lang="ts">
import { computed } from 'vue'
import { useDashboardStore } from '@/stores/modules/dashboard'
import { NGrid, NGridItem } from 'naive-ui'
import MetricCard from '@/components/monitoring/MetricCard.vue'

interface Props {
  timeRange: string
}

const props = defineProps<Props>()
const dashboardStore = useDashboardStore()

const metrics = computed(() => [
  {
    title: 'Total IOPS',
    value: formatNumber(dashboardStore.metrics.totalIOPS),
    unit: 'ops/s',
    trend: dashboardStore.metrics.iopsTrend,
    icon: 'mdi-speedometer'
  },
  {
    title: 'Total Bandwidth',
    value: formatBytes(dashboardStore.metrics.totalBandwidth),
    unit: '/s',
    trend: dashboardStore.metrics.bandwidthTrend,
    icon: 'mdi-gauge'
  },
  {
    title: 'Active Requests',
    value: formatNumber(dashboardStore.metrics.activeRequests),
    unit: 'req',
    icon: 'mdi-swap-horizontal'
  },
  {
    title: 'Avg Latency',
    value: dashboardStore.metrics.avgLatency.toFixed(2),
    unit: 'ms',
    trend: dashboardStore.metrics.latencyTrend,
    icon: 'mdi-clock'
  },
  {
    title: 'Token Usage',
    value: formatPercent(dashboardStore.metrics.tokenUsage),
    unit: '%',
    icon: 'mdi-ticket'
  },
  {
    title: 'Rate Limit Hits',
    value: formatNumber(dashboardStore.metrics.rateLimitHits),
    unit: 'hits',
    trend: dashboardStore.metrics.rateLimitTrend,
    icon: 'mdi-block-helper'
  }
])
</script>

<template>
  <div class="metrics-overview">
    <h3>System Metrics ({{ timeRange }})</h3>
    <NGrid :cols="3" :x-gap="16" :y-gap="16">
      <NGridItem v-for="metric in metrics" :key="metric.title">
        <MetricCard
          :title="metric.title"
          :value="metric.value"
          :unit="metric.unit"
          :trend="metric.trend"
          :icon="metric.icon"
        />
      </NGridItem>
    </NGrid>
  </div>
</template>
```

### 2.4 Cluster Management Components

#### ClusterList.vue
**Purpose:** List and manage L1 clusters

**Props:** None

**State:**
- `useClusterStore` - Cluster data
- Local state for pagination, filters

**Child Components:**
- `DataTable` - Enhanced table
- `ClusterForm` (modal)
- `ClusterStatus` (inline)

**API Calls:**
- `GET /api/v1/clusters` - List clusters with pagination
- `DELETE /api/v1/clusters/:id` - Delete cluster
- `POST /api/v1/clusters/:id/deploy` - Deploy configuration

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, computed, onMounted, h } from 'vue'
import { useRouter } from 'vue-router'
import { NButton, NTag, NSpace, useDialog } from 'naive-ui'
import { useClusterStore } from '@/stores/modules/cluster'
import { useMessage } from 'naive-ui'
import DataTable from '@/components/tables/DataTable.vue'
import ClusterForm from './ClusterForm.vue'
import ClusterStatus from './components/ClusterStatus.vue'

const router = useRouter()
const dialog = useDialog()
const message = useMessage()
const clusterStore = useClusterStore()

const loading = ref(false)
const showForm = ref(false)
const editingCluster = ref<Cluster | null>(null)

// Pagination
const pagination = ref({
  page: 1,
  pageSize: 20,
  itemCount: 0
})

// Filters
const filters = ref({
  status: '',
  search: ''
})

const columns = computed(() => [
  {
    title: 'Cluster ID',
    key: 'id',
    width: 200,
    render: (row: Cluster) => h('a', {
      onClick: () => viewCluster(row.id)
    }, row.id)
  },
  {
    title: 'Name',
    key: 'name',
    width: 200
  },
  {
    title: 'Status',
    key: 'status',
    width: 120,
    render: (row: Cluster) => h(ClusterStatus, { status: row.status })
  },
  {
    title: 'Region',
    key: 'region',
    width: 150
  },
  {
    title: 'Applications',
    key: 'appCount',
    width: 120,
    render: (row: Cluster) => row.applications?.length || 0
  },
  {
    title: 'Token Capacity',
    key: 'tokenCapacity',
    width: 150,
    render: (row: Cluster) => `${formatNumber(row.tokenCapacity)} tokens/s`
  },
  {
    title: 'Actions',
    key: 'actions',
    width: 200,
    render: (row: Cluster) => h(NSpace, null, {
      default: () => [
        h(NButton, {
          size: 'small',
          onClick: () => editCluster(row)
        }, { default: () => 'Edit' }),
        h(NButton, {
          size: 'small',
          type: 'error',
          onClick: () => deleteCluster(row)
        }, { default: () => 'Delete' })
      ]
    })
  }
])

const fetchClusters = async () => {
  loading.value = true
  try {
    const result = await clusterStore.fetchClusters({
      page: pagination.value.page,
      pageSize: pagination.value.pageSize,
      ...filters.value
    })
    pagination.value.itemCount = result.total
  } finally {
    loading.value = false
  }
}

const viewCluster = (id: string) => {
  router.push({ name: 'ClusterDetail', params: { id } })
}

const editCluster = (cluster: Cluster) => {
  editingCluster.value = cluster
  showForm.value = true
}

const deleteCluster = (cluster: Cluster) => {
  dialog.warning({
    title: 'Delete Cluster',
    content: `Are you sure you want to delete cluster "${cluster.name}"? This action cannot be undone.`,
    positiveText: 'Delete',
    negativeText: 'Cancel',
    onPositiveClick: async () => {
      try {
        await clusterStore.deleteCluster(cluster.id)
        message.success('Cluster deleted successfully')
        await fetchClusters()
      } catch (error) {
        message.error('Failed to delete cluster')
      }
    }
  })
}

const handleFormSubmit = async (data: ClusterFormData) => {
  try {
    if (editingCluster.value) {
      await clusterStore.updateCluster(editingCluster.value.id, data)
      message.success('Cluster updated successfully')
    } else {
      await clusterStore.createCluster(data)
      message.success('Cluster created successfully')
    }
    showForm.value = false
    await fetchClusters()
  } catch (error) {
    message.error('Failed to save cluster')
  }
}

onMounted(() => {
  fetchClusters()
})
</script>

<template>
  <div class="cluster-list">
    <div class="cluster-list__header">
      <h2>L1 Clusters</h2>
      <NButton type="primary" @click="showForm = true; editingCluster = null">
        Add Cluster
      </NButton>
    </div>

    <!-- Filters -->
    <div class="cluster-list__filters">
      <NInput
        v-model:value="filters.search"
        placeholder="Search clusters..."
        clearable
        @update:value="fetchClusters"
      />
      <NSelect
        v-model:value="filters.status"
        placeholder="Filter by status"
        clearable
        :options="[
          { label: 'Active', value: 'active' },
          { label: 'Degraded', value: 'degraded' },
          { label: 'Critical', value: 'critical' }
        ]"
        @update:value="fetchClusters"
      />
    </div>

    <!-- Table -->
    <DataTable
      :columns="columns"
      :data="clusterStore.clusters"
      :loading="loading"
      :pagination="pagination"
      @update:page="fetchClusters"
    />

    <!-- Form Modal -->
    <ClusterForm
      v-if="showForm"
      :cluster="editingCluster"
      @submit="handleFormSubmit"
      @cancel="showForm = false"
    />
  </div>
</template>
```

#### ClusterDetail.vue
**Purpose:** Detailed view of a single cluster

**Props:**
- `id: string` - Cluster ID (from route)

**State:**
- `useClusterStore` - Cluster data
- `useMonitoringStore` - Real-time metrics

**Child Components:**
- `ClusterNodeList`
- `ClusterMetrics`
- `TokenBucketDisplay`

**API Calls:**
- `GET /api/v1/clusters/:id` - Cluster details
- `GET /api/v1/clusters/:id/nodes` - Cluster nodes
- `GET /api/v1/clusters/:id/metrics` - Cluster metrics

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import { NTabs, NTabPane } from 'naive-ui'
import { useClusterStore } from '@/stores/modules/cluster'
import { useMonitoringStore } from '@/stores/modules/monitoring'
import { useWebSocket } from '@/stores/composables/useWebSocket'
import ClusterNodeList from './components/ClusterNodeList.vue'
import ClusterMetrics from './components/ClusterMetrics.vue'
import TokenBucketDisplay from '@/components/monitoring/TokenBucketDisplay.vue'

const route = useRoute()
const clusterStore = useClusterStore()
const monitoringStore = useMonitoringStore()
const ws = useWebSocket()

const clusterId = computed(() => route.params.id as string)
const loading = ref(true)

const cluster = computed(() => clusterStore.currentCluster)

const fetchClusterData = async () => {
  loading.value = true
  try {
    await Promise.all([
      clusterStore.fetchCluster(clusterId.value),
      clusterStore.fetchClusterNodes(clusterId.value),
      monitoringStore.fetchClusterMetrics(clusterId.value)
    ])
  } finally {
    loading.value = false
  }
}

onMounted(async () => {
  await fetchClusterData()

  // Subscribe to real-time updates
  ws.subscribe(`cluster:${clusterId.value}:metrics`, handleMetricsUpdate)
})

onUnmounted(() => {
  ws.unsubscribe(`cluster:${clusterId.value}:metrics`)
})

const handleMetricsUpdate = (data: any) => {
  monitoringStore.updateMetrics(clusterId.value, data)
}
</script>

<template>
  <div class="cluster-detail" v-if="!loading">
    <div class="cluster-detail__header">
      <div>
        <h2>{{ cluster?.name }}</h2>
        <p>{{ cluster?.id }}</p>
      </div>
      <NSpace>
        <NButton @click="$router.go(-1)">Back</NButton>
        <NButton type="primary" @click="editCluster">Edit</NButton>
      </NSpace>
    </div>

    <NTabs type="line" animated>
      <NTabPane name="overview" tab="Overview">
        <ClusterMetrics :cluster-id="clusterId" />
      </NTabPane>

      <NTabPane name="nodes" tab="Nodes">
        <ClusterNodeList :cluster-id="clusterId" />
      </NTabPane>

      <NTabPane name="token-buckets" tab="Token Buckets">
        <TokenBucketDisplay :cluster-id="clusterId" level="L1" />
      </NTabPane>

      <NTabPane name="applications" tab="Applications">
        <!-- Applications list -->
      </NTabPane>
    </NTabs>
  </div>
</template>
```

### 2.5 Application Management Components

#### ApplicationList.vue
**Purpose:** List and manage L2 applications

**Props:** None

**State:**
- `useApplicationStore` - Application data
- Pagination and filters

**Child Components:**
- `DataTable`
- `ApplicationForm` (modal)

**API Calls:**
- `GET /api/v1/applications` - List applications
- `POST /api/v1/applications` - Create application
- `PUT /api/v1/applications/:id` - Update application
- `DELETE /api/v1/applications/:id` - Delete application

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, computed, onMounted, h } from 'vue'
import { useRouter } from 'vue-router'
import { NButton, NProgress, NSpace, NTag } from 'naive-ui'
import { useApplicationStore } from '@/stores/modules/application'
import DataTable from '@/components/tables/DataTable.vue'

const router = useRouter()
const applicationStore = useApplicationStore()

const loading = ref(false)
const showForm = ref(false)
const editingApp = ref<Application | null>(null)

const pagination = ref({
  page: 1,
  pageSize: 20,
  itemCount: 0
})

const columns = computed(() => [
  {
    title: 'Application ID',
    key: 'id',
    width: 200
  },
  {
    title: 'Name',
    key: 'name',
    width: 200
  },
  {
    title: 'Cluster',
    key: 'clusterName',
    width: 150
  },
  {
    title: 'Quota Usage',
    key: 'quotaUsage',
    width: 200,
    render: (row: Application) => h(NProgress, {
      type: 'line',
      percentage: (row.usedTokens / row.quota) * 100,
      indicatorPlacement: 'inside',
      processing: row.quotaExceeded
    })
  },
  {
    title: 'IOPS Limit',
    key: 'iopsLimit',
    width: 120,
    render: (row: Application) => `${formatNumber(row.iopsLimit)} ops/s`
  },
  {
    title: 'Bandwidth Limit',
    key: 'bandwidthLimit',
    width: 150,
    render: (row: Application) => `${formatBytes(row.bandwidthLimit)}/s`
  },
  {
    title: 'Priority',
    key: 'priority',
    width: 100,
    render: (row: Application) => h(NTag, {
      type: row.priority === 'high' ? 'error' : row.priority === 'medium' ? 'warning' : 'default'
    }, { default: () => row.priority })
  },
  {
    title: 'Actions',
    key: 'actions',
    width: 200,
    render: (row: Application) => h(NSpace, null, {
      default: () => [
        h(NButton, {
          size: 'small',
          onClick: () => viewApp(row.id)
        }, { default: () => 'View' }),
        h(NButton, {
          size: 'small',
          onClick: () => editApp(row)
        }, { default: () => 'Edit' })
      ]
    })
  }
])

const fetchApplications = async () => {
  loading.value = true
  try {
    const result = await applicationStore.fetchApplications({
      page: pagination.value.page,
      pageSize: pagination.value.pageSize
    })
    pagination.value.itemCount = result.total
  } finally {
    loading.value = false
  }
}

const viewApp = (id: string) => {
  router.push({ name: 'ApplicationDetail', params: { id } })
}

const editApp = (app: Application) => {
  editingApp.value = app
  showForm.value = true
}

onMounted(() => {
  fetchApplications()
})
</script>

<template>
  <div class="application-list">
    <div class="application-list__header">
      <h2>L2 Applications</h2>
      <NButton type="primary" @click="showForm = true; editingApp = null">
        Add Application
      </NButton>
    </div>

    <DataTable
      :columns="columns"
      :data="applicationStore.applications"
      :loading="loading"
      :pagination="pagination"
      @update:page="fetchApplications"
    />
  </div>
</template>
```

#### ApplicationDetail.vue
**Purpose:** Detailed view of application with quotas and usage

**Props:**
- `id: string` - Application ID (from route)

**State:**
- `useApplicationStore` - Application data
- `useMonitoringStore` - Usage metrics

**Child Components:**
- `ApplicationQuota` - Quota configuration
- `UsageStats` - Usage statistics display
- `TokenBuckets` - Token bucket overview

**API Calls:**
- `GET /api/v1/applications/:id` - Application details
- `GET /api/v1/applications/:id/usage` - Usage statistics
- `GET /api/v1/applications/:id/token-buckets` - Token buckets

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute } from 'vue-router'
import { NTabs, NTabPane, NDescriptions, NDescriptionsItem } from 'naive-ui'
import { useApplicationStore } from '@/stores/modules/application'
import { useMonitoringStore } from '@/stores/modules/monitoring'
import ApplicationQuota from './components/ApplicationQuota.vue'
import UsageStats from './components/UsageStats.vue'
import TokenBuckets from './components/TokenBuckets.vue'

const route = useRoute()
const applicationStore = useApplicationStore()
const monitoringStore = useMonitoringStore()

const appId = computed(() => route.params.id as string)
const loading = ref(true)
const timeRange = ref('1h')

const application = computed(() => applicationStore.currentApplication)
const usageStats = computed(() => monitoringStore.applicationUsage[appId.value])

const fetchData = async () => {
  loading.value = true
  try {
    await Promise.all([
      applicationStore.fetchApplication(appId.value),
      monitoringStore.fetchApplicationUsage(appId.value, timeRange.value)
    ])
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  fetchData()
})

watch(timeRange, () => {
  fetchData()
})
</script>

<template>
  <div class="application-detail" v-if="!loading && application">
    <div class="application-detail__header">
      <div>
        <h2>{{ application.name }}</h2>
        <p>{{ application.id }}</p>
      </div>
      <NButton @click="$router.go(-1)">Back</NButton>
    </div>

    <NDescriptions bordered :column="3">
      <NDescriptionsItem label="Cluster">{{ application.clusterName }}</NDescriptionsItem>
      <NDescriptionsItem label="Priority">{{ application.priority }}</NDescriptionsItem>
      <NDescriptionsItem label="Status">{{ application.status }}</NDescriptionsItem>
      <NDescriptionsItem label="IOPS Limit">{{ formatNumber(application.iopsLimit) }} ops/s</NDescriptionsItem>
      <NDescriptionsItem label="Bandwidth Limit">{{ formatBytes(application.bandwidthLimit) }}/s</NDescriptionsItem>
      <NDescriptionsItem label="Quota">{{ formatNumber(application.quota) }} tokens</NDescriptionsItem>
    </NDescriptions>

    <NTabs type="line" animated class="mt-4">
      <NTabPane name="quota" tab="Quota Configuration">
        <ApplicationQuota :application="application" @updated="fetchData" />
      </NTabPane>

      <NTabPane name="usage" tab="Usage Statistics">
        <UsageStats
          :application-id="appId"
          :stats="usageStats"
          :time-range="timeRange"
          @update:time-range="timeRange = $event"
        />
      </NTabPane>

      <NTabPane name="token-buckets" tab="Token Buckets">
        <TokenBuckets :application-id="appId" />
      </NTabPane>
    </NTabs>
  </div>
</template>
```

### 2.6 Token Bucket Configuration Components

#### TokenBucketList.vue
**Purpose:** List all token bucket configurations across all levels

**Props:**
- `level: 'L1' | 'L2' | 'L3'` - Token bucket level

**State:**
- `useTokenBucketStore` - Token bucket data
- Filters and pagination

**Child Components:**
- `DataTable`
- `TokenBucketEditor` (modal)

**API Calls:**
- `GET /api/v1/token-buckets` - List token buckets
- `GET /api/v1/token-buckets/:id` - Get token bucket details

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { NButton, NTag, NSpace } from 'naive-ui'
import { useTokenBucketStore } from '@/stores/modules/tokenBucket'
import DataTable from '@/components/tables/DataTable.vue'

interface Props {
  level: 'L1' | 'L2' | 'L3'
}

const props = defineProps<Props>()
const tokenBucketStore = useTokenBucketStore()

const loading = ref(false)
const showEditor = ref(false)
const editingBucket = ref<TokenBucket | null>(null)

const tokenBuckets = computed(() =>
  tokenBucketStore.tokenBuckets.filter(tb => tb.level === props.level)
)

const columns = computed(() => [
  {
    title: 'ID',
    key: 'id',
    width: 200
  },
  {
    title: 'Name',
    key: 'name',
    width: 200
  },
  {
    title: 'Level',
    key: 'level',
    width: 100,
    render: (row: TokenBucket) => h(NTag, { type: 'info' }, { default: () => row.level })
  },
  {
    title: 'Capacity',
    key: 'capacity',
    width: 150,
    render: (row: TokenBucket) => `${formatNumber(row.capacity)} tokens/s`
  },
  {
    title: 'Refill Rate',
    key: 'refillRate',
    width: 150,
    render: (row: TokenBucket) => `${formatNumber(row.refillRate)} tokens/s`
  },
  {
    title: 'Parent',
    key: 'parentId',
    width: 200
  },
  {
    title: 'Actions',
    key: 'actions',
    render: (row: TokenBucket) => h(NSpace, null, {
      default: () => [
        h(NButton, {
          size: 'small',
          onClick: () => editBucket(row)
        }, { default: () => 'Edit' })
      ]
    })
  }
])

const fetchBuckets = async () => {
  loading.value = true
  try {
    await tokenBucketStore.fetchTokenBuckets({ level: props.level })
  } finally {
    loading.value = false
  }
}

const editBucket = (bucket: TokenBucket) => {
  editingBucket.value = bucket
  showEditor.value = true
}

onMounted(() => {
  fetchBuckets()
})
</script>

<template>
  <div class="token-bucket-list">
    <div class="token-bucket-list__header">
      <h2>Token Buckets - Level {{ level }}</h2>
      <NButton type="primary" @click="showEditor = true; editingBucket = null">
        Add Token Bucket
      </NButton>
    </div>

    <DataTable
      :columns="columns"
      :data="tokenBuckets"
      :loading="loading"
    />

    <TokenBucketEditor
      v-if="showEditor"
      :token-bucket="editingBucket"
      :level="level"
      @submit="handleSubmit"
      @cancel="showEditor = false"
    />
  </div>
</template>
```

#### TokenBucketEditor.vue
**Purpose:** Create/edit token bucket configuration

**Props:**
- `tokenBucket: TokenBucket | null` - Existing token bucket or null for new
- `level: 'L1' | 'L2' | 'L3'` - Token bucket level

**Events:**
- `submit: (data: TokenBucketFormData)` - Form submission
- `cancel` - Cancel editing

**State:**
- Form state (local)
- Validation state

**Child Components:**
- `L1Config`, `L2Config`, or `L3Config` based on level
- `ConfigPreview`

**API Calls:**
- `POST /api/v1/token-buckets` - Create token bucket
- `PUT /api/v1/token-buckets/:id` - Update token bucket

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { NModal, NForm, NFormItem, NInput, NInputNumber, NSelect } from 'naive-ui'
import { useForm } from '@/composables/useForm'

interface Props {
  tokenBucket: TokenBucket | null
  level: 'L1' | 'L2' | 'L3'
}

interface Emits {
  submit: [data: TokenBucketFormData]
  cancel: []
}

const props = defineProps<Props>()
const emit = defineEmits<Emits>()

const formRef = ref<FormInst>()
const loading = ref(false)

const formValue = ref<TokenBucketFormData>({
  name: '',
  capacity: 1000,
  refillRate: 100,
  parentId: '',
  level: props.level,
  config: {}
})

// Initialize form with existing data
watch(() => props.tokenBucket, (bucket) => {
  if (bucket) {
    formValue.value = { ...bucket }
  }
}, { immediate: true })

const rules = computed(() => ({
  name: {
    required: true,
    message: 'Name is required',
    trigger: 'blur'
  },
  capacity: {
    required: true,
    type: 'number',
    message: 'Capacity must be a positive number',
    trigger: 'blur'
  },
  refillRate: {
    required: true,
    type: 'number',
    message: 'Refill rate must be a positive number',
    trigger: 'blur'
  }
}))

const handleSubmit = async () => {
  try {
    await formRef.value?.validate()
    loading.value = true
    emit('submit', formValue.value)
  } catch (error) {
    // Validation failed
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <NModal
    :show="true"
    preset="card"
    :title="tokenBucket ? 'Edit Token Bucket' : 'Create Token Bucket'"
    style="width: 800px"
    @close="emit('cancel')"
  >
    <NForm
      ref="formRef"
      :model="formValue"
      :rules="rules"
      label-placement="left"
      label-width="150px"
    >
      <NFormItem label="Name" path="name">
        <NInput v-model:value="formValue.name" placeholder="Enter token bucket name" />
      </NFormItem>

      <NFormItem label="Capacity (tokens)" path="capacity">
        <NInputNumber
          v-model:value="formValue.capacity"
          :min="1"
          placeholder="Token capacity"
        />
      </NFormItem>

      <NFormItem label="Refill Rate (tokens/s)" path="refillRate">
        <NInputNumber
          v-model:value="formValue.refillRate"
          :min="1"
          placeholder="Refill rate"
        />
      </NFormItem>

      <!-- Level-specific configuration -->
      <L1Config
        v-if="level === 'L1'"
        v-model="formValue.config"
      />
      <L2Config
        v-if="level === 'L2'"
        v-model="formValue.config"
        :parent-id="formValue.parentId"
      />
      <L3Config
        v-if="level === 'L3'"
        v-model="formValue.config"
        :parent-id="formValue.parentId"
      />

      <!-- Configuration Preview -->
      <ConfigPreview :config="formValue" />
    </NForm>

    <template #footer>
      <NSpace justify="end">
        <NButton @click="emit('cancel')">Cancel</NButton>
        <NButton type="primary" :loading="loading" @click="handleSubmit">
          {{ tokenBucket ? 'Update' : 'Create' }}
        </NButton>
      </NSpace>
    </template>
  </NModal>
</template>
```

### 2.7 Monitoring Components

#### RealtimeMonitor.vue
**Purpose:** Real-time monitoring dashboard with live updates

**Props:** None

**State:**
- `useMonitoringStore` - Monitoring metrics
- WebSocket connection for live updates

**Child Components:**
- `LiveMetrics`
- `TokenUsageChart`
- `IOPSChart`
- `BandwidthChart`
- `RequestRateChart`

**API Calls:**
- `GET /api/v1/monitoring/realtime` - Initial data
- WebSocket updates for live data

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useMonitoringStore } from '@/stores/modules/monitoring'
import { useWebSocket } from '@/stores/composables/useWebSocket'
import LiveMetrics from './components/LiveMetrics.vue'
import TokenUsageChart from '@/components/charts/TokenUsageChart.vue'
import IOPSChart from '@/components/charts/IOPSChart.vue'
import BandwidthChart from '@/components/charts/BandwidthChart.vue'
import RequestRateChart from '@/components/charts/RequestRateChart.vue'

const monitoringStore = useMonitoringStore()
const ws = useWebSocket()

const connected = ref(false)
const metrics = ref<Record<string, any>>({})

const handleWebSocketMessage = (data: any) => {
  if (data.type === 'metrics_update') {
    metrics.value = { ...metrics.value, ...data.metrics }
    monitoringStore.updateRealtimeMetrics(data.metrics)
  }
}

onMounted(async () => {
  // Fetch initial data
  await monitoringStore.fetchRealtimeMetrics()
  metrics.value = monitoringStore.realtimeMetrics

  // Connect to WebSocket
  connected.value = await ws.connect()
  if (connected.value) {
    ws.subscribe('monitoring:realtime', handleWebSocketMessage)
  }
})

onUnmounted(() => {
  if (connected.value) {
    ws.unsubscribe('monitoring:realtime', handleWebSocketMessage)
  }
})
</script>

<template>
  <div class="realtime-monitor">
    <div class="realtime-monitor__header">
      <h2>Real-time Monitoring</h2>
      <div class="status-indicator" :class="{ connected }">
        <div class="dot"></div>
        <span>{{ connected ? 'Connected' : 'Disconnected' }}</span>
      </div>
    </div>

    <!-- Live Metrics Cards -->
    <LiveMetrics :metrics="metrics" />

    <!-- Charts Grid -->
    <div class="realtime-monitor__charts">
      <div class="chart-container">
        <h3>Token Usage</h3>
        <TokenUsageChart :data="metrics.tokenUsage" :live="true" />
      </div>

      <div class="chart-container">
        <h3>IOPS</h3>
        <IOPSChart :data="metrics.iops" :live="true" />
      </div>

      <div class="chart-container">
        <h3>Bandwidth</h3>
        <BandwidthChart :data="metrics.bandwidth" :live="true" />
      </div>

      <div class="chart-container">
        <h3>Request Rate</h3>
        <RequestRateChart :data="metrics.requestRate" :live="true" />
      </div>
    </div>
  </div>
</template>
```

#### TokenUsageChart.vue
**Purpose:** Display token usage over time with live updates

**Props:**
- `data: TokenUsageData[]` - Time series data
- `live: boolean` - Enable live updates

**State:**
- Local chart state
- ECharts instance

**Child Components:** None

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, onMounted, watch, onUnmounted } from 'vue'
import * as echarts from 'echarts'
import { useChart } from '@/composables/useChart'

interface Props {
  data: TokenUsageData[]
  live?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  live: false
})

const chartRef = ref<HTMLDivElement>()
let chartInstance: echarts.ECharts | null = null

const initChart = () => {
  if (!chartRef.value) return

  chartInstance = echarts.init(chartRef.value)
  updateChart()
}

const updateChart = () => {
  if (!chartInstance || !props.data.length) return

  const option = {
    title: {
      text: 'Token Usage',
      left: 'center'
    },
    tooltip: {
      trigger: 'axis',
      formatter: (params: any) => {
        const param = params[0]
        return `${param.axisValue}<br/>Used: ${param.value} tokens`
      }
    },
    xAxis: {
      type: 'category',
      data: props.data.map(d => d.timestamp),
      boundaryGap: false
    },
    yAxis: {
      type: 'value',
      name: 'Tokens',
      axisLabel: {
        formatter: (value: number) => formatNumber(value)
      }
    },
    series: [
      {
        name: 'Token Usage',
        type: 'line',
        data: props.data.map(d => d.used),
        smooth: true,
        areaStyle: {
          color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
            { offset: 0, color: 'rgba(24, 160, 88, 0.3)' },
            { offset: 1, color: 'rgba(24, 160, 88, 0.05)' }
          ])
        },
        lineStyle: {
          color: '#18a058'
        },
        itemStyle: {
          color: '#18a058'
        }
      }
    ],
    animation: props.live ? false : true
  }

  chartInstance.setOption(option)
}

watch(() => props.data, () => {
  updateChart()
}, { deep: true })

onMounted(() => {
  initChart()

  // Resize handler
  window.addEventListener('resize', () => {
    chartInstance?.resize()
  })
})

onUnmounted(() => {
  chartInstance?.dispose()
})
</script>

<template>
  <div ref="chartRef" class="token-usage-chart" style="width: 100%; height: 300px" />
</template>
```

### 2.8 Reusable Chart Components

#### MetricChart.vue
**Purpose:** Generic chart wrapper for consistent styling and behavior

**Props:**
- `title: string` - Chart title
- `data: any[]` - Chart data
- `type: 'line' | 'bar' | 'area' | 'pie'` - Chart type
- `options?: EChartsOption` - Additional ECharts options
- `loading?: boolean` - Loading state
- `live?: boolean` - Enable live updates

**Events:**
- `chart-ready: (instance: ECharts)` - Emitted when chart is ready

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, onMounted, watch, onUnmounted } from 'vue'
import * as echarts from 'echarts'
import type { EChartsOption } from 'echarts'

interface Props {
  title: string
  data: any[]
  type?: 'line' | 'bar' | 'area' | 'pie'
  options?: EChartsOption
  loading?: boolean
  live?: boolean
}

interface Emits {
  chartReady: [instance: echarts.ECharts]
}

const props = withDefaults(defineProps<Props>(), {
  type: 'line',
  loading: false,
  live: false
})

const emit = defineEmits<Emits>()

const chartRef = ref<HTMLDivElement>()
let chartInstance: echarts.ECharts | null = null

const getDefaultOptions = (): EChartsOption => ({
  title: {
    text: props.title,
    left: 'center',
    textStyle: {
      fontSize: 16,
      fontWeight: 600
    }
  },
  tooltip: {
    trigger: props.type === 'pie' ? 'item' : 'axis',
    confine: true
  },
  grid: {
    left: '3%',
    right: '4%',
    bottom: '3%',
    top: '60px',
    containLabel: true
  },
  xAxis: props.type !== 'pie' ? {
    type: 'category',
    boundaryGap: props.type === 'bar'
  } : undefined,
  yAxis: props.type !== 'pie' ? {
    type: 'value'
  } : undefined
})

const initChart = () => {
  if (!chartRef.value) return

  chartInstance = echarts.init(chartRef.value)
  const mergedOptions = { ...getDefaultOptions(), ...props.options }
  chartInstance.setOption(mergedOptions)
  emit('chartReady', chartInstance)
}

const updateChart = () => {
  if (!chartInstance) return

  const mergedOptions = { ...getDefaultOptions(), ...props.options }
  chartInstance.setOption(mergedOptions, props.live)
}

watch(() => props.options, () => {
  updateChart()
}, { deep: true })

onMounted(() => {
  initChart()

  window.addEventListener('resize', () => {
    chartInstance?.resize()
  })
})

onUnmounted(() => {
  chartInstance?.dispose()
})
</script>

<template>
  <div class="metric-chart">
    <NSpin :show="loading">
      <div ref="chartRef" class="metric-chart__container" />
    </NSpin>
  </div>
</template>

<style scoped>
.metric-chart__container {
  width: 100%;
  height: 300px;
}
</style>
```

---

## 3. State Management Architecture

### 3.1 Pinia Store Structure

#### Store: Auth Store (`stores/modules/auth.ts`)

**Purpose:** Manage authentication state and user session

**State:**
```typescript
interface AuthState {
  user: User | null
  token: string | null
  isAuthenticated: boolean
  permissions: string[]
}
```

**Actions:**
- `login(credentials: LoginCredentials)` - Authenticate user
- `logout()` - Clear session
- `refreshToken()` - Refresh access token
- `checkAuth()` - Verify authentication status
- `hasPermission(permission: string)` - Check permission

**Getters:**
- `isAdmin` - Check if user is admin
- `canManageClusters` - Check cluster management permission
- `canManageApplications` - Check application management permission

**Sample Code:**
```typescript
import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { authApi } from '@/api/modules/auth'
import type { User, LoginCredentials } from '@/types/models/user'

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null)
  const token = ref<string | null>(localStorage.getItem('auth_token'))
  const permissions = ref<string[]>([])

  const isAuthenticated = computed(() => !!token.value && !!user.value)
  const isAdmin = computed(() => user.value?.role === 'admin')

  const login = async (credentials: LoginCredentials) => {
    const response = await authApi.login(credentials)
    token.value = response.token
    user.value = response.user
    permissions.value = response.permissions
    localStorage.setItem('auth_token', response.token)
  }

  const logout = async () => {
    try {
      await authApi.logout()
    } finally {
      token.value = null
      user.value = null
      permissions.value = []
      localStorage.removeItem('auth_token')
    }
  }

  const hasPermission = (permission: string) => {
    return isAdmin.value || permissions.value.includes(permission)
  }

  return {
    user,
    token,
    permissions,
    isAuthenticated,
    isAdmin,
    login,
    logout,
    hasPermission
  }
})
```

#### Store: Cluster Store (`stores/modules/cluster.ts`)

**Purpose:** Manage cluster data and operations

**State:**
```typescript
interface ClusterState {
  clusters: Cluster[]
  currentCluster: Cluster | null
  clusterNodes: Record<string, ClusterNode[]>
  totalClusters: number
  healthyClusters: number
  degradedClusters: number
  criticalClusters: number
}
```

**Actions:**
- `fetchClusters(params)` - Get cluster list with filters
- `fetchCluster(id)` - Get single cluster details
- `createCluster(data)` - Create new cluster
- `updateCluster(id, data)` - Update cluster
- `deleteCluster(id)` - Delete cluster
- `fetchClusterNodes(id)` - Get cluster nodes
- `fetchClustersHealth()` - Get health statistics

**Sample Code:**
```typescript
import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { clusterApi } from '@/api/modules/cluster'
import type { Cluster, ClusterFormData } from '@/types/models/cluster'

export const useClusterStore = defineStore('cluster', () => {
  const clusters = ref<Cluster[]>([])
  const currentCluster = ref<Cluster | null>(null)
  const clusterNodes = ref<Record<string, ClusterNode[]>>({})

  const totalClusters = computed(() => clusters.value.length)
  const healthyClusters = computed(() =>
    clusters.value.filter(c => c.status === 'healthy').length
  )
  const degradedClusters = computed(() =>
    clusters.value.filter(c => c.status === 'degraded').length
  )
  const criticalClusters = computed(() =>
    clusters.value.filter(c => c.status === 'critical').length
  )

  const fetchClusters = async (params: any) => {
    const response = await clusterApi.getClusters(params)
    clusters.value = response.data
    return response
  }

  const fetchCluster = async (id: string) => {
    const response = await clusterApi.getCluster(id)
    currentCluster.value = response.data
    return response.data
  }

  const createCluster = async (data: ClusterFormData) => {
    const response = await clusterApi.createCluster(data)
    clusters.value.push(response.data)
    return response.data
  }

  const updateCluster = async (id: string, data: ClusterFormData) => {
    const response = await clusterApi.updateCluster(id, data)
    const index = clusters.value.findIndex(c => c.id === id)
    if (index !== -1) {
      clusters.value[index] = response.data
    }
    return response.data
  }

  const deleteCluster = async (id: string) => {
    await clusterApi.deleteCluster(id)
    clusters.value = clusters.value.filter(c => c.id !== id)
  }

  return {
    clusters,
    currentCluster,
    clusterNodes,
    totalClusters,
    healthyClusters,
    degradedClusters,
    criticalClusters,
    fetchClusters,
    fetchCluster,
    createCluster,
    updateCluster,
    deleteCluster
  }
})
```

#### Store: Monitoring Store (`stores/modules/monitoring.ts`)

**Purpose:** Real-time monitoring data management

**State:**
```typescript
interface MonitoringState {
  realtimeMetrics: Record<string, any>
  historicalMetrics: Record<string, MetricData[]>
  applicationUsage: Record<string, UsageStats>
  clusterMetrics: Record<string, ClusterMetrics>
}
```

**Actions:**
- `fetchRealtimeMetrics()` - Get current metrics
- `fetchHistoricalMetrics(params)` - Get historical data
- `fetchApplicationUsage(id, timeRange)` - Get app usage
- `fetchClusterMetrics(id)` - Get cluster metrics
- `updateRealtimeMetrics(data)` - Update via WebSocket

**Sample Code:**
```typescript
import { defineStore } from 'pinia'
import { ref } from 'vue'
import { monitoringApi } from '@/api/modules/monitoring'
import type { MetricData, UsageStats, ClusterMetrics } from '@/types/models/monitoring'

export const useMonitoringStore = defineStore('monitoring', () => {
  const realtimeMetrics = ref<Record<string, any>>({})
  const historicalMetrics = ref<Record<string, MetricData[]>>({})
  const applicationUsage = ref<Record<string, UsageStats>>({})
  const clusterMetrics = ref<Record<string, ClusterMetrics>>({})

  const fetchRealtimeMetrics = async () => {
    const response = await monitoringApi.getRealtimeMetrics()
    realtimeMetrics.value = response.data
    return response.data
  }

  const fetchHistoricalMetrics = async (params: any) => {
    const response = await monitoringApi.getHistoricalMetrics(params)
    const key = `${params.type}_${params.timeRange}`
    historicalMetrics.value[key] = response.data
    return response.data
  }

  const fetchApplicationUsage = async (appId: string, timeRange: string) => {
    const response = await monitoringApi.getApplicationUsage(appId, timeRange)
    applicationUsage.value[appId] = response.data
    return response.data
  }

  const fetchClusterMetrics = async (clusterId: string) => {
    const response = await monitoringApi.getClusterMetrics(clusterId)
    clusterMetrics.value[clusterId] = response.data
    return response.data
  }

  const updateRealtimeMetrics = (data: any) => {
    realtimeMetrics.value = { ...realtimeMetrics.value, ...data }
  }

  return {
    realtimeMetrics,
    historicalMetrics,
    applicationUsage,
    clusterMetrics,
    fetchRealtimeMetrics,
    fetchHistoricalMetrics,
    fetchApplicationUsage,
    fetchClusterMetrics,
    updateRealtimeMetrics
  }
})
```

#### Store: WebSocket Composable (`stores/composables/useWebSocket.ts`)

**Purpose:** Manage WebSocket connections and subscriptions

**Sample Code:**
```typescript
import { ref, onUnmounted } from 'vue'
import { useAuthStore } from '@/stores/modules/auth'

type MessageHandler = (data: any) => void

class WebSocketManager {
  private ws: WebSocket | null = null
  private subscriptions = new Map<string, Set<MessageHandler>>()
  private reconnectAttempts = 0
  private maxReconnectAttempts = 5
  private reconnectDelay = 1000

  connect(): Promise<boolean> {
    return new Promise((resolve, reject) => {
      const authStore = useAuthStore()
      const token = authStore.token

      const wsUrl = `${import.meta.env.VITE_WS_URL}/ws?token=${token}`

      this.ws = new WebSocket(wsUrl)

      this.ws.onopen = () => {
        console.log('WebSocket connected')
        this.reconnectAttempts = 0
        resolve(true)
      }

      this.ws.onerror = (error) => {
        console.error('WebSocket error:', error)
        reject(error)
      }

      this.ws.onclose = () => {
        console.log('WebSocket disconnected')
        this.reconnect()
      }

      this.ws.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data)
          this.handleMessage(message)
        } catch (error) {
          console.error('Failed to parse WebSocket message:', error)
        }
      }
    })
  }

  private reconnect() {
    if (this.reconnectAttempts < this.maxReconnectAttempts) {
      this.reconnectAttempts++
      const delay = this.reconnectDelay * this.reconnectAttempts
      setTimeout(() => {
        console.log(`Reconnecting... Attempt ${this.reconnectAttempts}`)
        this.connect()
      }, delay)
    }
  }

  subscribe(channel: string, handler: MessageHandler) {
    if (!this.subscriptions.has(channel)) {
      this.subscriptions.set(channel, new Set())
    }
    this.subscriptions.get(channel)!.add(handler)

    // Send subscription message to server
    this.send({
      type: 'subscribe',
      channel
    })
  }

  unsubscribe(channel: string, handler: MessageHandler) {
    const handlers = this.subscriptions.get(channel)
    if (handlers) {
      handlers.delete(handler)
      if (handlers.size === 0) {
        this.subscriptions.delete(channel)
        this.send({
          type: 'unsubscribe',
          channel
        })
      }
    }
  }

  private send(data: any) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data))
    }
  }

  private handleMessage(message: any) {
    const { channel, data } = message
    const handlers = this.subscriptions.get(channel)
    if (handlers) {
      handlers.forEach(handler => handler(data))
    }
  }

  disconnect() {
    this.ws?.close()
    this.subscriptions.clear()
  }
}

let wsManager: WebSocketManager | null = null

export function useWebSocket() {
  if (!wsManager) {
    wsManager = new WebSocketManager()
  }

  onUnmounted(() => {
    // Don't disconnect here as manager is shared
  })

  return wsManager
}
```

### 3.2 Shared State vs Local State

**Shared State (Pinia Stores):**
- User authentication
- Application/cluster lists
- Real-time monitoring data
- Global settings
- Cross-route data

**Local State (Component refs):**
- Form inputs
- UI states (modals, dropdowns)
- Pagination
- Temporary filters
- Component-specific flags

**Example:**
```vue
<script setup lang="ts">
import { ref } from 'vue'
import { useClusterStore } from '@/stores/modules/cluster'

// Shared state - managed by Pinia
const clusterStore = useClusterStore()

// Local state - component-specific
const showForm = ref(false)
const currentPage = ref(1)
const searchQuery = ref('')
</script>
```

---

## 4. Routing Design

### 4.1 Route Structure

```typescript
// router/routes.ts

export const routes: RouteRecordRaw[] = [
  {
    path: '/login',
    name: 'Login',
    component: () => import('@/views/auth/Login.vue'),
    meta: { requiresAuth: false }
  },
  {
    path: '/',
    component: () => import('@/components/layout/AppLayout.vue'),
    meta: { requiresAuth: true },
    children: [
      {
        path: '',
        name: 'Dashboard',
        component: () => import('@/views/Dashboard/Dashboard.vue'),
        meta: {
          title: 'Dashboard',
          icon: 'mdi-view-dashboard',
          permissions: ['dashboard:read']
        }
      },
      {
        path: 'clusters',
        name: 'ClusterList',
        component: () => import('@/views/Cluster/ClusterList.vue'),
        meta: {
          title: 'L1 Clusters',
          icon: 'mdi-server-network',
          permissions: ['cluster:read']
        }
      },
      {
        path: 'clusters/:id',
        name: 'ClusterDetail',
        component: () => import('@/views/Cluster/ClusterDetail.vue'),
        meta: {
          title: 'Cluster Detail',
          permissions: ['cluster:read']
        }
      },
      {
        path: 'applications',
        name: 'ApplicationList',
        component: () => import('@/views/Application/ApplicationList.vue'),
        meta: {
          title: 'L2 Applications',
          icon: 'mdi-application',
          permissions: ['application:read']
        }
      },
      {
        path: 'applications/:id',
        name: 'ApplicationDetail',
        component: () => import('@/views/Application/ApplicationDetail.vue'),
        meta: {
          title: 'Application Detail',
          permissions: ['application:read']
        }
      },
      {
        path: 'token-buckets/:level',
        name: 'TokenBucketList',
        component: () => import('@/views/TokenBucket/TokenBucketList.vue'),
        meta: {
          title: 'Token Buckets',
          icon: 'mdi-ticket',
          permissions: ['token-bucket:read']
        }
      },
      {
        path: 'cost-rules',
        name: 'CostRules',
        component: () => import('@/views/CostRules/CostRulesList.vue'),
        meta: {
          title: 'Cost Rules',
          icon: 'mdi-calculator',
          permissions: ['cost-rule:read']
        }
      },
      {
        path: 'configuration',
        name: 'Configuration',
        component: () => import('@/views/Configuration/ConfigList.vue'),
        meta: {
          title: 'Configuration',
          icon: 'mdi-cog',
          permissions: ['config:read']
        }
      },
      {
        path: 'monitoring',
        name: 'Monitoring',
        component: () => import('@/views/Monitoring/RealtimeMonitor.vue'),
        meta: {
          title: 'Real-time Monitoring',
          icon: 'mdi-chart-line',
          permissions: ['monitoring:read']
        }
      },
      {
        path: 'redis',
        name: 'RedisList',
        component: () => import('@/views/RedisCluster/RedisList.vue'),
        meta: {
          title: 'Redis Clusters',
          icon: 'mdi-database',
          permissions: ['redis:read']
        }
      },
      {
        path: 'alerts',
        name: 'AlertList',
        component: () => import('@/views/Alerts/AlertList.vue'),
        meta: {
          title: 'Alerts',
          icon: 'mdi-bell',
          permissions: ['alert:read']
        }
      },
      {
        path: 'users',
        name: 'UserList',
        component: () => import('@/views/Users/UserList.vue'),
        meta: {
          title: 'Users',
          icon: 'mdi-account',
          permissions: ['user:read'],
          role: 'admin'
        }
      },
      {
        path: 'audit-logs',
        name: 'AuditLogs',
        component: () => import('@/views/AuditLogs/AuditLogList.vue'),
        meta: {
          title: 'Audit Logs',
          icon: 'mdi-file-document',
          permissions: ['audit:read']
        }
      },
      {
        path: 'settings',
        name: 'Settings',
        component: () => import('@/views/Settings/SystemSettings.vue'),
        meta: {
          title: 'Settings',
          icon: 'mdi-cog-outline',
          permissions: ['settings:read']
        }
      }
    ]
  },
  {
    path: '/:pathMatch(.*)*',
    name: 'NotFound',
    component: () => import('@/views/errors/NotFound.vue')
  }
]
```

### 4.2 Navigation Guards

```typescript
// router/guards.ts

import { Router } from 'vue-router'
import { useAuthStore } from '@/stores/modules/auth'
import { useMessage } from 'naive-ui'

export function setupRouterGuards(router: Router) {
  // Auth guard
  router.beforeEach((to, from, next) => {
    const authStore = useAuthStore()
    const requiresAuth = to.matched.some(record => record.meta.requiresAuth !== false)

    if (requiresAuth && !authStore.isAuthenticated) {
      next({
        name: 'Login',
        query: { redirect: to.fullPath }
      })
    } else if (to.name === 'Login' && authStore.isAuthenticated) {
      next({ name: 'Dashboard' })
    } else {
      next()
    }
  })

  // Permission guard
  router.beforeEach((to, from, next) => {
    const authStore = useAuthStore()
    const requiredPermissions = to.meta.permissions as string[] | undefined

    if (requiredPermissions && requiredPermissions.length > 0) {
      const hasPermission = requiredPermissions.some(permission =>
        authStore.hasPermission(permission)
      )

      if (!hasPermission) {
        const message = useMessage()
        message.error('You do not have permission to access this page')
        next({ name: 'Dashboard' })
        return
      }
    }

    next()
  })

  // Role guard
  router.beforeEach((to, from, next) => {
    const authStore = useAuthStore()
    const requiredRole = to.meta.role as string | undefined

    if (requiredRole && authStore.user?.role !== requiredRole) {
      const message = useMessage()
      message.error('This page requires specific role access')
      next({ name: 'Dashboard' })
      return
    }

    next()
  })

  // Page title guard
  router.afterEach((to) => {
    document.title = to.meta.title
      ? `${to.meta.title} - Storage QoS Admin`
      : 'Storage QoS Admin'
  })
}
```

### 4.3 Navigation Patterns

**Breadcrumbs:**
```vue
<!-- AppBreadcrumb.vue -->
<script setup lang="ts">
import { computed } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { NBreadcrumb, NBreadcrumbItem } from 'naive-ui'

const router = useRouter()
const route = useRoute()

const breadcrumbs = computed(() => {
  const matched = route.matched.filter(record => record.meta.title)
  return matched.map(record => ({
    text: record.meta.title,
    path: record.path
  }))
})

const navigate = (path: string) => {
  router.push(path)
}
</script>

<template>
  <NBreadcrumb>
    <NBreadcrumbItem
      v-for="(item, index) in breadcrumbs"
      :key="index"
      @click="navigate(item.path)"
    >
      {{ item.text }}
    </NBreadcrumbItem>
  </NBreadcrumb>
</template>
```

---

## 5. Major Feature Areas - Detailed Components

### 5.1 Dashboard (Completed in Section 2.3)

### 5.2 Cluster Management (Completed in Section 2.4)

### 5.3 Application Management (Completed in Section 2.5)

### 5.4 Token Bucket Configuration (Completed in Section 2.6)

### 5.5 Cost Rules Editor

#### CostRulesList.vue
**Purpose:** List and manage operation cost rules

**Props:** None

**State:**
- `useCostRuleStore` - Cost rule data

**Child Components:**
- `DataTable`
- `CostRuleEditor` (modal)
- `CostMatrix` (inline)

**API Calls:**
- `GET /api/v1/cost-rules` - List cost rules
- `POST /api/v1/cost-rules` - Create cost rule
- `PUT /api/v1/cost-rules/:id` - Update cost rule
- `DELETE /api/v1/cost-rules/:id` - Delete cost rule

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, computed, onMounted, h } from 'vue'
import { NButton, NTag, NSpace } from 'naive-ui'
import { useCostRuleStore } from '@/stores/modules/costRule'
import DataTable from '@/components/tables/DataTable.vue'
import CostRuleEditor from './CostRuleEditor.vue'
import CostMatrix from './components/CostMatrix.vue'

const costRuleStore = useCostRuleStore()
const loading = ref(false)
const showEditor = ref(false)
const editingRule = ref<CostRule | null>(null)

const columns = computed(() => [
  {
    title: 'Rule ID',
    key: 'id',
    width: 200
  },
  {
    title: 'Name',
    key: 'name',
    width: 200
  },
  {
    title: 'Operation Types',
    key: 'operations',
    width: 300,
    render: (row: CostRule) => h(NSpace, { wrap: false }, {
      default: () => row.operations.map(op =>
        h(NTag, { size: 'small' }, { default: () => op })
      )
    })
  },
  {
    title: 'Base Cost',
    key: 'baseCost',
    width: 120,
    render: (row: CostRule) => row.baseCost.toString()
  },
  {
    title: 'Multipliers',
    key: 'multipliers',
    width: 200,
    render: (row: CostRule) => h(CostMatrix, { multipliers: row.multipliers })
  },
  {
    title: 'Actions',
    key: 'actions',
    render: (row: CostRule) => h(NSpace, null, {
      default: () => [
        h(NButton, {
          size: 'small',
          onClick: () => editRule(row)
        }, { default: () => 'Edit' }),
        h(NButton, {
          size: 'small',
          type: 'error',
          onClick: () => deleteRule(row)
        }, { default: () => 'Delete' })
      ]
    })
  }
])

const fetchRules = async () => {
  loading.value = true
  try {
    await costRuleStore.fetchCostRules()
  } finally {
    loading.value = false
  }
}

const editRule = (rule: CostRule) => {
  editingRule.value = rule
  showEditor.value = true
}

const deleteRule = async (rule: CostRule) => {
  await costRuleStore.deleteCostRule(rule.id)
  await fetchRules()
}

onMounted(() => {
  fetchRules()
})
</script>

<template>
  <div class="cost-rules-list">
    <div class="cost-rules-list__header">
      <h2>Cost Rules Configuration</h2>
      <NButton type="primary" @click="showEditor = true; editingRule = null">
        Add Cost Rule
      </NButton>
    </div>

    <DataTable
      :columns="columns"
      :data="costRuleStore.costRules"
      :loading="loading"
    />

    <CostRuleEditor
      v-if="showEditor"
      :cost-rule="editingRule"
      @submit="handleSubmit"
      @cancel="showEditor = false"
    />
  </div>
</template>
```

### 5.6 Configuration Management

#### ConfigList.vue
**Purpose:** View and manage configuration versions

**Props:** None

**State:**
- `useConfigurationStore` - Configuration state

**Child Components:**
- `DataTable`
- `VersionHistory` (modal)
- `ConfigDiff` (modal)

**API Calls:**
- `GET /api/v1/configurations` - List configurations
- `GET /api/v1/configurations/:id` - Get configuration details
- `GET /api/v1/configurations/:id/diff/:compareId` - Get diff

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { NButton, NTag, NSpace } from 'naive-ui'
import { useConfigurationStore } from '@/stores/modules/configuration'
import DataTable from '@/components/tables/DataTable.vue'

const router = useRouter()
const configStore = useConfigurationStore()

const loading = ref(false)
const showDiff = ref(false)
const compareConfig = ref<Configuration | null>(null)

const columns = computed(() => [
  {
    title: 'Version',
    key: 'version',
    width: 100,
    render: (row: Configuration) => `v${row.version}`
  },
  {
    title: 'Created At',
    key: 'createdAt',
    width: 200,
    render: (row: Configuration) => formatDate(row.createdAt)
  },
  {
    title: 'Created By',
    key: 'createdBy',
    width: 150
  },
  {
    title: 'Status',
    key: 'status',
    width: 120,
    render: (row: Configuration) => h(NTag, {
      type: row.status === 'active' ? 'success' : 'default'
    }, { default: () => row.status })
  },
  {
    title: 'Description',
    key: 'description',
    ellipsis: { tooltip: true }
  },
  {
    title: 'Actions',
    key: 'actions',
    width: 250,
    render: (row: Configuration) => h(NSpace, null, {
      default: () => [
        h(NButton, {
          size: 'small',
          onClick: () => viewConfig(row.id)
        }, { default: () => 'View' }),
        h(NButton, {
          size: 'small',
          disabled: row.status === 'active',
          onClick: () => deployConfig(row)
        }, { default: () => 'Deploy' }),
        h(NButton, {
          size: 'small',
          onClick: () => compareWith(row)
        }, { default: () => 'Compare' })
      ]
    })
  }
])

const fetchConfigs = async () => {
  loading.value = true
  try {
    await configStore.fetchConfigurations()
  } finally {
    loading.value = false
  }
}

const viewConfig = (id: string) => {
  router.push({ name: 'ConfigurationDetail', params: { id } })
}

const deployConfig = async (config: Configuration) => {
  await configStore.deployConfiguration(config.id)
}

const compareWith = (config: Configuration) => {
  compareConfig.value = config
  showDiff.value = true
}

onMounted(() => {
  fetchConfigs()
})
</script>

<template>
  <div class="config-list">
    <div class="config-list__header">
      <h2>Configuration History</h2>
      <NButton type="primary" @click="router.push({ name: 'ConfigurationDeploy' })">
        Deploy Configuration
      </NButton>
    </div>

    <DataTable
      :columns="columns"
      :data="configStore.configurations"
      :loading="loading"
    />

    <ConfigDiff
      v-if="showDiff"
      :config="compareConfig"
      :compare-with="configStore.activeConfiguration"
      @close="showDiff = false"
    />
  </div>
</template>
```

### 5.7 Real-time Monitoring (Completed in Section 2.7)

### 5.8 Redis Cluster Monitor

#### RedisList.vue
**Purpose:** List Redis clusters and their health

**Props:** None

**State:**
- `useRedisStore` - Redis cluster data

**Child Components:**
- `DataTable`
- `NodeHealth` (inline)

**API Calls:**
- `GET /api/v1/redis/clusters` - List Redis clusters
- `GET /api/v1/redis/clusters/:id` - Get cluster details
- `GET /api/v1/redis/clusters/:id/nodes` - Get cluster nodes

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, computed, onMounted, h } from 'vue'
import { useRouter } from 'vue-router'
import { NButton, NSpace, NProgress } from 'naive-ui'
import { useRedisStore } from '@/stores/modules/redis'
import DataTable from '@/components/tables/DataTable.vue'
import NodeHealth from './components/NodeHealth.vue'

const router = useRouter()
const redisStore = useRedisStore()

const loading = ref(false)

const columns = computed(() => [
  {
    title: 'Cluster ID',
    key: 'id',
    width: 200
  },
  {
    title: 'Name',
    key: 'name',
    width: 200
  },
  {
    title: 'Status',
    key: 'status',
    width: 120,
    render: (row: RedisCluster) => h(NodeHealth, { status: row.status })
  },
  {
    title: 'Nodes',
    key: 'nodeCount',
    width: 100,
    render: (row: RedisCluster) => `${row.nodes.length} nodes`
  },
  {
    title: 'Memory Usage',
    key: 'memoryUsage',
    width: 200,
    render: (row: RedisCluster) => h(NProgress, {
      type: 'line',
      percentage: (row.usedMemory / row.totalMemory) * 100,
      indicatorPlacement: 'inside'
    })
  },
  {
    title: 'Keys',
    key: 'keyCount',
    width: 120,
    render: (row: RedisCluster) => formatNumber(row.keyCount)
  },
  {
    title: 'Actions',
    key: 'actions',
    render: (row: RedisCluster) => h(NButton, {
      size: 'small',
      onClick: () => viewCluster(row.id)
    }, { default: () => 'View Details' })
  }
])

const fetchClusters = async () => {
  loading.value = true
  try {
    await redisStore.fetchClusters()
  } finally {
    loading.value = false
  }
}

const viewCluster = (id: string) => {
  router.push({ name: 'RedisDetail', params: { id } })
}

onMounted(() => {
  fetchClusters()
})
</script>

<template>
  <div class="redis-list">
    <div class="redis-list__header">
      <h2>Redis Clusters</h2>
    </div>

    <DataTable
      :columns="columns"
      :data="redisStore.clusters"
      :loading="loading"
    />
  </div>
</template>
```

### 5.9 Alert Management

#### AlertList.vue
**Purpose:** List and manage alerts

**Props:** None

**State:**
- `useAlertStore` - Alert data
- Filter state

**Child Components:**
- `DataTable`
- `AlertRuleForm` (modal)

**API Calls:**
- `GET /api/v1/alerts` - List alerts with filters
- `PUT /api/v1/alerts/:id/acknowledge` - Acknowledge alert
- `GET /api/v1/alert-rules` - List alert rules

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, computed, onMounted, h } from 'vue'
import { NButton, NTag, NSpace } from 'naive-ui'
import { useAlertStore } from '@/stores/modules/alert'
import DataTable from '@/components/tables/DataTable.vue'

const alertStore = useAlertStore()
const loading = ref(false)

const filters = ref({
  status: '',
  severity: '',
  timeRange: '24h'
})

const columns = computed(() => [
  {
    title: 'Alert ID',
    key: 'id',
    width: 200
  },
  {
    title: 'Severity',
    key: 'severity',
    width: 120,
    render: (row: Alert) => h(NTag, {
      type: row.severity === 'critical' ? 'error' : row.severity === 'warning' ? 'warning' : 'default'
    }, { default: () => row.severity })
  },
  {
    title: 'Status',
    key: 'status',
    width: 120,
    render: (row: Alert) => h(NTag, {
      type: row.status === 'active' ? 'error' : 'success'
    }, { default: () => row.status })
  },
  {
    title: 'Message',
    key: 'message',
    ellipsis: { tooltip: true }
  },
  {
    title: 'Created At',
    key: 'createdAt',
    width: 200,
    render: (row: Alert) => formatDateTime(row.createdAt)
  },
  {
    title: 'Actions',
    key: 'actions',
    width: 150,
    render: (row: Alert) => h(NSpace, null, {
      default: () => [
        h(NButton, {
          size: 'small',
          disabled: row.status === 'acknowledged',
          onClick: () => acknowledgeAlert(row)
        }, { default: () => 'Acknowledge' })
      ]
    })
  }
])

const fetchAlerts = async () => {
  loading.value = true
  try {
    await alertStore.fetchAlerts(filters.value)
  } finally {
    loading.value = false
  }
}

const acknowledgeAlert = async (alert: Alert) => {
  await alertStore.acknowledgeAlert(alert.id)
  await fetchAlerts()
}

onMounted(() => {
  fetchAlerts()
})
</script>

<template>
  <div class="alert-list">
    <div class="alert-list__header">
      <h2>Alerts</h2>
      <NButton @click="$router.push({ name: 'AlertRules' })">
        Configure Rules
      </NButton>
    </div>

    <div class="alert-list__filters">
      <NSelect
        v-model:value="filters.status"
        placeholder="Filter by status"
        clearable
        :options="[
          { label: 'Active', value: 'active' },
          { label: 'Acknowledged', value: 'acknowledged' },
          { label: 'Resolved', value: 'resolved' }
        ]"
        @update:value="fetchAlerts"
      />
      <NSelect
        v-model:value="filters.severity"
        placeholder="Filter by severity"
        clearable
        :options="[
          { label: 'Critical', value: 'critical' },
          { label: 'Warning', value: 'warning' },
          { label: 'Info', value: 'info' }
        ]"
        @update:value="fetchAlerts"
      />
    </div>

    <DataTable
      :columns="columns"
      :data="alertStore.alerts"
      :loading="loading"
    />
  </div>
</template>
```

### 5.10 User Management

#### UserList.vue
**Purpose:** Manage users and roles

**Props:** None

**State:**
- `useUserStore` - User data

**Child Components:**
- `DataTable`
- `UserForm` (modal)
- `RoleAssignment` (modal)

**API Calls:**
- `GET /api/v1/users` - List users
- `POST /api/v1/users` - Create user
- `PUT /api/v1/users/:id` - Update user
- `DELETE /api/v1/users/:id` - Delete user

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, computed, onMounted, h } from 'vue'
import { NButton, NTag, NSpace } from 'naive-ui'
import { useUserStore } from '@/stores/modules/user'
import DataTable from '@/components/tables/DataTable.vue'

const userStore = useUserStore()
const loading = ref(false)
const showForm = ref(false)
const editingUser = ref<User | null>(null)

const columns = computed(() => [
  {
    title: 'Username',
    key: 'username',
    width: 200
  },
  {
    title: 'Name',
    key: 'name',
    width: 200
  },
  {
    title: 'Email',
    key: 'email',
    width: 250
  },
  {
    title: 'Role',
    key: 'role',
    width: 150,
    render: (row: User) => h(NTag, { type: 'info' }, { default: () => row.role })
  },
  {
    title: 'Status',
    key: 'status',
    width: 120,
    render: (row: User) => h(NTag, {
      type: row.status === 'active' ? 'success' : 'error'
    }, { default: () => row.status })
  },
  {
    title: 'Actions',
    key: 'actions',
    render: (row: User) => h(NSpace, null, {
      default: () => [
        h(NButton, {
          size: 'small',
          onClick: () => editUser(row)
        }, { default: () => 'Edit' }),
        h(NButton, {
          size: 'small',
          onClick: () => assignRoles(row)
        }, { default: () => 'Roles' })
      ]
    })
  }
])

const fetchUsers = async () => {
  loading.value = true
  try {
    await userStore.fetchUsers()
  } finally {
    loading.value = false
  }
}

const editUser = (user: User) => {
  editingUser.value = user
  showForm.value = true
}

const assignRoles = (user: User) => {
  // Open role assignment modal
}

onMounted(() => {
  fetchUsers()
})
</script>

<template>
  <div class="user-list">
    <div class="user-list__header">
      <h2>Users</h2>
      <NButton type="primary" @click="showForm = true; editingUser = null">
        Add User
      </NButton>
    </div>

    <DataTable
      :columns="columns"
      :data="userStore.users"
      :loading="loading"
    />
  </div>
</template>
```

### 5.11 Audit Logs

#### AuditLogList.vue
**Purpose:** View and filter audit logs

**Props:** None

**State:**
- `useAuditStore` - Audit log data
- Filter state

**Child Components:**
- `DataTable`
- `AuditFilters` (sidebar)

**API Calls:**
- `GET /api/v1/audit-logs` - List audit logs with filters

**Sample Code:**
```vue
<script setup lang="ts">
import { ref, computed, onMounted, h } from 'vue'
import { NTag, NButton } from 'naive-ui'
import { useAuditStore } from '@/stores/modules/audit'
import DataTable from '@/components/tables/DataTable.vue'
import AuditFilters from './AuditFilters.vue'

const auditStore = useAuditStore()
const loading = ref(false)
const showFilters = ref(false)

const filters = ref({
  userId: '',
  action: '',
  resourceType: '',
  startDate: null,
  endDate: null
})

const columns = computed(() => [
  {
    title: 'Timestamp',
    key: 'timestamp',
    width: 200,
    render: (row: AuditLog) => formatDateTime(row.timestamp)
  },
  {
    title: 'User',
    key: 'username',
    width: 150
  },
  {
    title: 'Action',
    key: 'action',
    width: 150,
    render: (row: AuditLog) => h(NTag, {}, { default: () => row.action })
  },
  {
    title: 'Resource Type',
    key: 'resourceType',
    width: 150
  },
  {
    title: 'Resource ID',
    key: 'resourceId',
    width: 200
  },
  {
    title: 'IP Address',
    key: 'ipAddress',
    width: 150
  },
  {
    title: 'Details',
    key: 'actions',
    width: 100,
    render: (row: AuditLog) => h(NButton, {
      size: 'small',
      onClick: () => viewDetails(row)
    }, { default: () => 'View' })
  }
])

const fetchLogs = async () => {
  loading.value = true
  try {
    await auditStore.fetchAuditLogs(filters.value)
  } finally {
    loading.value = false
  }
}

const viewDetails = (log: AuditLog) => {
  // Show log details modal
}

onMounted(() => {
  fetchLogs()
})
</script>

<template>
  <div class="audit-log-list">
    <div class="audit-log-list__header">
      <h2>Audit Logs</h2>
      <NSpace>
        <NButton @click="showFilters = !showFilters">
          Filters
        </NButton>
        <NButton @click="exportLogs">
          Export
        </NButton>
      </NSpace>
    </div>

    <AuditFilters
      v-if="showFilters"
      v-model="filters"
      @apply="fetchLogs"
      @reset="filters = {}; fetchLogs()"
    />

    <DataTable
      :columns="columns"
      :data="auditStore.logs"
      :loading="loading"
    />
  </div>
</template>
```

---

## 6. Reusable UI Components

### 6.1 DataTable Component

**Purpose:** Enhanced table with built-in features

**Props:**
```typescript
interface DataTableProps {
  columns: DataTableColumn[]
  data: any[]
  loading?: boolean
  pagination?: PaginationConfig
  selectable?: boolean
  scrollX?: number
}
```

**Sample Code:**
```vue
<script setup lang="ts">
import { computed } from 'vue'
import { NDataTable, NSpin, NEmpty } from 'naive-ui'

interface Props {
  columns: any[]
  data: any[]
  loading?: boolean
  pagination?: any
  selectable?: boolean
  scrollX?: number
}

const props = withDefaults(defineProps<Props>(), {
  loading: false,
  selectable: false,
  scrollX: 1200
})

const isEmpty = computed(() => !props.loading && props.data.length === 0)
</script>

<template>
  <div class="data-table">
    <NSpin :show="loading">
      <NDataTable
        v-if="!isEmpty"
        :columns="columns"
        :data="data"
        :pagination="pagination"
        :scroll-x="scrollX"
        :row-key="(row: any) => row.id"
      />
      <NEmpty v-else description="No data available" />
    </NSpin>
  </div>
</template>
```

### 6.2 Form Components

#### FormField.vue
**Purpose:** Consistent form field wrapper with label and validation

**Props:**
```typescript
interface FormFieldProps {
  label: string
  required?: boolean
  error?: string
  hint?: string
}
```

**Sample Code:**
```vue
<script setup lang="ts">
interface Props {
  label: string
  required?: boolean
  error?: string
  hint?: string
}

withDefaults(defineProps<Props>(), {
  required: false
})
</script>

<template>
  <div class="form-field" :class="{ 'form-field--error': error }">
    <label class="form-field__label">
      {{ label }}
      <span v-if="required" class="form-field__required">*</span>
    </label>
    <div class="form-field__content">
      <slot />
      <p v-if="error" class="form-field__error">{{ error }}</p>
      <p v-else-if="hint" class="form-field__hint">{{ hint }}</p>
    </div>
  </div>
</template>
```

### 6.3 Monitoring Components

#### MetricCard.vue
**Purpose:** Display single metric with icon, value, and trend

**Props:**
```typescript
interface MetricCardProps {
  title: string
  value: string | number
  unit?: string
  icon?: string
  color?: string
  trend?: number // Percentage change
  loading?: boolean
}
```

**Sample Code:**
```vue
<script setup lang="ts">
import { computed } from 'vue'
import { NIcon } from 'naive-ui'

interface Props {
  title: string
  value: string | number
  unit?: string
  icon?: string
  color?: string
  trend?: number
  loading?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  loading: false
})

const trendClass = computed(() => {
  if (!props.trend) return ''
  return props.trend > 0 ? 'trend--up' : 'trend--down'
})

const trendIcon = computed(() => {
  if (!props.trend) return ''
  return props.trend > 0 ? 'mdi-arrow-up' : 'mdi-arrow-down'
})
</script>

<template>
  <div class="metric-card">
    <div class="metric-card__header">
      <NIcon v-if="icon" :size="24" :color="color">
        <component :is="icon" />
      </NIcon>
      <span class="metric-card__title">{{ title }}</span>
    </div>

    <div class="metric-card__value" :style="{ color }">
      {{ loading ? '-' : value }}
      <span v-if="unit" class="metric-card__unit">{{ unit }}</span>
    </div>

    <div v-if="trend !== undefined" class="metric-card__trend" :class="trendClass">
      <NIcon :size="16">
        <component :is="trendIcon" />
      </NIcon>
      <span>{{ Math.abs(trend) }}%</span>
    </div>
  </div>
</template>

<style scoped>
.metric-card {
  padding: 20px;
  background: white;
  border-radius: 8px;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
}

.metric-card__header {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 12px;
}

.metric-card__title {
  font-size: 14px;
  color: #666;
}

.metric-card__value {
  font-size: 32px;
  font-weight: 600;
  margin-bottom: 8px;
}

.metric-card__unit {
  font-size: 16px;
  font-weight: 400;
  color: #999;
}

.metric-card__trend {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 14px;
}

.trend--up {
  color: #18a058;
}

.trend--down {
  color: #d03050;
}
</style>
```

---

## 7. API Layer Design

### 7.1 Axios Instance Setup

```typescript
// api/index.ts

import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse } from 'axios'
import { useAuthStore } from '@/stores/modules/auth'
import { useMessage } from 'naive-ui'

const BASE_URL = import.meta.env.VITE_API_URL || '/api/v1'

class ApiClient {
  private client: AxiosInstance

  constructor() {
    this.client = axios.create({
      baseURL: BASE_URL,
      timeout: 30000,
      headers: {
        'Content-Type': 'application/json'
      }
    })

    this.setupInterceptors()
  }

  private setupInterceptors() {
    // Request interceptor
    this.client.interceptors.request.use(
      (config) => {
        const authStore = useAuthStore()
        if (authStore.token) {
          config.headers.Authorization = `Bearer ${authStore.token}`
        }
        return config
      },
      (error) => {
        return Promise.reject(error)
      }
    )

    // Response interceptor
    this.client.interceptors.response.use(
      (response: AxiosResponse) => {
        return response.data
      },
      (error) => {
        const message = useMessage()

        if (error.response) {
          switch (error.response.status) {
            case 401:
              message.error('Unauthorized. Please login again.')
              const authStore = useAuthStore()
              authStore.logout()
              window.location.href = '/login'
              break
            case 403:
              message.error('You do not have permission to perform this action.')
              break
            case 404:
              message.error('Resource not found.')
              break
            case 500:
              message.error('Server error. Please try again later.')
              break
            default:
              message.error(error.response.data?.message || 'An error occurred.')
          }
        } else if (error.request) {
          message.error('Network error. Please check your connection.')
        } else {
          message.error('An error occurred.')
        }

        return Promise.reject(error)
      }
    )
  }

  public get<T = any>(url: string, config?: AxiosRequestConfig): Promise<T> {
    return this.client.get(url, config)
  }

  public post<T = any>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
    return this.client.post(url, data, config)
  }

  public put<T = any>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
    return this.client.put(url, data, config)
  }

  public patch<T = any>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
    return this.client.patch(url, data, config)
  }

  public delete<T = any>(url: string, config?: AxiosRequestConfig): Promise<T> {
    return this.client.delete(url, config)
  }
}

export const apiClient = new ApiClient()
```

### 7.2 API Modules

#### Cluster API

```typescript
// api/modules/cluster.ts

import { apiClient } from '../index'
import type { Cluster, ClusterFormData, ClusterNode } from '@/types/models/cluster'

export const clusterApi = {
  getClusters(params?: any) {
    return apiClient.get<PaginatedResponse<Cluster>>('/clusters', { params })
  },

  getCluster(id: string) {
    return apiClient.get<Cluster>(`/clusters/${id}`)
  },

  createCluster(data: ClusterFormData) {
    return apiClient.post<Cluster>('/clusters', data)
  },

  updateCluster(id: string, data: ClusterFormData) {
    return apiClient.put<Cluster>(`/clusters/${id}`, data)
  },

  deleteCluster(id: string) {
    return apiClient.delete(`/clusters/${id}`)
  },

  getClusterNodes(id: string) {
    return apiClient.get<ClusterNode[]>(`/clusters/${id}/nodes`)
  },

  getClusterMetrics(id: string, timeRange: string) {
    return apiClient.get(`/clusters/${id}/metrics`, {
      params: { timeRange }
    })
  },

  deployConfig(id: string, configId: string) {
    return apiClient.post(`/clusters/${id}/deploy`, { configId })
  }
}
```

#### Monitoring API

```typescript
// api/modules/monitoring.ts

import { apiClient } from '../index'
import type { MetricData, UsageStats } from '@/types/models/monitoring'

export const monitoringApi = {
  getRealtimeMetrics() {
    return apiClient.get<Record<string, any>>('/monitoring/realtime')
  },

  getHistoricalMetrics(params: {
    type: string
    timeRange: string
    granularity?: string
  }) {
    return apiClient.get<MetricData[]>('/monitoring/historical', { params })
  },

  getApplicationUsage(appId: string, timeRange: string) {
    return apiClient.get<UsageStats>(`/monitoring/applications/${appId}/usage`, {
      params: { timeRange }
    })
  },

  getClusterMetrics(clusterId: string) {
    return apiClient.get(`/monitoring/clusters/${clusterId}/metrics`)
  },

  getTokenBucketStats(bucketId: string) {
    return apiClient.get(`/monitoring/token-buckets/${bucketId}/stats`)
  }
}
```

---

## 8. Real-time Communication

### 8.1 WebSocket Integration

Already covered in Section 3.1 (`useWebSocket` composable)

### 8.2 Server-Sent Events (SSE)

For features that don't need bidirectional communication:

```typescript
// utils/sse.ts

export class SSEClient {
  private eventSource: EventSource | null = null

  connect(url: string, handlers: {
    onMessage?: (data: any) => void
    onError?: (error: Event) => void
    onOpen?: (event: Event) => void
  }) {
    this.eventSource = new EventSource(url)

    this.eventSource.onopen = (event) => {
      handlers.onOpen?.(event)
    }

    this.eventSource.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data)
        handlers.onMessage?.(data)
      } catch (error) {
        console.error('Failed to parse SSE message:', error)
      }
    }

    this.eventSource.onerror = (error) => {
      handlers.onError?.(error)
    }
  }

  disconnect() {
    this.eventSource?.close()
    this.eventSource = null
  }
}

// Usage
export function useSSE(channel: string, onMessage: (data: any) => void) {
  const client = new SSEClient()

  const token = localStorage.getItem('auth_token')
  const url = `${import.meta.env.VITE_API_URL}/sse?token=${token}&channel=${channel}`

  client.connect(url, {
    onMessage,
    onError: (error) => {
      console.error('SSE error:', error)
    }
  })

  onUnmounted(() => {
    client.disconnect()
  })
}
```

---

## 9. TypeScript Type Definitions

### 9.1 Model Types

```typescript
// types/models/cluster.ts

export interface Cluster {
  id: string
  name: string
  region: string
  status: 'healthy' | 'degraded' | 'critical'
  tokenCapacity: number
  applications: Application[]
  createdAt: string
  updatedAt: string
}

export interface ClusterFormData {
  name: string
  region: string
  tokenCapacity: number
}

export interface ClusterNode {
  id: string
  clusterId: string
  host: string
  port: number
  status: 'online' | 'offline'
  metrics: NodeMetrics
}

export interface NodeMetrics {
  cpu: number
  memory: number
  connections: number
  requestsPerSecond: number
}
```

```typescript
// types/models/application.ts

export interface Application {
  id: string
  name: string
  clusterId: string
  clusterName: string
  priority: 'high' | 'medium' | 'low'
  iopsLimit: number
  bandwidthLimit: number
  quota: number
  usedTokens: number
  quotaExceeded: boolean
  status: 'active' | 'inactive' | 'suspended'
  createdAt: string
  updatedAt: string
}

export interface ApplicationFormData {
  name: string
  clusterId: string
  priority: 'high' | 'medium' | 'low'
  iopsLimit: number
  bandwidthLimit: number
  quota: number
}
```

```typescript
// types/models/tokenBucket.ts

export interface TokenBucket {
  id: string
  name: string
  level: 'L1' | 'L2' | 'L3'
  capacity: number
  refillRate: number
  parentId: string | null
  config: Record<string, any>
  children?: TokenBucket[]
  createdAt: string
  updatedAt: string
}

export interface TokenBucketFormData {
  name: string
  level: 'L1' | 'L2' | 'L3'
  capacity: number
  refillRate: number
  parentId: string | null
  config: Record<string, any>
}
```

```typescript
// types/models/monitoring.ts

export interface MetricData {
  timestamp: string
  value: number
  metadata?: Record<string, any>
}

export interface UsageStats {
  applicationId: string
  timeRange: string
  totalIOPS: number
  totalBandwidth: number
  totalRequests: number
  avgLatency: number
  tokenUsage: TokenUsageData[]
}

export interface TokenUsageData {
  timestamp: string
  used: number
  capacity: number
  refillRate: number
}

export interface ClusterMetrics {
  clusterId: string
  nodes: NodeMetrics[]
  aggregate: {
    totalRequests: number
    avgLatency: number
    p95Latency: number
    p99Latency: number
  }
}
```

### 9.2 API Response Types

```typescript
// types/api/request.ts

export interface PaginatedResponse<T> {
  data: T[]
  total: number
  page: number
  pageSize: number
  totalPages: number
}

export interface ApiResponse<T = any> {
  success: boolean
  data: T
  message?: string
  errors?: Record<string, string[]>
}
```

---

## 10. Key UI Patterns

### 10.1 Form Pattern with Validation

```vue
<script setup lang="ts">
import { ref } from 'vue'
import { NForm, NFormItem, NInput, NButton, useMessage } from 'naive-ui'

const formRef = ref<FormInst>()
const message = useMessage()

const formValue = ref({
  name: '',
  capacity: 1000
})

const rules = {
  name: {
    required: true,
    message: 'Name is required',
    trigger: 'blur'
  },
  capacity: {
    required: true,
    type: 'number',
    message: 'Capacity must be a positive number',
    trigger: 'blur',
    validator: (rule: any, value: number) => {
      return value > 0
    }
  }
}

const handleSubmit = async () => {
  try {
    await formRef.value?.validate()
    // Submit form
    message.success('Form submitted successfully')
  } catch (errors) {
    message.error('Please fix the validation errors')
  }
}
</script>

<template>
  <NForm
    ref="formRef"
    :model="formValue"
    :rules="rules"
    label-placement="left"
    label-width="150px"
  >
    <NFormItem label="Name" path="name">
      <NInput v-model:value="formValue.name" />
    </NFormItem>

    <NFormItem label="Capacity" path="capacity">
      <NInputNumber v-model:value="formValue.capacity" />
    </NFormItem>

    <NFormItem>
      <NButton type="primary" @click="handleSubmit">Submit</NButton>
    </NFormItem>
  </NForm>
</template>
```

### 10.2 Table with Sorting/Filtering/Pagination

```vue
<script setup lang="ts">
import { ref, computed } from 'vue'
import { NDataTable, NInput } from 'naive-ui'

const data = ref([...])
const loading = ref(false)
const pagination = ref({
  page: 1,
  pageSize: 20,
  itemCount: 0,
  showSizePicker: true,
  pageSizes: [10, 20, 50, 100]
})

const sortKey = ref<'name' | 'created' | null>(null)
const sortOrder = ref<'ascend' | 'descend' | false>(false)

const filterValue = ref('')

const columns = computed(() => [
  {
    title: 'Name',
    key: 'name',
    sorter: true,
    sortOrder: sortKey.value === 'name' ? sortOrder.value : false
  },
  {
    title: 'Created',
    key: 'created',
    sorter: true,
    sortOrder: sortKey.value === 'created' ? sortOrder.value : false
  }
])

const handleSort = (sort: any) => {
  sortKey.value = sort.columnKey
  sortOrder.value = sort.order
  fetchData()
}

const handlePageChange = (page: number) => {
  pagination.value.page = page
  fetchData()
}

const handlePageSizeChange = (pageSize: number) => {
  pagination.value.pageSize = pageSize
  fetchData()
}
</script>

<template>
  <div>
    <NInput
      v-model:value="filterValue"
      placeholder="Filter..."
      clearable
      @update:value="fetchData"
    />

    <NDataTable
      :columns="columns"
      :data="data"
      :loading="loading"
      :pagination="pagination"
      @update:sorter="handleSort"
      @update:page="handlePageChange"
      @update:page-size="handlePageSizeChange"
    />
  </div>
</template>
```

### 10.3 Real-time Updates Pattern

```vue
<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useWebSocket } from '@/stores/composables/useWebSocket'

const ws = useWebSocket()
const metrics = ref({})
const connected = ref(false)

const handleUpdate = (data: any) => {
  metrics.value = data
}

onMounted(async () => {
  connected.value = await ws.connect()
  if (connected.value) {
    ws.subscribe('metrics:update', handleUpdate)
  }
})

onUnmounted(() => {
  if (connected.value) {
    ws.unsubscribe('metrics:update', handleUpdate)
  }
})
</script>

<template>
  <div>
    <div class="status" :class="{ connected }">
      {{ connected ? 'Live' : 'Disconnected' }}
    </div>
    <!-- Display metrics -->
  </div>
</template>
```

### 10.4 Modal Dialog Pattern

```vue
<script setup lang="ts">
import { ref } from 'vue'
import { NButton, NModal, NCard } from 'naive-ui'

const showModal = ref(false)

const openModal = () => {
  showModal.value = true
}

const closeModal = () => {
  showModal.value = false
}

const handleSubmit = () => {
  // Handle submission
  closeModal()
}
</script>

<template>
  <div>
    <NButton @click="openModal">Open Modal</NButton>

    <NModal
      v-model:show="showModal"
      preset="card"
      title="Edit Item"
      style="width: 600px"
      @close="closeModal"
    >
      <!-- Modal content -->
      <template #footer>
        <NButton @click="closeModal">Cancel</NButton>
        <NButton type="primary" @click="handleSubmit">Submit</NButton>
      </template>
    </NModal>
  </div>
</template>
```

### 10.5 Toast Notification Pattern

```vue
<script setup lang="ts">
import { useMessage } from 'naive-ui'

const message = useMessage()

const showSuccess = () => {
  message.success('Operation completed successfully')
}

const showError = () => {
  message.error('An error occurred')
}

const showWarning = () => {
  message.warning('Please check your input')
}

const showInfo = () => {
  message.info('Processing your request...')
}
</script>
```

---

## Summary

This comprehensive frontend architecture design document provides:

1. **Complete project structure** with organized file hierarchy
2. **Detailed component hierarchy** with samples for all major areas
3. **State management architecture** using Pinia with real-time WebSocket integration
4. **Routing design** with authentication and permission guards
5. **11 major feature areas** fully detailed with component specifications
6. **Reusable UI components** for consistency across the application
7. **API layer design** with Axios configuration and module structure
8. **Real-time communication** via WebSocket and SSE
9. **Complete TypeScript type definitions** for type safety
10. **Key UI patterns** with code samples for common scenarios

The architecture focuses on:
- **Storage QoS specific needs**: IOPS, bandwidth, token bucket visualizations
- **Real-time monitoring**: WebSocket integration for live metrics
- **Multi-tenant management**: Cluster and application hierarchy
- **Developer experience**: TypeScript, composition API, clear structure
- **Performance**: Optimized rendering, lazy loading, efficient state management
- **Maintainability**: Modular design, reusable components, clear patterns

All components follow Vue 3 best practices with the Composition API and TypeScript for type safety.
