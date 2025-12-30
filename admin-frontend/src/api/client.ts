import axios, { AxiosError, InternalAxiosRequestConfig, AxiosResponse } from 'axios'
import { useAuthStore } from '../stores/auth'
import router from '../router'
import { ElMessage } from 'element-plus'
import { getStorageItem, setStorageItem, removeStorageItem } from '../utils/storage'

// Token 刷新状态锁，防止并发刷新
let isRefreshing = false
let refreshSubscribers: Array<(token: string) => void> = []

/**
 * 将等待的请求加入队列
 */
function subscribeTokenRefresh(callback: (token: string) => void) {
  refreshSubscribers.push(callback)
}

/**
 * Token 刷新成功后，执行队列中的请求
 */
function onRefreshed(token: string) {
  refreshSubscribers.forEach(callback => callback(token))
  refreshSubscribers = []
}

/**
 * 创建 API 客户端实例
 */
const client = axios.create({
  baseURL: '/api/v1',
  timeout: 15000,
  headers: {
    'Content-Type': 'application/json'
  }
})

/**
 * 刷新 Token
 */
async function refreshAccessToken(): Promise<string> {
  const refreshToken = getStorageItem<string>('refreshToken')
  if (!refreshToken) {
    throw new Error('No refresh token available')
  }

  const response = await axios.post('/api/v1/auth/refresh', {
    refresh_token: refreshToken
  })

  const { access_token, refresh_token: newRefreshToken } = response.data

  // 更新存储的 token
  setStorageItem('accessToken', access_token, true)
  if (newRefreshToken) {
    setStorageItem('refreshToken', newRefreshToken, true)
  }

  return access_token
}

/**
 * 请求重试逻辑（指数退避）
 */
async function retryRequest(originalRequest: InternalAxiosRequestConfig, token: string) {
  // 设置新的 token
  if (originalRequest.headers) {
    originalRequest.headers.Authorization = `Bearer ${token}`
  }

  // 重试原始请求
  return client(originalRequest)
}

/**
 * 请求拦截器
 */
client.interceptors.request.use(
  (config) => {
    // 从存储中获取 token（而不是直接从 store）
    const token = getStorageItem<string>('accessToken')
    if (token && config.headers) {
      config.headers.Authorization = `Bearer ${token}`
    }

    // 添加请求 ID 用于追踪
    config.headers['X-Request-ID'] = `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`

    return config
  },
  (error) => {
    return Promise.reject(error)
  }
)

/**
 * 响应拦截器
 */
client.interceptors.response.use(
  (response: AxiosResponse) => {
    return response
  },
  async (error: AxiosError) => {
    const originalRequest = error.config as InternalAxiosRequestConfig & { _retry?: boolean }

    // 网络错误处理
    if (!error.response) {
      ElMessage.error('网络连接失败，请检查网络设置')
      return Promise.reject(error)
    }

    // 401 未授权 - 尝试刷新 token
    if (error.response?.status === 401 && originalRequest && !originalRequest._retry) {
      if (isRefreshing) {
        // 如果正在刷新，将请求加入队列
        return new Promise((resolve) => {
          subscribeTokenRefresh((token: string) => {
            if (originalRequest.headers) {
              originalRequest.headers.Authorization = `Bearer ${token}`
            }
            resolve(client(originalRequest))
          })
        })
      }

      originalRequest._retry = true
      isRefreshing = true

      try {
        const newToken = await refreshAccessToken()
        isRefreshing = false
        onRefreshed(newToken)

        // 重试原始请求
        return retryRequest(originalRequest, newToken)
      } catch (refreshError) {
        isRefreshing = false
        refreshSubscribers = []

        // Token 刷新失败，清除认证信息并跳转到登录页
        const authStore = useAuthStore()
        authStore.logout()
        router.push('/login')

        ElMessage.error('登录已过期，请重新登录')
        return Promise.reject(refreshError)
      }
    }

    // 403 无权限
    if (error.response?.status === 403) {
      ElMessage.error('没有权限执行此操作')
      return Promise.reject(error)
    }

    // 404 资源不存在
    if (error.response?.status === 404) {
      ElMessage.error('请求的资源不存在')
      return Promise.reject(error)
    }

    // 429 请求过于频繁
    if (error.response?.status === 429) {
      ElMessage.warning('请求过于频繁，请稍后重试')
      return Promise.reject(error)
    }

    // 500+ 服务器错误
    if (error.response?.status >= 500) {
      ElMessage.error('服务器错误，请稍后重试')
      return Promise.reject(error)
    }

    // 其他错误
    const errorMessage = (error.response?.data as any)?.error || error.message || '请求失败'
    ElMessage.error(errorMessage)

    return Promise.reject(error)
  }
)

/**
 * 创建一个带超时的请求
 */
export function createRequestWithTimeout<T>(
  requestFn: () => Promise<T>,
  timeout: number = 30000,
  timeoutMessage: string = '请求超时，请稍后重试'
): Promise<T> {
  return Promise.race([
    requestFn(),
    new Promise<T>((_, reject) => {
      setTimeout(() => {
        reject(new Error(timeoutMessage))
      }, timeout)
    })
  ])
}

/**
 * 导出带重试和超时的请求方法
 */
export const requestWithRetry = async <T>(
  requestFn: () => Promise<T>,
  maxRetries: number = 3,
  retryDelay: number = 1000
): Promise<T> => {
  let lastError: Error | null = null

  for (let i = 0; i < maxRetries; i++) {
    try {
      return await requestFn()
    } catch (error) {
      lastError = error as Error

      // 如果是 4xx 错误（除了 429），不重试
      if (error instanceof AxiosError) {
        const status = error.response?.status
        if (status && status >= 400 && status < 500 && status !== 429) {
          throw error
        }
      }

      // 等待后重试（指数退避）
      if (i < maxRetries - 1) {
        await new Promise(resolve => setTimeout(resolve, retryDelay * Math.pow(2, i)))
      }
    }
  }

  throw lastError
}

export default client

