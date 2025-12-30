-- ratelimit/metrics.lua
-- Metrics Collector: 监控指标收集器
-- 提供 Prometheus 兼容格式的指标暴露

local _M = {
    _VERSION = '1.0.0'
}

local shared = ngx.shared.ratelimit_dict
local connlimit_dict = ngx.shared.connlimit_dict
local redis_client = require "ratelimit.redis"
local cjson = require "cjson.safe"

local CONFIG = {
    REPORT_INTERVAL = 10,  -- Redis 上报间隔（秒）
}

--- 生成 Prometheus 格式指标
--- @return string metrics Prometheus 格式文本
function _M.prometheus()
    local lines = {}
    
    -- 请求指标
    table.insert(lines, "# HELP ratelimit_requests_total Total number of requests")
    table.insert(lines, "# TYPE ratelimit_requests_total counter")
    _M.add_counter_metrics(lines, "ratelimit_requests_total", "stats:requests:")
    
    -- 拒绝指标
    table.insert(lines, "# HELP ratelimit_rejected_total Total number of rejected requests")
    table.insert(lines, "# TYPE ratelimit_rejected_total counter")
    _M.add_counter_metrics(lines, "ratelimit_rejected_total", "stats:rejected:")
    
    -- 令牌指标
    table.insert(lines, "# HELP ratelimit_tokens_available Available tokens")
    table.insert(lines, "# TYPE ratelimit_tokens_available gauge")
    _M.add_token_metrics(lines)
    
    -- 连接限制指标
    table.insert(lines, "# HELP connlimit_active_connections Current active connections")
    table.insert(lines, "# TYPE connlimit_active_connections gauge")
    _M.add_connection_metrics(lines, "connlimit_active_connections", "current")
    
    table.insert(lines, "# HELP connlimit_peak_connections Peak connections")
    table.insert(lines, "# TYPE connlimit_peak_connections gauge")
    _M.add_connection_metrics(lines, "connlimit_peak_connections", "peak")
    
    table.insert(lines, "# HELP connlimit_rejected_total Total rejected connections")
    table.insert(lines, "# TYPE connlimit_rejected_total counter")
    local rejected = connlimit_dict:get("conn:rejected:total") or 0
    table.insert(lines, string.format("connlimit_rejected_total %d", rejected))
    
    table.insert(lines, "# HELP connlimit_leaked_total Total leaked connections cleaned")
    table.insert(lines, "# TYPE connlimit_leaked_total counter")
    local leaked = connlimit_dict:get("conn:leaked:total") or 0
    table.insert(lines, string.format("connlimit_leaked_total %d", leaked))
    
    -- Redis 延迟指标
    table.insert(lines, "# HELP ratelimit_redis_latency_seconds Redis operation latency")
    table.insert(lines, "# TYPE ratelimit_redis_latency_seconds histogram")
    _M.add_redis_latency_metrics(lines)
    
    -- 紧急模式指标
    table.insert(lines, "# HELP ratelimit_emergency_mode Emergency mode status (1=active)")
    table.insert(lines, "# TYPE ratelimit_emergency_mode gauge")
    local emergency_active = shared:get("emergency:active") and 1 or 0
    table.insert(lines, string.format("ratelimit_emergency_mode %d", emergency_active))
    
    -- 降级状态指标
    table.insert(lines, "# HELP ratelimit_degradation_level Degradation level (0=normal,1=mild,2=significant,3=fail_open)")
    table.insert(lines, "# TYPE ratelimit_degradation_level gauge")
    local level = _M.get_degradation_level_num()
    table.insert(lines, string.format("ratelimit_degradation_level %d", level))
    
    -- 对账修正指标
    table.insert(lines, "# HELP ratelimit_reconcile_corrections_total Total reconciliation corrections")
    table.insert(lines, "# TYPE ratelimit_reconcile_corrections_total counter")
    local corrections = shared:get("reconcile:corrections:total") or 0
    table.insert(lines, string.format("ratelimit_reconcile_corrections_total %d", corrections))
    
    -- 缓存命中率
    table.insert(lines, "# HELP ratelimit_cache_hit_ratio L3 cache hit ratio")
    table.insert(lines, "# TYPE ratelimit_cache_hit_ratio gauge")
    local hit_ratio = _M.calculate_cache_hit_ratio()
    table.insert(lines, string.format("ratelimit_cache_hit_ratio %.4f", hit_ratio))
    
    return table.concat(lines, "\n") .. "\n"
end

--- 添加计数器指标
--- @param lines table 输出行
--- @param metric_name string 指标名
--- @param key_prefix string 键前缀
function _M.add_counter_metrics(lines, metric_name, key_prefix)
    local keys = shared:get_keys(1000)
    local added = {}
    
    for _, key in ipairs(keys) do
        if string.match(key, "^" .. key_prefix) then
            local app_id = string.match(key, "^" .. key_prefix .. "(.+)$")
            if app_id and app_id ~= "total" and not added[app_id] then
                local value = shared:get(key) or 0
                table.insert(lines, string.format(
                    '%s{app_id="%s"} %d',
                    metric_name, app_id, value
                ))
                added[app_id] = true
            end
        end
    end
    
    -- 总计
    local total = shared:get(key_prefix .. "total") or 0
    table.insert(lines, string.format('%s{app_id="total"} %d', metric_name, total))
end

--- 添加令牌指标
--- @param lines table 输出行
function _M.add_token_metrics(lines)
    local keys = shared:get_keys(1000)
    local apps = {}
    
    for _, key in ipairs(keys) do
        local app_id = string.match(key, "^app:(.+):tokens$")
        if app_id and not apps[app_id] then
            apps[app_id] = true
            local tokens = shared:get(key) or 0
            table.insert(lines, string.format(
                'ratelimit_tokens_available{app_id="%s",layer="l3"} %d',
                app_id, tokens
            ))
        end
    end
end

--- 添加连接指标
--- @param lines table 输出行
--- @param metric_name string 指标名
--- @param field string 字段名
function _M.add_connection_metrics(lines, metric_name, field)
    if not connlimit_dict then return end
    
    local keys = connlimit_dict:get_keys(1000)
    
    for _, key in ipairs(keys) do
        local app_id = string.match(key, "^conn:app:(.+)$")
        if app_id then
            local data_str = connlimit_dict:get(key)
            if data_str then
                local data = cjson.decode(data_str)
                if data and data[field] then
                    table.insert(lines, string.format(
                        '%s{type="app",id="%s"} %d',
                        metric_name, app_id, data[field]
                    ))
                end
            end
        end
        
        local cluster_id = string.match(key, "^conn:cluster:(.+)$")
        if cluster_id then
            local data_str = connlimit_dict:get(key)
            if data_str then
                local data = cjson.decode(data_str)
                if data and data[field] then
                    table.insert(lines, string.format(
                        '%s{type="cluster",id="%s"} %d',
                        metric_name, cluster_id, data[field]
                    ))
                end
            end
        end
    end
end

--- 添加 Redis 延迟指标
--- @param lines table 输出行
function _M.add_redis_latency_metrics(lines)
    local latency_str = shared:get("degradation:latency_history")
    if not latency_str then return end
    
    local history = cjson.decode(latency_str) or {}
    if #history == 0 then return end
    
    -- 计算分位数
    local latencies = {}
    for _, record in ipairs(history) do
        table.insert(latencies, record.latency / 1000)  -- 转换为秒
    end
    table.sort(latencies)
    
    local count = #latencies
    local sum = 0
    for _, v in ipairs(latencies) do sum = sum + v end
    
    local buckets = {0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1}
    for _, bucket in ipairs(buckets) do
        local bucket_count = 0
        for _, v in ipairs(latencies) do
            if v <= bucket then bucket_count = bucket_count + 1 end
        end
        table.insert(lines, string.format(
            'ratelimit_redis_latency_seconds_bucket{le="%.3f"} %d',
            bucket, bucket_count
        ))
    end
    table.insert(lines, string.format(
        'ratelimit_redis_latency_seconds_bucket{le="+Inf"} %d', count
    ))
    table.insert(lines, string.format('ratelimit_redis_latency_seconds_sum %.6f', sum))
    table.insert(lines, string.format('ratelimit_redis_latency_seconds_count %d', count))
end

--- 获取降级级别数值
--- @return number level
function _M.get_degradation_level_num()
    local level = shared:get("degradation:level") or "normal"
    local levels = {normal = 0, mild = 1, significant = 2, fail_open = 3}
    return levels[level] or 0
end

--- 计算缓存命中率
--- @return number ratio
function _M.calculate_cache_hit_ratio()
    local hits = shared:get("stats:l3_hits") or 0
    local total = shared:get("stats:requests:total") or 0
    
    if total == 0 then return 0 end
    return hits / total
end

--- 增加请求计数
--- @param app_id string 应用 ID
--- @param method string HTTP 方法
--- @param status number HTTP 状态码
function _M.incr_request(app_id, method, status)
    shared:incr("stats:requests:total", 1, 0)
    shared:incr("stats:requests:" .. app_id, 1, 0)
    
    if status == 429 then
        shared:incr("stats:rejected:total", 1, 0)
        shared:incr("stats:rejected:" .. app_id, 1, 0)
    end
end

--- 记录 L3 缓存命中
function _M.record_l3_hit()
    shared:incr("stats:l3_hits", 1, 0)
end

--- 上报统计到 Redis
function _M.report_to_redis()
    local ok, err = pcall(function()
        local red = redis_client.get_connection()
        if not red then return end
        
        local stats = {
            requests_total = shared:get("stats:requests:total") or 0,
            rejected_total = shared:get("stats:rejected:total") or 0,
            l3_hits = shared:get("stats:l3_hits") or 0,
            timestamp = ngx.now(),
            worker_id = ngx.worker.id()
        }
        
        red:hset("ratelimit:stats:" .. ngx.var.server_addr, 
                 "worker:" .. ngx.worker.id(),
                 cjson.encode(stats))
        red:expire("ratelimit:stats:" .. ngx.var.server_addr, 300)
        
        redis_client.release_connection(red)
    end)
    
    if not ok then
        ngx.log(ngx.WARN, "[metrics] Failed to report to Redis: ", err)
    end
end

--- 获取汇总统计
--- @return table stats
function _M.get_summary()
    return {
        requests_total = shared:get("stats:requests:total") or 0,
        rejected_total = shared:get("stats:rejected:total") or 0,
        l3_hits = shared:get("stats:l3_hits") or 0,
        cache_hit_ratio = _M.calculate_cache_hit_ratio(),
        emergency_active = shared:get("emergency:active") and true or false,
        degradation_level = shared:get("degradation:level") or "normal",
        reconcile_corrections = shared:get("reconcile:corrections:total") or 0
    }
end

--- 启动上报定时器
function _M.start_report_timer()
    local handler
    handler = function(premature)
        if premature then return end
        pcall(_M.report_to_redis)
        ngx.timer.at(CONFIG.REPORT_INTERVAL, handler)
    end
    ngx.timer.at(CONFIG.REPORT_INTERVAL, handler)
end

--- Prometheus 端点处理
function _M.serve_prometheus()
    ngx.header["Content-Type"] = "text/plain; charset=utf-8"
    ngx.say(_M.prometheus())
end

return _M
