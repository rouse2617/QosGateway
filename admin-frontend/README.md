# Token Management Platform - Admin Frontend

分布式令牌限流管理系统的管理控制台前端。

## 技术栈

- **框架**: Vue 3.4+ (Composition API)
- **构建工具**: Vite 5.0
- **语言**: TypeScript 5.3
- **状态管理**: Pinia 2.1
- **路由**: Vue Router 4.2
- **HTTP客户端**: Axios 1.6
- **UI组件库**: Element Plus 2.4
- **图表库**: ECharts 5.4 + vue-echarts 6.6
- **工具库**: date-fns 3.0
- **测试框架**: Vitest 1.0 + @vue/test-utils 2.4

## 项目结构

```
admin-frontend/
├── src/
│   ├── api/              # API 接口层
│   │   ├── client.ts     # Axios 客户端（带token刷新和重试）
│   │   └── index.ts      # API 方法定义
│   ├── components/       # 可复用组件
│   │   ├── LoadingSkeleton.vue
│   │   ├── EmptyState.vue
│   │   ├── ErrorState.vue
│   │   ├── TableSkeleton.vue
│   │   └── CardSkeleton.vue
│   ├── composables/      # 组合式函数
│   │   ├── useToast.ts   # 消息提示
│   │   ├── useDialog.ts  # 对话框
│   │   ├── useLoading.ts # 加载状态
│   │   ├── useError.ts   # 错误处理
│   │   ├── useTheme.ts   # 主题管理
│   │   ├── useOnline.ts  # 网络状态
│   │   ├── useDebounce.ts
│   │   └── useThrottle.ts
│   ├── layouts/          # 布局组件
│   │   └── MainLayout.vue
│   ├── stores/           # Pinia 状态管理
│   │   ├── auth.ts       # 认证状态
│   │   └── metrics.ts    # 指标数据（带缓存）
│   ├── types/            # TypeScript 类型定义
│   │   └── index.ts
│   ├── utils/            # 工具函数
│   │   ├── formatters.ts # 格式化函数
│   │   ├── validators.ts # 验证函数
│   │   ├── storage.ts    # 安全存储
│   │   └── index.ts
│   ├── views/            # 页面组件
│   │   ├── Login.vue
│   │   ├── Dashboard.vue
│   │   ├── Apps.vue
│   │   ├── Clusters.vue
│   │   ├── Connections.vue
│   │   └── Emergency.vue
│   ├── App.vue
│   └── main.ts
├── tests/                # 测试文件
│   ├── setup.ts
│   ├── utils/
│   └── components/
├── index.html
├── package.json
├── tsconfig.json
├── vite.config.ts
└── vitest.config.ts
```

## 核心功能

### 1. 安全性增强

- **Token 自动刷新**: 当 401 发生时自动刷新 token 并重试请求
- **请求队列机制**: 防止并发 token 刷新
- **安全存储**: Token 使用 Base64 编码存储在 localStorage
- **XSS 防护**: 所有用户输入经过验证和转义
- **CSRF 处理**: 请求头包含 CSRF token
- **指数退避重试**: 网络错误自动重试（最多3次）

### 2. 用户体验优化

- **加载骨架屏**: 数据加载时显示优雅的占位符
- **空状态提示**: 无数据时显示友好的空状态
- **错误边界**: 组件错误不影响整个应用
- **离线检测**: 实时检测网络状态并提示用户
- **Toast 通知**: 统一的成功/错误提示
- **确认对话框**: 删除等危险操作需要二次确认

### 3. 性能优化

- **代码分割**: 路由懒加载，按需加载组件
- **Tree Shaking**: 移除未使用的代码
- **压缩优化**: Terser 压缩，生产环境移除 console
- **缓存策略**: 指标数据 5 秒缓存，减少 API 请求
- **防抖节流**: 输入和滚动事件使用防抖节流
- **手动分包**: Element Plus 和 ECharts 单独打包

### 4. 开发体验

- **TypeScript**: 完整的类型定义
- **Composition API**: 逻辑复用更简单
- **Composables**: 可复用的业务逻辑
- **工具函数**: 丰富的格式化和验证函数
- **测试支持**: Vitest 单元测试配置
- **ESLint**: 代码风格检查

### 5. 响应式设计

- **移动端适配**: 断点优化（xs/sm/md/lg/xl）
- **暗色模式**: 支持亮色/暗色/自动主题
- **弹性布局**: Grid 和 Flexbox 响应式布局

## 可用的脚本

```bash
# 开发服务器
npm run dev

# 生产构建
npm run build

# 构建并检查类型
npm run build:check

# 预览构建结果
npm run preview

# 运行测试
npm run test

# 测试 UI 模式
npm run test:ui

# 测试覆盖率
npm run test:coverage

# 代码检查
npm run lint

# 类型检查
npm run type-check
```

## 主要改进

### 1. 代码结构
- 创建了清晰的组件层次结构
- 业务逻辑与 UI 组件分离
- 使用 Composables 复用逻辑
- 添加完整的 TypeScript 类型

### 2. 错误处理
- 统一的错误处理机制
- 用户友好的错误消息
- 自动重试失败的请求
- 错误边界防止应用崩溃

### 3. 加载状态
- 优雅的骨架屏加载
- 空状态提示
- 加载和错误状态分离
- 防止重复提交

### 4. 表单验证
- 客户端验证
- 实时反馈
- 友好的错误提示
- 防止无效提交

### 5. 主题支持
- 亮色/暗色模式
- 跟随系统设置
- 平滑过渡动画
- 全局样式变量

## 环境要求

- Node.js >= 16.0.0
- npm >= 8.0.0

## 快速开始

```bash
# 安装依赖
npm install

# 启动开发服务器
npm run dev

# 构建生产版本
npm run build
```

## API 代理配置

开发环境下，API 请求会被代理到 `http://localhost:8081`。可以在 `vite.config.ts` 中修改配置。

## 浏览器支持

- Chrome >= 87
- Firefox >= 78
- Safari >= 14
- Edge >= 88

## License

MIT
