// Package main is the entry point for the admin backend service.
package main

import (
	"admin-backend/config"
	"admin-backend/handlers"
	"admin-backend/logger"
	"admin-backend/middleware"
	"admin-backend/storage"
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/go-redis/redis/v8"
)

const (
	// DefaultShutdownTimeout is the maximum time to wait for graceful shutdown
	DefaultShutdownTimeout = 30 * time.Second
)

func main() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to load configuration: %v\n", err)
		os.Exit(1)
	}

	// Initialize logger
	if err := logger.Init(cfg.Log.Level, cfg.Log.Format, cfg.Log.OutputPath); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to initialize logger: %v\n", err)
		os.Exit(1)
	}

	logger.Infow("starting admin backend",
		"version", "1.0.0",
		"port", cfg.Server.Port,
	)

	// Initialize storage
	store, err := storage.NewRedisStorage(&redis.Options{
		Addr:         cfg.Redis.Addr,
		Password:     cfg.Redis.Password,
		DB:           cfg.Redis.DB,
		PoolSize:     cfg.Redis.PoolSize,
		MinIdleConns: cfg.Redis.MinIdleConns,
		MaxRetries:   cfg.Redis.MaxRetries,
		DialTimeout:  cfg.Redis.DialTimeout,
		ReadTimeout:  cfg.Redis.ReadTimeout,
		WriteTimeout: cfg.Redis.WriteTimeout,
		PoolTimeout:  cfg.Redis.PoolTimeout,
	})
	if err != nil {
		logger.Fatalw("failed to initialize storage", "error", err)
	}
	defer func() {
		if err := store.Close(); err != nil {
			logger.Errorw("error closing storage", "error", err)
		}
	}()

	logger.Info("storage initialized successfully")

	// Initialize JWT
	if err := middleware.InitJWT(&cfg.JWT); err != nil {
		logger.Fatalw("failed to initialize JWT", "error", err)
	}

	// Set Gin mode
	gin.SetMode(gin.ReleaseMode)

	// Create Gin engine
	r := gin.New()

	// Global middleware
	r.Use(middleware.RecoveryMiddleware())
	r.Use(middleware.RequestIDMiddleware())
	r.Use(middleware.LoggingMiddleware())
	r.Use(middleware.CORS(&cfg.CORS))

	// Rate limiting middleware (if enabled)
	if cfg.RateLimit.Enabled {
		r.Use(middleware.RateLimitMiddleware(&cfg.RateLimit, store))
	}

	// Create handlers
	h := handlers.NewHandler(store)
	defer h.Close()

	// Health check endpoint (no authentication required)
	r.GET("/health", h.Health)

	// Authentication routes
	auth := r.Group("/api/v1/auth")
	{
		auth.POST("/login", h.Login)
		auth.POST("/refresh", h.RefreshToken)
	}

	// API routes (require authentication)
	api := r.Group("/api/v1")
	api.Use(middleware.AuthMiddleware())
	{
		// Application management
		apps := api.Group("/apps")
		{
			apps.GET("", h.ListApps)
			apps.POST("", h.CreateApp)
			apps.GET("/:id", h.GetApp)
			apps.PUT("/:id", h.UpdateApp)
			apps.DELETE("/:id", h.DeleteApp)
		}

		// Cluster management
		clusters := api.Group("/clusters")
		{
			clusters.GET("", h.ListClusters)
			clusters.GET("/:id", h.GetCluster)
			clusters.PUT("/:id", h.UpdateCluster)
		}

		// Connection management
		connections := api.Group("/connections")
		{
			connections.GET("", h.GetConnectionStats)
			connections.PUT("", h.UpdateConnectionLimit)
		}

		// Emergency mode
		emergency := api.Group("/emergency")
		{
			emergency.GET("", h.GetEmergencyStatus)
			emergency.POST("/activate", h.ActivateEmergency)
			emergency.POST("/deactivate", h.DeactivateEmergency)
		}

		// Metrics
		metrics := api.Group("/metrics")
		{
			metrics.GET("", h.GetMetrics)
			metrics.GET("/apps/:id", h.GetAppMetrics)
			metrics.GET("/connections", h.GetConnectionMetrics)
		}
	}

	// WebSocket endpoint (requires authentication)
	r.GET("/ws", middleware.AuthMiddleware(), h.WebSocketHandler)

	// Create HTTP server
	srv := &http.Server{
		Addr:         ":" + cfg.Server.Port,
		Handler:      r,
		ReadTimeout:  cfg.Server.ReadTimeout,
		WriteTimeout: cfg.Server.WriteTimeout,
	}

	// Start server in a goroutine
	go func() {
		logger.Infow("server listening",
			"port", cfg.Server.Port,
			"read_timeout", cfg.Server.ReadTimeout.String(),
			"write_timeout", cfg.Server.WriteTimeout.String(),
		)

		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatalw("server failed to start", "error", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("shutting down server...")

	// Create context with timeout for shutdown
	ctx, cancel := context.WithTimeout(context.Background(), cfg.Server.ShutdownTimeout)
	defer cancel()

	// Attempt graceful shutdown
	if err := srv.Shutdown(ctx); err != nil {
		logger.Errorw("server forced to shutdown", "error", err)
	} else {
		logger.Info("server shutdown complete")
	}

	// Flush logger
	if err := logger.Sync(); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to sync logger: %v\n", err)
	}
}
