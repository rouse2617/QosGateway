import { defineStore } from 'pinia'
import { ref } from 'vue'
import { metricsApi, emergencyApi } from '../api'
import type { Metrics, EmergencyStatus } from '../types'

export const useMetricsStore = defineStore('metrics', () => {
  const metrics = ref<Metrics | null>(null)
  const emergency = ref<EmergencyStatus | null>(null)
  const loading = ref(false)

  async function fetchMetrics() {
    loading.value = true
    try {
      const { data } = await metricsApi.get()
      metrics.value = data
    } finally {
      loading.value = false
    }
  }

  async function fetchEmergency() {
    const { data } = await emergencyApi.getStatus()
    emergency.value = data
  }

  return { metrics, emergency, loading, fetchMetrics, fetchEmergency }
})
