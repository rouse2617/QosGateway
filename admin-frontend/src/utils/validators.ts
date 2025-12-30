/**
 * 验证用户名
 */
export function validateUsername(username: string): boolean {
  if (!username) return false
  const regex = /^[a-zA-Z0-9_]{3,20}$/
  return regex.test(username)
}

/**
 * 验证密码强度
 */
export function validatePassword(password: string): {
  valid: boolean
  strength: 'weak' | 'medium' | 'strong'
  message?: string
} {
  if (!password || password.length < 6) {
    return { valid: false, strength: 'weak', message: '密码至少需要6个字符' }
  }

  let score = 0
  if (password.length >= 8) score++
  if (password.length >= 12) score++
  if (/[a-z]/.test(password)) score++
  if (/[A-Z]/.test(password)) score++
  if (/[0-9]/.test(password)) score++
  if (/[^a-zA-Z0-9]/.test(password)) score++

  if (score < 3) {
    return { valid: true, strength: 'weak', message: '密码强度较弱' }
  } else if (score < 5) {
    return { valid: true, strength: 'medium', message: '密码强度中等' }
  }
  return { valid: true, strength: 'strong', message: '密码强度较强' }
}

/**
 * 验证应用ID
 */
export function validateAppId(appId: string): boolean {
  if (!appId) return false
  const regex = /^[a-z0-9-]{2,50}$/
  return regex.test(appId)
}

/**
 * 验证集群ID
 */
export function validateClusterId(clusterId: string): boolean {
  if (!clusterId) return false
  const regex = /^[a-z0-9-]{2,50}$/
  return regex.test(clusterId)
}

/**
 * 验证数值范围
 */
export function validateRange(
  value: number,
  min: number,
  max: number
): { valid: boolean; message?: string } {
  if (isNaN(value)) {
    return { valid: false, message: '请输入有效的数字' }
  }
  if (value < min) {
    return { valid: false, message: `不能小于 ${min}` }
  }
  if (value > max) {
    return { valid: false, message: `不能大于 ${max}` }
  }
  return { valid: true }
}

/**
 * 验证百分比 (0-1)
 */
export function validatePercentage(value: number): { valid: boolean; message?: string } {
  return validateRange(value, 0, 1)
}

/**
 * 验证正整数
 */
export function validatePositiveInteger(value: number): { valid: boolean; message?: string } {
  if (!Number.isInteger(value) || value <= 0) {
    return { valid: false, message: '请输入正整数' }
  }
  return { valid: true }
}

/**
 * 验证邮箱
 */
export function validateEmail(email: string): boolean {
  if (!email) return false
  const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
  return regex.test(email)
}

/**
 * 验证URL
 */
export function validateUrl(url: string): boolean {
  if (!url) return false
  try {
    new URL(url)
    return true
  } catch {
    return false
  }
}

/**
 * 验证IP地址
 */
export function validateIP(ip: string): boolean {
  if (!ip) return false
  const ipv4Regex = /^(\d{1,3}\.){3}\d{1,3}$/
  const ipv6Regex = /^([0-9a-fA-F]{0,4}:){7}[0-9a-fA-F]{0,4}$/

  if (ipv4Regex.test(ip)) {
    return ip.split('.').every(octet => parseInt(octet) <= 255)
  }
  return ipv6Regex.test(ip)
}

/**
 * 验证端口号
 */
export function validatePort(port: number): { valid: boolean; message?: string } {
  return validateRange(port, 1, 65535)
}
