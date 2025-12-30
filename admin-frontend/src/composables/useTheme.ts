import { ref, watch, onMounted } from 'vue'
import { setStorageItem, getStorageItem } from '../utils/storage'
import type { ThemeMode } from '../types'

const THEME_KEY = 'theme'

/**
 * 主题管理 composable
 */
export function useTheme() {
  const theme = ref<ThemeMode>('light')
  const isDark = ref(false)

  /**
   * 应用主题到 DOM
   */
  const applyTheme = (mode: ThemeMode) => {
    const html = document.documentElement

    if (mode === 'auto') {
      const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
      isDark.value = prefersDark
      html.classList.toggle('dark', prefersDark)
    } else {
      isDark.value = mode === 'dark'
      html.classList.toggle('dark', mode === 'dark')
    }
  }

  /**
   * 设置主题
   */
  const setTheme = (mode: ThemeMode) => {
    theme.value = mode
    applyTheme(mode)
    setStorageItem(THEME_KEY, mode)
  }

  /**
   * 切换主题（亮色/暗色）
   */
  const toggleTheme = () => {
    const newTheme: ThemeMode = isDark.value ? 'light' : 'dark'
    setTheme(newTheme)
  }

  /**
   * 初始化主题
   */
  const initTheme = () => {
    const savedTheme = getStorageItem<ThemeMode>(THEME_KEY)
    const initialTheme = savedTheme || 'light'
    theme.value = initialTheme
    applyTheme(initialTheme)
  }

  /**
   * 监听系统主题变化
   */
  const watchSystemTheme = () => {
    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
    const handler = (e: MediaQueryListEvent) => {
      if (theme.value === 'auto') {
        isDark.value = e.matches
        document.documentElement.classList.toggle('dark', e.matches)
      }
    }

    mediaQuery.addEventListener('change', handler)
    return () => mediaQuery.removeEventListener('change', handler)
  }

  // 监听主题变化
  watch(theme, (newTheme) => {
    applyTheme(newTheme)
  })

  // 组件挂载时初始化
  onMounted(() => {
    initTheme()
    const cleanup = watchSystemTheme()
    return cleanup
  })

  return {
    theme,
    isDark,
    setTheme,
    toggleTheme,
    initTheme
  }
}
