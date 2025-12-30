-- ratelimit/borrow.lua
-- Borrow Manager: 令牌借用管理器
-- 管理令牌借用和归还，支持利息计算

local _M = {
    _VERSION = '1.0.0'
}

local redis_client = require "ratelimit.redis"
local cjson = require "cjson.safe"

-- 配置常量
local CONFIG = {
    INTEREST_RATE = 0.2,            -- 20% 利息
    DEFAULT_MAX_BORROW = 10000,     -- 默认最大借用
    HISTORY_RETENTION = 86400,      -- 历史记录保留 24 小时
    MAX_HISTORY_ENTRIES = 100,      -- 最大历史记录数
}

--- 借用令牌
--- @param app_id string 应用 ID
--- @param amount number 借用数量
--- @return table result 借用结果
function _M.borrow(app_id, amount)
    local app_key = "ratelimit:l2:" .. app_id
    local cluster_key = "ratelimit:l1:cluster"
    
    local result, err = redis_client.eval_script("BORROW", 
        {app_key, cluster_key}, 
        {amount, ngx.now()}
    )
    
    if err then
        return {
            success = false,
            code = "redis_error",
            error = err
        }
    end
    
    if type(result) ~= "table" then
        return {
            success = false,
            code = "invalid_response"
        }
    end
    
    local success = result[1] == 1
    local code = result[2]
    
    if success then
        local borrowed = result[3]
        local debt = result[4]
        
        -- 记录借用历史
        _M.record_history(app_id, "borrow", {
            amount = borrowed,
            debt = debt,
            timestamp = ngx.now()
        })
        
        return {
            success = true,
            code = "borrowed",
            borrowed = borrowed,
            debt = debt,
            interest_rate = CONFIG.INTEREST_RATE
        }
    else
        local available = result[3] or 0
        return {
            success = false,
            code = code,
            available = available
        }
    end
end

--- 还款
--- @param app_id string 应用 ID
--- @param amount number 还款数量
--- @return table result 还款结果
function _M.repay(app_id, amount)
    local app_key = "ratelimit:l2:" .. app_id
    local cluster_key = "ratelimit:l1:cluster"
    
    local red, err = redis_client.get_connection()
    if not red then
        return {
            success = false,
            code = "redis_error",
            error = err
        }
    end
    
    -- 获取当前债务和借用
    local debt = tonumber(red:hget(app_key, "debt")) or 0
    local borrowed = tonumber(red:hget(app_key, "borrowed")) or 0
    
    if debt <= 0 then
        redis_client.release_connection(red)
        return {
            success = true,
            code = "no_debt",
            repaid = 0
        }
    end
    
    -- 计算实际还款
    local repay_amount = math.min(amount, debt)
    
    -- 计算本金部分 (债务 = 本金 × 1.2)
    local principal_ratio = borrowed / debt
    local principal_repaid = repay_amount * principal_ratio
    
    -- 更新债务和借用
    red:init_pipeline()
    red:hincrby(app_key, "debt", -repay_amount)
    red:hincrbyfloat(app_key, "borrowed", -principal_repaid)
    
    -- 归还集群配额
    red:incrby(cluster_key .. ":available", math.floor(principal_repaid))
    
    local results, err = red:commit_pipeline()
    redis_client.release_connection(red)
    
    if err then
        return {
            success = false,
            code = "redis_error",
            error = err
        }
    end
    
    -- 记录还款历史
    _M.record_history(app_id, "repay", {
        amount = repay_amount,
        principal = principal_repaid,
        timestamp = ngx.now()
    })
    
    return {
        success = true,
        code = "repaid",
        repaid = repay_amount,
        principal_repaid = principal_repaid,
        remaining_debt = debt - repay_amount
    }
end

--- 获取借用状态
--- @param app_id string 应用 ID
--- @return table status 借用状态
function _M.get_status(app_id)
    local app_key = "ratelimit:l2:" .. app_id
    
    local red, err = redis_client.get_connection()
    if not red then
        return nil, err
    end
    
    red:init_pipeline()
    red:hget(app_key, "borrowed")
    red:hget(app_key, "debt")
    red:hget(app_key, "max_borrow")
    
    local results, err = red:commit_pipeline()
    redis_client.release_connection(red)
    
    if err or not results then
        return nil, err
    end
    
    local borrowed = tonumber(results[1]) or 0
    local debt = tonumber(results[2]) or 0
    local max_borrow = tonumber(results[3]) or CONFIG.DEFAULT_MAX_BORROW
    
    return {
        borrowed = borrowed,
        debt = debt,
        max_borrow = max_borrow,
        available_borrow = max_borrow - borrowed,
        interest_accrued = debt - borrowed,
        interest_rate = CONFIG.INTEREST_RATE
    }
end

--- 记录借用/还款历史
--- @param app_id string 应用 ID
--- @param action string 操作类型 (borrow/repay)
--- @param data table 数据
function _M.record_history(app_id, action, data)
    local history_key = "ratelimit:borrow:history:" .. app_id
    
    local red, err = redis_client.get_connection()
    if not red then
        return
    end
    
    local entry = cjson.encode({
        action = action,
        data = data,
        timestamp = ngx.now()
    })
    
    -- 添加到列表头部
    red:lpush(history_key, entry)
    
    -- 限制列表长度
    red:ltrim(history_key, 0, CONFIG.MAX_HISTORY_ENTRIES - 1)
    
    -- 设置过期时间
    red:expire(history_key, CONFIG.HISTORY_RETENTION)
    
    redis_client.release_connection(red)
end

--- 获取借用历史
--- @param app_id string 应用 ID
--- @param limit number 限制数量 (可选)
--- @return table history 历史记录
function _M.get_history(app_id, limit)
    limit = limit or 20
    local history_key = "ratelimit:borrow:history:" .. app_id
    
    local red, err = redis_client.get_connection()
    if not red then
        return {}, err
    end
    
    local entries, err = red:lrange(history_key, 0, limit - 1)
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

--- 设置最大借用限制
--- @param app_id string 应用 ID
--- @param max_borrow number 最大借用
--- @return boolean success 是否成功
function _M.set_max_borrow(app_id, max_borrow)
    local app_key = "ratelimit:l2:" .. app_id
    
    local red, err = redis_client.get_connection()
    if not red then
        return false, err
    end
    
    local ok, err = red:hset(app_key, "max_borrow", max_borrow)
    redis_client.release_connection(red)
    
    return ok ~= nil
end

--- 强制清除债务 (管理员操作)
--- @param app_id string 应用 ID
--- @return boolean success 是否成功
function _M.clear_debt(app_id)
    local app_key = "ratelimit:l2:" .. app_id
    
    local red, err = redis_client.get_connection()
    if not red then
        return false, err
    end
    
    red:init_pipeline()
    red:hset(app_key, "borrowed", 0)
    red:hset(app_key, "debt", 0)
    
    local results, err = red:commit_pipeline()
    redis_client.release_connection(red)
    
    if err then
        return false, err
    end
    
    -- 记录历史
    _M.record_history(app_id, "clear_debt", {
        timestamp = ngx.now(),
        admin_action = true
    })
    
    return true
end

--- 获取配置
--- @return table config 配置
function _M.get_config()
    return {
        INTEREST_RATE = CONFIG.INTEREST_RATE,
        DEFAULT_MAX_BORROW = CONFIG.DEFAULT_MAX_BORROW,
    }
end

return _M
