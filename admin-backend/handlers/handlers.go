// Package handlers provides HTTP request handlers for the admin backend API.
package handlers

import (
	"admin-backend/logger"
	"admin-backend/middleware"
	"admin-backend/models"
	"admin-backend/storage"
	"admin-backend/validation"
	"context"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

const (
	// DefaultWebSocketReadTimeout is the default timeout for WebSocket reads
	DefaultWebSocketReadTimeout = 60 * time.Second
	// MetricsPushInterval is the interval between metrics pushes to WebSocket clients
	MetricsPushInterval = 5 * time.Second
)

// Handler holds dependencies for HTTP handlers.
type Handler struct {
	storage     storage.Storage
	wsUpgrader  *websocket.Upgrader
	wsClients   map[*websocket.Conn]bool
	wsMutex     sync.RWMutex
	requestOpts map[context.Context]context.CancelFunc
	reqOptsMu   sync.RWMutex
}

// NewHandler creates a new handler instance with the given storage backend.
func NewHandler(store storage.Storage) *Handler {
	return &Handler{
		storage: store,
		wsUpgrader: &websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool {
				// In production, implement proper origin checking
				return true
			},
			HandshakeTimeout: DefaultWebSocketReadTimeout,
		},
		wsClients:   make(map[*websocket.Conn]bool),
		requestOpts: make(map[context.Context]context.CancelFunc),
	}
}

// Close gracefully closes the handler and cleans up resources.
func (h *Handler) Close() error {
	h.wsMutex.Lock()
	defer h.wsMutex.Unlock()

	// Close all WebSocket connections
	for conn := range h.wsClients {
		conn.Close()
		delete(h.wsClients, conn)
	}

	return nil
}

// Health handles health check requests.
// @Summary Health check
// @Description Check if the API is healthy
// @Tags health
// @Accept json
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Router /health [get]
func (h *Handler) Health(c *gin.Context) {
	// Check storage health
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	if err := h.storage.Ping(ctx); err != nil {
		logger.Errorw("health check failed", "error", err)
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status":    "unhealthy",
			"timestamp": time.Now().Unix(),
			"error":     "storage unavailable",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":    "healthy",
		"timestamp": time.Now().Unix(),
	})
}

// Login handles user authentication requests.
// @Summary User login
// @Description Authenticate a user and return JWT tokens
// @Tags auth
// @Accept json
// @Produce json
// @Param request body models.LoginRequest true "Login credentials"
// @Success 200 {object} models.TokenResponse
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Invalid credentials"
// @Router /api/v1/auth/login [post]
func (h *Handler) Login(c *gin.Context) {
	var req models.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request format"})
		return
	}

	// Validate username
	if err := validation.ValidateUsername(req.Username); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate password
	if err := validation.ValidatePassword(req.Password); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Authenticate user (simplified for demo - use database in production)
	// TODO: Replace with proper authentication against user database
	if req.Username == "admin" && req.Password == "admin123" {
		accessToken, refreshToken, err := middleware.GenerateToken("1", req.Username, "admin")
		if err != nil {
			logger.Errorw("failed to generate token", "error", err, "username", req.Username)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
			return
		}

		logger.Infow("user logged in",
			"request_id", c.GetString(middleware.RequestIDKey),
			"username", req.Username,
		)

		c.JSON(http.StatusOK, models.TokenResponse{
			AccessToken:  accessToken,
			RefreshToken: refreshToken,
			ExpiresIn:    3600,
		})
		return
	}

	// Invalid credentials
	c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
}

// RefreshToken handles token refresh requests.
// @Summary Refresh access token
// @Description Refresh an access token using a refresh token
// @Tags auth
// @Accept json
// @Produce json
// @Param request body object{refresh_token=string} true "Refresh token"
// @Success 200 {object} models.TokenResponse
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Invalid token"
// @Router /api/v1/auth/refresh [post]
func (h *Handler) RefreshToken(c *gin.Context) {
	var req struct {
		RefreshToken string `json:"refresh_token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request format"})
		return
	}

	// Validate refresh token
	claims, err := middleware.ValidateToken(req.RefreshToken)
	if err != nil {
		logger.Warnw("invalid refresh token",
			"request_id", c.GetString(middleware.RequestIDKey),
			"error", err,
		)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid refresh token"})
		return
	}

	// Generate new tokens
	accessToken, refreshToken, err := middleware.GenerateToken(claims.UserID, claims.Username, claims.Role)
	if err != nil {
		logger.Errorw("failed to generate token", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, models.TokenResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    3600,
	})
}

// ListApps returns all application configurations.
// @Summary List all applications
// @Description Get a list of all application configurations
// @Tags apps
// @Accept json
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /api/v1/apps [get]
func (h *Handler) ListApps(c *gin.Context) {
	ctx := h.getRequestContext(c, 5*time.Second)
	defer h.cancelRequestContext(c)

	apps, err := h.storage.ListAppConfigs(ctx)
	if err != nil {
		logger.Errorw("failed to list apps",
			"request_id", c.GetString(middleware.RequestIDKey),
			"error", err,
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list applications"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"apps": apps})
}

// CreateApp creates a new application configuration.
// @Summary Create application
// @Description Create a new application configuration
// @Tags apps
// @Accept json
// @Produce json
// @Param request body models.AppConfig true "Application configuration"
// @Success 201 {object} map[string]interface{}
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /api/v1/apps [post]
func (h *Handler) CreateApp(c *gin.Context) {
	var config models.AppConfig
	if err := c.ShouldBindJSON(&config); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request format"})
		return
	}

	// Validate app ID
	if err := validation.ValidateAppID(config.AppID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate config
	if err := validation.ValidateAppConfig(config.GuaranteedQuota, config.BurstQuota, config.Priority); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := h.getRequestContext(c, 5*time.Second)
	defer h.cancelRequestContext(c)

	if err := h.storage.SetAppConfig(ctx, &config); err != nil {
		logger.Errorw("failed to create app",
			"request_id", c.GetString(middleware.RequestIDKey),
			"app_id", config.AppID,
			"error", err,
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create application"})
		return
	}

	logger.Infow("app created",
		"request_id", c.GetString(middleware.RequestIDKey),
		"user_id", c.GetString(middleware.UserIDKey),
		"app_id", config.AppID,
	)

	c.JSON(http.StatusCreated, gin.H{"success": true, "app_id": config.AppID})
}

// GetApp retrieves an application configuration by ID.
// @Summary Get application
// @Description Get an application configuration by ID
// @Tags apps
// @Accept json
// @Produce json
// @Param id path string true "Application ID"
// @Success 200 {object} models.AppConfig
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 404 {object} map[string]string "Not found"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /api/v1/apps/{id} [get]
func (h *Handler) GetApp(c *gin.Context) {
	appID := c.Param("id")

	// Validate app ID
	if err := validation.ValidateAppID(appID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := h.getRequestContext(c, 5*time.Second)
	defer h.cancelRequestContext(c)

	config, err := h.storage.GetAppConfig(ctx, appID)
	if err != nil {
		logger.Errorw("failed to get app",
			"request_id", c.GetString(middleware.RequestIDKey),
			"app_id", appID,
			"error", err,
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get application"})
		return
	}

	if config == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "application not found"})
		return
	}

	c.JSON(http.StatusOK, config)
}

// UpdateApp updates an application configuration.
// @Summary Update application
// @Description Update an application configuration
// @Tags apps
// @Accept json
// @Produce json
// @Param id path string true "Application ID"
// @Param request body models.AppConfig true "Application configuration"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /api/v1/apps/{id} [put]
func (h *Handler) UpdateApp(c *gin.Context) {
	appID := c.Param("id")
	var config models.AppConfig
	if err := c.ShouldBindJSON(&config); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request format"})
		return
	}

	// Validate app ID
	if err := validation.ValidateAppID(appID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate config
	if err := validation.ValidateAppConfig(config.GuaranteedQuota, config.BurstQuota, config.Priority); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	config.AppID = appID

	ctx := h.getRequestContext(c, 5*time.Second)
	defer h.cancelRequestContext(c)

	if err := h.storage.SetAppConfig(ctx, &config); err != nil {
		logger.Errorw("failed to update app",
			"request_id", c.GetString(middleware.RequestIDKey),
			"app_id", appID,
			"error", err,
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update application"})
		return
	}

	logger.Infow("app updated",
		"request_id", c.GetString(middleware.RequestIDKey),
		"user_id", c.GetString(middleware.UserIDKey),
		"app_id", appID,
	)

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// DeleteApp deletes an application configuration.
// @Summary Delete application
// @Description Delete an application configuration
// @Tags apps
// @Accept json
// @Produce json
// @Param id path string true "Application ID"
// @Success 204
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /api/v1/apps/{id} [delete]
func (h *Handler) DeleteApp(c *gin.Context) {
	appID := c.Param("id")

	// Validate app ID
	if err := validation.ValidateAppID(appID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := h.getRequestContext(c, 5*time.Second)
	defer h.cancelRequestContext(c)

	if err := h.storage.DeleteAppConfig(ctx, appID); err != nil {
		logger.Errorw("failed to delete app",
			"request_id", c.GetString(middleware.RequestIDKey),
			"app_id", appID,
			"error", err,
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete application"})
		return
	}

	logger.Infow("app deleted",
		"request_id", c.GetString(middleware.RequestIDKey),
		"user_id", c.GetString(middleware.UserIDKey),
		"app_id", appID,
	)

	c.Status(http.StatusNoContent)
}

// ListClusters returns all cluster configurations.
// @Summary List all clusters
// @Description Get a list of all cluster configurations
// @Tags clusters
// @Accept json
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /api/v1/clusters [get]
func (h *Handler) ListClusters(c *gin.Context) {
	ctx := h.getRequestContext(c, 5*time.Second)
	defer h.cancelRequestContext(c)

	clusters, err := h.storage.ListClusterConfigs(ctx)
	if err != nil {
		logger.Errorw("failed to list clusters",
			"request_id", c.GetString(middleware.RequestIDKey),
			"error", err,
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list clusters"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"clusters": clusters})
}

// GetCluster retrieves a cluster configuration by ID.
// @Summary Get cluster
// @Description Get a cluster configuration by ID
// @Tags clusters
// @Accept json
// @Produce json
// @Param id path string true "Cluster ID"
// @Success 200 {object} models.ClusterConfig
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 404 {object} map[string]string "Not found"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /api/v1/clusters/{id} [get]
func (h *Handler) GetCluster(c *gin.Context) {
	clusterID := c.Param("id")

	// Validate cluster ID
	if err := validation.ValidateClusterID(clusterID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := h.getRequestContext(c, 5*time.Second)
	defer h.cancelRequestContext(c)

	config, err := h.storage.GetClusterConfig(ctx, clusterID)
	if err != nil {
		logger.Errorw("failed to get cluster",
			"request_id", c.GetString(middleware.RequestIDKey),
			"cluster_id", clusterID,
			"error", err,
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get cluster"})
		return
	}

	if config == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "cluster not found"})
		return
	}

	c.JSON(http.StatusOK, config)
}

// UpdateCluster updates a cluster configuration.
// @Summary Update cluster
// @Description Update a cluster configuration
// @Tags clusters
// @Accept json
// @Produce json
// @Param id path string true "Cluster ID"
// @Param request body models.ClusterConfig true "Cluster configuration"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /api/v1/clusters/{id} [put]
func (h *Handler) UpdateCluster(c *gin.Context) {
	clusterID := c.Param("id")
	var config models.ClusterConfig
	if err := c.ShouldBindJSON(&config); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request format"})
		return
	}

	// Validate cluster ID
	if err := validation.ValidateClusterID(clusterID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate config
	if err := validation.ValidateClusterConfig(config.MaxCapacity, config.ReservedRatio, config.EmergencyThreshold); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	config.ClusterID = clusterID

	ctx := h.getRequestContext(c, 5*time.Second)
	defer h.cancelRequestContext(c)

	if err := h.storage.SetClusterConfig(ctx, &config); err != nil {
		logger.Errorw("failed to update cluster",
			"request_id", c.GetString(middleware.RequestIDKey),
			"cluster_id", clusterID,
			"error", err,
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update cluster"})
		return
	}

	logger.Infow("cluster updated",
		"request_id", c.GetString(middleware.RequestIDKey),
		"user_id", c.GetString(middleware.UserIDKey),
		"cluster_id", clusterID,
	)

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// GetConnectionStats returns connection statistics.
// @Summary Get connection statistics
// @Description Get connection statistics
// @Tags connections
// @Accept json
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /api/v1/connections [get]
func (h *Handler) GetConnectionStats(c *gin.Context) {
	ctx := h.getRequestContext(c, 5*time.Second)
	defer h.cancelRequestContext(c)

	stats, err := h.storage.GetConnectionMetrics(ctx)
	if err != nil {
		logger.Errorw("failed to get connection stats",
			"request_id", c.GetString(middleware.RequestIDKey),
			"error", err,
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get connection statistics"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"connections": stats})
}

// UpdateConnectionLimit updates connection limits.
// @Summary Update connection limit
// @Description Update connection limits for a target
// @Tags connections
// @Accept json
// @Produce json
// @Param request body models.ConnectionLimit true "Connection limit"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Unauthorized"
// @Router /api/v1/connections [put]
func (h *Handler) UpdateConnectionLimit(c *gin.Context) {
	var req models.ConnectionLimit
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request format"})
		return
	}

	// TODO: Implement connection limit update logic
	logger.Infow("connection limit update requested",
		"request_id", c.GetString(middleware.RequestIDKey),
		"user_id", c.GetString(middleware.UserIDKey),
		"target_type", req.TargetType,
		"target_id", req.TargetID,
		"limit", req.Limit,
	)

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// GetEmergencyStatus returns the current emergency mode status.
// @Summary Get emergency status
// @Description Get the current emergency mode status
// @Tags emergency
// @Accept json
// @Produce json
// @Success 200 {object} models.EmergencyStatus
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /api/v1/emergency [get]
func (h *Handler) GetEmergencyStatus(c *gin.Context) {
	ctx := h.getRequestContext(c, 5*time.Second)
	defer h.cancelRequestContext(c)

	status, err := h.storage.GetEmergencyStatus(ctx)
	if err != nil {
		logger.Errorw("failed to get emergency status",
			"request_id", c.GetString(middleware.RequestIDKey),
			"error", err,
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get emergency status"})
		return
	}

	c.JSON(http.StatusOK, status)
}

// ActivateEmergency activates emergency mode.
// @Summary Activate emergency mode
// @Description Activate emergency mode
// @Tags emergency
// @Accept json
// @Produce json
// @Param request body models.EmergencyRequest true "Emergency request"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /api/v1/emergency/activate [post]
func (h *Handler) ActivateEmergency(c *gin.Context) {
	var req models.EmergencyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		// Use default values if request body is empty or invalid
		req.Reason = "manual activation"
		req.Duration = 300
	}

	// Sanitize reason
	req.Reason = validation.SanitizeReason(req.Reason)

	// Validate request
	if err := validation.ValidateEmergencyRequest(req.Reason, req.Duration); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := h.getRequestContext(c, 5*time.Second)
	defer h.cancelRequestContext(c)

	if err := h.storage.ActivateEmergency(ctx, req.Reason, req.Duration); err != nil {
		logger.Errorw("failed to activate emergency",
			"request_id", c.GetString(middleware.RequestIDKey),
			"user_id", c.GetString(middleware.UserIDKey),
			"error", err,
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to activate emergency mode"})
		return
	}

	logger.Warnw("emergency mode activated",
		"request_id", c.GetString(middleware.RequestIDKey),
		"user_id", c.GetString(middleware.UserIDKey),
		"reason", req.Reason,
		"duration", req.Duration,
	)

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// DeactivateEmergency deactivates emergency mode.
// @Summary Deactivate emergency mode
// @Description Deactivate emergency mode
// @Tags emergency
// @Accept json
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /api/v1/emergency/deactivate [post]
func (h *Handler) DeactivateEmergency(c *gin.Context) {
	ctx := h.getRequestContext(c, 5*time.Second)
	defer h.cancelRequestContext(c)

	if err := h.storage.DeactivateEmergency(ctx); err != nil {
		logger.Errorw("failed to deactivate emergency",
			"request_id", c.GetString(middleware.RequestIDKey),
			"user_id", c.GetString(middleware.UserIDKey),
			"error", err,
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to deactivate emergency mode"})
		return
	}

	logger.Warnw("emergency mode deactivated",
		"request_id", c.GetString(middleware.RequestIDKey),
		"user_id", c.GetString(middleware.UserIDKey),
	)

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// GetMetrics returns system metrics.
// @Summary Get system metrics
// @Description Get aggregated system metrics
// @Tags metrics
// @Accept json
// @Produce json
// @Success 200 {object} models.Metrics
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /api/v1/metrics [get]
func (h *Handler) GetMetrics(c *gin.Context) {
	ctx := h.getRequestContext(c, 10*time.Second)
	defer h.cancelRequestContext(c)

	metrics, err := h.storage.GetSystemMetrics(ctx)
	if err != nil {
		logger.Errorw("failed to get metrics",
			"request_id", c.GetString(middleware.RequestIDKey),
			"error", err,
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get metrics"})
		return
	}

	c.JSON(http.StatusOK, metrics)
}

// GetAppMetrics returns metrics for a specific application.
// @Summary Get application metrics
// @Description Get metrics for a specific application
// @Tags metrics
// @Accept json
// @Produce json
// @Param id path string true "Application ID"
// @Success 200 {object} models.AppMetrics
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /api/v1/metrics/apps/{id} [get]
func (h *Handler) GetAppMetrics(c *gin.Context) {
	appID := c.Param("id")

	// Validate app ID
	if err := validation.ValidateAppID(appID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := h.getRequestContext(c, 5*time.Second)
	defer h.cancelRequestContext(c)

	metrics, err := h.storage.GetAppMetrics(ctx, appID)
	if err != nil {
		logger.Errorw("failed to get app metrics",
			"request_id", c.GetString(middleware.RequestIDKey),
			"app_id", appID,
			"error", err,
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get application metrics"})
		return
	}

	c.JSON(http.StatusOK, metrics)
}

// GetConnectionMetrics returns connection metrics.
// @Summary Get connection metrics
// @Description Get connection metrics
// @Tags metrics
// @Accept json
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 401 {object} map[string]string "Unauthorized"
// @Failure 500 {object} map[string]string "Internal server error"
// @Router /api/v1/metrics/connections [get]
func (h *Handler) GetConnectionMetrics(c *gin.Context) {
	ctx := h.getRequestContext(c, 5*time.Second)
	defer h.cancelRequestContext(c)

	stats, err := h.storage.GetConnectionMetrics(ctx)
	if err != nil {
		logger.Errorw("failed to get connection metrics",
			"request_id", c.GetString(middleware.RequestIDKey),
			"error", err,
		)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get connection metrics"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"connections": stats})
}

// WebSocketHandler handles WebSocket connections for real-time updates.
// @Summary WebSocket endpoint
// @Description WebSocket endpoint for real-time updates
// @Tags websocket
// @Accept json
// @Produce json
// @Param Authorization header string true "Bearer token"
// @Success 101 {string} string "Switching to WebSocket protocol"
// @Failure 401 {object} map[string]string "Unauthorized"
// @Router /ws [get]
func (h *Handler) WebSocketHandler(c *gin.Context) {
	// Upgrade HTTP connection to WebSocket
	conn, err := h.wsUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		logger.Errorw("failed to upgrade websocket",
			"request_id", c.GetString(middleware.RequestIDKey),
			"error", err,
		)
		return
	}

	requestID := c.GetString(middleware.RequestIDKey)
	userID := c.GetString(middleware.UserIDKey)

	// Register client
	h.wsMutex.Lock()
	h.wsClients[conn] = true
	h.wsMutex.Unlock()

	logger.Infow("websocket client connected",
		"request_id", requestID,
		"user_id", userID,
		"remote_addr", c.Request.RemoteAddr,
	)

	// Clean up on disconnect
	defer func() {
		h.wsMutex.Lock()
		delete(h.wsClients, conn)
		h.wsMutex.Unlock()
		conn.Close()

		logger.Infow("websocket client disconnected",
			"request_id", requestID,
			"user_id", userID,
		)
	}()

	// Start metrics push goroutine
	stopMetrics := make(chan struct{})
	go h.pushMetrics(conn, stopMetrics)
	defer close(stopMetrics)

	// Subscribe to Redis events
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	msgChan, err := h.storage.Subscribe(ctx)
	if err != nil {
		logger.Errorw("failed to subscribe to events",
			"request_id", requestID,
			"error", err,
		)
		return
	}

	// Handle incoming messages
	for {
		select {
		case msg, ok := <-msgChan:
			if !ok {
				return
			}

			wsMsg := models.WebSocketMessage{
				Type:      "event",
				Data:      string(msg.Payload),
				Timestamp: time.Now(),
			}

			if err := conn.WriteJSON(wsMsg); err != nil {
				logger.Warnw("failed to write websocket message",
					"request_id", requestID,
					"error", err,
				)
				return
			}

		case <-ctx.Done():
			return

		case <-time.After(DefaultWebSocketReadTimeout):
			// Send ping to keep connection alive
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// pushMetrics pushes metrics to a WebSocket client at regular intervals.
func (h *Handler) pushMetrics(conn *websocket.Conn, stop chan struct{}) {
	ticker := time.NewTicker(MetricsPushInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			metrics, err := h.storage.GetSystemMetrics(ctx)
			cancel()

			if err != nil {
				logger.Warnw("failed to get metrics for websocket", "error", err)
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

		case <-stop:
			return
		}
	}
}

// getRequestContext creates a context with timeout for the request.
// It tracks the cancel function for cleanup.
func (h *Handler) getRequestContext(c *gin.Context, timeout time.Duration) context.Context {
	ctx, cancel := context.WithTimeout(c.Request.Context(), timeout)

	h.reqOptsMu.Lock()
	h.requestOpts[ctx] = cancel
	h.reqOptsMu.Unlock()

	return ctx
}

// cancelRequestContext cancels and removes the request context.
func (h *Handler) cancelRequestContext(c *gin.Context) {
	ctx := c.Request.Context()

	h.reqOptsMu.RLock()
	cancel, exists := h.requestOpts[ctx]
	h.reqOptsMu.RUnlock()

	if exists {
		cancel()

		h.reqOptsMu.Lock()
		delete(h.requestOpts, ctx)
		h.reqOptsMu.Unlock()
	}
}
