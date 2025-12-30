<template>
  <div class="dashboard">
    <!-- 概览卡片 -->
    <el-row :gutter="20" class="overview-cards">
      <el-col :span="6">
        <el-card shadow="hover">
          <el-statistic title="总请求数" :value="metrics?.requests_total || 0">
            <template #prefix><el-icon><Document /></el-icon></template>
          </el-statistic>
        </el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="hover">
          <el-statistic title="拒绝请求" :value="metrics?.rejected_total || 0" value-style="color: #f56c6c">
            <template #prefix><el-icon><CircleClose /></el-icon></template>
          </el-statistic>
        </el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="hover">
          <el-statistic title="缓存命中率" :value="cacheHitPercent" suffix="%">
            <template #prefix><el-icon><TrendCharts /></el-icon></template>
          </el-statistic>
        </el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="hover" :class="{ 'emergency-active': metrics?.emergency_active }">
          <el-statistic title="系统状态" :value="systemStatus">
            <template #prefix><el-icon><Monitor /></el-icon></template>
          </el-statistic>
        </el-card>
      </el-col>
    </el-row>

    <!-- 图表区域 -->
    <el-row :gutter="20" class="charts-row">
      <el-col :span="16">
        <el-card>
          <template #header>
            <div class="card-header">
              <span>请求趋势</span>
              <el-radio-group v-model="timeRange" size="small">
                <el-radio-button label="1h">1小时</el-radio-button>
                <el-radio-button label="6h">6小时</el-radio-button>
                <el-radio-button label="24h">24小时</el-radio-button>
              </el-radio-group>
            </div>
          </template>
          <v-chart :option="chartOption" style="height: 300px" autoresize />
        </el-card>
      </el-col>
      <el-col :span="8">
        <el-card>
          <template #header>令牌分布</template>
          <v-chart :option="tokenChartOption" style="height: 300px" autoresize />
        </el-card>
      </el-col>
    </el-row>

    <!-- 告警面板 -->
    <el-card class="alert-panel" v-if="metrics?.emergency_active">
      <template #header>
        <div class="alert-header">
          <el-icon color="#f56c6c"><Warning /></el-icon>
          <span>紧急模式已激活</span>
        </div>
      </template>
      <p>系统当前处于紧急模式，部分低优先级请求可能被限制。</p>
      <el-button type="danger" @click="router.push('/emergency')">查看详情</el-button>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { use } from 'echarts/core'
import { CanvasRenderer } from 'echarts/renderers'
import { LineChart, PieChart } from 'echarts/charts'
import { GridComponent, TooltipComponent, LegendComponent } from 'echarts/components'
import VChart from 'vue-echarts'
import { useMetricsStore } from '../stores/metrics'

use([CanvasRenderer, LineChart, PieChart, GridComponent, TooltipComponent, LegendComponent])

const router = useRouter()
const metricsStore = useMetricsStore()
const timeRange = ref('1h')

const metrics = computed(() => metricsStore.metrics)
const cacheHitPercent = computed(() => ((metrics.value?.cache_hit_ratio || 0) * 100).toFixed(1))
const systemStatus = computed(() => {
  if (metrics.value?.emergency_active) return '紧急'
  if (metrics.value?.degradation_level !== 'normal') return '降级'
  return '正常'
})

const chartOption = computed(() => ({
  tooltip: { trigger: 'axis' },
  legend: { data: ['请求数', '拒绝数'] },
  xAxis: { type: 'category', data: ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00'] },
  yAxis: { type: 'value' },
  series: [
    { name: '请求数', type: 'line', smooth: true, data: [120, 200, 150, 80, 70, 110] },
    { name: '拒绝数', type: 'line', smooth: true, data: [5, 10, 8, 3, 2, 4] }
  ]
}))

const tokenChartOption = computed(() => ({
  tooltip: { trigger: 'item' },
  legend: { orient: 'vertical', left: 'left' },
  series: [{
    type: 'pie',
    radius: '60%',
    data: [
      { value: 60, name: 'L3 本地' },
      { value: 30, name: 'L2 应用' },
      { value: 10, name: 'L1 集群' }
    ]
  }]
}))

let refreshTimer: number | null = null

onMounted(() => {
  metricsStore.fetchMetrics()
  refreshTimer = window.setInterval(() => metricsStore.fetchMetrics(), 5000)
})

onUnmounted(() => {
  if (refreshTimer) clearInterval(refreshTimer)
})
</script>

<style scoped>
.dashboard {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.overview-cards .el-card {
  text-align: center;
}

.emergency-active {
  border-color: #f56c6c;
  background: #fef0f0;
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.alert-panel {
  border-color: #f56c6c;
}

.alert-header {
  display: flex;
  align-items: center;
  gap: 8px;
  color: #f56c6c;
  font-weight: bold;
}
</style>
