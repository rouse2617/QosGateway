import { ElMessage, ElMessageBox, ElNotification } from 'element-plus'
import type { MessageParams, MessageBoxData } from 'element-plus'

/**
 * Toast 通知 composable
 * 提供统一的消息提示接口
 */
export function useToast() {
  /**
   * 成功消息
   */
  const success = (message: string, options?: Partial<MessageParams>) => {
    return ElMessage.success({
      message,
      duration: 3000,
      ...options
    })
  }

  /**
   * 错误消息
   */
  const error = (message: string, options?: Partial<MessageParams>) => {
    return ElMessage.error({
      message,
      duration: 5000,
      ...options
    })
  }

  /**
   * 警告消息
   */
  const warning = (message: string, options?: Partial<MessageParams>) => {
    return ElMessage.warning({
      message,
      duration: 4000,
      ...options
    })
  }

  /**
   * 信息消息
   */
  const info = (message: string, options?: Partial<MessageParams>) => {
    return ElMessage.info({
      message,
      duration: 3000,
      ...options
    })
  }

  /**
   * 显示通知（带标题和图标）
   */
  const notify = (options: {
    title: string
    message: string
    type?: 'success' | 'warning' | 'info' | 'error'
    duration?: number
  }) => {
    return ElNotification({
      title: options.title,
      message: options.message,
      type: options.type || 'info',
      duration: options.duration || 4500
    })
  }

  /**
   * 从错误对象中提取消息
   */
  const getErrorMessage = (err: any): string => {
    if (typeof err === 'string') return err
    if (err?.response?.data?.error) return err.response.data.error
    if (err?.response?.data?.message) return err.response.data.message
    if (err?.message) return err.message
    return '操作失败，请稍后重试'
  }

  /**
   * 显示错误信息（自动提取）
   */
  const showError = (err: any, defaultMessage: string = '操作失败') => {
    const message = getErrorMessage(err)
    error(message || defaultMessage)
  }

  return {
    success,
    error,
    warning,
    info,
    notify,
    getErrorMessage,
    showError
  }
}
