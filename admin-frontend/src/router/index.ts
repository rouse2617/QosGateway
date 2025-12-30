import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'Login',
      component: () => import('../views/Login.vue')
    },
    {
      path: '/',
      component: () => import('../layouts/MainLayout.vue'),
      meta: { requiresAuth: true },
      children: [
        {
          path: '',
          name: 'Dashboard',
          component: () => import('../views/Dashboard.vue')
        },
        {
          path: 'apps',
          name: 'Apps',
          component: () => import('../views/Apps.vue')
        },
        {
          path: 'clusters',
          name: 'Clusters',
          component: () => import('../views/Clusters.vue')
        },
        {
          path: 'connections',
          name: 'Connections',
          component: () => import('../views/Connections.vue')
        },
        {
          path: 'emergency',
          name: 'Emergency',
          component: () => import('../views/Emergency.vue')
        }
      ]
    }
  ]
})

router.beforeEach((to, _from, next) => {
  const authStore = useAuthStore()
  
  if (to.meta.requiresAuth && !authStore.isAuthenticated) {
    next('/login')
  } else if (to.path === '/login' && authStore.isAuthenticated) {
    next('/')
  } else {
    next()
  }
})

export default router
