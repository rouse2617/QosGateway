import { ref, onMounted, onUnmounted } from 'vue'

/**
 * 网络状态 composable
 */
export function useOnline() {
  const isOnline = ref(navigator.onLine)
  const wasOffline = ref(false)

  /**
   * 在线状态变化处理
   */
  const handleOnline = () => {
    isOnline.value = true
    if (wasOffline.value) {
      // 网络恢复
      wasOffline.value = false
    }
  }

  /**
   * 离线状态变化处理
   */
  const handleOffline = () => {
    isOnline.value = false
    wasOffline.value = true
  }

  onMounted(() => {
    window.addEventListener('online', handleOnline)
    window.addEventListener('offline', handleOffline)
  })

  onUnmounted(() => {
    window.removeEventListener('online', handleOnline)
    window.removeEventListener('offline', handleOffline)
  })

  return {
    isOnline,
    wasOffline
  }
}
