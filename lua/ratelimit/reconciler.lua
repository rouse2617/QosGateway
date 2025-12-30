-- ratelimit/reconciler.lua
-- Reconciler: 对账器
-- 定期对账 L3 与 L2 的令牌状态，修正累积偏差

local _M = {
    _VERSION = '1.0.0'
}

local redis_client = require "ratelimit.redis"
local l1_cluster = require "ratelimit.l1_cluster"
local l2_bucket = require "ratelimit.l2_bucket"
local cjson = require "cjson.safe"

local shared = ngx.shared.ratelimit_dict

-- 配置常量
local CONFIG = {
    RECONCILE_INTERVAL = 60,        -- 60 秒对账周期
    DRIFT_TOLERANCE = 0.1,          -- 10% 漂移容忍度
    MAX_CORRECTION = 10000,         -- 单次最大修正量
    STATS_KEY = "reconciler:stats",
}

--- 获取 L3 本地状态
--- @param app_id string 应用 ID
--- @return table status L3 状态
local function get_l3_status(app_id)
    local prefix = "app:" .. app_id
    
    return {
        tokens = shared:get(prefix .. ":tokens") or 0,
        pending_cost = shared:get(prefix .. ":pending_cost") or 0,
        pending_count = shared:get(prefix .. ":pending_count") or 0,
        last_sync = shared:get(prefix .. ":last_sync") or 0,
    }
end

--- 对账单个应用
--- @param app_id string 应用 ID
--- @return table result 对账结果
function _M.reconcile_app(app_id)
    local l3_status = get_l3_status(app_id)
    local l2_config = l2_bucket.get_config(app_id)
    
    if not l2_config then
        return {
            app_id = app_id,
            success = false,
            error = "l2_config_not_found"
        }
    end
    
    -- 计算预期 L3 令牌数
    -- L3 应该 = L2 当前令牌 - 待同步消耗
    local expected_l3 = l2_config.current_tokens - l3_status.pending_cost
    local actual_l3 = l3_status.tokens
    
    -- 计算漂移
    local drift = actual_l3 - expected_l3
    local drift_ratio = math.abs(drift) / math.max(l2_config.guaranteed_quota, 1)
    
    local corrected = false
    local correction = 0
    
    -- 如果漂移超过容忍度，进行修正
    if drift_ratio > CONFIG.DRIFT_TOLERANCE then
        -- 限制单次修正量
        correction = math.min(math.abs(drift), CONFIG.MAX_CORRECTION)
        if drift > 0 then
            correction = -correction  -- 需要减少
        end
        
        -- 应用修正
        local prefix = "app:" .. app_id
        shared:incr(prefix .. ":tokens", correction, 0)
        
        corrected = true
        
        -- 记录修正
        _M.record_correction(app_id, drift, correction)
        
        ngx.log(ngx.WARN, "Reconciliation corrected app ", app_id, 
                ": drift=", drift, " (", drift_ratio * 100, "%), correction=", correction)
    end
    
    -- 同步待处理消耗到 L2
    if l3_status.pending_cost > 0 then
        local ok = l2_bucket.report_consumption(
            app_id, 
            l3_status.pending_cost, 
            l3_status.pending_count
        )
        
        if ok then
            local prefix = "app:" .. app_id
            shared:set(prefix .. ":pending_cost", 0)
            shared:set(prefix .. ":pending_count", 0)
            shared:set(prefix .. ":last_sync", ngx.now())
        end
    end
    
    return {
        app_id = app_id,
        success = true,
        l3_tokens = actual_l3,
        l2_tokens = l2_config.current_tokens,
        pending_cost = l3_status.pending_cost,
        expected_l3 = expected_l3,
        drift = drift,
        drift_ratio = drift_ratio,
        corrected = corrected,
        correction = correction
    }
end

--- 执行全局对账
--- @return table result 对账结果
function _M.reconcile_all()
    local start_time = ngx.now()
    
    -- 获取所有应用
    local apps = l2_bucket.list_apps()
    
    local results = {
        total_apps = #apps,
        corrected_apps = 0,
        total_drift = 0,
        app_results = {},
        timestamp = start_time
    }
    
    -- 对账每个应用
    for _, app_id in ipairs(apps) do
        local result = _M.reconcile_app(app_id)
        table.insert(results.app_results, result)
        
        if result.corrected then
            results.corrected_apps = results.corrected_apps + 1
        end
        
        if result.drift then
            results.total_drift = results.total_drift + math.abs(result.drift)
        end
    end
    
    -- 执行 L1 全局对账
    local l1_result = l1_cluster.reconcile()
    results.l1_reconcile = l1_result
    
    -- 更新统计
    _M.update_stats(results)
    
    results.duration = ngx.now() - start_time
    
    ngx.log(ngx.INFO, "Reconciliation completed: apps=", results.total_apps,
            ", corrected=", results.corrected_apps, 
            ", duration=", results.duration, "s")
    
    return results
end

--- 记录修正
--- @param app_id string 应用 ID
--- @param drift number 漂移量
--- @param correction number 修正量
function _M.record_correction(app_id, drift, correction)
    local key = "ratelimit:reconcile:corrections:" .. app_id
    
    local red, err = redis_client.get_connection()
    if not red then
        return
    end
    
    local entry = cjson.encode({
        drift = drift,
        correction = correction,
        timestamp = ngx.now()
    })
    
    red:lpush(key, entry)
    red:ltrim(key, 0, 99)  -- 保留最近 100 条
    red:expire(key, 86400)  -- 24 小时过期
    
    -- 增加全局修正计数
    red:incr("ratelimit:reconcile:correction_count")
    
    redis_client.release_connection(red)
end

--- 更新统计
--- @param results table 对账结果
function _M.update_stats(results)
    local red, err = redis_client.get_connection()
    if not red then
        return
    end
    
    red:init_pipeline()
    red:set("ratelimit:reconcile:last_run", ngx.now())
    red:set("ratelimit:reconcile:last_duration", results.duration or 0)
    red:set("ratelimit:reconcile:last_corrected", results.corrected_apps or 0)
    red:incr("ratelimit:reconcile:total_runs")
    
    local results_json = cjson.encode(results)
    red:set("ratelimit:reconcile:last_result", results_json)
    
    red:commit_pipeline()
    redis_client.release_connection(red)
end

--- 获取统计
--- @return table stats 统计
function _M.get_stats()
    local red, err = redis_client.get_connection()
    if not red then
        return nil, err
    end
    
    red:init_pipeline()
    red:get("ratelimit:reconcile:last_run")
    red:get("ratelimit:reconcile:last_duration")
    red:get("ratelimit:reconcile:last_corrected")
    red:get("ratelimit:reconcile:total_runs")
    red:get("ratelimit:reconcile:correction_count")
    
    local results, err = red:commit_pipeline()
    redis_client.release_connection(red)
    
    if err or not results then
        return nil, err
    end
    
    return {
        last_run = tonumber(results[1]) or 0,
        last_duration = tonumber(results[2]) or 0,
        last_corrected = tonumber(results[3]) or 0,
        total_runs = tonumber(results[4]) or 0,
        correction_count = tonumber(results[5]) or 0,
    }
end

--- 获取应用的修正历史
--- @param app_id string 应用 ID
--- @param limit number 限制数量
--- @return table history 历史
function _M.get_correction_history(app_id, limit)
    limit = limit or 20
    local key = "ratelimit:reconcile:corrections:" .. app_id
    
    local red, err = redis_client.get_connection()
    if not red then
        return {}, err
    end
    
    local entries, err = red:lrange(key, 0, limit - 1)
    redis_client.release_connection(red)
    
    if err or not entries then
        return {}
    end
    
    local history = {}
    for _, entry in ipairs(entries) do
        local data = cjson.decode(entry)
        if data then
            table.insert(history, data)
        end
    end
    
    return history
end

--- 启动对账定时器
function _M.start_timer()
    local handler
    handler = function(premature)
        if premature then return end
        
        local ok, err = pcall(_M.reconcile_all)
        if not ok then
            ngx.log(ngx.ERR, "Reconciliation error: ", err)
        end
        
        -- 重新调度
        ngx.timer.at(CONFIG.RECONCILE_INTERVAL, handler)
    end
    
    -- 延迟启动，避免启动时负载过高
    ngx.timer.at(10, handler)
end

--- 手动触发对账
--- @return table result 对账结果
function _M.trigger()
    return _M.reconcile_all()
end

--- 获取配置
--- @return table config 配置
function _M.get_config()
    return {
        RECONCILE_INTERVAL = CONFIG.RECONCILE_INTERVAL,
        DRIFT_TOLERANCE = CONFIG.DRIFT_TOLERANCE,
        MAX_CORRECTION = CONFIG.MAX_CORRECTION,
    }
end

return _M
