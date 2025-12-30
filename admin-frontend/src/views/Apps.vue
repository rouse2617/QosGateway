<template>
  <div class="apps-page">
    <el-card>
      <template #header>
        <div class="card-header">
          <span>应用管理</span>
          <el-button type="primary" @click="showDialog()">
            <el-icon><Plus /></el-icon>新建应用
          </el-button>
        </div>
      </template>

      <el-table :data="apps" v-loading="loading" stripe>
        <el-table-column prop="app_id" label="应用 ID" width="180" />
        <el-table-column prop="guaranteed_quota" label="保证配额" width="120">
          <template #default="{ row }">{{ formatNumber(row.guaranteed_quota) }}/s</template>
        </el-table-column>
        <el-table-column prop="burst_quota" label="突发配额" width="120">
          <template #default="{ row }">{{ formatNumber(row.burst_quota) }}</template>
        </el-table-column>
        <el-table-column prop="priority" label="优先级" width="100">
          <template #default="{ row }">
            <el-tag :type="priorityType(row.priority)">P{{ row.priority }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="max_connections" label="最大连接" width="100" />
        <el-table-column prop="updated_at" label="更新时间" width="180">
          <template #default="{ row }">{{ formatDate(row.updated_at) }}</template>
        </el-table-column>
        <el-table-column label="操作" width="150" fixed="right">
          <template #default="{ row }">
            <el-button link type="primary" @click="showDialog(row)">编辑</el-button>
            <el-popconfirm title="确定删除?" @confirm="handleDelete(row.app_id)">
              <template #reference>
                <el-button link type="danger">删除</el-button>
              </template>
            </el-popconfirm>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <!-- 编辑对话框 -->
    <el-dialog v-model="dialogVisible" :title="isEdit ? '编辑应用' : '新建应用'" width="500px">
      <el-form ref="formRef" :model="form" :rules="rules" label-width="100px">
        <el-form-item label="应用 ID" prop="app_id">
          <el-input v-model="form.app_id" :disabled="isEdit" placeholder="唯一标识符" />
        </el-form-item>
        <el-form-item label="保证配额" prop="guaranteed_quota">
          <el-input-number v-model="form.guaranteed_quota" :min="1" :max="10000000" />
          <span class="unit">/秒</span>
        </el-form-item>
        <el-form-item label="突发配额" prop="burst_quota">
          <el-input-number v-model="form.burst_quota" :min="1" :max="10000000" />
        </el-form-item>
        <el-form-item label="优先级" prop="priority">
          <el-select v-model="form.priority">
            <el-option :value="0" label="P0 - 最高" />
            <el-option :value="1" label="P1 - 高" />
            <el-option :value="2" label="P2 - 中" />
            <el-option :value="3" label="P3 - 低" />
          </el-select>
        </el-form-item>
        <el-form-item label="最大借用">
          <el-input-number v-model="form.max_borrow" :min="0" />
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
import { ref, reactive, onMounted } from 'vue'
import { appsApi } from '../api'
import type { AppConfig } from '../types'
import { ElMessage, type FormInstance } from 'element-plus'

const apps = ref<AppConfig[]>([])
const loading = ref(false)
const dialogVisible = ref(false)
const isEdit = ref(false)
const submitting = ref(false)
const formRef = ref<FormInstance>()

const form = reactive<Partial<AppConfig>>({
  app_id: '',
  guaranteed_quota: 10000,
  burst_quota: 50000,
  priority: 2,
  max_borrow: 10000,
  max_connections: 1000
})

const rules = {
  app_id: [{ required: true, message: '请输入应用 ID', trigger: 'blur' }],
  guaranteed_quota: [{ required: true, message: '请输入保证配额', trigger: 'blur' }]
}

async function fetchApps() {
  loading.value = true
  try {
    const { data } = await appsApi.list()
    apps.value = data.apps || []
  } finally {
    loading.value = false
  }
}

function showDialog(app?: AppConfig) {
  isEdit.value = !!app
  if (app) {
    Object.assign(form, app)
  } else {
    Object.assign(form, {
      app_id: '',
      guaranteed_quota: 10000,
      burst_quota: 50000,
      priority: 2,
      max_borrow: 10000,
      max_connections: 1000
    })
  }
  dialogVisible.value = true
}

async function handleSubmit() {
  if (!formRef.value) return
  await formRef.value.validate(async (valid) => {
    if (!valid) return
    submitting.value = true
    try {
      if (isEdit.value) {
        await appsApi.update(form.app_id!, form)
      } else {
        await appsApi.create(form)
      }
      ElMessage.success(isEdit.value ? '更新成功' : '创建成功')
      dialogVisible.value = false
      fetchApps()
    } catch (e: any) {
      ElMessage.error(e.response?.data?.error || '操作失败')
    } finally {
      submitting.value = false
    }
  })
}

async function handleDelete(appId: string) {
  try {
    await appsApi.delete(appId)
    ElMessage.success('删除成功')
    fetchApps()
  } catch (e: any) {
    ElMessage.error(e.response?.data?.error || '删除失败')
  }
}

function formatNumber(n: number) {
  return n?.toLocaleString() || '0'
}

function formatDate(ts: string) {
  if (!ts) return '-'
  return new Date(ts).toLocaleString()
}

function priorityType(p: number) {
  return ['danger', 'warning', 'info', 'success'][p] || 'info'
}

onMounted(fetchApps)
</script>

<style scoped>
.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.unit {
  margin-left: 8px;
  color: #909399;
}
</style>
