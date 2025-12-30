<template>
  <div class="emergency-page">
    <el-row :gutter="20">
      <el-col :span="12">
        <el-card :class="{ 'emergency-active': status?.active }">
          <template #header>
            <div class="card-header">
              <span>紧急模式状态</span>
              <el-tag :type="status?.active ? 'danger' : 'success'">
                {{ status?.active ? '已激活' : '正常' }}
              </el-tag>
            </div>
          </template>
          
          <el-descriptions :column="1" border v-if="status?.active">
            <el-descriptions-item label="激活原因">{{ status.reason }}</el-descriptions-item>
            <el-descriptions-item label="激活时间">{{ formatDate(status.activated_at) }}</el-descriptions-item>
            <el-descriptions-item label="过期时间">{{ formatDate(status.expires_at) }}</el-descriptions-item>
          </el-descriptions>
          
          <div class="actions" style="margin-top: 20px">
            <el-button v-if="!status?.active" type="danger" @click="showActivateDialog">
              <el-icon><Warning /></el-icon>激活紧急模式
            </el-button>
            <el-button v-else type="success" @click="handleDeactivate" :loading="loading">
              <el-icon><CircleCheck /></el-icon>停用紧急模式
            </el-button>
          </div>
        </el-card>
      </el-col>
      
      <el-col :span="12">
        <el-card>
          <template #header>优先级配额说明</template>
          <el-table :data="priorityData" stripe>
            <el-table-column prop="priority" label="优先级" width="100">
              <template #default="{ row }">
                <el-tag :type="row.type">{{ row.priority }}</el-tag>
              </template>
            </el-table-column>
            <el-table-column prop="ratio" label="紧急模式配额" />
            <el-table-column prop="desc" label="说明" />
          </el-table>
        </el-card>
      </el-col>
    </el-row>

    <el-card style="margin-top: 20px">
      <template #header>紧急模式历史</template>
      <el-timeline>
        <el-timeline-item
          v-for="item in history"
          :key="item.timestamp"
          :timestamp="formatDate(item.timestamp)"
          :type="item.type === 'activated' ? 'danger' : 'success'"
        >
          {{ item.type === 'activated' ? '激活' : '停用' }} - {{ item.reason }}
        </el-timeline-item>
      </el-timeline>
    </el-card>

    <el-dialog v-model="dialogVisible" title="激活紧急模式" width="400px">
      <el-alert type="warning" :closable="false" style="margin-bottom: 20px">
        激活紧急模式后，低优先级应用的请求将被限制或拒绝。
      </el-alert>
      <el-form :model="form" label-width="80px">
        <el-form-item label="原因">
          <el-input v-model="form.reason" placeholder="请输入激活原因" />
        </el-form-item>
        <el-form-item label="持续时间">
          <el-select v-model="form.duration">
            <el-option :value="300" label="5 分钟" />
            <el-option :value="600" label="10 分钟" />
            <el-option :value="1800" label="30 分钟" />
            <el-option :value="3600" label="1 小时" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="danger" @click="handleActivate" :loading="loading">确认激活</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted, onUnmounted } from 'vue'
import { emergencyApi } from '../api'
import type { EmergencyStatus } from '../types'
import { ElMessage } from 'element-plus'

const status = ref<EmergencyStatus | null>(null)
const loading = ref(false)
const dialogVisible = ref(false)

const form = reactive({
  reason: '',
  duration: 300
})

const priorityData = [
  { priority: 'P0', ratio: '100%', desc: '完全保障', type: 'danger' },
  { priority: 'P1', ratio: '50%', desc: '部分保障', type: 'warning' },
  { priority: 'P2', ratio: '10%', desc: '最低保障', type: 'info' },
  { priority: 'P3+', ratio: '0%', desc: '完全限制', type: 'success' }
]

const history = ref([
  { type: 'deactivated', reason: '系统恢复正常', timestamp: '2024-01-15T10:30:00Z' },
  { type: 'activated', reason: '流量突增', timestamp: '2024-01-15T10:00:00Z' }
])

async function fetchStatus() {
  try {
    const { data } = await emergencyApi.getStatus()
    status.value = data
  } catch (e) {
    status.value = { active: false, reason: '', activated_at: '', expires_at: '', duration: 0 }
  }
}

function showActivateDialog() {
  form.reason = ''
  form.duration = 300
  dialogVisible.value = true
}

async function handleActivate() {
  loading.value = true
  try {
    await emergencyApi.activate(form.reason || '手动激活', form.duration)
    ElMessage.success('紧急模式已激活')
    dialogVisible.value = false
    fetchStatus()
  } catch (e: any) {
    ElMessage.error(e.response?.data?.error || '激活失败')
  } finally {
    loading.value = false
  }
}

async function handleDeactivate() {
  loading.value = true
  try {
    await emergencyApi.deactivate()
    ElMessage.success('紧急模式已停用')
    fetchStatus()
  } catch (e: any) {
    ElMessage.error(e.response?.data?.error || '停用失败')
  } finally {
    loading.value = false
  }
}

function formatDate(ts: string) {
  if (!ts) return '-'
  return new Date(ts).toLocaleString()
}

let refreshTimer: number | null = null

onMounted(() => {
  fetchStatus()
  refreshTimer = window.setInterval(fetchStatus, 5000)
})

onUnmounted(() => {
  if (refreshTimer) clearInterval(refreshTimer)
})
</script>

<style scoped>
.emergency-active {
  border-color: #f56c6c;
  background: linear-gradient(135deg, #fef0f0 0%, #fff 100%);
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
</style>
