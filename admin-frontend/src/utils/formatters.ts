import { format, formatDistanceToNow, isValid } from 'date-fns'
import { zhCN } from 'date-fns/locale/zh-CN'

/**
 * 格式化数字，添加千位分隔符
 */
export function formatNumber(num: number | undefined | null): string {
  if (num == null || isNaN(num)) return '0'
  return num.toLocaleString('zh-CN')
}

/**
 * 格式化百分比
 */
export function formatPercent(value: number, decimals: number = 1): string {
  if (isNaN(value)) return '0%'
  return `${(value * 100).toFixed(decimals)}%`
}

/**
 * 格式化日期时间
 */
export function formatDateTime(
  dateStr: string | undefined | null,
  formatStr: string = 'yyyy-MM-dd HH:mm:ss'
): string {
  if (!dateStr) return '-'
  const date = new Date(dateStr)
  if (!isValid(date)) return '-'
  return format(date, formatStr, { locale: zhCN })
}

/**
 * 格式化相对时间
 */
export function formatRelativeTime(dateStr: string | undefined | null): string {
  if (!dateStr) return '-'
  const date = new Date(dateStr)
  if (!isValid(date)) return '-'
  return formatDistanceToNow(date, { locale: zhCN, addSuffix: true })
}

/**
 * 格式化文件大小
 */
export function formatFileSize(bytes: number): string {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`
}

/**
 * 格式化速率
 */
export function formatRate(rate: number): string {
  if (rate >= 1000000) {
    return `${(rate / 1000000).toFixed(2)}M/s`
  } else if (rate >= 1000) {
    return `${(rate / 1000).toFixed(2)}K/s`
  }
  return `${rate}/s`
}

/**
 * 格式化时长（秒）
 */
export function formatDuration(seconds: number): string {
  if (seconds < 60) {
    return `${seconds}秒`
  } else if (seconds < 3600) {
    const minutes = Math.floor(seconds / 60)
    return `${minutes}分钟`
  } else if (seconds < 86400) {
    const hours = Math.floor(seconds / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    return minutes > 0 ? `${hours}小时${minutes}分钟` : `${hours}小时`
  } else {
    const days = Math.floor(seconds / 86400)
    const hours = Math.floor((seconds % 86400) / 3600)
    return hours > 0 ? `${days}天${hours}小时` : `${days}天`
  }
}

/**
 * 截断文本
 */
export function truncateText(text: string, maxLength: number = 50): string {
  if (!text) return ''
  if (text.length <= maxLength) return text
  return `${text.substring(0, maxLength)}...`
}

/**
 * 格式化优先级标签
 */
export function getPriorityLabel(priority: number): string {
  const labels: Record<number, string> = {
    0: 'P0 - 最高',
    1: 'P1 - 高',
    2: 'P2 - 中',
    3: 'P3 - 低'
  }
  return labels[priority] || `P${priority}`
}

/**
 * 获取优先级对应的 Element Plus 标签类型
 */
export function getPriorityType(priority: number): 'danger' | 'warning' | 'info' | 'success' {
  const types: Record<number, 'danger' | 'warning' | 'info' | 'success'> = {
    0: 'danger',
    1: 'warning',
    2: 'info',
    3: 'success'
  }
  return types[priority] || 'info'
}

/**
 * 格式化降级级别
 */
export function getDegradationLabel(level: string): string {
  const labels: Record<string, string> = {
    normal: '正常',
    degraded: '降级',
    emergency: '紧急'
  }
  return labels[level] || level
}

/**
 * 获取降级级别对应的标签类型
 */
export function getDegradationType(level: string): 'success' | 'warning' | 'danger' {
  const types: Record<string, 'success' | 'warning' | 'danger'> = {
    normal: 'success',
    degraded: 'warning',
    emergency: 'danger'
  }
  return types[level] || 'info'
}

/**
 * 高亮搜索关键词
 */
export function highlightKeyword(text: string, keyword: string): string {
  if (!keyword) return text
  const regex = new RegExp(`(${keyword})`, 'gi')
  return text.replace(regex, '<mark>$1</mark>')
}
