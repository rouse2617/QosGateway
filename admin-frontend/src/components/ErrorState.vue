<template>
  <div class="error-state">
    <div class="error-state-icon">
      <el-icon :size="60" color="#f56c6c">
        <CircleClose />
      </el-icon>
    </div>
    <div class="error-state-title">{{ title }}</div>
    <div v-if="errorMessage" class="error-state-message">{{ errorMessage }}</div>
    <div v-if="showDetails && errorDetails" class="error-state-details">
      <el-collapse>
        <el-collapse-item title="错误详情" name="details">
          <pre>{{ errorDetails }}</pre>
        </el-collapse-item>
      </el-collapse>
    </div>
    <div class="error-state-actions">
      <el-button type="primary" @click="handleRetry">
        <el-icon><Refresh /></el-icon>
        重试
      </el-button>
      <el-button v-if="showGoHome" @click="goHome">
        <el-icon><HomeFilled /></el-icon>
        返回首页
      </el-button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { CircleClose, Refresh, HomeFilled } from '@element-plus/icons-vue'

interface Props {
  title?: string
  errorMessage?: string
  errorDetails?: string
  showDetails?: boolean
  showGoHome?: boolean
}

const props = withDefaults(defineProps<Props>(), {
  title: '加载失败',
  errorMessage: '抱歉，数据加载失败',
  showDetails: false,
  showGoHome: false
})

const emit = defineEmits<{
  retry: []
}>()

const router = useRouter()

/**
 * 重试
 */
function handleRetry() {
  emit('retry')
}

/**
 * 返回首页
 */
function goHome() {
  router.push('/')
}
</script>

<style scoped>
.error-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 60px 20px;
  text-align: center;
  min-height: 400px;
}

.error-state-icon {
  margin-bottom: 20px;
}

.error-state-title {
  font-size: 18px;
  color: #303133;
  font-weight: 500;
  margin-bottom: 12px;
}

.error-state-message {
  font-size: 14px;
  color: #909399;
  margin-bottom: 20px;
  max-width: 500px;
}

.error-state-details {
  width: 100%;
  max-width: 600px;
  margin-bottom: 20px;
  text-align: left;
}

.error-state-details pre {
  background: #f5f5f5;
  padding: 12px;
  border-radius: 4px;
  font-size: 12px;
  color: #606266;
  overflow-x: auto;
}

.error-state-actions {
  display: flex;
  gap: 12px;
}

/* 暗色模式 */
:global(.dark) .error-state-title {
  color: #e0e0e0;
}

:global(.dark) .error-state-message {
  color: #a0a0a0;
}

:global(.dark) .error-state-details pre {
  background: #2a2a2a;
  color: #b0b0b0;
}
</style>
