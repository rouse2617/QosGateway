import { ref, computed, type Ref } from 'vue'

/**
 * 加载状态 composable
 * 管理异步操作的加载状态
 */
export function useLoading(initialState: boolean = false) {
  const loading = ref(initialState)
  const error = ref<Error | null>(null)

  /**
   * 设置加载状态
   */
  const setLoading = (state: boolean) => {
    loading.value = state
  }

  /**
   * 设置错误状态
   */
  const setError = (err: Error | null) => {
    error.value = err
  }

  /**
   * 包装异步函数，自动处理加载状态
   */
  const withLoading = async <T>(
    fn: () => Promise<T>,
    showError: boolean = true
  ): Promise<T> => {
    loading.value = true
    error.value = null
    try {
      return await fn()
    } catch (err) {
      error.value = err as Error
      throw err
    } finally {
      loading.value = false
    }
  }

  return {
    loading,
    error,
    setLoading,
    setError,
    withLoading
  }
}

/**
 * 多个加载状态管理
 */
export function useMultiLoading() {
  const loadingStates = ref<Record<string, boolean>>({})
  const errorStates = ref<Record<string, Error | null>>({})

  /**
   * 获取特定键的加载状态
   */
  const isLoading = (key: string): boolean => {
    return loadingStates.value[key] || false
  }

  /**
   * 检查是否有任何加载状态
   */
  const anyLoading = computed(() => {
    return Object.values(loadingStates.value).some(v => v)
  })

  /**
   * 设置加载状态
   */
  const setLoading = (key: string, state: boolean) => {
    loadingStates.value[key] = state
  }

  /**
   * 设置错误状态
   */
  const setError = (key: string, err: Error | null) => {
    errorStates.value[key] = err
  }

  /**
   * 包装异步函数
   */
  const withLoading = async <T>(
    key: string,
    fn: () => Promise<T>
  ): Promise<T> => {
    setLoading(key, true)
    setError(key, null)
    try {
      return await fn()
    } catch (err) {
      setError(key, err as Error)
      throw err
    } finally {
      setLoading(key, false)
    }
  }

  return {
    loadingStates,
    errorStates,
    isLoading,
    anyLoading,
    setLoading,
    setError,
    withLoading
  }
}
