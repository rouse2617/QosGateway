package main

import (
	"admin-backend/handlers"
	"admin-backend/middleware"
	"admin-backend/services"
	"log"
	"os"

	"github.com/gin-gonic/gin"
)

func main() {
	// 初始化 Redis
	redisAddr := os.Getenv("REDIS_ADDR")
	if redisAddr == "" {
		redisAddr = "localhost:6379"
	}
	services.InitRedis(redisAddr)

	// 初始化 JWT
	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		jwtSecret = "your-secret-key-change-in-production"
	}
	middleware.InitJWT(jwtSecret)

	// 创建 Gin 引擎
	r := gin.Default()

	// CORS 中间件
	r.Use(middleware.CORS())

	// 健康检查
	r.GET("/health", handlers.Health)

	// 认证路由
	auth := r.Group("/api/v1/auth")
	{
		auth.POST("/login", handlers.Login)
		auth.POST("/refresh", handlers.RefreshToken)
	}

	// API 路由（需要认证）
	api := r.Group("/api/v1")
	api.Use(middleware.AuthMiddleware())
	{
		// 应用管理
		api.GET("/apps", handlers.ListApps)
		api.POST("/apps", handlers.CreateApp)
		api.GET("/apps/:id", handlers.GetApp)
		api.PUT("/apps/:id", handlers.UpdateApp)
		api.DELETE("/apps/:id", handlers.DeleteApp)

		// 集群管理
		api.GET("/clusters", handlers.ListClusters)
		api.GET("/clusters/:id", handlers.GetCluster)
		api.PUT("/clusters/:id", handlers.UpdateCluster)

		// 连接限制
		api.GET("/connections", handlers.GetConnectionStats)
		api.PUT("/connections", handlers.UpdateConnectionLimit)

		// 紧急模式
		api.GET("/emergency", handlers.GetEmergencyStatus)
		api.POST("/emergency/activate", handlers.ActivateEmergency)
		api.POST("/emergency/deactivate", handlers.DeactivateEmergency)

		// 指标
		api.GET("/metrics", handlers.GetMetrics)
		api.GET("/metrics/apps/:id", handlers.GetAppMetrics)
		api.GET("/metrics/connections", handlers.GetConnectionMetrics)
	}

	// WebSocket 实时推送
	r.GET("/ws", middleware.AuthMiddleware(), handlers.WebSocketHandler)

	// 启动服务器
	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}
	log.Printf("Admin backend starting on port %s", port)
	r.Run(":" + port)
}
