package services

import (
	"admin-backend/models"
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/go-redis/redis/v8"
)

var rdb *redis.Client
var ctx = context.Background()

// InitRedis 初始化 Redis 连接
func InitRedis(addr string) {
	rdb = redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: "",
		DB:       0,
	})
}

// GetRedis 获取 Redis 客户端
func GetRedis() *redis.Client {
	return rdb
}

// GetAppConfig 获取应用配置
func GetAppConfig(appID string) (*models.AppConfig, error) {
	key := "ratelimit:app:" + appID
	data, err := rdb.HGetAll(ctx, key).Result()
	if err != nil {
		return nil, err
	}
	if len(data) == 0 {
		return nil, nil
	}

	config := &models.AppConfig{
		AppID: appID,
	}
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

// SetAppConfig 设置应用配置
func SetAppConfig(config *models.AppConfig) error {
	key := "ratelimit:app:" + config.AppID
	now := time.Now().Unix()

	if config.BurstQuota == 0 {
		config.BurstQuota = config.GuaranteedQuota * 5
	}
	if config.MaxBorrow == 0 {
		config.MaxBorrow = config.GuaranteedQuota
	}
	if config.MaxConnections == 0 {
		config.MaxConnections = 1000
	}

	err := rdb.HSet(ctx, key,
		"app_id", config.AppID,
		"guaranteed_quota", config.GuaranteedQuota,
		"burst_quota", config.BurstQuota,
		"priority", config.Priority,
		"max_borrow", config.MaxBorrow,
		"max_connections", config.MaxConnections,
		"updated_at", now,
	).Err()
	if err != nil {
		return err
	}

	// 发布配置更新事件
	event := map[string]interface{}{
		"type":      "app_config",
		"app_id":    config.AppID,
		"timestamp": now,
	}
	eventJSON, _ := json.Marshal(event)
	rdb.Publish(ctx, "ratelimit:config_update", eventJSON)

	return nil
}

// DeleteAppConfig 删除应用配置
func DeleteAppConfig(appID string) error {
	key := "ratelimit:app:" + appID
	err := rdb.Del(ctx, key).Err()
	if err != nil {
		return err
	}

	event := map[string]interface{}{
		"type":      "app_deleted",
		"app_id":    appID,
		"timestamp": time.Now().Unix(),
	}
	eventJSON, _ := json.Marshal(event)
	rdb.Publish(ctx, "ratelimit:config_update", eventJSON)

	return nil
}

// ListAppConfigs 列出所有应用配置
func ListAppConfigs() ([]*models.AppConfig, error) {
	keys, err := rdb.Keys(ctx, "ratelimit:app:*").Result()
	if err != nil {
		return nil, err
	}

	var configs []*models.AppConfig
	for _, key := range keys {
		appID := key[len("ratelimit:app:"):]
		config, err := GetAppConfig(appID)
		if err == nil && config != nil {
			configs = append(configs, config)
		}
	}

	return configs, nil
}

// GetClusterConfig 获取集群配置
func GetClusterConfig(clusterID string) (*models.ClusterConfig, error) {
	key := "ratelimit:cluster:" + clusterID
	data, err := rdb.HGetAll(ctx, key).Result()
	if err != nil {
		return nil, err
	}
	if len(data) == 0 {
		return nil, nil
	}

	config := &models.ClusterConfig{
		ClusterID: clusterID,
	}
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

	return config, nil
}

// SetClusterConfig 设置集群配置
func SetClusterConfig(config *models.ClusterConfig) error {
	key := "ratelimit:cluster:" + config.ClusterID
	now := time.Now().Unix()

	if config.ReservedRatio == 0 {
		config.ReservedRatio = 0.1
	}
	if config.EmergencyThreshold == 0 {
		config.EmergencyThreshold = 0.95
	}
	if config.MaxConnections == 0 {
		config.MaxConnections = 5000
	}

	return rdb.HSet(ctx, key,
		"cluster_id", config.ClusterID,
		"max_capacity", config.MaxCapacity,
		"reserved_ratio", config.ReservedRatio,
		"emergency_threshold", config.EmergencyThreshold,
		"max_connections", config.MaxConnections,
		"updated_at", now,
	).Err()
}

// ListClusterConfigs 列出所有集群配置
func ListClusterConfigs() ([]*models.ClusterConfig, error) {
	keys, err := rdb.Keys(ctx, "ratelimit:cluster:*").Result()
	if err != nil {
		return nil, err
	}

	var configs []*models.ClusterConfig
	for _, key := range keys {
		clusterID := key[len("ratelimit:cluster:"):]
		config, err := GetClusterConfig(clusterID)
		if err == nil && config != nil {
			configs = append(configs, config)
		}
	}

	return configs, nil
}

// GetEmergencyStatus 获取紧急模式状态
func GetEmergencyStatus() (*models.EmergencyStatus, error) {
	status := &models.EmergencyStatus{}

	active, _ := rdb.Get(ctx, "ratelimit:emergency:active").Result()
	status.Active = active == "1"

	if status.Active {
		status.Reason, _ = rdb.Get(ctx, "ratelimit:emergency:reason").Result()
		activatedAt, _ := rdb.Get(ctx, "ratelimit:emergency:activated_at").Result()
		if ts, err := strconv.ParseFloat(activatedAt, 64); err == nil {
			status.ActivatedAt = time.Unix(int64(ts), 0)
		}
		expiresAt, _ := rdb.Get(ctx, "ratelimit:emergency:expires_at").Result()
		if ts, err := strconv.ParseFloat(expiresAt, 64); err == nil {
			status.ExpiresAt = time.Unix(int64(ts), 0)
		}
	}

	return status, nil
}

// ActivateEmergency 激活紧急模式
func ActivateEmergency(reason string, duration int64) error {
	now := time.Now().Unix()
	if duration == 0 {
		duration = 300
	}

	pipe := rdb.Pipeline()
	pipe.Set(ctx, "ratelimit:emergency:active", "1", 0)
	pipe.Set(ctx, "ratelimit:emergency:reason", reason, 0)
	pipe.Set(ctx, "ratelimit:emergency:activated_at", now, 0)
	pipe.Set(ctx, "ratelimit:emergency:expires_at", now+duration, 0)
	_, err := pipe.Exec(ctx)
	if err != nil {
		return err
	}

	event := map[string]interface{}{
		"type":      "emergency_activated",
		"reason":    reason,
		"duration":  duration,
		"timestamp": now,
	}
	eventJSON, _ := json.Marshal(event)
	rdb.Publish(ctx, "ratelimit:events", eventJSON)

	return nil
}

// DeactivateEmergency 停用紧急模式
func DeactivateEmergency() error {
	pipe := rdb.Pipeline()
	pipe.Set(ctx, "ratelimit:emergency:active", "0", 0)
	pipe.Del(ctx, "ratelimit:emergency:reason")
	pipe.Del(ctx, "ratelimit:emergency:activated_at")
	pipe.Del(ctx, "ratelimit:emergency:expires_at")
	_, err := pipe.Exec(ctx)
	if err != nil {
		return err
	}

	event := map[string]interface{}{
		"type":      "emergency_deactivated",
		"timestamp": time.Now().Unix(),
	}
	eventJSON, _ := json.Marshal(event)
	rdb.Publish(ctx, "ratelimit:events", eventJSON)

	return nil
}

// GetMetrics 获取系统指标
func GetMetrics() (*models.Metrics, error) {
	metrics := &models.Metrics{}

	// 从 Redis 获取聚合指标
	keys, _ := rdb.Keys(ctx, "ratelimit:stats:*").Result()
	for _, key := range keys {
		data, _ := rdb.HGetAll(ctx, key).Result()
		for _, v := range data {
			var stats map[string]interface{}
			if err := json.Unmarshal([]byte(v), &stats); err == nil {
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
	}

	if metrics.RequestsTotal > 0 {
		metrics.CacheHitRatio = float64(metrics.L3Hits) / float64(metrics.RequestsTotal)
	}

	status, _ := GetEmergencyStatus()
	metrics.EmergencyActive = status.Active

	level, _ := rdb.Get(ctx, "ratelimit:degradation:level").Result()
	if level == "" {
		level = "normal"
	}
	metrics.DegradationLevel = level

	return metrics, nil
}

// GetAppMetrics 获取应用指标
func GetAppMetrics(appID string) (*models.AppMetrics, error) {
	metrics := &models.AppMetrics{
		AppID: appID,
	}

	// 这里需要从 Nginx 共享内存获取，通过 Redis 中转
	key := fmt.Sprintf("ratelimit:app_metrics:%s", appID)
	data, _ := rdb.HGetAll(ctx, key).Result()

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

// SubscribeEvents 订阅事件
func SubscribeEvents() *redis.PubSub {
	return rdb.Subscribe(ctx, "ratelimit:events", "ratelimit:config_update")
}
