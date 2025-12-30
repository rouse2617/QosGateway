// Package config provides configuration management for the admin backend service.
// It loads configuration from environment variables with sensible defaults and validation.
package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

// Config holds all configuration for the application.
type Config struct {
	// Server configuration
	Server ServerConfig
	// Redis configuration
	Redis RedisConfig
	// JWT configuration
	JWT JWTConfig
	// CORS configuration
	CORS CORSConfig
	// Rate limiting configuration
	RateLimit RateLimitConfig
	// Logging configuration
	Log LogConfig
}

// ServerConfig contains HTTP server configuration.
type ServerConfig struct {
	// Port is the port the server listens on
	Port string
	// ReadTimeout is the maximum duration for reading the entire request
	ReadTimeout time.Duration
	// WriteTimeout is the maximum duration before timing out writes of the response
	WriteTimeout time.Duration
	// ShutdownTimeout is the maximum time to wait for graceful shutdown
	ShutdownTimeout time.Duration
}

// RedisConfig contains Redis connection configuration.
type RedisConfig struct {
	// Addr is the Redis server address (host:port)
	Addr string
	// Password is the Redis password (empty if no password)
	Password string
	// DB is the Redis database number to use
	DB int
	// PoolSize is the maximum number of socket connections
	PoolSize int
	// MinIdleConns is the minimum number of idle connections
	MinIdleConns int
	// MaxRetries is the maximum number of retries before giving up
	MaxRetries int
	// DialTimeout is the timeout for establishing new connections
	DialTimeout time.Duration
	// ReadTimeout is the timeout for reading a single command
	ReadTimeout time.Duration
	// WriteTimeout is the timeout for writing a single command
	WriteTimeout time.Duration
	// PoolTimeout is the amount of time to wait for a connection to become available
	PoolTimeout time.Duration
}

// JWTConfig contains JWT token configuration.
type JWTConfig struct {
	// Secret is the signing secret for JWT tokens (must be set in production)
	Secret string
	// AccessExpiration is the duration until access tokens expire
	AccessExpiration time.Duration
	// RefreshExpiration is the duration until refresh tokens expire
	RefreshExpiration time.Duration
	// Issuer is the JWT issuer claim
	Issuer string
}

// CORSConfig contains CORS middleware configuration.
type CORSConfig struct {
	// AllowedOrigins is a list of allowed origins (wildcards supported)
	AllowedOrigins []string
	// AllowedMethods is a list of allowed HTTP methods
	AllowedMethods []string
	// AllowedHeaders is a list of allowed headers
	AllowedHeaders []string
	// ExposedHeaders is a list of headers exposed to the browser
	ExposedHeaders []string
	// AllowCredentials indicates whether credentials can be included
	AllowCredentials bool
	// MaxAge is the maximum age to cache preflight responses
	MaxAge time.Duration
}

// RateLimitConfig contains rate limiting configuration.
type RateLimitConfig struct {
	// Enabled indicates whether rate limiting is active
	Enabled bool
	// RequestsPerWindow is the maximum number of requests per time window
	RequestsPerWindow int
	// Window is the time window for rate limiting
	Window time.Duration
	// CleanupInterval is how often to clean up stale rate limit data
	CleanupInterval time.Duration
}

// LogConfig contains logging configuration.
type LogConfig struct {
	// Level is the minimum log level to output (debug, info, warn, error)
	Level string
	// Format is the log format (json or console)
	Format string
	// OutputPath is the file path for log output (empty for stdout)
	OutputPath string
}

// Load loads configuration from environment variables with defaults.
// Returns an error if required configuration is missing or invalid.
func Load() (*Config, error) {
	cfg := &Config{}

	// Load server configuration
	cfg.Server = ServerConfig{
		Port:            getEnv("PORT", "8081"),
		ReadTimeout:     getDurationEnv("SERVER_READ_TIMEOUT", 15*time.Second),
		WriteTimeout:    getDurationEnv("SERVER_WRITE_TIMEOUT", 15*time.Second),
		ShutdownTimeout: getDurationEnv("SERVER_SHUTDOWN_TIMEOUT", 30*time.Second),
	}

	// Load Redis configuration
	redisDB, _ := strconv.Atoi(getEnv("REDIS_DB", "0"))
	cfg.Redis = RedisConfig{
		Addr:         getEnv("REDIS_ADDR", "localhost:6379"),
		Password:     getEnv("REDIS_PASSWORD", ""),
		DB:           redisDB,
		PoolSize:     getIntEnv("REDIS_POOL_SIZE", 10),
		MinIdleConns: getIntEnv("REDIS_MIN_IDLE_CONNS", 5),
		MaxRetries:   getIntEnv("REDIS_MAX_RETRIES", 3),
		DialTimeout:  getDurationEnv("REDIS_DIAL_TIMEOUT", 5*time.Second),
		ReadTimeout:  getDurationEnv("REDIS_READ_TIMEOUT", 3*time.Second),
		WriteTimeout: getDurationEnv("REDIS_WRITE_TIMEOUT", 3*time.Second),
		PoolTimeout:  getDurationEnv("REDIS_POOL_TIMEOUT", 4*time.Second),
	}

	// Load JWT configuration
	cfg.JWT = JWTConfig{
		Secret:           getEnv("JWT_SECRET", ""),
		AccessExpiration:  getDurationEnv("JWT_ACCESS_EXPIRATION", 1*time.Hour),
		RefreshExpiration: getDurationEnv("JWT_REFRESH_EXPIRATION", 7*24*time.Hour),
		Issuer:           getEnv("JWT_ISSUER", "qos-gateway-admin"),
	}

	// Load CORS configuration
	cfg.CORS = CORSConfig{
		AllowedOrigins:   getStringSliceEnv("CORS_ALLOWED_ORIGINS", []string{"*"}),
		AllowedMethods:   getStringSliceEnv("CORS_ALLOWED_METHODS", []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"}),
		AllowedHeaders:   getStringSliceEnv("CORS_ALLOWED_HEADERS", []string{"Origin", "Content-Type", "Authorization"}),
		ExposedHeaders:   getStringSliceEnv("CORS_EXPOSED_HEADERS", []string{}),
		AllowCredentials: getBoolEnv("CORS_ALLOW_CREDENTIALS", false),
		MaxAge:           getDurationEnv("CORS_MAX_AGE", 86400*time.Second),
	}

	// Load rate limiting configuration
	cfg.RateLimit = RateLimitConfig{
		Enabled:          getBoolEnv("RATE_LIMIT_ENABLED", true),
		RequestsPerWindow: getIntEnv("RATE_LIMIT_REQUESTS", 100),
		Window:           getDurationEnv("RATE_LIMIT_WINDOW", 1*time.Minute),
		CleanupInterval:  getDurationEnv("RATE_LIMIT_CLEANUP_INTERVAL", 5*time.Minute),
	}

	// Load logging configuration
	cfg.Log = LogConfig{
		Level:     getEnv("LOG_LEVEL", "info"),
		Format:    getEnv("LOG_FORMAT", "console"),
		OutputPath: getEnv("LOG_OUTPUT_PATH", ""),
	}

	// Validate configuration
	if err := cfg.Validate(); err != nil {
		return nil, fmt.Errorf("configuration validation failed: %w", err)
	}

	return cfg, nil
}

// Validate checks that the configuration is valid and complete.
// Returns an error if validation fails.
func (c *Config) Validate() error {
	// Validate server port
	if c.Server.Port == "" {
		return fmt.Errorf("server port cannot be empty")
	}

	// Validate Redis configuration
	if c.Redis.Addr == "" {
		return fmt.Errorf("redis address cannot be empty")
	}
	if c.Redis.DB < 0 || c.Redis.DB > 15 {
		return fmt.Errorf("redis DB must be between 0 and 15")
	}
	if c.Redis.PoolSize <= 0 {
		return fmt.Errorf("redis pool size must be positive")
	}

	// Validate JWT configuration
	if c.JWT.Secret == "" {
		return fmt.Errorf("JWT secret must be set (use JWT_SECRET environment variable)")
	}
	if len(c.JWT.Secret) < 32 {
		return fmt.Errorf("JWT secret must be at least 32 characters for security")
	}
	if c.JWT.AccessExpiration <= 0 {
		return fmt.Errorf("JWT access expiration must be positive")
	}
	if c.JWT.RefreshExpiration <= 0 {
		return fmt.Errorf("JWT refresh expiration must be positive")
	}

	// Validate log level
	validLogLevels := map[string]bool{
		"debug": true,
		"info":  true,
		"warn":  true,
		"error": true,
	}
	if !validLogLevels[c.Log.Level] {
		return fmt.Errorf("invalid log level: %s (must be debug, info, warn, or error)", c.Log.Level)
	}

	// Validate CORS
	if len(c.CORS.AllowedOrigins) == 0 {
		return fmt.Errorf("CORS allowed origins cannot be empty")
	}

	return nil
}

// getEnv retrieves an environment variable or returns a default value.
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getIntEnv retrieves an environment variable as an integer or returns a default value.
func getIntEnv(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
	}
	return defaultValue
}

// getBoolEnv retrieves an environment variable as a boolean or returns a default value.
func getBoolEnv(key string, defaultValue bool) bool {
	if value := os.Getenv(key); value != "" {
		if boolVal, err := strconv.ParseBool(value); err == nil {
			return boolVal
		}
	}
	return defaultValue
}

// getDurationEnv retrieves an environment variable as a duration or returns a default value.
func getDurationEnv(key string, defaultValue time.Duration) time.Duration {
	if value := os.Getenv(key); value != "" {
		if duration, err := time.ParseDuration(value); err == nil {
			return duration
		}
	}
	return defaultValue
}

// getStringSliceEnv retrieves an environment variable as a string slice or returns a default value.
// The environment variable should be a comma-separated list.
func getStringSliceEnv(key string, defaultValue []string) []string {
	if value := os.Getenv(key); value != "" {
		if value != "" {
			return []string{value}
		}
	}
	return defaultValue
}
