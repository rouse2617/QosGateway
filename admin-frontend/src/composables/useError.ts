import { ref, computed } from 'vue'
import type { Router } from 'vue-router'

/**
 * 错误处理 composable
 */
export function useError(router?: Router) {
  const error = ref<Error | null>(null)
  const errors = ref<Record<string, string>>({})

  /**
   * 清除错误
   */
  const clearError = () => {
    error.value = null
  }

  /**
   * 清除字段错误
   */
  const clearFieldError = (field: string) => {
    delete errors.value[field]
  }

  /**
   * 清除所有字段错误
   */
  const clearAllErrors = () => {
    errors.value = {}
  }

  /**
   * 设置错误
   */
  const setError = (err: Error | string) => {
    error.value = err instanceof Error ? err : new Error(err)
  }

  /**
   * 设置字段错误
   */
  const setFieldError = (field: string, message: string) => {
    errors.value[field] = message
  }

  /**
   * 批量设置字段错误
   */
  const setFieldErrors = (errs: Record<string, string>) => {
    errors.value = { ...errs }
  }

  /**
   * 是否有错误
   */
  const hasError = computed(() => error.value !== null)
  const hasFieldErrors = computed(() => Object.keys(errors.value).length > 0)

  /**
   * 从 API 响应中提取错误
   */
  const extractApiError = (err: any): string => {
    if (typeof err === 'string') return err
    if (err?.response?.data?.error) return err.response.data.error
    if (err?.response?.data?.message) return err.response.data.message
    if (err?.message) return err.message
    return '操作失败，请稍后重试'
  }

  /**
   * 处理 API 错误
   */
  const handleApiError = (err: any) => {
    const message = extractApiError(err)
    setError(message)

    // 根据错误状态码处理
    if (err?.response?.status === 401) {
      // 未授权，跳转到登录页
      router?.push('/login')
    } else if (err?.response?.status === 403) {
      // 无权限
      setError('没有权限执行此操作')
    } else if (err?.response?.status === 404) {
      // 资源不存在
      setError('请求的资源不存在')
    } else if (err?.response?.status >= 500) {
      // 服务器错误
      setError('服务器错误，请稍后重试')
    }

    return message
  }

  /**
   * 处理表单验证错误
   */
  const handleFormError = (err: any) => {
    if (err?.response?.data?.errors) {
      setFieldErrors(err.response.data.errors)
    } else {
      setError(extractApiError(err))
    }
  }

  return {
    error,
    errors,
    hasError,
    hasFieldErrors,
    clearError,
    clearFieldError,
    clearAllErrors,
    setError,
    setFieldError,
    setFieldErrors,
    extractApiError,
    handleApiError,
    handleFormError
  }
}
