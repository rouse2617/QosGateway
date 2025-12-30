// Package storage provides Redis implementation of the storage interface.
package storage

import (
	"admin-backend/errors"
	"admin-backend/models"
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"sync"
	"time"

	"github.com/go-redis/redis/v8"
)

// redisStorage implements the Storage interface using Redis.
type redisStorage struct {
	client *redis.Client
	mu     sync.RWMutex
	// Config constants
	appKeyPrefix         string
	clusterKeyPrefix     string
	emergencyKeyPrefix   string
	metricsKeyPrefix     string
	statsKeyPrefix       string
	eventChannel         string
	configUpdateChannel  string
}

// NewRedisStorage creates a new Redis storage instance.
// The options parameter configures the Redis connection.
func NewRedisStorage(opts *redis.Options) (Storage, error) {
	if opts == nil {
		return nil, errors.BadRequest("redis options cannot be nil", nil)
	}

	client := redis.NewClient(opts)

	// Test connection
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := client.Ping(ctx).Err(); err != nil {
		return nil, errors.InternalServerError("failed to connect to redis", err)
	}

	return &redisStorage{
		client:             client,
		appKeyPrefix:       "ratelimit:app:",
		clusterKeyPrefix:   "ratelimit:cluster:",
		emergencyKeyPrefix: "ratelimit:emergency:",
		metricsKeyPrefix:   "ratelimit:app_metrics:",
		statsKeyPrefix:     "ratelimit:stats:",
		eventChannel:       "ratelimit:events",
		configUpdateChannel: "ratelimit:config_update",
	}, nil
}

// Close closes the Redis connection.
func (r *redisStorage) Close() error {
	return r.client.Close()
}

// Ping checks if Redis is accessible.
func (r *redisStorage) Ping(ctx context.Context) error {
	return r.client.Ping(ctx).Err()
}

// AppConfig operations

// GetAppConfig retrieves an application configuration by ID.
func (r *redisStorage) GetAppConfig(ctx context.Context, appID string) (*models.AppConfig, error) {
	if appID == "" {
		return nil, errors.BadRequest("app ID cannot be empty", nil)
	}

	key := r.appKeyPrefix + appID
	data, err := r.client.HGetAll(ctx, key).Result()
	if err != nil {
		return nil, errors.InternalServerError("failed to get app config", err)
	}

	if len(data) == 0 {
		return nil, nil
	}

	config := &models.AppConfig{AppID: appID}

	if v, ok := data["guaranteed_quota"]; ok {
		config.GuaranteedQuota, _ = strconv.ParseInt(v, 10, 64)
	}
	if v, ok := data["burst_quota"]; ok {
		config.BurstQuota, _ = strconv.ParseInt(v, 10, 64)
	}
	if v, ok := data["priority"]; ok {
		p, _ := strconv.Atoi(v)
		config.Priority = p
	}
	if v, ok := data["max_borrow"]; ok {
		config.MaxBorrow, _ = strconv.ParseInt(v, 10, 64)
	}
	if v, ok := data["max_connections"]; ok {
		config.MaxConnections, _ = strconv.ParseInt(v, 10, 64)
	}
	if v, ok := data["updated_at"]; ok {
		ts, _ := strconv.ParseFloat(v, 64)
		config.UpdatedAt = time.Unix(int64(ts), 0)
	}

	return config, nil
}

// SetAppConfig creates or updates an application configuration.
func (r *redisStorage) SetAppConfig(ctx context.Context, config *models.AppConfig) error {
	if config == nil {
		return errors.BadRequest("config cannot be nil", nil)
	}
	if config.AppID == "" {
		return errors.BadRequest("app ID cannot be empty", nil)
	}

	key := r.appKeyPrefix + config.AppID
	now := time.Now().Unix()

	// Set defaults for zero values
	burstQuota := config.BurstQuota
	if burstQuota == 0 {
		burstQuota = config.GuaranteedQuota * 5
	}

	maxBorrow := config.MaxBorrow
	if maxBorrow == 0 {
		maxBorrow = config.GuaranteedQuota
	}

	maxConnections := config.MaxConnections
	if maxConnections == 0 {
		maxConnections = 1000
	}

	// Use pipeline for atomic operation
	pipe := r.client.Pipeline()
	pipe.HSet(ctx, key,
		"app_id", config.AppID,
		"guaranteed_quota", config.GuaranteedQuota,
		"burst_quota", burstQuota,
		"priority", config.Priority,
		"max_borrow", maxBorrow,
		"max_connections", maxConnections,
		"updated_at", now,
	)

	// Publish configuration update event
	event := map[string]interface{}{
		"type":      "app_config",
		"app_id":    config.AppID,
		"timestamp": now,
	}
	eventJSON, _ := json.Marshal(event)
	pipe.Publish(ctx, r.configUpdateChannel, eventJSON)

	if _, err := pipe.Exec(ctx); err != nil {
		return errors.InternalServerError("failed to set app config", err)
	}

	return nil
}

// DeleteAppConfig removes an application configuration.
func (r *redisStorage) DeleteAppConfig(ctx context.Context, appID string) error {
	if appID == "" {
		return errors.BadRequest("app ID cannot be empty", nil)
	}

	key := r.appKeyPrefix + appID

	// Use pipeline for atomic operation
	pipe := r.client.Pipeline()
	pipe.Del(ctx, key)

	// Publish deletion event
	event := map[string]interface{}{
		"type":      "app_deleted",
		"app_id":    appID,
		"timestamp": time.Now().Unix(),
	}
	eventJSON, _ := json.Marshal(event)
	pipe.Publish(ctx, r.configUpdateChannel, eventJSON)

	if _, err := pipe.Exec(ctx); err != nil {
		return errors.InternalServerError("failed to delete app config", err)
	}

	return nil
}

// ListAppConfigs returns all application configurations.
func (r *redisStorage) ListAppConfigs(ctx context.Context) ([]*models.AppConfig, error) {
	keys, err := r.client.Keys(ctx, r.appKeyPrefix+"*").Result()
	if err != nil {
		return nil, errors.InternalServerError("failed to list app configs", err)
	}

	var configs []*models.AppConfig
	var wg sync.WaitGroup
	var mu sync.Mutex
	errChan := make(chan error, len(keys))

	for _, key := range keys {
		wg.Add(1)
		go func(k string) {
			defer wg.Done()
			appID := k[len(r.appKeyPrefix):]
			config, err := r.GetAppConfig(ctx, appID)
			if err != nil {
				errChan <- err
				return
			}
			if config != nil {
				mu.Lock()
				configs = append(configs, config)
				mu.Unlock()
			}
		}(key)
	}

	wg.Wait()
	close(errChan)

	// Check for errors
	for err := range errChan {
		if err != nil {
			return nil, err
		}
	}

	return configs, nil
}

// ClusterConfig operations

// GetClusterConfig retrieves a cluster configuration by ID.
func (r *redisStorage) GetClusterConfig(ctx context.Context, clusterID string) (*models.ClusterConfig, error) {
	if clusterID == "" {
		return nil, errors.BadRequest("cluster ID cannot be empty", nil)
	}

	key := r.clusterKeyPrefix + clusterID
	data, err := r.client.HGetAll(ctx, key).Result()
	if err != nil {
		return nil, errors.InternalServerError("failed to get cluster config", err)
	}

	if len(data) == 0 {
		return nil, nil
	}

	config := &models.ClusterConfig{ClusterID: clusterID}

	if v, ok := data["max_capacity"]; ok {
		config.MaxCapacity, _ = strconv.ParseInt(v, 10, 64)
	}
	if v, ok := data["reserved_ratio"]; ok {
		config.ReservedRatio, _ = strconv.ParseFloat(v, 64)
	}
	if v, ok := data["emergency_threshold"]; ok {
		config.EmergencyThreshold, _ = strconv.ParseFloat(v, 64)
	}
	if v, ok := data["max_connections"]; ok {
		config.MaxConnections, _ = strconv.ParseInt(v, 10, 64)
	}
	if v, ok := data["updated_at"]; ok {
		ts, _ := strconv.ParseFloat(v, 64)
		config.UpdatedAt = time.Unix(int64(ts), 0)
	}

	return config, nil
}

// SetClusterConfig creates or updates a cluster configuration.
func (r *redisStorage) SetClusterConfig(ctx context.Context, config *models.ClusterConfig) error {
	if config == nil {
		return errors.BadRequest("config cannot be nil", nil)
	}
	if config.ClusterID == "" {
		return errors.BadRequest("cluster ID cannot be empty", nil)
	}

	key := r.clusterKeyPrefix + config.ClusterID
	now := time.Now().Unix()

	// Set defaults for zero values
	reservedRatio := config.ReservedRatio
	if reservedRatio == 0 {
		reservedRatio = 0.1
	}

	emergencyThreshold := config.EmergencyThreshold
	if emergencyThreshold == 0 {
		emergencyThreshold = 0.95
	}

	maxConnections := config.MaxConnections
	if maxConnections == 0 {
		maxConnections = 5000
	}

	if err := r.client.HSet(ctx, key,
		"cluster_id", config.ClusterID,
		"max_capacity", config.MaxCapacity,
		"reserved_ratio", reservedRatio,
		"emergency_threshold", emergencyThreshold,
		"max_connections", maxConnections,
		"updated_at", now,
	).Err(); err != nil {
		return errors.InternalServerError("failed to set cluster config", err)
	}

	return nil
}

// ListClusterConfigs returns all cluster configurations.
func (r *redisStorage) ListClusterConfigs(ctx context.Context) ([]*models.ClusterConfig, error) {
	keys, err := r.client.Keys(ctx, r.clusterKeyPrefix+"*").Result()
	if err != nil {
		return nil, errors.InternalServerError("failed to list cluster configs", err)
	}

	var configs []*models.ClusterConfig
	var wg sync.WaitGroup
	var mu sync.Mutex
	errChan := make(chan error, len(keys))

	for _, key := range keys {
		wg.Add(1)
		go func(k string) {
			defer wg.Done()
			clusterID := k[len(r.clusterKeyPrefix):]
			config, err := r.GetClusterConfig(ctx, clusterID)
			if err != nil {
				errChan <- err
				return
			}
			if config != nil {
				mu.Lock()
				configs = append(configs, config)
				mu.Unlock()
			}
		}(key)
	}

	wg.Wait()
	close(errChan)

	// Check for errors
	for err := range errChan {
		if err != nil {
			return nil, err
		}
	}

	return configs, nil
}

// Emergency operations

// GetEmergencyStatus retrieves the current emergency mode status.
func (r *redisStorage) GetEmergencyStatus(ctx context.Context) (*models.EmergencyStatus, error) {
	status := &models.EmergencyStatus{}

	active, err := r.client.Get(ctx, r.emergencyKeyPrefix+"active").Result()
	if err != nil && err != redis.Nil {
		return nil, errors.InternalServerError("failed to get emergency status", err)
	}

	status.Active = active == "1"

	if status.Active {
		status.Reason, _ = r.client.Get(ctx, r.emergencyKeyPrefix+"reason").Result()

		activatedAt, _ := r.client.Get(ctx, r.emergencyKeyPrefix+"activated_at").Result()
		if ts, err := strconv.ParseFloat(activatedAt, 64); err == nil {
			status.ActivatedAt = time.Unix(int64(ts), 0)
		}

		expiresAt, _ := r.client.Get(ctx, r.emergencyKeyPrefix+"expires_at").Result()
		if ts, err := strconv.ParseFloat(expiresAt, 64); err == nil {
			status.ExpiresAt = time.Unix(int64(ts), 0)
		}
	}

	return status, nil
}

// ActivateEmergency activates emergency mode with the given reason and duration.
func (r *redisStorage) ActivateEmergency(ctx context.Context, reason string, duration int64) error {
	now := time.Now().Unix()
	if duration == 0 {
		duration = 300 // Default 5 minutes
	}

	// Use pipeline for atomic operation
	pipe := r.client.Pipeline()
	pipe.Set(ctx, r.emergencyKeyPrefix+"active", "1", 0)
	pipe.Set(ctx, r.emergencyKeyPrefix+"reason", reason, 0)
	pipe.Set(ctx, r.emergencyKeyPrefix+"activated_at", now, 0)
	pipe.Set(ctx, r.emergencyKeyPrefix+"expires_at", now+duration, 0)

	// Publish emergency activation event
	event := map[string]interface{}{
		"type":      "emergency_activated",
		"reason":    reason,
		"duration":  duration,
		"timestamp": now,
	}
	eventJSON, _ := json.Marshal(event)
	pipe.Publish(ctx, r.eventChannel, eventJSON)

	if _, err := pipe.Exec(ctx); err != nil {
		return errors.InternalServerError("failed to activate emergency mode", err)
	}

	return nil
}

// DeactivateEmergency deactivates emergency mode.
func (r *redisStorage) DeactivateEmergency(ctx context.Context) error {
	// Use pipeline for atomic operation
	pipe := r.client.Pipeline()
	pipe.Set(ctx, r.emergencyKeyPrefix+"active", "0", 0)
	pipe.Del(ctx, r.emergencyKeyPrefix+"reason")
	pipe.Del(ctx, r.emergencyKeyPrefix+"activated_at")
	pipe.Del(ctx, r.emergencyKeyPrefix+"expires_at")

	// Publish emergency deactivation event
	event := map[string]interface{}{
		"type":      "emergency_deactivated",
		"timestamp": time.Now().Unix(),
	}
	eventJSON, _ := json.Marshal(event)
	pipe.Publish(ctx, r.eventChannel, eventJSON)

	if _, err := pipe.Exec(ctx); err != nil {
		return errors.InternalServerError("failed to deactivate emergency mode", err)
	}

	return nil
}

// Metrics operations

// GetSystemMetrics retrieves aggregated system metrics.
func (r *redisStorage) GetSystemMetrics(ctx context.Context) (*models.Metrics, error) {
	metrics := &models.Metrics{}

	// Get all stats keys
	keys, err := r.client.Keys(ctx, r.statsKeyPrefix+"*").Result()
	if err != nil {
		return nil, errors.InternalServerError("failed to get metrics keys", err)
	}

	// Aggregate metrics from all apps
	for _, key := range keys {
		data, err := r.client.HGetAll(ctx, key).Result()
		if err != nil {
			continue
		}

		for _, v := range data {
			var stats map[string]interface{}
			if err := json.Unmarshal([]byte(v), &stats); err != nil {
				continue
			}

			if rt, ok := stats["requests_total"].(float64); ok {
				metrics.RequestsTotal += int64(rt)
			}
			if rj, ok := stats["rejected_total"].(float64); ok {
				metrics.RejectedTotal += int64(rj)
			}
			if l3, ok := stats["l3_hits"].(float64); ok {
				metrics.L3Hits += int64(l3)
			}
		}
	}

	if metrics.RequestsTotal > 0 {
		metrics.CacheHitRatio = float64(metrics.L3Hits) / float64(metrics.RequestsTotal)
	}

	// Get emergency status
	status, err := r.GetEmergencyStatus(ctx)
	if err == nil {
		metrics.EmergencyActive = status.Active
	}

	// Get degradation level
	level, _ := r.client.Get(ctx, "ratelimit:degradation:level").Result()
	if level == "" {
		level = "normal"
	}
	metrics.DegradationLevel = level

	return metrics, nil
}

// GetAppMetrics retrieves metrics for a specific application.
func (r *redisStorage) GetAppMetrics(ctx context.Context, appID string) (*models.AppMetrics, error) {
	if appID == "" {
		return nil, errors.BadRequest("app ID cannot be empty", nil)
	}

	metrics := &models.AppMetrics{AppID: appID}

	key := fmt.Sprintf("%s%s", r.metricsKeyPrefix, appID)
	data, err := r.client.HGetAll(ctx, key).Result()
	if err != nil && err != redis.Nil {
		return nil, errors.InternalServerError("failed to get app metrics", err)
	}

	if v, ok := data["requests_total"]; ok {
		metrics.RequestsTotal, _ = strconv.ParseInt(v, 10, 64)
	}
	if v, ok := data["rejected_total"]; ok {
		metrics.RejectedTotal, _ = strconv.ParseInt(v, 10, 64)
	}
	if v, ok := data["tokens_available"]; ok {
		metrics.TokensAvailable, _ = strconv.ParseInt(v, 10, 64)
	}
	if v, ok := data["pending_cost"]; ok {
		metrics.PendingCost, _ = strconv.ParseInt(v, 10, 64)
	}

	return metrics, nil
}

// GetConnectionMetrics retrieves connection statistics.
func (r *redisStorage) GetConnectionMetrics(ctx context.Context) ([]*models.ConnectionStats, error) {
	// This would need to be implemented based on actual metrics storage
	// For now, return empty slice
	return []*models.ConnectionStats{}, nil
}

// PubSub operations

// Subscribe subscribes to one or more channels and returns a message channel.
func (r *redisStorage) Subscribe(ctx context.Context, channels ...string) (<-chan *PubSubMessage, error) {
	if len(channels) == 0 {
		return nil, errors.BadRequest("at least one channel required", nil)
	}

	// Default channels if none specified
	if len(channels) == 1 && channels[0] == "" {
		channels = []string{r.eventChannel, r.configUpdateChannel}
	}

	pubsub := r.client.Subscribe(ctx, channels...)

	msgChan := make(chan *PubSubMessage, 100)

	go func() {
		defer close(msgChan)
		defer pubsub.Close()

		redisChan := pubsub.Channel()
		for {
			select {
			case msg := <-redisChan:
				if msg != nil {
					msgChan <- &PubSubMessage{
						Channel: msg.Channel,
						Payload: []byte(msg.Payload),
					}
				}
			case <-ctx.Done():
				return
			}
		}
	}()

	return msgChan, nil
}

// Publish publishes a message to a channel.
func (r *redisStorage) Publish(ctx context.Context, channel string, message interface{}) error {
	if channel == "" {
		return errors.BadRequest("channel cannot be empty", nil)
	}

	data, err := json.Marshal(message)
	if err != nil {
		return errors.InternalServerError("failed to marshal message", err)
	}

	if err := r.client.Publish(ctx, channel, data).Err(); err != nil {
		return errors.InternalServerError("failed to publish message", err)
	}

	return nil
}
