// ============= Core Domain Types =============

// 应用配置
export interface AppConfig {
  app_id: string
  guaranteed_quota: number
  burst_quota: number
  priority: number
  max_borrow: number
  max_connections: number
  updated_at?: string
}

// 集群配置
export interface ClusterConfig {
  cluster_id: string
  max_capacity: number
  reserved_ratio: number
  emergency_threshold: number
  max_connections: number
  updated_at?: string
}

// 连接统计
export interface ConnectionStats {
  type: 'app' | 'cluster'
  id: string
  current: number
  limit: number
  peak: number
  rejected: number
}

// 紧急模式状态
export interface EmergencyStatus {
  active: boolean
  reason: string
  activated_at: string
  expires_at: string
  duration: number
}

// 系统指标
export interface Metrics {
  requests_total: number
  rejected_total: number
  l3_hits: number
  cache_hit_ratio: number
  emergency_active: boolean
  degradation_level: 'normal' | 'degraded' | 'emergency'
  reconcile_corrections: number
}

// 应用指标
export interface AppMetrics {
  app_id: string
  requests_total: number
  rejected_total: number
  tokens_available: number
  pending_cost: number
}

// ============= Authentication Types =============

// 用户
export interface User {
  id: string
  username: string
  role: 'admin' | 'operator' | 'viewer'
  email?: string
}

// Token 响应
export interface TokenResponse {
  access_token: string
  refresh_token: string
  expires_in: number
  token_type?: string
}

// 登录请求
export interface LoginRequest {
  username: string
  password: string
}

// ============= API Types =============

// API 响应基础结构
export interface ApiResponse<T = any> {
  data: T
  success?: boolean
  error?: string
  message?: string
}

// API 错误响应
export interface ApiError {
  message: string
  code?: string
  status?: number
  details?: Record<string, any>
}

// 分页参数
export interface PaginationParams {
  page: number
  page_size: number
  sort_by?: string
  order?: 'asc' | 'desc'
}

// 分页响应
export interface PaginatedResponse<T> {
  items: T[]
  total: number
  page: number
  page_size: number
  total_pages: number
}

// ============= WebSocket Types =============

// WebSocket 消息
export interface WebSocketMessage<T = any> {
  type: 'metrics' | 'emergency' | 'connection' | 'error'
  data: T
  timestamp: string
}

// WebSocket 连接状态
export type WebSocketStatus = 'connecting' | 'connected' | 'disconnected' | 'error'

// ============= UI Types =============

// 优先级类型
export type Priority = 0 | 1 | 2 | 3

// 降级级别
export type DegradationLevel = 'normal' | 'degraded' | 'emergency'

// 主题模式
export type ThemeMode = 'light' | 'dark' | 'auto'

// 加载状态
export type LoadingState = 'idle' | 'loading' | 'success' | 'error'

// 表单验证规则
export interface FormRule {
  required?: boolean
  message?: string
  trigger?: 'blur' | 'change'
  min?: number
  max?: number
  pattern?: RegExp
  validator?: (rule: any, value: any) => boolean | Promise<boolean>
}

// ============= Chart Types =============

// 图表时间范围
export type TimeRange = '1h' | '6h' | '24h' | '7d'

// 时间序列数据点
export interface TimeSeriesDataPoint {
  timestamp: string
  value: number
}

// ============= Emergency History Types =============

// 紧急模式历史记录
export interface EmergencyHistory {
  type: 'activated' | 'deactivated'
  reason: string
  timestamp: string
  duration?: number
}

// ============= Utility Types =============

// 可选字段
export type Optional<T> = T | null | undefined

// 只读字段
export type ReadonlyFields<T, K extends keyof T> = Omit<T, K> & Readonly<Pick<T, K>>

// 部分更新
export type PartialUpdate<T> = Partial<Omit<T, 'id' | 'app_id' | 'cluster_id'>> & {
  id?: string
  app_id?: string
  cluster_id?: string
}
