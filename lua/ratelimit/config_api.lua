-- ratelimit/config_api.lua
-- Config API: 配置管理 API
-- 提供应用配额、集群配置、紧急模式控制等 API

local _M = {
    _VERSION = '1.0.0'
}

local shared = ngx.shared.ratelimit_dict
local config_dict = ngx.shared.config_dict
local connlimit_dict = ngx.shared.connlimit_dict
local redis_client = require "ratelimit.redis"
local config_validator = require "ratelimit.config_validator"
local emergency = require "ratelimit.emergency"
local metrics = require "ratelimit.metrics"
local cjson = require "cjson.safe"

local CONFIG = {
    CONFIG_CACHE_TTL = 60,  -- 配置缓存 TTL（秒）
    AUTH_HEADER = "X-Admin-Token",
}

--- 验证 API 认证
--- @return boolean valid
--- @return string error
local function check_auth()
    local token = ngx.req.get_headers()[CONFIG.AUTH_HEADER]
    if not token then
        return false, "missing auth token"
    end
    
    local valid_token = config_dict:get("admin:token")
    if not valid_token or token ~= valid_token then
        return false, "invalid auth token"
    end
    
    return true, nil
end

--- 记录审计日志
--- @param action string 操作
--- @param details table 详情
local function audit_log(action, details)
    local log_entry = {
        action = action,
        details = details,
        timestamp = ngx.now(),
        client_ip = ngx.var.remote_addr,
        user_agent = ngx.req.get_headers()["User-Agent"]
    }
    
    ngx.log(ngx.NOTICE, "[config_api] AUDIT: ", cjson.encode(log_entry))
    
    -- 存储到 Redis
    pcall(function()
        local red = redis_client.get_connection()
        if red then
            red:lpush("ratelimit:audit_log", cjson.encode(log_entry))
            red:ltrim("ratelimit:audit_log", 0, 9999)
            redis_client.release_connection(red)
        end
    end)
end

--- 发送 JSON 响应
--- @param status number HTTP 状态码
--- @param data table 响应数据
local function json_response(status, data)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode(data))
    ngx.exit(status)
end

--- 获取应用配置
--- @param app_id string 应用 ID
--- @return table config
function _M.get_app_config(app_id)
    -- 先查本地缓存
    local cache_key = "config:app:" .. app_id
    local cached = config_dict:get(cache_key)
    if cached then
        return cjson.decode(cached)
    end
    
    -- 查 Redis
    local config = nil
    pcall(function()
        local red = redis_client.get_connection()
        if red then
            local data = red:hgetall("ratelimit:app:" .. app_id)
            if data and #data > 0 then
                config = redis_client.array_to_hash(data)
            end
            redis_client.release_connection(red)
        end
    end)
    
    -- 缓存结果
    if config then
        config_dict:set(cache_key, cjson.encode(config), CONFIG.CONFIG_CACHE_TTL)
    end
    
    return config
end

--- 设置应用配置
--- @param app_id string 应用 ID
--- @param config table 配置
--- @return boolean success
--- @return string error
function _M.set_app_config(app_id, config)
    config.app_id = app_id
    
    -- 验证配置
    local valid, errors = config_validator.validate_app_config(config)
    if not valid then
        return false, table.concat(errors, "; ")
    end
    
    -- 存储到 Redis
    local ok, err = pcall(function()
        local red = redis_client.get_connection()
        if not red then
            error("redis connection failed")
        end
        
        local key = "ratelimit:app:" .. app_id
        red:hmset(key,
            "app_id", app_id,
            "guaranteed_quota", config.guaranteed_quota,
            "burst_quota", config.burst_quota or config.guaranteed_quota * 5,
            "priority", config.priority or 2,
            "max_borrow", config.max_borrow or config.guaranteed_quota,
            "max_connections", config.max_connections or 1000,
            "updated_at", ngx.now()
        )
        
        -- 发布配置更新事件
        red:publish("ratelimit:config_update", cjson.encode({
            type = "app_config",
            app_id = app_id,
            timestamp = ngx.now()
        }))
        
        redis_client.release_connection(red)
    end)
    
    if not ok then
        return false, err
    end
    
    -- 清除本地缓存
    config_dict:delete("config:app:" .. app_id)
    
    -- 审计日志
    audit_log("set_app_config", {app_id = app_id, config = config})
    
    return true, nil
end

--- 删除应用配置
--- @param app_id string 应用 ID
--- @return boolean success
function _M.delete_app_config(app_id)
    pcall(function()
        local red = redis_client.get_connection()
        if red then
            red:del("ratelimit:app:" .. app_id)
            red:publish("ratelimit:config_update", cjson.encode({
                type = "app_deleted",
                app_id = app_id,
                timestamp = ngx.now()
            }))
            redis_client.release_connection(red)
        end
    end)
    
    config_dict:delete("config:app:" .. app_id)
    audit_log("delete_app_config", {app_id = app_id})
    
    return true
end

--- 获取所有应用配置
--- @return table configs
function _M.list_app_configs()
    local configs = {}
    
    pcall(function()
        local red = redis_client.get_connection()
        if red then
            local keys = red:keys("ratelimit:app:*")
            for _, key in ipairs(keys) do
                local data = red:hgetall(key)
                if data and #data > 0 then
                    table.insert(configs, redis_client.array_to_hash(data))
                end
            end
            redis_client.release_connection(red)
        end
    end)
    
    return configs
end

--- 设置集群配置
--- @param cluster_id string 集群 ID
--- @param config table 配置
--- @return boolean success
--- @return string error
function _M.set_cluster_config(cluster_id, config)
    config.cluster_id = cluster_id
    
    local valid, errors = config_validator.validate_cluster_config(config)
    if not valid then
        return false, table.concat(errors, "; ")
    end
    
    pcall(function()
        local red = redis_client.get_connection()
        if red then
            local key = "ratelimit:cluster:" .. cluster_id
            red:hmset(key,
                "cluster_id", cluster_id,
                "max_capacity", config.max_capacity,
                "reserved_ratio", config.reserved_ratio or 0.1,
                "emergency_threshold", config.emergency_threshold or 0.95,
                "max_connections", config.max_connections or 5000,
                "updated_at", ngx.now()
            )
            redis_client.release_connection(red)
        end
    end)
    
    audit_log("set_cluster_config", {cluster_id = cluster_id, config = config})
    return true, nil
end

--- 设置连接限制配置
--- @param target_type string 目标类型 ("app" | "cluster")
--- @param target_id string 目标 ID
--- @param limit number 连接限制
--- @return boolean success
function _M.set_connection_limit(target_type, target_id, limit)
    if target_type ~= "app" and target_type ~= "cluster" then
        return false, "invalid target_type"
    end
    
    if type(limit) ~= "number" or limit < 1 then
        return false, "limit must be >= 1"
    end
    
    local key = "conn:" .. target_type .. ":" .. target_id
    local data_str = connlimit_dict:get(key)
    local data = data_str and cjson.decode(data_str) or {current = 0, peak = 0, rejected = 0}
    
    data.limit = limit
    data.last_update = ngx.now()
    
    connlimit_dict:set(key, cjson.encode(data))
    
    audit_log("set_connection_limit", {
        target_type = target_type,
        target_id = target_id,
        limit = limit
    })
    
    return true, nil
end

--- 激活紧急模式
--- @param reason string 原因
--- @param duration number 持续时间（秒）
--- @return boolean success
function _M.activate_emergency(reason, duration)
    local ok = emergency.activate(reason, duration)
    audit_log("activate_emergency", {reason = reason, duration = duration})
    return ok
end

--- 停用紧急模式
--- @return boolean success
function _M.deactivate_emergency()
    local ok = emergency.deactivate()
    audit_log("deactivate_emergency", {})
    return ok
end

--- 获取紧急模式状态
--- @return table status
function _M.get_emergency_status()
    return emergency.get_status()
end

--- 获取实时指标
--- @return table metrics
function _M.get_metrics()
    return metrics.get_summary()
end

--- 获取应用指标
--- @param app_id string 应用 ID
--- @return table metrics
function _M.get_app_metrics(app_id)
    return {
        app_id = app_id,
        requests_total = shared:get("stats:requests:" .. app_id) or 0,
        rejected_total = shared:get("stats:rejected:" .. app_id) or 0,
        tokens_available = shared:get("app:" .. app_id .. ":tokens") or 0,
        pending_cost = shared:get("app:" .. app_id .. ":pending_cost") or 0
    }
end

--- API 路由处理
function _M.handle_request()
    local method = ngx.req.get_method()
    local uri = ngx.var.uri
    
    -- 认证检查（除了 GET /health）
    if uri ~= "/admin/health" then
        local auth_ok, auth_err = check_auth()
        if not auth_ok then
            json_response(401, {error = "unauthorized", message = auth_err})
            return
        end
    end
    
    -- 路由分发
    if uri == "/admin/health" then
        json_response(200, {status = "ok", timestamp = ngx.now()})
        
    elseif uri == "/admin/apps" then
        if method == "GET" then
            json_response(200, {apps = _M.list_app_configs()})
        elseif method == "POST" then
            ngx.req.read_body()
            local body = cjson.decode(ngx.req.get_body_data())
            if not body or not body.app_id then
                json_response(400, {error = "invalid request"})
                return
            end
            local ok, err = _M.set_app_config(body.app_id, body)
            if ok then
                json_response(201, {success = true, app_id = body.app_id})
            else
                json_response(400, {error = err})
            end
        end
        
    elseif string.match(uri, "^/admin/apps/[^/]+$") then
        local app_id = string.match(uri, "^/admin/apps/([^/]+)$")
        if method == "GET" then
            local config = _M.get_app_config(app_id)
            if config then
                json_response(200, config)
            else
                json_response(404, {error = "not found"})
            end
        elseif method == "PUT" then
            ngx.req.read_body()
            local body = cjson.decode(ngx.req.get_body_data())
            local ok, err = _M.set_app_config(app_id, body or {})
            if ok then
                json_response(200, {success = true})
            else
                json_response(400, {error = err})
            end
        elseif method == "DELETE" then
            _M.delete_app_config(app_id)
            json_response(204, nil)
        end
        
    elseif uri == "/admin/emergency" then
        if method == "GET" then
            json_response(200, _M.get_emergency_status())
        end
        
    elseif uri == "/admin/emergency/activate" and method == "POST" then
        ngx.req.read_body()
        local body = cjson.decode(ngx.req.get_body_data()) or {}
        _M.activate_emergency(body.reason or "manual", body.duration or 300)
        json_response(200, {success = true})
        
    elseif uri == "/admin/emergency/deactivate" and method == "POST" then
        _M.deactivate_emergency()
        json_response(200, {success = true})
        
    elseif uri == "/admin/metrics" then
        json_response(200, _M.get_metrics())
        
    elseif string.match(uri, "^/admin/metrics/apps/[^/]+$") then
        local app_id = string.match(uri, "^/admin/metrics/apps/([^/]+)$")
        json_response(200, _M.get_app_metrics(app_id))
        
    elseif uri == "/admin/connections" then
        if method == "PUT" then
            ngx.req.read_body()
            local body = cjson.decode(ngx.req.get_body_data())
            if body then
                local ok, err = _M.set_connection_limit(
                    body.target_type, body.target_id, body.limit
                )
                if ok then
                    json_response(200, {success = true})
                else
                    json_response(400, {error = err})
                end
            else
                json_response(400, {error = "invalid request"})
            end
        end
        
    else
        json_response(404, {error = "not found"})
    end
end

return _M
