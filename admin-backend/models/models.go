package models

import "time"

// AppConfig 应用配置
type AppConfig struct {
	AppID           string    `json:"app_id" binding:"required"`
	GuaranteedQuota int64     `json:"guaranteed_quota" binding:"required,min=1"`
	BurstQuota      int64     `json:"burst_quota"`
	Priority        int       `json:"priority" binding:"min=0,max=3"`
	MaxBorrow       int64     `json:"max_borrow"`
	MaxConnections  int64     `json:"max_connections"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// ClusterConfig 集群配置
type ClusterConfig struct {
	ClusterID          string    `json:"cluster_id" binding:"required"`
	MaxCapacity        int64     `json:"max_capacity" binding:"required,min=1"`
	ReservedRatio      float64   `json:"reserved_ratio"`
	EmergencyThreshold float64   `json:"emergency_threshold"`
	MaxConnections     int64     `json:"max_connections"`
	UpdatedAt          time.Time `json:"updated_at"`
}

// ConnectionLimit 连接限制配置
type ConnectionLimit struct {
	TargetType string `json:"target_type" binding:"required,oneof=app cluster"`
	TargetID   string `json:"target_id" binding:"required"`
	Limit      int64  `json:"limit" binding:"required,min=1"`
}

// ConnectionStats 连接统计
type ConnectionStats struct {
	Type     string `json:"type"`
	ID       string `json:"id"`
	Current  int64  `json:"current"`
	Limit    int64  `json:"limit"`
	Peak     int64  `json:"peak"`
	Rejected int64  `json:"rejected"`
}

// EmergencyStatus 紧急模式状态
type EmergencyStatus struct {
	Active      bool      `json:"active"`
	Reason      string    `json:"reason"`
	ActivatedAt time.Time `json:"activated_at"`
	ExpiresAt   time.Time `json:"expires_at"`
	Duration    int64     `json:"duration"`
}

// EmergencyRequest 紧急模式请求
type EmergencyRequest struct {
	Reason   string `json:"reason"`
	Duration int64  `json:"duration"`
}

// Metrics 系统指标
type Metrics struct {
	RequestsTotal       int64   `json:"requests_total"`
	RejectedTotal       int64   `json:"rejected_total"`
	L3Hits              int64   `json:"l3_hits"`
	CacheHitRatio       float64 `json:"cache_hit_ratio"`
	EmergencyActive     bool    `json:"emergency_active"`
	DegradationLevel    string  `json:"degradation_level"`
	ReconcileCorrections int64  `json:"reconcile_corrections"`
}

// AppMetrics 应用指标
type AppMetrics struct {
	AppID           string `json:"app_id"`
	RequestsTotal   int64  `json:"requests_total"`
	RejectedTotal   int64  `json:"rejected_total"`
	TokensAvailable int64  `json:"tokens_available"`
	PendingCost     int64  `json:"pending_cost"`
}

// User 用户
type User struct {
	ID       string `json:"id"`
	Username string `json:"username"`
	Role     string `json:"role"`
}

// LoginRequest 登录请求
type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// TokenResponse Token 响应
type TokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int64  `json:"expires_in"`
}

// WebSocketMessage WebSocket 消息
type WebSocketMessage struct {
	Type      string      `json:"type"`
	Data      interface{} `json:"data"`
	Timestamp time.Time   `json:"timestamp"`
}
