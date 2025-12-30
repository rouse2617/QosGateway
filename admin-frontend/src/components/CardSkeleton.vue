<template>
  <div class="card-skeleton">
    <div v-if="showHeader" class="card-skeleton-header">
      <div class="skeleton-title">
        <div class="skeleton-shimmer"></div>
      </div>
    </div>
    <div class="card-skeleton-body">
      <slot>
        <div v-for="i in lines" :key="i" class="skeleton-line" :style="{ width: getLineWidth(i) }">
          <div class="skeleton-shimmer"></div>
        </div>
      </slot>
    </div>
  </div>
</template>

<script setup lang="ts">
interface Props {
  showHeader?: boolean
  lines?: number
}

const props = withDefaults(defineProps<Props>(), {
  showHeader: true,
  lines: 3
})

/**
 * 生成随机行宽
 */
function getLineWidth(index: number): string {
  if (index === props.lines) return '70%'
  return `${85 + Math.random() * 10}%`
}
</script>

<style scoped>
.card-skeleton {
  border: 1px solid #ebeef5;
  border-radius: 4px;
  padding: 16px;
  background: #fff;
}

.card-skeleton-header {
  margin-bottom: 16px;
  padding-bottom: 12px;
  border-bottom: 1px solid #ebeef5;
}

.skeleton-title {
  height: 24px;
  width: 40%;
}

.card-skeleton-body {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.skeleton-line {
  height: 16px;
}

.skeleton-shimmer {
  height: 100%;
  background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
  background-size: 200% 100%;
  border-radius: 4px;
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

/* 暗色模式 */
:global(.dark) .card-skeleton {
  background: #1a1a1a;
  border-color: #3a3a3a;
}

:global(.dark) .card-skeleton-header {
  border-bottom-color: #3a3a3a;
}

:global(.dark) .skeleton-shimmer {
  background: linear-gradient(90deg, #2a2a2a 25%, #3a3a3a 50%, #2a2a2a 75%);
  background-size: 200% 100%;
}
</style>
