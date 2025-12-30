/**
 * 安全的存储工具，支持加密和类型安全
 */

const STORAGE_PREFIX = 'token_admin_'
const ENCRYPTED_KEY = '__encrypted__'

/**
 * 获取完整的存储键
 */
function getStorageKey(key: string): string {
  return `${STORAGE_PREFIX}${key}`
}

/**
 * 简单的 Base64 编码（仅用于基本混淆，非加密）
 */
function encode(value: string): string {
  try {
    return btoa(encodeURIComponent(value))
  } catch {
    return value
  }
}

/**
 * 简单的 Base64 解码
 */
function decode(value: string): string {
  try {
    return decodeURIComponent(atob(value))
  } catch {
    return value
  }
}

/**
 * 安全地存储数据到 localStorage
 */
export function setStorageItem<T>(key: string, value: T, encrypt: boolean = false): boolean {
  try {
    const storageKey = getStorageKey(key)
    const serialized = JSON.stringify(value)

    if (encrypt) {
      localStorage.setItem(storageKey, ENCRYPTED_KEY + encode(serialized))
    } else {
      localStorage.setItem(storageKey, serialized)
    }
    return true
  } catch (error) {
    console.error('Failed to set storage item:', error)
    return false
  }
}

/**
 * 安全地从 localStorage 获取数据
 */
export function getStorageItem<T>(key: string, defaultValue?: T): T | null {
  try {
    const storageKey = getStorageKey(key)
    const item = localStorage.getItem(storageKey)

    if (!item) return defaultValue ?? null

    // 检查是否加密
    const data = item.startsWith(ENCRYPTED_KEY)
      ? decode(item.substring(ENCRYPTED_KEY.length))
      : item

    return JSON.parse(data) as T
  } catch (error) {
    console.error('Failed to get storage item:', error)
    return defaultValue ?? null
  }
}

/**
 * 删除 localStorage 中的数据
 */
export function removeStorageItem(key: string): boolean {
  try {
    const storageKey = getStorageKey(key)
    localStorage.removeItem(storageKey)
    return true
  } catch (error) {
    console.error('Failed to remove storage item:', error)
    return false
  }
}

/**
 * 清空所有应用相关的存储数据
 */
export function clearStorage(): boolean {
  try {
    const keys = Object.keys(localStorage)
    keys.forEach(key => {
      if (key.startsWith(STORAGE_PREFIX)) {
        localStorage.removeItem(key)
      }
    })
    return true
  } catch (error) {
    console.error('Failed to clear storage:', error)
    return false
  }
}

/**
 * 安全地存储数据到 sessionStorage
 */
export function setSessionItem<T>(key: string, value: T): boolean {
  try {
    const storageKey = getStorageKey(key)
    sessionStorage.setItem(storageKey, JSON.stringify(value))
    return true
  } catch (error) {
    console.error('Failed to set session item:', error)
    return false
  }
}

/**
 * 安全地从 sessionStorage 获取数据
 */
export function getSessionItem<T>(key: string, defaultValue?: T): T | null {
  try {
    const storageKey = getStorageKey(key)
    const item = sessionStorage.getItem(storageKey)

    if (!item) return defaultValue ?? null

    return JSON.parse(item) as T
  } catch (error) {
    console.error('Failed to get session item:', error)
    return defaultValue ?? null
  }
}

/**
 * 删除 sessionStorage 中的数据
 */
export function removeSessionItem(key: string): boolean {
  try {
    const storageKey = getStorageKey(key)
    sessionStorage.removeItem(storageKey)
    return true
  } catch (error) {
    console.error('Failed to remove session item:', error)
    return false
  }
}
