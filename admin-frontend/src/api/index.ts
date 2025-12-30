import client from './client'
import type { AppConfig, ClusterConfig, Metrics, EmergencyStatus, TokenResponse } from '../types'

// 认证
export const authApi = {
  login: (username: string, password: string) =>
    client.post<TokenResponse>('/auth/login', { username, password }),
  refresh: (refreshToken: string) =>
    client.post<TokenResponse>('/auth/refresh', { refresh_token: refreshToken })
}

// 应用管理
export const appsApi = {
  list: () => client.get<{ apps: AppConfig[] }>('/apps'),
  get: (id: string) => client.get<AppConfig>(`/apps/${id}`),
  create: (config: Partial<AppConfig>) => client.post('/apps', config),
  update: (id: string, config: Partial<AppConfig>) => client.put(`/apps/${id}`, config),
  delete: (id: string) => client.delete(`/apps/${id}`)
}

// 集群管理
export const clustersApi = {
  list: () => client.get<{ clusters: ClusterConfig[] }>('/clusters'),
  get: (id: string) => client.get<ClusterConfig>(`/clusters/${id}`),
  update: (id: string, config: Partial<ClusterConfig>) => client.put(`/clusters/${id}`, config)
}

// 连接管理
export const connectionsApi = {
  getStats: () => client.get('/connections'),
  updateLimit: (targetType: string, targetId: string, limit: number) =>
    client.put('/connections', { target_type: targetType, target_id: targetId, limit })
}

// 紧急模式
export const emergencyApi = {
  getStatus: () => client.get<EmergencyStatus>('/emergency'),
  activate: (reason: string, duration: number) =>
    client.post('/emergency/activate', { reason, duration }),
  deactivate: () => client.post('/emergency/deactivate')
}

// 指标
export const metricsApi = {
  get: () => client.get<Metrics>('/metrics'),
  getApp: (id: string) => client.get(`/metrics/apps/${id}`),
  getConnections: () => client.get('/metrics/connections')
}
