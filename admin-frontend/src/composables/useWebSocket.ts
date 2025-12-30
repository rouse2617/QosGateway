import { ref, onMounted, onUnmounted } from 'vue'
import { useAuthStore } from '../stores/auth'
import type { WebSocketMessage } from '../types'

export function useWebSocket() {
  const ws = ref<WebSocket | null>(null)
  const connected = ref(false)
  const messages = ref<WebSocketMessage[]>([])
  const lastMetrics = ref<any>(null)

  let reconnectTimer: number | null = null

  function connect() {
    const authStore = useAuthStore()
    if (!authStore.accessToken) return

    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/ws?token=${authStore.accessToken}`

    ws.value = new WebSocket(wsUrl)

    ws.value.onopen = () => {
      connected.value = true
      if (reconnectTimer) {
        clearTimeout(reconnectTimer)
        reconnectTimer = null
      }
    }

    ws.value.onmessage = (event) => {
      try {
        const msg: WebSocketMessage = JSON.parse(event.data)
        messages.value.push(msg)
        if (messages.value.length > 100) {
          messages.value.shift()
        }
        if (msg.type === 'metrics') {
          lastMetrics.value = msg.data
        }
      } catch (e) {
        console.error('WebSocket message parse error:', e)
      }
    }

    ws.value.onclose = () => {
      connected.value = false
      reconnectTimer = window.setTimeout(connect, 5000)
    }

    ws.value.onerror = () => {
      ws.value?.close()
    }
  }

  function disconnect() {
    if (reconnectTimer) {
      clearTimeout(reconnectTimer)
      reconnectTimer = null
    }
    ws.value?.close()
    ws.value = null
  }

  onMounted(connect)
  onUnmounted(disconnect)

  return { connected, messages, lastMetrics, connect, disconnect }
}
