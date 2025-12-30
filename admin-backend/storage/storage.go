// Package storage provides interfaces and implementations for data persistence.
// It follows the repository pattern with dependency injection for testability.
package storage

import (
	"admin-backend/models"
	"context"
)

// Storage defines the interface for all data persistence operations.
// This allows for easy testing and swapping of implementations.
type Storage interface {
	// App operations
	AppStorage
	// Cluster operations
	ClusterStorage
	// Emergency operations
	EmergencyStorage
	// Metrics operations
	MetricsStorage
	// PubSub operations
	PubSubStorage
	// Health check
	HealthChecker
}

// AppStorage defines application configuration operations.
type AppStorage interface {
	// GetAppConfig retrieves an application configuration by ID.
	// Returns nil if not found.
	GetAppConfig(ctx context.Context, appID string) (*models.AppConfig, error)

	// SetAppConfig creates or updates an application configuration.
	SetAppConfig(ctx context.Context, config *models.AppConfig) error

	// DeleteAppConfig removes an application configuration.
	DeleteAppConfig(ctx context.Context, appID string) error

	// ListAppConfigs returns all application configurations.
	ListAppConfigs(ctx context.Context) ([]*models.AppConfig, error)
}

// ClusterStorage defines cluster configuration operations.
type ClusterStorage interface {
	// GetClusterConfig retrieves a cluster configuration by ID.
	// Returns nil if not found.
	GetClusterConfig(ctx context.Context, clusterID string) (*models.ClusterConfig, error)

	// SetClusterConfig creates or updates a cluster configuration.
	SetClusterConfig(ctx context.Context, config *models.ClusterConfig) error

	// ListClusterConfigs returns all cluster configurations.
	ListClusterConfigs(ctx context.Context) ([]*models.ClusterConfig, error)
}

// EmergencyStorage defines emergency mode operations.
type EmergencyStorage interface {
	// GetEmergencyStatus retrieves the current emergency mode status.
	GetEmergencyStatus(ctx context.Context) (*models.EmergencyStatus, error)

	// ActivateEmergency activates emergency mode with the given reason and duration.
	ActivateEmergency(ctx context.Context, reason string, duration int64) error

	// DeactivateEmergency deactivates emergency mode.
	DeactivateEmergency(ctx context.Context) error
}

// MetricsStorage defines metrics operations.
type MetricsStorage interface {
	// GetSystemMetrics retrieves aggregated system metrics.
	GetSystemMetrics(ctx context.Context) (*models.Metrics, error)

	// GetAppMetrics retrieves metrics for a specific application.
	GetAppMetrics(ctx context.Context, appID string) (*models.AppMetrics, error)

	// GetConnectionMetrics retrieves connection statistics.
	GetConnectionMetrics(ctx context.Context) ([]*models.ConnectionStats, error)
}

// PubSubStorage defines pub/sub operations.
type PubSubStorage interface {
	// Subscribe subscribes to one or more channels.
	Subscribe(ctx context.Context, channels ...string) (<-chan *PubSubMessage, error)

	// Publish publishes a message to a channel.
	Publish(ctx context.Context, channel string, message interface{}) error
}

// PubSubMessage represents a message from a pub/sub channel.
type PubSubMessage struct {
	// Channel is the channel the message was published to
	Channel string
	// Payload is the message content
	Payload []byte
}

// HealthChecker defines health check operations.
type HealthChecker interface {
	// Ping checks if the storage backend is accessible.
	Ping(ctx context.Context) error

	// Close closes any open connections.
	Close() error
}
