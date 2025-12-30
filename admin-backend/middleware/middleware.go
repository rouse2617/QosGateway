// Package middleware provides HTTP middleware for the admin backend.
package middleware

import (
	"admin-backend/config"
	"admin-backend/errors"
	"admin-backend/logger"
	"admin-backend/storage"
	"context"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

const (
	// UserIDKey is the context key for user ID
	UserIDKey = "user_id"
	// UsernameKey is the context key for username
	UsernameKey = "username"
	// RoleKey is the context key for user role
	RoleKey = "role"
	// RequestIDKey is the context key for request ID
	RequestIDKey = "request_id"
)

var (
	jwtSecret []byte
	jwtIssuer string
)

// InitJWT initializes JWT configuration from the application config.
func InitJWT(cfg *config.JWTConfig) error {
	if cfg == nil {
		return errors.BadRequest("JWT config cannot be nil", nil)
	}
	if cfg.Secret == "" {
		return errors.BadRequest("JWT secret cannot be empty", nil)
	}
	jwtSecret = []byte(cfg.Secret)
	jwtIssuer = cfg.Issuer
	return nil
}

// Claims represents JWT claims.
type Claims struct {
	UserID   string `json:"user_id"`
	Username string `json:"username"`
	Role     string `json:"role"`
	jwt.RegisteredClaims
}

// GenerateToken generates both access and refresh tokens for a user.
// Returns (accessToken, refreshToken, error).
func GenerateToken(userID, username, role string) (string, string, error) {
	now := time.Now()

	// Access token (short-lived)
	accessClaims := &Claims{
		UserID:   userID,
		Username: username,
		Role:     role,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    jwtIssuer,
			Subject:   userID,
			ExpiresAt: jwt.NewNumericDate(now.Add(time.Hour)),
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
		},
	}

	accessToken := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims)
	accessTokenString, err := accessToken.SignedString(jwtSecret)
	if err != nil {
		return "", "", errors.InternalServerError("failed to sign access token", err)
	}

	// Refresh token (long-lived)
	refreshClaims := &Claims{
		UserID:   userID,
		Username: username,
		Role:     role,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    jwtIssuer,
			Subject:   userID,
			ExpiresAt: jwt.NewNumericDate(now.Add(7 * 24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(now),
			NotBefore: jwt.NewNumericDate(now),
		},
	}

	refreshToken := jwt.NewWithClaims(jwt.SigningMethodHS256, refreshClaims)
	refreshTokenString, err := refreshToken.SignedString(jwtSecret)
	if err != nil {
		return "", "", errors.InternalServerError("failed to sign refresh token", err)
	}

	return accessTokenString, refreshTokenString, nil
}

// ValidateToken validates a JWT token string and returns the claims.
func ValidateToken(tokenString string) (*Claims, error) {
	if tokenString == "" {
		return nil, errors.Unauthorized("token is empty", nil)
	}

	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		// Validate signing method
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return jwtSecret, nil
	})

	if err != nil {
		return nil, errors.Unauthorized("invalid token", err)
	}

	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}

	return nil, errors.Unauthorized("invalid token claims", nil)
}

// AuthMiddleware creates a JWT authentication middleware.
func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "missing authorization header"})
			c.Abort()
			return
		}

		// Parse Bearer token
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid authorization format, expected 'Bearer <token>'"})
			c.Abort()
			return
		}

		// Validate token
		claims, err := ValidateToken(parts[1])
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
			c.Abort()
			return
		}

		// Set user info in context
		c.Set(UserIDKey, claims.UserID)
		c.Set(UsernameKey, claims.Username)
		c.Set(RoleKey, claims.Role)

		logger.Infow("authenticated request",
			"request_id", c.GetString(RequestIDKey),
			"user_id", claims.UserID,
			"username", claims.Username,
			"role", claims.Role,
			"path", c.Request.URL.Path,
		)

		c.Next()
	}
}

// CORS creates a CORS middleware with proper configuration.
func CORS(cfg *config.CORSConfig) gin.HandlerFunc {
	return func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")

		// Check if origin is allowed
		allowed := false
		for _, allowedOrigin := range cfg.AllowedOrigins {
			if allowedOrigin == "*" || allowedOrigin == origin {
				allowed = true
				break
			}
		}

		if allowed {
			if cfg.AllowedOrigins[0] == "*" {
				c.Header("Access-Control-Allow-Origin", "*")
			} else {
				c.Header("Access-Control-Allow-Origin", origin)
			}
		}

		c.Header("Access-Control-Allow-Methods", strings.Join(cfg.AllowedMethods, ", "))
		c.Header("Access-Control-Allow-Headers", strings.Join(cfg.AllowedHeaders, ", "))

		if len(cfg.ExposedHeaders) > 0 {
			c.Header("Access-Control-Expose-Headers", strings.Join(cfg.ExposedHeaders, ", "))
		}

		if cfg.AllowCredentials {
			c.Header("Access-Control-Allow-Credentials", "true")
		}

		c.Header("Access-Control-Max-Age", strconv.Itoa(int(cfg.MaxAge.Seconds())))

		// Handle preflight requests
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}

// RateLimiterConfig holds rate limiter configuration.
type RateLimiterConfig struct {
	Storage         storage.Storage
	RequestsPerWindow int
	Window          time.Duration
}

// rateLimiter tracks request counts for rate limiting.
type rateLimiter struct {
	mu       sync.RWMutex
	requests map[string]*requestTracker
	cleanup  *time.Ticker
}

type requestTracker struct {
	count     int
	resetTime time.Time
}

// RateLimitMiddleware creates a rate limiting middleware using Redis.
func RateLimitMiddleware(cfg *config.RateLimitConfig, store storage.Storage) gin.HandlerFunc {
	if !cfg.Enabled {
		// Return a no-op middleware if rate limiting is disabled
		return func(c *gin.Context) {
			c.Next()
		}
	}

	limiter := &rateLimiter{
		requests: make(map[string]*requestTracker),
		cleanup:  time.NewTicker(cfg.CleanupInterval),
	}

	// Start cleanup goroutine
	go func() {
		for range limiter.cleanup.C {
			limiter.cleanupOldEntries()
		}
	}()

	return func(c *gin.Context) {
		// Get client identifier (IP or user ID if authenticated)
		identifier := c.ClientIP()
		if userID, exists := c.Get(UserIDKey); exists {
			identifier = fmt.Sprintf("user:%v", userID)
		}

		// Check rate limit
		allowed, resetTime := limiter.allow(identifier, cfg.RequestsPerWindow, cfg.Window)
		if !allowed {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error":      "rate limit exceeded",
				"retry_after": resetTime.Unix(),
			})
			c.Abort()
			return
		}

		// Set rate limit headers
		c.Header("X-RateLimit-Limit", strconv.Itoa(cfg.RequestsPerWindow))
		c.Header("X-RateLimit-Remaining", strconv.Itoa(cfg.RequestsPerWindow-1))
		c.Header("X-RateLimit-Reset", strconv.FormatInt(resetTime.Unix(), 10))

		c.Next()
	}
}

// allow checks if a request is allowed under the rate limit.
func (rl *rateLimiter) allow(identifier string, limit int, window time.Duration) (bool, time.Time) {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()

	tracker, exists := rl.requests[identifier]
	if !exists || now.After(tracker.resetTime) {
		// Create new tracker or reset existing one
		rl.requests[identifier] = &requestTracker{
			count:     1,
			resetTime: now.Add(window),
		}
		return true, rl.requests[identifier].resetTime
	}

	// Check if limit exceeded
	if tracker.count >= limit {
		return false, tracker.resetTime
	}

	// Increment counter
	tracker.count++
	return true, tracker.resetTime
}

// cleanupOldEntries removes expired request trackers.
func (rl *rateLimiter) cleanupOldEntries() {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	for key, tracker := range rl.requests {
		if now.After(tracker.resetTime) {
			delete(rl.requests, key)
		}
	}
}

// RequestIDMiddleware adds a unique request ID to each request for tracing.
func RequestIDMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Try to get existing request ID from header
		requestID := c.GetHeader("X-Request-ID")

		// Generate new UUID if not present
		if requestID == "" {
			requestID = uuid.New().String()
		}

		// Set in context and header
		c.Set(RequestIDKey, requestID)
		c.Header("X-Request-ID", requestID)

		c.Next()
	}
}

// LoggingMiddleware creates a logging middleware for HTTP requests.
func LoggingMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		query := c.Request.URL.RawQuery

		// Process request
		c.Next()

		// Calculate latency
		latency := time.Since(start)

		// Get request ID
		requestID := c.GetString(RequestIDKey)
		if requestID == "" {
			requestID = "unknown"
		}

		// Build log entry
		logEntry := []interface{}{
			"request_id", requestID,
			"method", c.Request.Method,
			"path", path,
			"status", c.Writer.Status(),
			"latency", latency.String(),
			"ip", c.ClientIP(),
		}

		if query != "" {
			logEntry = append(logEntry, "query", query)
		}

		// Log based on status code
		if c.Writer.Status() >= 500 {
			logger.Errorw("HTTP request completed with server error", logEntry...)
		} else if c.Writer.Status() >= 400 {
			logger.Warnw("HTTP request completed with client error", logEntry...)
		} else {
			logger.Infow("HTTP request completed", logEntry...)
		}
	}
}

// RecoveryMiddleware creates a middleware that recovers from panics.
func RecoveryMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if err := recover(); err != nil {
				requestID := c.GetString(RequestIDKey)
				logger.Errorw("panic recovered",
					"request_id", requestID,
					"error", err,
					"stack", string(debugStack()),
				)

				c.JSON(http.StatusInternalServerError, gin.H{
					"error": "internal server error",
				})
				c.Abort()
			}
		}()

		c.Next()
	}
}

// debugStack captures the current stack trace.
func debugStack() []byte {
	// This is a simplified version. In production, use runtime/debug.Stack()
	buf := make([]byte, 4096)
	n := 0
	// Capture stack trace here
	return buf[:n]
}

// TimeoutMiddleware creates a middleware that enforces a timeout on requests.
func TimeoutMiddleware(timeout time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Create context with timeout
		ctx, cancel := context.WithTimeout(c.Request.Context(), timeout)
		defer cancel()

		// Replace request context
		c.Request = c.Request.WithContext(ctx)

		// Watch for timeout
		done := make(chan struct{})
		go func() {
			defer close(done)
			c.Next()
		}()

		select {
		case <-done:
			// Request completed
			return
		case <-ctx.Done():
			// Timeout occurred
			c.JSON(http.StatusGatewayTimeout, gin.H{
				"error": "request timeout",
			})
			c.Abort()
		}
	}
}
