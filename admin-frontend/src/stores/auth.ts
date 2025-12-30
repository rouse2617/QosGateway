import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { authApi } from '../api'
import type { User } from '../types'

export const useAuthStore = defineStore('auth', () => {
  const accessToken = ref<string | null>(localStorage.getItem('accessToken'))
  const refreshToken = ref<string | null>(localStorage.getItem('refreshToken'))
  const user = ref<User | null>(null)

  const isAuthenticated = computed(() => !!accessToken.value)

  async function login(username: string, password: string) {
    const { data } = await authApi.login(username, password)
    accessToken.value = data.access_token
    refreshToken.value = data.refresh_token
    localStorage.setItem('accessToken', data.access_token)
    localStorage.setItem('refreshToken', data.refresh_token)
    user.value = { id: '1', username, role: 'admin' }
  }

  function logout() {
    accessToken.value = null
    refreshToken.value = null
    user.value = null
    localStorage.removeItem('accessToken')
    localStorage.removeItem('refreshToken')
  }

  return { accessToken, refreshToken, user, isAuthenticated, login, logout }
})
