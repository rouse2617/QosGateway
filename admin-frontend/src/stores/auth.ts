import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { authApi } from '../api'
import type { User, LoginRequest } from '../types'
import { setStorageItem, getStorageItem, removeStorageItem } from '../utils/storage'

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null)
  const loginLoading = ref(false)
  const loginError = ref<Error | null>(null)

  // 从安全存储中获取 token
  const accessToken = ref<string | null>(getStorageItem<string>('accessToken', null))
  const refreshToken = ref<string | null>(getStorageItem<string>('refreshToken', null))

  const isAuthenticated = computed(() => !!accessToken.value)
  const isAdmin = computed(() => user.value?.role === 'admin')
  const canWrite = computed(() => user.value?.role === 'admin' || user.value?.role === 'operator')

  /**
   * 登录
   */
  async function login(username: string, password: string) {
    loginLoading.value = true
    loginError.value = null

    try {
      const { data } = await authApi.login(username, password)

      // 使用加密存储
      setStorageItem('accessToken', data.access_token, true)
      setStorageItem('refreshToken', data.refresh_token, true)

      accessToken.value = data.access_token
      refreshToken.value = data.refresh_token

      // 创建用户对象（实际项目中应该从 API 获取）
      user.value = {
        id: '1',
        username,
        role: 'admin',
        email: `${username}@example.com`
      }

      return { success: true }
    } catch (error) {
      loginError.value = error as Error
      throw error
    } finally {
      loginLoading.value = false
    }
  }

  /**
   * 登出
   */
  function logout() {
    // 清除 store 状态
    accessToken.value = null
    refreshToken.value = null
    user.value = null
    loginError.value = null

    // 清除存储
    removeStorageItem('accessToken')
    removeStorageItem('refreshToken')
  }

  /**
   * 刷新用户信息
   */
  async function refreshUserInfo() {
    // 实际项目中应该调用 API 获取最新用户信息
    // 这里仅作为示例
    if (accessToken.value && !user.value) {
      // 从 token 中解析用户信息或调用 API
    }
  }

  /**
   * 更新 token（用于自动刷新）
   */
  function updateTokens(newAccessToken: string, newRefreshToken?: string) {
    setStorageItem('accessToken', newAccessToken, true)
    if (newRefreshToken) {
      setStorageItem('refreshToken', newRefreshToken, true)
      refreshToken.value = newRefreshToken
    }
    accessToken.value = newAccessToken
  }

  return {
    // State
    user,
    accessToken,
    refreshToken,
    loginLoading,
    loginError,

    // Computed
    isAuthenticated,
    isAdmin,
    canWrite,

    // Actions
    login,
    logout,
    refreshUserInfo,
    updateTokens
  }
})
