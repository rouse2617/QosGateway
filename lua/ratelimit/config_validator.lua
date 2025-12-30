-- ratelimit/config_validator.lua
-- Config Validator: 配置验证器
-- 验证应用配置和集群容量的合法性

local _M = {
    _VERSION = '1.0.0'
}

local cjson = require "cjson.safe"

local CONFIG = {
    MAX_PRIORITY = 3,
    MIN_PRIORITY = 0,
    MAX_QUOTA = 10000000,
    MIN_QUOTA = 1,
    CLUSTER_RESERVE_RATIO = 0.9,  -- 90% 可分配
    MAX_APP_ID_LENGTH = 128,
    MAX_CLUSTER_ID_LENGTH = 128,
}

--- 验证应用配置
--- @param config table 配置对象
--- @return boolean valid 是否有效
--- @return table errors 错误列表
function _M.validate_app_config(config)
    local errors = {}
    
    if type(config) ~= "table" then
        return false, {"config must be a table"}
    end
    
    -- 检查 app_id
    if not config.app_id or type(config.app_id) ~= "string" or #config.app_id == 0 then
        table.insert(errors, "app_id is required and must be non-empty string")
    elseif #config.app_id > CONFIG.MAX_APP_ID_LENGTH then
        table.insert(errors, "app_id exceeds max length " .. CONFIG.MAX_APP_ID_LENGTH)
    elseif config.app_id:match("[^%w%-_]") then
        table.insert(errors, "app_id contains invalid characters")
    end
    
    -- 检查 guaranteed_quota
    if not config.guaranteed_quota then
        table.insert(errors, "guaranteed_quota is required")
    elseif type(config.guaranteed_quota) ~= "number" then
        table.insert(errors, "guaranteed_quota must be a number")
    elseif config.guaranteed_quota < CONFIG.MIN_QUOTA then
        table.insert(errors, "guaranteed_quota must be >= " .. CONFIG.MIN_QUOTA)
    elseif config.guaranteed_quota > CONFIG.MAX_QUOTA then
        table.insert(errors, "guaranteed_quota must be <= " .. CONFIG.MAX_QUOTA)
    end
    
    -- 检查 burst_quota
    if config.burst_quota then
        if type(config.burst_quota) ~= "number" then
            table.insert(errors, "burst_quota must be a number")
        elseif config.burst_quota < CONFIG.MIN_QUOTA then
            table.insert(errors, "burst_quota must be >= " .. CONFIG.MIN_QUOTA)
        elseif config.burst_quota > CONFIG.MAX_QUOTA then
            table.insert(errors, "burst_quota must be <= " .. CONFIG.MAX_QUOTA)
        elseif config.guaranteed_quota and config.burst_quota < config.guaranteed_quota then
            table.insert(errors, "burst_quota must be >= guaranteed_quota")
        end
    end
    
    -- 检查 priority
    if config.priority then
        if type(config.priority) ~= "number" then
            table.insert(errors, "priority must be a number")
        elseif config.priority < CONFIG.MIN_PRIORITY or config.priority > CONFIG.MAX_PRIORITY then
            table.insert(errors, "priority must be " .. CONFIG.MIN_PRIORITY .. "-" .. CONFIG.MAX_PRIORITY)
        elseif math.floor(config.priority) ~= config.priority then
            table.insert(errors, "priority must be an integer")
        end
    end
    
    -- 检查 max_borrow
    if config.max_borrow then
        if type(config.max_borrow) ~= "number" then
            table.insert(errors, "max_borrow must be a number")
        elseif config.max_borrow < 0 then
            table.insert(errors, "max_borrow must be >= 0")
        end
    end
    
    -- 检查连接限制
    if config.max_connections then
        if type(config.max_connections) ~= "number" then
            table.insert(errors, "max_connections must be a number")
        elseif config.max_connections < 1 then
            table.insert(errors, "max_connections must be >= 1")
        end
    end
    
    return #errors == 0, errors
end

--- 验证集群配额总和
--- @param cluster_capacity number 集群容量
--- @param app_quotas table 应用配额列表
--- @return boolean valid 是否有效
--- @return string error 错误信息
function _M.validate_cluster_capacity(cluster_capacity, app_quotas)
    if type(cluster_capacity) ~= "number" or cluster_capacity <= 0 then
        return false, "cluster_capacity must be a positive number"
    end
    
    if type(app_quotas) ~= "table" then
        return false, "app_quotas must be a table"
    end
    
    local total_guaranteed = 0
    for i, quota in ipairs(app_quotas) do
        if type(quota) ~= "table" then
            return false, "app_quotas[" .. i .. "] must be a table"
        end
        total_guaranteed = total_guaranteed + (tonumber(quota.guaranteed_quota) or 0)
    end
    
    local max_allowed = cluster_capacity * CONFIG.CLUSTER_RESERVE_RATIO
    if total_guaranteed > max_allowed then
        return false, string.format(
            "sum of guaranteed_quotas (%d) exceeds %.0f%% of cluster_capacity (%d)",
            total_guaranteed,
            CONFIG.CLUSTER_RESERVE_RATIO * 100,
            math.floor(max_allowed)
        )
    end
    
    return true, nil
end

--- 验证集群配置
--- @param config table 集群配置
--- @return boolean valid 是否有效
--- @return table errors 错误列表
function _M.validate_cluster_config(config)
    local errors = {}
    
    if type(config) ~= "table" then
        return false, {"config must be a table"}
    end
    
    -- 检查 cluster_id
    if not config.cluster_id or type(config.cluster_id) ~= "string" or #config.cluster_id == 0 then
        table.insert(errors, "cluster_id is required")
    elseif #config.cluster_id > CONFIG.MAX_CLUSTER_ID_LENGTH then
        table.insert(errors, "cluster_id exceeds max length")
    end
    
    -- 检查 max_capacity
    if not config.max_capacity then
        table.insert(errors, "max_capacity is required")
    elseif type(config.max_capacity) ~= "number" or config.max_capacity <= 0 then
        table.insert(errors, "max_capacity must be a positive number")
    end
    
    -- 检查 reserved_ratio
    if config.reserved_ratio then
        if type(config.reserved_ratio) ~= "number" then
            table.insert(errors, "reserved_ratio must be a number")
        elseif config.reserved_ratio < 0 or config.reserved_ratio > 1 then
            table.insert(errors, "reserved_ratio must be 0-1")
        end
    end
    
    -- 检查 emergency_threshold
    if config.emergency_threshold then
        if type(config.emergency_threshold) ~= "number" then
            table.insert(errors, "emergency_threshold must be a number")
        elseif config.emergency_threshold < 0 or config.emergency_threshold > 1 then
            table.insert(errors, "emergency_threshold must be 0-1")
        end
    end
    
    -- 检查连接限制
    if config.max_connections then
        if type(config.max_connections) ~= "number" or config.max_connections < 1 then
            table.insert(errors, "max_connections must be >= 1")
        end
    end
    
    return #errors == 0, errors
end

--- Dry-run 模式验证
--- @param config_type string 配置类型 ("app" | "cluster")
--- @param config table 配置对象
--- @param context table 上下文（可选，用于集群容量验证）
--- @return table result 验证结果
function _M.dry_run(config_type, config, context)
    local result = {
        valid = false,
        errors = {},
        warnings = {},
        config_type = config_type,
        timestamp = ngx.now()
    }
    
    if config_type == "app" then
        result.valid, result.errors = _M.validate_app_config(config)
        
        -- 额外警告检查
        if result.valid then
            if config.burst_quota and config.burst_quota > config.guaranteed_quota * 10 then
                table.insert(result.warnings, "burst_quota is more than 10x guaranteed_quota")
            end
            if config.priority == 0 then
                table.insert(result.warnings, "P0 priority should be reserved for critical apps")
            end
        end
        
        -- 集群容量检查
        if result.valid and context and context.cluster_capacity and context.existing_quotas then
            local quotas = {}
            for _, q in ipairs(context.existing_quotas) do
                if q.app_id ~= config.app_id then
                    table.insert(quotas, q)
                end
            end
            table.insert(quotas, config)
            
            local cap_valid, cap_err = _M.validate_cluster_capacity(
                context.cluster_capacity, quotas
            )
            if not cap_valid then
                result.valid = false
                table.insert(result.errors, cap_err)
            end
        end
        
    elseif config_type == "cluster" then
        result.valid, result.errors = _M.validate_cluster_config(config)
        
        -- 额外警告检查
        if result.valid then
            if config.reserved_ratio and config.reserved_ratio < 0.05 then
                table.insert(result.warnings, "reserved_ratio below 5% may cause issues")
            end
            if config.emergency_threshold and config.emergency_threshold > 0.98 then
                table.insert(result.warnings, "emergency_threshold above 98% may trigger too late")
            end
        end
    else
        result.errors = {"unknown config_type: " .. tostring(config_type)}
    end
    
    -- 记录验证日志
    if ngx and ngx.log then
        local log_level = result.valid and ngx.INFO or ngx.WARN
        ngx.log(log_level, string.format(
            "[config_validator] dry_run: type=%s, valid=%s, errors=%d, warnings=%d",
            config_type,
            tostring(result.valid),
            #result.errors,
            #result.warnings
        ))
    end
    
    return result
end

--- 批量验证应用配置
--- @param configs table 配置列表
--- @return table results 验证结果列表
function _M.validate_batch(configs)
    local results = {}
    
    for i, config in ipairs(configs) do
        local valid, errors = _M.validate_app_config(config)
        results[i] = {
            index = i,
            app_id = config.app_id,
            valid = valid,
            errors = errors
        }
    end
    
    return results
end

return _M
