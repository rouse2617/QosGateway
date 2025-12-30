import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import EmptyState from '@/components/EmptyState.vue'

describe('EmptyState Component', () => {
  it('renders properly with default props', () => {
    const wrapper = mount(EmptyState)
    expect(wrapper.find('.empty-state').exists()).toBe(true)
    expect(wrapper.text()).toContain('暂无数据')
  })

  it('renders with custom title', () => {
    const wrapper = mount(EmptyState, {
      props: {
        title: 'Custom Title',
        description: 'Custom Description'
      }
    })
    expect(wrapper.text()).toContain('Custom Title')
    expect(wrapper.text()).toContain('Custom Description')
  })

  it('renders action slot', () => {
    const wrapper = mount(EmptyState, {
      slots: {
        action: '<button>Action</button>'
      }
    })
    expect(wrapper.html()).toContain('<button>Action</button>')
  })
})
