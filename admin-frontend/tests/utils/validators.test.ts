import { describe, it, expect } from 'vitest'
import {
  validateUsername,
  validatePassword,
  validateAppId,
  validateRange,
  validatePercentage
} from '../../src/utils/validators'

describe('Validators', () => {
  describe('validateUsername', () => {
    it('should validate valid usernames', () => {
      expect(validateUsername('user123')).toBe(true)
      expect(validateUsername('test_user')).toBe(true)
      expect(validateUsername('abc')).toBe(true)
    })

    it('should reject invalid usernames', () => {
      expect(validateUsername('')).toBe(false)
      expect(validateUsername('ab')).toBe(false)
      expect(validateUsername('user-123')).toBe(false)
      expect(validateUsername('user@123')).toBe(false)
    })
  })

  describe('validatePassword', () => {
    it('should validate password strength', () => {
      const result = validatePassword('Test@123')
      expect(result.valid).toBe(true)
      expect(result.strength).toBeDefined()
    })

    it('should reject short passwords', () => {
      const result = validatePassword('12345')
      expect(result.valid).toBe(false)
    })
  })

  describe('validateAppId', () => {
    it('should validate valid app IDs', () => {
      expect(validateAppId('app-123')).toBe(true)
      expect(validateAppId('test-app')).toBe(true)
    })

    it('should reject invalid app IDs', () => {
      expect(validateAppId('')).toBe(false)
      expect(validateAppId('App_123')).toBe(false)
    })
  })

  describe('validateRange', () => {
    it('should validate numeric range', () => {
      expect(validateRange(5, 1, 10).valid).toBe(true)
      expect(validateRange(0, 1, 10).valid).toBe(false)
      expect(validateRange(11, 1, 10).valid).toBe(false)
    })
  })

  describe('validatePercentage', () => {
    it('should validate percentage values', () => {
      expect(validatePercentage(0.5).valid).toBe(true)
      expect(validatePercentage(0).valid).toBe(true)
      expect(validatePercentage(1).valid).toBe(true)
      expect(validatePercentage(1.5).valid).toBe(false)
    })
  })
})
