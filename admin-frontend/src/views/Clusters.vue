<template>
  <div class="clusters-page">
    <el-card>
      <template #header>集群配置</template>
      <el-table :data="clusters" v-loading="loading" stripe>
        <el-table-column prop="cluster_id" label="集群 ID" width="180" />
        <el-table-column prop="max_capacity" label="最大容量" width="150">
          <template #default="{ row }">{{ formatNumber(row.max_capacity) }}/s</template>
        </el-table-column>
        <el-table-column prop="reserved_ratio" label="预留比例" width="120">
          <template #default="{ row }">{{ (row.reserved_ratio * 100).toFixed(0) }}%</template>
        </el-table-column>
        <el-table-column prop="emergency_threshold" label="紧急阈值" width="120">
          <template #default="{ row }">{{ (row.emergency_threshold * 100).toFixed(0) }}%</template>
        </el-table-column>
        <el-table-column prop="max_connections" label="最大连接" width="120" />
        <el-table-column label="操作" width="100">
          <template #default="{ row }">
            <el-button link type="primary" @click="showDialog(row)">编辑</el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <el-dialog v-model="dialogVisible" title="编辑集群" width="500px">
      <el-form ref="formRef" :model="form" label-width="100px">
        <el-form-item label="集群 ID">
          <el-input v-model="form.cluster_id" disabled />
        </el-form-item>
        <el-form-item label="最大容量">
          <el-input-number v-model="form.max_capacity" :min="1" />
          <span class="unit">/秒</span>
        </el-form-item>
        <el-form-item label="预留比例">
          <el-slider v-model="reservedPercent" :min="0" :max="50" :format-tooltip="(v: number) => v + '%'" />
        </el-form-item>
        <el-form-item label="紧急阈值">
          <el-slider v-model="emergencyPercent" :min="50" :max="100" :format-tooltip="(v: number) => v + '%'" />
        </el-form-item>
        <el-form-item label="最大连接">
          <el-input-number v-model="form.max_connections" :min="1" />
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
import { ref, reactive, computed, onMounted } from 'vue'
import { clustersApi } from '../api'
import type { ClusterConfig } from '../types'
import { ElMessage } from 'element-plus'

const clusters = ref<ClusterConfig[]>([])
const loading = ref(false)
const dialogVisible = ref(false)
const submitting = ref(false)

const form = reactive<Partial<ClusterConfig>>({
  cluster_id: '',
  max_capacity: 1000000,
  reserved_ratio: 0.1,
  emergency_threshold: 0.95,
  max_connections: 5000
})

const reservedPercent = computed({
  get: () => (form.reserved_ratio || 0) * 100,
  set: (v) => { form.reserved_ratio = v / 100 }
})

const emergencyPercent = computed({
  get: () => (form.emergency_threshold || 0) * 100,
  set: (v) => { form.emergency_threshold = v / 100 }
})

async function fetchClusters() {
  loading.value = true
  try {
    const { data } = await clustersApi.list()
    clusters.value = data.clusters || []
  } finally {
    loading.value = false
  }
}

function showDialog(cluster: ClusterConfig) {
  Object.assign(form, cluster)
  dialogVisible.value = true
}

async function handleSubmit() {
  submitting.value = true
  try {
    await clustersApi.update(form.cluster_id!, form)
    ElMessage.success('更新成功')
    dialogVisible.value = false
    fetchClusters()
  } catch (e: any) {
    ElMessage.error(e.response?.data?.error || '更新失败')
  } finally {
    submitting.value = false
  }
}

function formatNumber(n: number) {
  return n?.toLocaleString() || '0'
}

onMounted(fetchClusters)
</script>

<style scoped>
.unit {
  margin-left: 8px;
  color: #909399;
}
</style>
