<template>
  <div class="login-container">
    <el-card class="login-card" shadow="always">
      <template #header>
        <div class="card-header">
          <el-icon :size="40" color="#409eff"><DataAnalysis /></el-icon>
          <h1>Token 管理平台</h1>
          <p class="subtitle">分布式令牌限流管理系统</p>
        </div>
      </template>

      <el-form
        ref="formRef"
        :model="form"
        :rules="formRules"
        label-position="top"
        size="large"
        @submit.prevent="handleLogin"
      >
        <el-form-item label="用户名" prop="username">
          <el-input
            v-model="form.username"
            placeholder="请输入用户名"
            :prefix-icon="User"
            clearable
            autofocus
            @keyup.enter="handleLogin"
          />
        </el-form-item>

        <el-form-item label="密码" prop="password">
          <el-input
            v-model="form.password"
            type="password"
            placeholder="请输入密码"
            :prefix-icon="Lock"
            show-password
            clearable
            @keyup.enter="handleLogin"
          />
        </el-form-item>

        <el-form-item>
          <el-button
            type="primary"
            native-type="submit"
            :loading="authStore.loginLoading"
            :disabled="!canSubmit"
            style="width: 100%"
            size="large"
          >
            {{ authStore.loginLoading ? '登录中...' : '登录' }}
          </el-button>
        </el-form-item>
      </el-form>

      <!-- 离线提示 -->
      <div v-if="!isOnline" class="offline-warning">
        <el-alert
          type="error"
          :closable="false"
          show-icon
        >
          网络连接已断开，请检查网络设置
        </el-alert>
      </div>
    </el-card>

    <!-- 页脚信息 -->
    <div class="login-footer">
      <p>© 2024 Token Management Platform. All rights reserved.</p>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, computed } from 'vue'
import { useRouter } from 'vue-router'
import { User, Lock, DataAnalysis } from '@element-plus/icons-vue'
import { useAuthStore } from '../stores/auth'
import { useToast } from '../composables'
import { useOnline } from '../composables'
import { validateUsername, validatePassword } from '../utils'
import type { FormInstance, FormRules } from 'element-plus'

const router = useRouter()
const authStore = useAuthStore()
const { success, showError } = useToast()
const { isOnline } = useOnline()

const formRef = ref<FormInstance>()

const form = reactive({
  username: '',
  password: ''
})

// 表单验证规则
const formRules: FormRules = {
  username: [
    { required: true, message: '请输入用户名', trigger: 'blur' },
    {
      validator: (_rule, value, callback) => {
        if (value && !validateUsername(value)) {
          callback(new Error('用户名格式不正确（3-20位字母数字下划线）'))
        } else {
          callback()
        }
      },
      trigger: 'blur'
    }
  ],
  password: [
    { required: true, message: '请输入密码', trigger: 'blur' },
    {
      validator: (_rule, value, callback) => {
        if (value && value.length < 6) {
          callback(new Error('密码至少需要6个字符'))
        } else {
          callback()
        }
      },
      trigger: 'blur'
    }
  ]
}

// 是否可以提交
const canSubmit = computed(() => {
  return form.username.trim().length > 0 && form.password.trim().length >= 6 && isOnline.value
})

/**
 * 处理登录
 */
async function handleLogin() {
  if (!formRef.value) return

  await formRef.value.validate(async (valid) => {
    if (!valid) return

    try {
      await authStore.login(form.username.trim(), form.password)
      success('登录成功，正在跳转...')
      router.push('/')
    } catch (err: any) {
      showError(err, '登录失败，请检查用户名和密码')
    }
  })
}
</script>

<style scoped>
.login-container {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  padding: 20px;
  position: relative;
  overflow: hidden;
}

.login-container::before {
  content: '';
  position: absolute;
  top: -50%;
  left: -50%;
  width: 200%;
  height: 200%;
  background: radial-gradient(circle, rgba(255,255,255,0.1) 1px, transparent 1px);
  background-size: 50px 50px;
  animation: backgroundMove 20s linear infinite;
}

@keyframes backgroundMove {
  0% {
    transform: translate(0, 0);
  }
  100% {
    transform: translate(50px, 50px);
  }
}

.login-card {
  width: 100%;
  max-width: 420px;
  z-index: 1;
  border-radius: 12px;
  backdrop-filter: blur(10px);
  background: rgba(255, 255, 255, 0.95);
}

.card-header {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  text-align: center;
}

.card-header h1 {
  margin: 0;
  font-size: 24px;
  font-weight: 600;
  color: #303133;
}

.subtitle {
  margin: 0;
  font-size: 14px;
  color: #909399;
}

.offline-warning {
  margin-top: 16px;
}

.login-footer {
  margin-top: 24px;
  text-align: center;
  color: rgba(255, 255, 255, 0.8);
  font-size: 13px;
  z-index: 1;
}

.login-footer p {
  margin: 0;
}

/* 暗色模式 */
:global(.dark) .login-card {
  background: rgba(30, 30, 30, 0.95);
}

:global(.dark) .card-header h1 {
  color: #e0e0e0;
}

:global(.dark) .subtitle {
  color: #a0a0a0;
}

/* 响应式设计 */
@media (max-width: 480px) {
  .login-card {
    max-width: 100%;
  }

  .card-header h1 {
    font-size: 20px;
  }
}
</style>
