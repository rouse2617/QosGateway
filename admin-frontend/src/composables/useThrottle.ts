import { ref, watch, type Ref } from 'vue'

/**
 * 节流 composable
 */
export function useThrottle<T>(value: Ref<T>, delay: number = 300): Ref<T> {
  const throttledValue = ref(value.value) as Ref<T>
  let lastUpdate = 0

  watch(value, (newValue) => {
    const now = Date.now()
    if (now - lastUpdate >= delay) {
      throttledValue.value = newValue
      lastUpdate = now
    }
  })

  return throttledValue
}

/**
 * 节流函数 composable
 */
export function useThrottleFn<T extends (...args: any[]) => any>(
  fn: T,
  delay: number = 300
): (...args: Parameters<T>) => void {
  let lastCall = 0
  let timeout: ReturnType<typeof setTimeout> | null = null

  return (...args: Parameters<T>) => {
    const now = Date.now()
    const remaining = delay - (now - lastCall)

    if (remaining <= 0) {
      if (timeout) {
        clearTimeout(timeout)
        timeout = null
      }
      lastCall = now
      fn(...args)
    } else if (!timeout) {
      timeout = setTimeout(() => {
        lastCall = Date.now()
        timeout = null
        fn(...args)
      }, remaining)
    }
  }
}
