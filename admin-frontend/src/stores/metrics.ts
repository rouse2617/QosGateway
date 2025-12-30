import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { metricsApi, emergencyApi } from '../api'
import type { Metrics, EmergencyStatus } from '../types'
import { useToast } from '../composables'

const CACHE_DURATION = 5000 // 5秒缓存

export const useMetricsStore = defineStore('metrics', () => {
  const metrics = ref<Metrics | null>(null)
  const emergency = ref<EmergencyStatus | null>(null)

  const loading = ref(false)
  const error = ref<Error | null>(null)

  // 缓存时间戳
  const metricsCacheTime = ref(0)
  const emergencyCacheTime = ref(0)

  const { error: showError } = useToast()

  /**
   * 检查缓存是否有效
   */
  const isCacheValid = (cacheTime: number) => {
    return Date.now() - cacheTime < CACHE_DURATION
  }

  /**
   * 获取系统指标
   */
  async function fetchMetrics(forceRefresh: boolean = false) {
    // 检查缓存
    if (!forceRefresh && isCacheValid(metricsCacheTime.value) && metrics.value) {
      return metrics.value
    }

    loading.value = true
    error.value = null

    try {
      const { data } = await metricsApi.get()
      metrics.value = data
      metricsCacheTime.value = Date.now()
      return data
    } catch (err) {
      error.value = err as Error
      showError(err, '获取指标失败')
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * 获取紧急模式状态
   */
  async function fetchEmergency(forceRefresh: boolean = false) {
    // 检查缓存
    if (!forceRefresh && isCacheValid(emergencyCacheTime.value) && emergency.value) {
      return emergency.value
    }

    try {
      const { data } = await emergencyApi.getStatus()
      emergency.value = data
      emergencyCacheTime.value = Date.now()
      return data
    } catch (err) {
      error.value = err as Error
      showError(err, '获取紧急状态失败')
      throw err
    }
  }

  /**
   * 刷新所有数据
   */
  async function refreshAll() {
    await Promise.all([
      fetchMetrics(true),
      fetchEmergency(true)
    ])
  }

  /**
   * 重置状态
   */
  function reset() {
    metrics.value = null
    emergency.value = null
    error.value = null
    metricsCacheTime.value = 0
    emergencyCacheTime.value = 0
  }

  // 计算属性
  const cacheHitRatioPercent = computed(() => {
    return metrics.value ? (metrics.value.cache_hit_ratio * 100).toFixed(1) : '0'
  })

  const systemStatus = computed(() => {
    if (!metrics.value) return 'unknown'
    if (metrics.value.emergency_active) return 'emergency'
    if (metrics.value.degradation_level !== 'normal') return 'degraded'
    return 'normal'
  })

  const isEmergencyActive = computed(() => emergency.value?.active || false)

  return {
    // State
    metrics,
    emergency,
    loading,
    error,

    // Computed
    cacheHitRatioPercent,
    systemStatus,
    isEmergencyActive,

    // Actions
    fetchMetrics,
    fetchEmergency,
    refreshAll,
    reset
  }
})

