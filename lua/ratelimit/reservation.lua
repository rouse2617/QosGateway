-- ratelimit/reservation.lua
-- Reservation Manager: 预留管理器
-- 管理长时间操作的令牌预留与释放

local _M = {
    _VERSION = '1.0.0'
}

local shared = ngx.shared.ratelimit_dict
local redis_client = require "ratelimit.redis"
local cjson = require "cjson.safe"

local CONFIG = {
    DEFAULT_TIMEOUT = 3600,     -- 1 小时默认超时
    CLEANUP_INTERVAL = 60,      -- 60 秒清理间隔
    MAX_RESERVATIONS = 10000,   -- 最大预留数
}

--- 创建令牌预留
--- @param app_id string 应用 ID
--- @param estimated_cost number 预估 Cost
--- @return string reservation_id 预留 ID
function _M.create(app_id, estimated_cost)
    local reservation_id = ngx.md5(app_id .. ngx.now() .. math.random())
    local key = "reservation:" .. reservation_id
    
    shared:set(key .. ":app_id", app_id)
    shared:set(key .. ":estimated", estimated_cost)
    shared:set(key .. ":actual", 0)
    shared:set(key .. ":created_at", ngx.now())
    shared:set(key .. ":expires_at", ngx.now() + CONFIG.DEFAULT_TIMEOUT)
    shared:set(key .. ":status", "active")
    
    -- 预扣令牌
    local bucket_key = "app:" .. app_id
    shared:incr(bucket_key .. ":tokens", -estimated_cost)
    shared:incr(bucket_key .. ":reserved", estimated_cost, 0)
    
    return reservation_id
end

--- 完成预留并对账
--- @param reservation_id string 预留 ID
--- @param actual_cost number 实际 Cost
--- @return boolean success 是否成功
--- @return number diff 差额
function _M.complete(reservation_id, actual_cost)
    local key = "reservation:" .. reservation_id
    local app_id = shared:get(key .. ":app_id")
    local estimated = shared:get(key .. ":estimated") or 0
    local status = shared:get(key .. ":status")
    
    if not app_id or status ~= "active" then
        return false, 0
    end
    
    local diff = estimated - actual_cost
    local bucket_key = "app:" .. app_id
    
    -- 对账：退还或补扣
    if diff ~= 0 then
        shared:incr(bucket_key .. ":tokens", diff)
    end
    
    shared:incr(bucket_key .. ":reserved", -estimated)
    
    -- 更新预留状态
    shared:set(key .. ":actual", actual_cost)
    shared:set(key .. ":status", "completed")
    shared:set(key .. ":completed_at", ngx.now())
    
    return true, diff
end

--- 取消预留
--- @param reservation_id string 预留 ID
--- @return boolean success 是否成功
function _M.cancel(reservation_id)
    local key = "reservation:" .. reservation_id
    local app_id = shared:get(key .. ":app_id")
    local estimated = shared:get(key .. ":estimated") or 0
    local status = shared:get(key .. ":status")
    
    if not app_id or status ~= "active" then
        return false
    end
    
    local bucket_key = "app:" .. app_id
    
    -- 退还预留令牌
    shared:incr(bucket_key .. ":tokens", estimated)
    shared:incr(bucket_key .. ":reserved", -estimated)
    
    -- 更新状态
    shared:set(key .. ":status", "cancelled")
    shared:set(key .. ":cancelled_at", ngx.now())
    
    return true
end

--- 获取预留状态
--- @param reservation_id string 预留 ID
--- @return table status 状态
function _M.get_status(reservation_id)
    local key = "reservation:" .. reservation_id
    
    return {
        app_id = shared:get(key .. ":app_id"),
        estimated = shared:get(key .. ":estimated") or 0,
        actual = shared:get(key .. ":actual") or 0,
        created_at = shared:get(key .. ":created_at") or 0,
        expires_at = shared:get(key .. ":expires_at") or 0,
        status = shared:get(key .. ":status") or "unknown"
    }
end

--- 清理过期预留
--- @return number cleaned 清理数量
function _M.cleanup_expired()
    local now = ngx.now()
    local cleaned = 0
    local keys = shared:get_keys(1000)
    
    for _, key in ipairs(keys) do
        if string.match(key, "^reservation:.-:expires_at$") then
            local expires_at = shared:get(key) or 0
            if expires_at > 0 and now > expires_at then
                local reservation_id = string.match(key, "^reservation:(.-):expires_at$")
                if reservation_id then
                    local status = shared:get("reservation:" .. reservation_id .. ":status")
                    if status == "active" then
                        _M.cancel(reservation_id)
                        cleaned = cleaned + 1
                    end
                end
            end
        end
    end
    
    return cleaned
end

--- 启动清理定时器
function _M.start_cleanup_timer()
    local handler
    handler = function(premature)
        if premature then return end
        pcall(_M.cleanup_expired)
        ngx.timer.at(CONFIG.CLEANUP_INTERVAL, handler)
    end
    ngx.timer.at(CONFIG.CLEANUP_INTERVAL, handler)
end

return _M
