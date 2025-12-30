-- ratelimit/init.lua
-- Main Entry Module: 主入口模块
-- 整合所有限流组件，提供统一的 Nginx 集成接口

local _M = {
    _VERSION = '1.0.0'
}

-- 加载依赖模块
local cost_calculator = require "ratelimit.cost"
local l3_bucket = require "ratelimit.l3_bucket"
local l2_bucket = require "ratelimit.l2_bucket"
local l1_cluster = require "ratelimit.l1_cluster"
local borrow = require "ratelimit.borrow"
local emergency = require "ratelimit.emergency"
local reconciler = require "ratelimit.reconciler"
local connection_limiter = require "ratelimit.connection_limiter"
local reservation = require "ratelimit.reservation"
local config_validator = require "ratelimit.config_validator"
local cjson = require "cjson.safe"

local shared = ngx.shared.ratelimit_dict
local config_dict = ngx.shared.config_dict

local CONFIG = {
    HEALTH_PATH = "/health",
    METRICS_PATH = "/metrics",
    ADMIN_PREFIX = "/admin",
}

--- 初始化限流系统（在 init_worker_by_lua 阶段调用）
function _M.init()
    -- 只在 worker 0 启动定时器
    if ngx.worker.id() == 0 then
        -- 启动对账定时器
        reconciler.start_timer()
        
        -- 启动连接清理定时器
        connection_limiter.start_cleanup_timer()
        
        -- 启动预留清理定时器
        reservation.start_cleanup_timer()
        
        ngx.log(ngx.NOTICE, "[ratelimit] System initialized on worker 0")
    end
    
    ngx.log(ngx.NOTICE, "[ratelimit] Worker ", ngx.worker.id(), " ready")
    return true
end

--- 主限流检查（在 access_by_lua 阶段调用）
--- @param app_id string 应用 ID
--- @param user_id string 用户 ID（可选）
--- @param cluster_id string 集群 ID
--- @return boolean allowed 是否允许
function _M.check(app_id, user_id, cluster_id)
    local start_time = ngx.now()
    
    -- 跳过健康检查和指标端点
    local uri = ngx.var.uri
    if uri == CONFIG.HEALTH_PATH or uri == CONFIG.METRICS_PATH then
        return true
    end
    
    -- 参数默认值
    app_id = app_id or ngx.var.arg_app_id or "default"
    cluster_id = cluster_id or ngx.var.arg_cluster_id or "default"
    user_id = user_id or ngx.var.arg_user_id
    
    -- 存储到上下文
    ngx.ctx.ratelimit = {
        app_id = app_id,
        user_id = user_id,
        cluster_id = cluster_id,
        start_time = start_time
    }
    
    -- 1. 连接限制检查
    local conn_ok, conn_result = connection_limiter.acquire(app_id, cluster_id)
    if not conn_ok then
        _M.reject(429, conn_result)
        return false
    end
    
    -- 2. 计算请求 Cost
    local method = ngx.req.get_method()
    local body_size = tonumber(ngx.var.content_length) or 0
    local cost, cost_details = cost_calculator.calculate(method, body_size)
    
    ngx.ctx.ratelimit.cost = cost
    ngx.ctx.ratelimit.cost_details = cost_details
    
    -- 3. 检查紧急模式
    if emergency.is_active() then
        local em_ok, em_reason = emergency.check_emergency_request(app_id, cost)
        if not em_ok then
            _M.reject(429, {code = em_reason, cost = cost})
            return false
        end
    end
    
    -- 4. L3 本地令牌检查
    local l3_ok, l3_result = l3_bucket.acquire(app_id, cost)
    if l3_ok then
        ngx.ctx.ratelimit.remaining = l3_result.remaining
        ngx.ctx.ratelimit.source = "l3_local"
        _M.set_response_headers(cost, l3_result.remaining)
        return true
    end
    
    -- 5. L2 应用层获取
    local l2_ok, l2_result = l2_bucket.acquire(app_id, cost)
    if l2_ok then
        ngx.ctx.ratelimit.remaining = l2_result.remaining
        ngx.ctx.ratelimit.source = "l2_app"
        _M.set_response_headers(cost, l2_result.remaining)
        return true
    end
    
    -- 6. 尝试借用
    local borrow_ok, borrow_result = borrow.borrow(app_id, cost)
    if borrow_ok then
        ngx.ctx.ratelimit.remaining = borrow_result.remaining
        ngx.ctx.ratelimit.source = "borrowed"
        ngx.ctx.ratelimit.borrowed = true
        _M.set_response_headers(cost, borrow_result.remaining)
        return true
    end
    
    -- 7. 限流拒绝
    _M.reject(429, {
        code = "rate_limit_exceeded",
        cost = cost,
        app_id = app_id,
        retry_after = _M.calculate_retry_after(app_id)
    })
    return false
end

--- 设置响应头
--- @param cost number 请求 Cost
--- @param remaining number 剩余令牌
function _M.set_response_headers(cost, remaining)
    ngx.header["X-RateLimit-Cost"] = cost
    ngx.header["X-RateLimit-Remaining"] = math.max(0, remaining or 0)
    
    -- 连接限制头
    local conn_id = ngx.ctx.conn_limit_id
    if conn_id then
        local conn_stats = connection_limiter.get_stats(
            ngx.ctx.ratelimit.app_id,
            ngx.ctx.ratelimit.cluster_id
        )
        if conn_stats.app then
            ngx.header["X-Connection-Limit"] = conn_stats.app.limit or 0
            ngx.header["X-Connection-Current"] = conn_stats.app.current or 0
        end
    end
end

--- 拒绝请求
--- @param status number HTTP 状态码
--- @param details table 详情
function _M.reject(status, details)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.header["Retry-After"] = details.retry_after or 1
    
    local response = {
        error = details.code or "rate_limited",
        message = _M.get_error_message(details.code),
        details = {
            app_id = details.app_id or ngx.ctx.ratelimit and ngx.ctx.ratelimit.app_id,
            cost = details.cost,
            limit = details.limit,
            current = details.current
        },
        retry_after = details.retry_after or 1
    }
    
    ngx.say(cjson.encode(response))
    ngx.exit(status)
end

--- 获取错误消息
--- @param code string 错误码
--- @return string message 错误消息
function _M.get_error_message(code)
    local messages = {
        rate_limit_exceeded = "Rate limit exceeded, please retry later",
        app_limit_exceeded = "Application connection limit exceeded",
        cluster_limit_exceeded = "Cluster connection limit exceeded",
        emergency_blocked = "Request blocked due to emergency mode",
        emergency_quota_exceeded = "Emergency quota exceeded",
        invalid_input = "Invalid request parameters"
    }
    return messages[code] or "Request rejected"
end

--- 计算重试等待时间
--- @param app_id string 应用 ID
--- @return number seconds 等待秒数
function _M.calculate_retry_after(app_id)
    local config = _M.get_app_config(app_id)
    if not config then return 1 end
    
    local refill_rate = config.guaranteed_quota or 1000
    local cost = ngx.ctx.ratelimit and ngx.ctx.ratelimit.cost or 1
    
    return math.ceil(cost / refill_rate) + 1
end

--- 获取应用配置
--- @param app_id string 应用 ID
--- @return table config 配置
function _M.get_app_config(app_id)
    local key = "config:app:" .. app_id
    local config_str = config_dict:get(key)
    if config_str then
        return cjson.decode(config_str)
    end
    return nil
end

--- 日志阶段处理（在 log_by_lua 阶段调用）
function _M.log()
    -- 释放连接
    connection_limiter.release()
    
    -- 记录请求日志
    local ctx = ngx.ctx.ratelimit
    if not ctx then return end
    
    local latency = ngx.now() - ctx.start_time
    local status = ngx.status
    
    -- 更新统计
    shared:incr("stats:requests:total", 1, 0)
    shared:incr("stats:requests:" .. ctx.app_id, 1, 0)
    
    if status == 429 then
        shared:incr("stats:rejected:total", 1, 0)
        shared:incr("stats:rejected:" .. ctx.app_id, 1, 0)
    end
    
    -- 记录延迟
    if latency > 0.05 then  -- > 50ms
        ngx.log(ngx.WARN, string.format(
            "[ratelimit] Slow request: app=%s, cost=%d, latency=%.3fs, status=%d",
            ctx.app_id, ctx.cost or 0, latency, status
        ))
    end
end

--- 健康检查端点
function _M.health()
    ngx.header["Content-Type"] = "application/json"
    
    local health = {
        status = "healthy",
        timestamp = ngx.now(),
        worker_id = ngx.worker.id(),
        components = {
            ratelimit_dict = shared and "ok" or "missing",
            config_dict = config_dict and "ok" or "missing"
        }
    }
    
    ngx.say(cjson.encode(health))
end

--- 创建预留
--- @param app_id string 应用 ID
--- @param estimated_cost number 预估 Cost
--- @return string reservation_id 预留 ID
function _M.create_reservation(app_id, estimated_cost)
    return reservation.create(app_id, estimated_cost)
end

--- 完成预留
--- @param reservation_id string 预留 ID
--- @param actual_cost number 实际 Cost
--- @return boolean success
--- @return number diff 差额
function _M.complete_reservation(reservation_id, actual_cost)
    return reservation.complete(reservation_id, actual_cost)
end

--- 取消预留
--- @param reservation_id string 预留 ID
--- @return boolean success
function _M.cancel_reservation(reservation_id)
    return reservation.cancel(reservation_id)
end

--- 回滚令牌（请求取消时）
--- @param app_id string 应用 ID
--- @param cost number Cost
--- @return boolean success
function _M.rollback(app_id, cost)
    return l3_bucket.rollback(app_id, cost)
end

return _M
