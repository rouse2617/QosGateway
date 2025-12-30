<template>
  <el-container class="layout-container">
    <el-aside width="220px" class="aside">
      <div class="logo">
        <el-icon size="24"><DataAnalysis /></el-icon>
        <span>Token 管理平台</span>
      </div>
      <el-menu
        :default-active="route.path"
        router
        background-color="#001529"
        text-color="#fff"
        active-text-color="#409eff"
      >
        <el-menu-item index="/">
          <el-icon><Odometer /></el-icon>
          <span>仪表盘</span>
        </el-menu-item>
        <el-menu-item index="/apps">
          <el-icon><Grid /></el-icon>
          <span>应用管理</span>
        </el-menu-item>
        <el-menu-item index="/clusters">
          <el-icon><Connection /></el-icon>
          <span>集群配置</span>
        </el-menu-item>
        <el-menu-item index="/connections">
          <el-icon><Link /></el-icon>
          <span>连接限制</span>
        </el-menu-item>
        <el-menu-item index="/emergency">
          <el-icon><Warning /></el-icon>
          <span>紧急模式</span>
        </el-menu-item>
      </el-menu>
    </el-aside>
    <el-container>
      <el-header class="header">
        <div class="header-left">
          <el-breadcrumb separator="/">
            <el-breadcrumb-item :to="{ path: '/' }">首页</el-breadcrumb-item>
            <el-breadcrumb-item>{{ currentTitle }}</el-breadcrumb-item>
          </el-breadcrumb>
        </div>
        <div class="header-right">
          <el-badge :is-dot="wsConnected" :type="wsConnected ? 'success' : 'danger'">
            <el-icon><Connection /></el-icon>
          </el-badge>
          <el-dropdown @command="handleCommand">
            <span class="user-info">
              <el-avatar :size="32" icon="User" />
              <span>{{ authStore.user?.username || 'Admin' }}</span>
            </span>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item command="logout">退出登录</el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
        </div>
      </el-header>
      <el-main class="main">
        <router-view />
      </el-main>
    </el-container>
  </el-container>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import { useWebSocket } from '../composables/useWebSocket'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const { connected: wsConnected } = useWebSocket()

const titles: Record<string, string> = {
  '/': '仪表盘',
  '/apps': '应用管理',
  '/clusters': '集群配置',
  '/connections': '连接限制',
  '/emergency': '紧急模式'
}

const currentTitle = computed(() => titles[route.path] || '')

function handleCommand(command: string) {
  if (command === 'logout') {
    authStore.logout()
    router.push('/login')
  }
}
</script>

<style scoped>
.layout-container {
  height: 100vh;
}

.aside {
  background-color: #001529;
}

.logo {
  height: 64px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  color: #fff;
  font-size: 18px;
  font-weight: bold;
}

.header {
  background: #fff;
  display: flex;
  align-items: center;
  justify-content: space-between;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1);
}

.header-right {
  display: flex;
  align-items: center;
  gap: 20px;
}

.user-info {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
}

.main {
  background: #f0f2f5;
  padding: 20px;
}
</style>
