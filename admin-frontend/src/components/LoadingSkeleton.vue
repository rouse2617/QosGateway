<template>
  <div class="skeleton-wrapper" :class="{ 'skeleton-animated': animated }">
    <slot>
      <!-- 默认骨架屏样式 -->
      <div v-for="i in rows" :key="i" class="skeleton-item" :style="{ width: getWidth(i) }">
        <div class="skeleton-content"></div>
      </div>
    </slot>
  </div>
</template>

<script setup lang="ts">
interface Props {
  rows?: number
  animated?: boolean
}

withDefaults(defineProps<Props>(), {
  rows: 3,
  animated: true
})

/**
 * 根据行号返回宽度
 */
function getWidth(row: number): string {
  // 第一行通常较宽
  if (row === 1) return '100%'
  // 最后一行通常较窄
  if (row === (props?.rows || 3)) return '60%'
  // 中间行随机宽度
  return `${70 + Math.random() * 20}%`
}
</script>

<script lang="ts">
const props = defineProps<Props>()
export default {}
</script>

<style scoped>
.skeleton-wrapper {
  padding: 16px;
}

.skeleton-item {
  height: 16px;
  margin-bottom: 12px;
  border-radius: 4px;
}

.skeleton-content {
  height: 100%;
  background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
  background-size: 200% 100%;
  border-radius: 4px;
}

.skeleton-animated .skeleton-content {
  animation: shimmer 1.5s infinite;
}

@keyframes shimmer {
  0% {
    background-position: 200% 0;
  }
  100% {
    background-position: -200% 0;
  }
}

/* 暗色模式支持 */
:global(.dark) .skeleton-content {
  background: linear-gradient(90deg, #2a2a2a 25%, #3a3a3a 50%, #2a2a2a 75%);
  background-size: 200% 100%;
}
</style>
