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
  type: string
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
  degradation_level: string
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

// 用户
export interface User {
  id: string
  username: string
  role: string
}

// Token 响应
export interface TokenResponse {
  access_token: string
  refresh_token: string
  expires_in: number
}

// WebSocket 消息
export interface WebSocketMessage {
  type: string
  data: any
  timestamp: string
}

// API 响应
export interface ApiResponse<T> {
  data?: T
  error?: string
  success?: boolean
}
