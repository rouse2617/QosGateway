<template>
  <div class="dashboard">
    <!-- 加载状态 -->
    <CardSkeleton v-if="metricsStore.loading && !metrics" :show-header="false" :lines="4" />

    <!-- 错误状态 -->
    <ErrorState
      v-else-if="metricsStore.error && !metrics"
      title="加载失败"
      :error-message="metricsStore.error?.message"
      @retry="handleRefresh"
    />

    <template v-else>
      <!-- 概览卡片 -->
      <el-row :gutter="20" class="overview-cards">
        <el-col :xs="12" :sm="6">
          <el-card shadow="hover" class="stat-card">
            <el-statistic
              title="总请求数"
              :value="metrics?.requests_total || 0"
              :precision="0"
            >
              <template #prefix>
                <el-icon color="#409eff"><Document /></el-icon>
              </template>
            </el-statistic>
          </el-card>
        </el-col>
        <el-col :xs="12" :sm="6">
          <el-card shadow="hover" class="stat-card">
            <el-statistic
              title="拒绝请求"
              :value="metrics?.rejected_total || 0"
              :precision="0"
              value-style="color: #f56c6c"
            >
              <template #prefix>
                <el-icon color="#f56c6c"><CircleClose /></el-icon>
              </template>
            </el-statistic>
          </el-card>
        </el-col>
        <el-col :xs="12" :sm="6">
          <el-card shadow="hover" class="stat-card">
            <el-statistic
              title="缓存命中率"
              :value="Number(cacheHitRatioPercent)"
              suffix="%"
              :precision="1"
            >
              <template #prefix>
                <el-icon color="#67c23a"><TrendCharts /></el-icon>
              </template>
            </el-statistic>
          </el-card>
        </el-col>
        <el-col :xs="12" :sm="6">
          <el-card
            shadow="hover"
            class="stat-card"
            :class="{ 'emergency-active': isEmergencyActive }"
          >
            <el-statistic title="系统状态" :value="systemStatusText">
              <template #prefix>
                <el-icon :color="systemStatusColor"><Monitor /></el-icon>
              </template>
            </el-statistic>
          </el-card>
        </el-col>
      </el-row>

      <!-- 图表区域 -->
      <el-row :gutter="20" class="charts-row">
        <el-col :xs="24" :lg="16">
          <el-card shadow="hover">
            <template #header>
              <div class="card-header">
                <span class="card-title">请求趋势</span>
                <el-radio-group v-model="timeRange" size="small">
                  <el-radio-button label="1h">1小时</el-radio-button>
                  <el-radio-button label="6h">6小时</el-radio-button>
                  <el-radio-button label="24h">24小时</el-radio-button>
                </el-radio-group>
              </div>
            </template>
            <v-chart :option="requestChartOption" style="height: 320px" autoresize />
          </el-card>
        </el-col>
        <el-col :xs="24" :lg="8">
          <el-card shadow="hover">
            <template #header>
              <span class="card-title">令牌分布</span>
            </template>
            <v-chart :option="tokenChartOption" style="height: 320px" autoresize />
          </el-card>
        </el-col>
      </el-row>

      <!-- 告警面板 -->
      <el-alert
        v-if="isEmergencyActive"
        type="error"
        :closable="false"
        show-icon
        class="emergency-alert"
      >
        <template #title>
          <div class="alert-content">
            <span>紧急模式已激活，部分低优先级请求可能被限制</span>
            <el-button type="danger" size="small" @click="router.push('/emergency')">
              查看详情
            </el-button>
          </div>
        </template>
      </el-alert>
    </template>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { LineChart, PieChart } from 'echarts/charts'
import {
  GridComponent,
  TooltipComponent,
  LegendComponent,
  TitleComponent
} from 'echarts/components'
import VChart from 'vue-echarts'
import { Document, CircleClose, TrendCharts, Monitor } from '@element-plus/icons-vue'
import { useMetricsStore } from '../stores/metrics'
import { getDegradationLabel, getDegradationType } from '../utils'
import CardSkeleton from '../components/CardSkeleton.vue'
import ErrorState from '../components/ErrorState.vue'

use([
  CanvasRenderer,
  LineChart,
  PieChart,
  GridComponent,
  TooltipComponent,
  LegendComponent,
  TitleComponent
])

const router = useRouter()
const metricsStore = useMetricsStore()
const timeRange = ref<'1h' | '6h' | '24h'>('1h')

const metrics = computed(() => metricsStore.metrics)
const cacheHitRatioPercent = computed(() => metricsStore.cacheHitRatioPercent)
const isEmergencyActive = computed(() => metricsStore.isEmergencyActive)

const systemStatusText = computed(() => {
  if (!metrics.value) return '未知'
  if (metrics.value.emergency_active) return '紧急'
  return getDegradationLabel(metrics.value.degradation_level)
})

const systemStatusColor = computed(() => {
  if (!metrics.value) return '#909399'
  if (metrics.value.emergency_active) return '#f56c6c'
  const type = getDegradationType(metrics.value.degradation_level)
  const colors = { success: '#67c23a', warning: '#e6a23c', danger: '#f56c6c' }
  return colors[type] || '#909399'
})

// 请求趋势图表配置
const requestChartOption = computed(() => ({
  tooltip: {
    trigger: 'axis',
    axisPointer: { type: 'cross' }
  },
  legend: {
    data: ['请求数', '拒绝数'],
    bottom: 0
  },
  grid: {
    left: '3%',
    right: '4%',
    bottom: '15%',
    top: '10%',
    containLabel: true
  },
  xAxis: {
    type: 'category',
    data: ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00'],
    boundaryGap: false
  },
  yAxis: {
    type: 'value',
    name: '请求数'
  },
  series: [
    {
      name: '请求数',
      type: 'line',
      smooth: true,
      data: [120, 200, 150, 80, 70, 110],
      areaStyle: {
        color: {
          type: 'linear',
          x: 0,
          y: 0,
          x2: 0,
          y2: 1,
          colorStops: [
            { offset: 0, color: 'rgba(64, 158, 255, 0.3)' },
            { offset: 1, color: 'rgba(64, 158, 255, 0.05)' }
          ]
        }
      },
      itemStyle: { color: '#409eff' }
    },
    {
      name: '拒绝数',
      type: 'line',
      smooth: true,
      data: [5, 10, 8, 3, 2, 4],
      itemStyle: { color: '#f56c6c' }
    }
  ]
}))

// 令牌分布图表配置
const tokenChartOption = computed(() => ({
  tooltip: {
    trigger: 'item',
    formatter: '{a} <br/>{b}: {c} ({d}%)'
  },
  legend: {
    orient: 'vertical',
    left: 'left',
    bottom: 0
  },
  series: [{
    name: '令牌层级',
    type: 'pie',
    radius: ['40%', '70%'],
    center: ['50%', '45%'],
    avoidLabelOverlap: false,
    itemStyle: {
      borderRadius: 10,
      borderColor: '#fff',
      borderWidth: 2
    },
    label: {
      show: true,
      formatter: '{b}: {d}%'
    },
    emphasis: {
      label: {
        show: true,
        fontSize: 16,
        fontWeight: 'bold'
      }
    },
    data: [
      { value: 60, name: 'L3 本地', itemStyle: { color: '#67c23a' } },
      { value: 30, name: 'L2 应用', itemStyle: { color: '#409eff' } },
      { value: 10, name: 'L1 集群', itemStyle: { color: '#e6a23c' } }
    ]
  }]
}))

/**
 * 刷新数据
 */
async function handleRefresh() {
  await metricsStore.refreshAll()
}

let refreshTimer: number | null = null

onMounted(async () => {
  await handleRefresh()
  // 每5秒自动刷新
  refreshTimer = window.setInterval(() => {
    metricsStore.fetchMetrics().catch(console.error)
  }, 5000)
})

onUnmounted(() => {
  if (refreshTimer) {
    clearInterval(refreshTimer)
    refreshTimer = null
  }
})
</script>

<style scoped>
.dashboard {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.overview-cards {
  margin-bottom: 0;
}

.stat-card {
  text-align: center;
  transition: transform 0.3s ease;
}

.stat-card:hover {
  transform: translateY(-4px);
}

.stat-card :deep(.el-statistic__head) {
  font-size: 14px;
  color: #909399;
  margin-bottom: 8px;
}

.stat-card :deep(.el-statistic__content) {
  font-size: 28px;
  font-weight: 600;
}

.emergency-active {
  border: 2px solid #f56c6c;
  background: linear-gradient(135deg, #fef0f0 0%, #fff 100%);
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex-wrap: wrap;
  gap: 12px;
}

.card-title {
  font-size: 16px;
  font-weight: 600;
  color: #303133;
}

.charts-row {
  margin-top: 0;
}

.emergency-alert {
  border: 2px solid #f56c6c;
}

.emergency-alert :deep(.el-alert__content) {
  width: 100%;
}

.alert-content {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  flex-wrap: wrap;
}

/* 暗色模式 */
:global(.dark) .stat-card {
  background: #1a1a1a;
  border-color: #3a3a3a;
}

:global(.dark) .card-title {
  color: #e0e0e0;
}

:global(.dark) .emergency-active {
  background: linear-gradient(135deg, #4a2a2a 0%, #1a1a1a 100%);
}

/* 响应式设计 */
@media (max-width: 768px) {
  .overview-cards .el-col {
    margin-bottom: 12px;
  }

  .stat-card :deep(.el-statistic__content) {
    font-size: 24px;
  }

  .card-header {
    flex-direction: column;
    align-items: flex-start;
  }

  .alert-content {
    flex-direction: column;
    align-items: flex-start;
  }
}
</style>
