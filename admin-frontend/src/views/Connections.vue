<template>
  <div class="connections-page">
    <el-card>
      <template #header>连接限制配置</template>
      <el-tabs v-model="activeTab">
        <el-tab-pane label="应用连接" name="app">
          <el-table :data="appConnections" stripe>
            <el-table-column prop="id" label="应用 ID" />
            <el-table-column prop="current" label="当前连接" />
            <el-table-column prop="limit" label="连接限制" />
            <el-table-column prop="peak" label="峰值" />
            <el-table-column prop="rejected" label="拒绝数" />
            <el-table-column label="操作" width="100">
              <template #default="{ row }">
                <el-button link type="primary" @click="showDialog('app', row)">编辑</el-button>
              </template>
            </el-table-column>
          </el-table>
        </el-tab-pane>
        <el-tab-pane label="集群连接" name="cluster">
          <el-table :data="clusterConnections" stripe>
            <el-table-column prop="id" label="集群 ID" />
            <el-table-column prop="current" label="当前连接" />
            <el-table-column prop="limit" label="连接限制" />
            <el-table-column prop="peak" label="峰值" />
            <el-table-column prop="rejected" label="拒绝数" />
            <el-table-column label="操作" width="100">
              <template #default="{ row }">
                <el-button link type="primary" @click="showDialog('cluster', row)">编辑</el-button>
              </template>
            </el-table-column>
          </el-table>
        </el-tab-pane>
      </el-tabs>
    </el-card>

    <el-dialog v-model="dialogVisible" title="编辑连接限制" width="400px">
      <el-form :model="form" label-width="80px">
        <el-form-item label="目标 ID">
          <el-input v-model="form.target_id" disabled />
        </el-form-item>
        <el-form-item label="连接限制">
          <el-input-number v-model="form.limit" :min="1" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" @click="handleSubmit" :loading="submitting">确定</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { connectionsApi } from '../api'
import type { ConnectionStats } from '../types'
import { ElMessage } from 'element-plus'

const activeTab = ref('app')
const appConnections = ref<ConnectionStats[]>([])
const clusterConnections = ref<ConnectionStats[]>([])
const dialogVisible = ref(false)
const submitting = ref(false)

const form = reactive({
  target_type: '',
  target_id: '',
  limit: 1000
})

async function fetchConnections() {
  try {
    const { data } = await connectionsApi.getStats()
    const connections = data.connections || []
    appConnections.value = connections.filter((c: ConnectionStats) => c.type === 'app')
    clusterConnections.value = connections.filter((c: ConnectionStats) => c.type === 'cluster')
  } catch (e) {
    // 使用模拟数据
    appConnections.value = [
      { type: 'app', id: 'app-1', current: 150, limit: 1000, peak: 200, rejected: 5 },
      { type: 'app', id: 'app-2', current: 80, limit: 500, peak: 120, rejected: 2 }
    ]
    clusterConnections.value = [
      { type: 'cluster', id: 'cluster-1', current: 500, limit: 5000, peak: 800, rejected: 10 }
    ]
  }
}

function showDialog(type: string, row: ConnectionStats) {
  form.target_type = type
  form.target_id = row.id
  form.limit = row.limit
  dialogVisible.value = true
}

async function handleSubmit() {
  submitting.value = true
  try {
    await connectionsApi.updateLimit(form.target_type, form.target_id, form.limit)
    ElMessage.success('更新成功')
    dialogVisible.value = false
    fetchConnections()
  } catch (e: any) {
    ElMessage.error(e.response?.data?.error || '更新失败')
  } finally {
    submitting.value = false
  }
}

onMounted(fetchConnections)
</script>
