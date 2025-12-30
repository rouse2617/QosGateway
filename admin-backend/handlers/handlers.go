package handlers

import (
	"admin-backend/middleware"
	"admin-backend/models"
	"admin-backend/services"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

// Health 健康检查
func Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":    "ok",
		"timestamp": time.Now().Unix(),
	})
}

// Login 登录
func Login(c *gin.Context) {
	var req models.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 简单验证（生产环境应使用数据库）
	if req.Username == "admin" && req.Password == "admin123" {
		accessToken, refreshToken, err := middleware.GenerateToken("1", req.Username, "admin")
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
			return
		}

		c.JSON(http.StatusOK, models.TokenResponse{
			AccessToken:  accessToken,
			RefreshToken: refreshToken,
			ExpiresIn:    3600,
		})
		return
	}

	c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
}

// RefreshToken 刷新 Token
func RefreshToken(c *gin.Context) {
	var req struct {
		RefreshToken string `json:"refresh_token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	claims, err := middleware.ValidateToken(req.RefreshToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid refresh token"})
		return
	}

	accessToken, refreshToken, err := middleware.GenerateToken(claims.UserID, claims.Username, claims.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, models.TokenResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    3600,
	})
}

// ListApps 列出所有应用
func ListApps(c *gin.Context) {
	apps, err := services.ListAppConfigs()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"apps": apps})
}

// CreateApp 创建应用
func CreateApp(c *gin.Context) {
	var config models.AppConfig
	if err := c.ShouldBindJSON(&config); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := services.SetAppConfig(&config); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"success": true, "app_id": config.AppID})
}

// GetApp 获取应用
func GetApp(c *gin.Context) {
	appID := c.Param("id")
	config, err := services.GetAppConfig(appID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if config == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	c.JSON(http.StatusOK, config)
}

// UpdateApp 更新应用
func UpdateApp(c *gin.Context) {
	appID := c.Param("id")
	var config models.AppConfig
	if err := c.ShouldBindJSON(&config); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	config.AppID = appID

	if err := services.SetAppConfig(&config); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// DeleteApp 删除应用
func DeleteApp(c *gin.Context) {
	appID := c.Param("id")
	if err := services.DeleteAppConfig(appID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.Status(http.StatusNoContent)
}

// ListClusters 列出所有集群
func ListClusters(c *gin.Context) {
	clusters, err := services.ListClusterConfigs()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"clusters": clusters})
}

// GetCluster 获取集群
func GetCluster(c *gin.Context) {
	clusterID := c.Param("id")
	config, err := services.GetClusterConfig(clusterID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if config == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	c.JSON(http.StatusOK, config)
}

// UpdateCluster 更新集群
func UpdateCluster(c *gin.Context) {
	clusterID := c.Param("id")
	var config models.ClusterConfig
	if err := c.ShouldBindJSON(&config); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	config.ClusterID = clusterID

	if err := services.SetClusterConfig(&config); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// GetConnectionStats 获取连接统计
func GetConnectionStats(c *gin.Context) {
	// 从 Redis 获取连接统计
	c.JSON(http.StatusOK, gin.H{"connections": []models.ConnectionStats{}})
}

// UpdateConnectionLimit 更新连接限制
func UpdateConnectionLimit(c *gin.Context) {
	var req models.ConnectionLimit
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// GetEmergencyStatus 获取紧急模式状态
func GetEmergencyStatus(c *gin.Context) {
	status, err := services.GetEmergencyStatus()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, status)
}

// ActivateEmergency 激活紧急模式
func ActivateEmergency(c *gin.Context) {
	var req models.EmergencyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		req.Reason = "manual"
		req.Duration = 300
	}

	if err := services.ActivateEmergency(req.Reason, req.Duration); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// DeactivateEmergency 停用紧急模式
func DeactivateEmergency(c *gin.Context) {
	if err := services.DeactivateEmergency(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// GetMetrics 获取系统指标
func GetMetrics(c *gin.Context) {
	metrics, err := services.GetMetrics()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, metrics)
}

// GetAppMetrics 获取应用指标
func GetAppMetrics(c *gin.Context) {
	appID := c.Param("id")
	metrics, err := services.GetAppMetrics(appID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, metrics)
}

// GetConnectionMetrics 获取连接指标
func GetConnectionMetrics(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"connections": []models.ConnectionStats{}})
}

// WebSocket 相关
var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

var wsClients = make(map[*websocket.Conn]bool)
var wsMutex sync.RWMutex

// WebSocketHandler WebSocket 处理
func WebSocketHandler(c *gin.Context) {
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}
	defer conn.Close()

	wsMutex.Lock()
	wsClients[conn] = true
	wsMutex.Unlock()

	defer func() {
		wsMutex.Lock()
		delete(wsClients, conn)
		wsMutex.Unlock()
	}()

	// 启动指标推送
	go pushMetrics(conn)

	// 订阅 Redis 事件
	pubsub := services.SubscribeEvents()
	defer pubsub.Close()

	ch := pubsub.Channel()
	for msg := range ch {
		wsMsg := models.WebSocketMessage{
			Type:      "event",
			Data:      msg.Payload,
			Timestamp: time.Now(),
		}
		conn.WriteJSON(wsMsg)
	}
}

func pushMetrics(conn *websocket.Conn) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		metrics, err := services.GetMetrics()
		if err != nil {
			continue
		}

		wsMsg := models.WebSocketMessage{
			Type:      "metrics",
			Data:      metrics,
			Timestamp: time.Now(),
		}

		if err := conn.WriteJSON(wsMsg); err != nil {
			return
		}
	}
}
