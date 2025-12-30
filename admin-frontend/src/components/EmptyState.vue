<template>
  <div class="empty-state">
    <div class="empty-state-icon">
      <slot name="icon">
        <el-icon :size="60" color="#909399">
          <component :is="iconComponent" />
        </el-icon>
      </slot>
    </div>
    <div class="empty-state-title">{{ title }}</div>
    <div v-if="description" class="empty-state-description">{{ description }}</div>
    <div v-if="$slots.action" class="empty-state-action">
      <slot name="action"></slot>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import {
  Document,
  FolderOpened,
  Warning,
  InfoFilled,
  Picture
} from '@element-plus/icons-vue'

interface Props {
  type?: 'data' | 'folder' | 'warning' | 'info' | 'image'
  title?: string
  description?: string
}

const props = withDefaults(defineProps<Props>(), {
  type: 'data',
  title: '暂无数据',
  description: ''
})

const iconComponent = computed(() => {
  const icons = {
    data: Document,
    folder: FolderOpened,
    warning: Warning,
    info: InfoFilled,
    image: Picture
  }
  return icons[props.type] || Document
})
</script>

<style scoped>
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 60px 20px;
  text-align: center;
}

.empty-state-icon {
  margin-bottom: 20px;
  opacity: 0.5;
}

.empty-state-title {
  font-size: 16px;
  color: #606266;
  margin-bottom: 8px;
}

.empty-state-description {
  font-size: 14px;
  color: #909399;
  margin-bottom: 20px;
  max-width: 400px;
}

.empty-state-action {
  margin-top: 8px;
}

/* 暗色模式 */
:global(.dark) .empty-state-title {
  color: #e0e0e0;
}

:global(.dark) .empty-state-description {
  color: #a0a0a0;
}
</style>
