<template>
  <div class="table-skeleton">
    <div class="table-skeleton-header">
      <div v-for="col in columns" :key="col" class="skeleton-header-cell">
        <div class="skeleton-shimmer"></div>
      </div>
    </div>
    <div v-for="row in rows" :key="row" class="table-skeleton-body">
      <div v-for="col in columns" :key="col" class="skeleton-body-cell">
        <div class="skeleton-shimmer"></div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
interface Props {
  columns?: number
  rows?: number
}

withDefaults(defineProps<Props>(), {
  columns: 5,
  rows: 10
})
</script>

<style scoped>
.table-skeleton {
  width: 100%;
  border: 1px solid #ebeef5;
  border-radius: 4px;
  overflow: hidden;
}

.table-skeleton-header {
  display: flex;
  background: #f5f7fa;
  border-bottom: 1px solid #ebeef5;
}

.skeleton-header-cell {
  flex: 1;
  padding: 12px;
  height: 40px;
}

.skeleton-header-cell .skeleton-shimmer {
  height: 16px;
  width: 60%;
  margin: 4px 0;
}

.table-skeleton-body {
  display: flex;
  border-bottom: 1px solid #ebeef5;
}

.table-skeleton-body:last-child {
  border-bottom: none;
}

.skeleton-body-cell {
  flex: 1;
  padding: 12px;
  height: 48px;
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
:global(.dark) .table-skeleton {
  border-color: #4a4a4a;
}

:global(.dark) .table-skeleton-header {
  background: #2a2a2a;
  border-bottom-color: #4a4a4a;
}

:global(.dark) .table-skeleton-body {
  border-bottom-color: #4a4a4a;
}

:global(.dark) .skeleton-shimmer {
  background: linear-gradient(90deg, #3a3a3a 25%, #4a4a4a 50%, #3a3a3a 75%);
  background-size: 200% 100%;
}
</style>
