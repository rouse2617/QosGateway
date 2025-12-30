import { describe, it, expect } from 'vitest'
import {
  formatNumber,
  formatPercent,
  formatDateTime,
  formatDuration,
  getPriorityLabel,
  getPriorityType
} from '../../src/utils/formatters'

describe('Formatters', () => {
  describe('formatNumber', () => {
    it('should format numbers with locale string', () => {
      expect(formatNumber(1234567)).toBe('1,234,567')
      expect(formatNumber(0)).toBe('0')
      expect(formatNumber(null)).toBe('0')
      expect(formatNumber(undefined)).toBe('0')
    })
  })

  describe('formatPercent', () => {
    it('should format decimal to percentage', () => {
      expect(formatPercent(0.1234)).toBe('12.3%')
      expect(formatPercent(0.9567, 2)).toBe('95.67%')
      expect(formatPercent(1)).toBe('100.0%')
    })
  })

  describe('formatDateTime', () => {
    it('should format date string', () => {
      const date = '2024-01-15T10:30:00Z'
      const result = formatDateTime(date)
      expect(result).not.toBe('-')
    })

    it('should return hyphen for invalid date', () => {
      expect(formatDateTime('')).toBe('-')
      expect(formatDateTime(null)).toBe('-')
      expect(formatDateTime(undefined)).toBe('-')
    })
  })

  describe('formatDuration', () => {
    it('should format duration in seconds', () => {
      expect(formatDuration(30)).toBe('30秒')
      expect(formatDuration(120)).toBe('2分钟')
      expect(formatDuration(3600)).toBe('1小时')
      expect(formatDuration(86400)).toBe('1天')
    })
  })

  describe('getPriorityLabel', () => {
    it('should return correct priority labels', () => {
      expect(getPriorityLabel(0)).toBe('P0 - 最高')
      expect(getPriorityLabel(1)).toBe('P1 - 高')
      expect(getPriorityLabel(2)).toBe('P2 - 中')
      expect(getPriorityLabel(3)).toBe('P3 - 低')
    })
  })

  describe('getPriorityType', () => {
    it('should return correct element plus tag types', () => {
      expect(getPriorityType(0)).toBe('danger')
      expect(getPriorityType(1)).toBe('warning')
      expect(getPriorityType(2)).toBe('info')
      expect(getPriorityType(3)).toBe('success')
    })
  })
})
