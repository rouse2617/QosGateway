-- ratelimit/redis.lua
-- Redis Client: Redis 连接管理
-- 高效管理 Redis 连接池，支持 Lua 脚本预加载和故障重试

local _M = {
    _VERSION = '1.0.0'
}

local redis = require "resty.redis"
local cjson = require "cjson.safe"

-- 配置常量
local CONFIG = {
    HOST = os.getenv("REDIS_HOST") or "127.0.0.1",
    PORT = tonumber(os.getenv("REDIS_PORT")) or 6379,
    PASSWORD = os.getenv("REDIS_PASSWORD"),
    DATABASE = tonumber(os.getenv("REDIS_DATABASE")) or 0,
    TIMEOUT = 1000,                 -- 连接超时 1000ms
    POOL_SIZE = 50,                 -- 连接池大小
    IDLE_TIMEOUT = 60000,           -- 空闲超时 60s
    MAX_RETRIES = 3,                -- 最大重试次数
    RETRY_DELAY = 0.1,              -- 重试延迟 100ms
}

-- 预加载的 Lua 脚本
local SCRIPTS = {}

-- 脚本 SHA 缓存
local script_sha_cache = {}

--- 创建 Redis 连接
--- @return table red Redis 连接对象
--- @return string err 错误信息
local function create_connection()
    local red = redis:new()
    red:set_timeout(CONFIG.TIMEOUT)
    
    local ok, err = red:connect(CONFIG.HOST, CONFIG.PORT)
    if not ok then
        return nil, "connect failed: " .. (err or "unknown")
    end
    
    -- 认证
    if CONFIG.PASSWORD and CONFIG.PASSWORD ~= "" then
        local res, err = red:auth(CONFIG.PASSWORD)
        if not res then
            return nil, "auth failed: " .. (err or "unknown")
        end
    end
    
    -- 选择数据库
    if CONFIG.DATABASE > 0 then
        local res, err = red:select(CONFIG.DATABASE)
        if not res then
            return nil, "select db failed: " .. (err or "unknown")
        end
    end
    
    return red, nil
end

--- 获取 Redis 连接 (从连接池)
--- @return table red Redis 连接对象
--- @return string err 错误信息
function _M.get_connection()
    local red, err = create_connection()
    if not red then
        return nil, err
    end
    
    -- 检查连接是否可用
    local ok, err = red:ping()
    if not ok then
        return nil, "ping failed: " .. (err or "unknown")
    end
    
    return red, nil
end

--- 释放 Redis 连接 (归还连接池)
--- @param red table Redis 连接对象
function _M.release_connection(red)
    if not red then return end
    
    local ok, err = red:set_keepalive(CONFIG.IDLE_TIMEOUT, CONFIG.POOL_SIZE)
    if not ok then
        ngx.log(ngx.WARN, "failed to set keepalive: ", err)
    end
end

--- 关闭 Redis 连接
--- @param red table Redis 连接对象
function _M.close_connection(red)
    if not red then return end
    red:close()
end

--- 执行 Redis 命令 (带重试)
--- @param cmd string 命令名
--- @param ... any 命令参数
--- @return any result 执行结果
--- @return string err 错误信息
function _M.execute(cmd, ...)
    local args = {...}
    local last_err
    
    for i = 1, CONFIG.MAX_RETRIES do
        local red, err = _M.get_connection()
        if not red then
            last_err = err
            ngx.sleep(CONFIG.RETRY_DELAY)
        else
            local ok, result = pcall(function()
                return red[cmd](red, unpack(args))
            end)
            
            if ok then
                _M.release_connection(red)
                return result, nil
            else
                last_err = result
                _M.close_connection(red)
                ngx.sleep(CONFIG.RETRY_DELAY)
            end
        end
    end
    
    return nil, "max retries exceeded: " .. (last_err or "unknown")
end

--- 注册 Lua 脚本
--- @param name string 脚本名称
--- @param script string 脚本内容
function _M.register_script(name, script)
    SCRIPTS[name] = script
    script_sha_cache[name] = nil  -- 清除缓存
end

--- 加载脚本到 Redis
--- @param red table Redis 连接对象
--- @param name string 脚本名称
--- @return string sha 脚本 SHA
--- @return string err 错误信息
local function load_script(red, name)
    local script = SCRIPTS[name]
    if not script then
        return nil, "script not found: " .. name
    end
    
    -- 检查缓存
    if script_sha_cache[name] then
        return script_sha_cache[name], nil
    end
    
    -- 加载脚本
    local sha, err = red:script("LOAD", script)
    if not sha then
        return nil, "script load failed: " .. (err or "unknown")
    end
    
    script_sha_cache[name] = sha
    return sha, nil
end

--- 执行 Lua 脚本
--- @param name string 脚本名称
--- @param keys table 键列表
--- @param args table 参数列表
--- @return any result 执行结果
--- @return string err 错误信息
function _M.eval_script(name, keys, args)
    local red, err = _M.get_connection()
    if not red then
        return nil, err
    end
    
    -- 获取脚本 SHA
    local sha, err = load_script(red, name)
    if not sha then
        _M.release_connection(red)
        return nil, err
    end
    
    -- 构建参数
    local num_keys = #keys
    local eval_args = {sha, num_keys}
    
    for _, key in ipairs(keys) do
        table.insert(eval_args, key)
    end
    for _, arg in ipairs(args) do
        table.insert(eval_args, arg)
    end
    
    -- 执行脚本
    local result, err = red:evalsha(unpack(eval_args))
    
    if err and string.find(err, "NOSCRIPT") then
        -- 脚本不存在，重新加载
        script_sha_cache[name] = nil
        sha, err = load_script(red, name)
        if sha then
            eval_args[1] = sha
            result, err = red:evalsha(unpack(eval_args))
        end
    end
    
    _M.release_connection(red)
    
    if err then
        return nil, "evalsha failed: " .. err
    end
    
    return result, nil
end

--- 预加载所有脚本
function _M.preload_scripts()
    local red, err = _M.get_connection()
    if not red then
        ngx.log(ngx.ERR, "failed to preload scripts: ", err)
        return
    end
    
    for name, script in pairs(SCRIPTS) do
        local sha, err = red:script("LOAD", script)
        if sha then
            script_sha_cache[name] = sha
            ngx.log(ngx.INFO, "preloaded script: ", name, " sha: ", sha)
        else
            ngx.log(ngx.ERR, "failed to preload script ", name, ": ", err)
        end
    end
    
    _M.release_connection(red)
end

--- 检查 Redis 健康状态
--- @return boolean healthy 是否健康
--- @return number latency 延迟 (ms)
function _M.health_check()
    local start = ngx.now()
    local red, err = _M.get_connection()
    
    if not red then
        return false, -1
    end
    
    local ok, err = red:ping()
    local latency = (ngx.now() - start) * 1000
    
    _M.release_connection(red)
    
    return ok ~= nil, latency
end

--- 获取配置 (供测试使用)
--- @return table config 配置
function _M.get_config()
    return {
        HOST = CONFIG.HOST,
        PORT = CONFIG.PORT,
        TIMEOUT = CONFIG.TIMEOUT,
        POOL_SIZE = CONFIG.POOL_SIZE,
        IDLE_TIMEOUT = CONFIG.IDLE_TIMEOUT,
        MAX_RETRIES = CONFIG.MAX_RETRIES,
    }
end

--- 设置配置 (供测试使用)
--- @param key string 配置键
--- @param value any 配置值
function _M.set_config(key, value)
    if CONFIG[key] ~= nil then
        CONFIG[key] = value
    end
end

-- 注册内置脚本
_M.register_script("ACQUIRE", [[
    local key = KEYS[1]
    local cost = tonumber(ARGV[1])
    local now = tonumber(ARGV[2])
    
    local guaranteed = tonumber(redis.call('HGET', key, 'guaranteed_quota')) or 10000
    local burst = tonumber(redis.call('HGET', key, 'burst_quota')) or 50000
    local current = tonumber(redis.call('HGET', key, 'current_tokens')) or guaranteed
    local last_refill = tonumber(redis.call('HGET', key, 'last_refill')) or now
    
    local elapsed = math.max(0, now - last_refill)
    local refill_amount = elapsed * guaranteed
    local new_tokens = math.min(burst, current + refill_amount)
    
    if new_tokens >= cost then
        local remaining = new_tokens - cost
        redis.call('HSET', key, 'current_tokens', remaining)
        redis.call('HSET', key, 'last_refill', now)
        redis.call('HINCRBY', key, 'total_consumed', cost)
        redis.call('HINCRBY', key, 'total_requests', 1)
        return {1, remaining, burst - remaining}
    else
        redis.call('HSET', key, 'current_tokens', new_tokens)
        redis.call('HSET', key, 'last_refill', now)
        return {0, new_tokens, 0}
    end
]])

_M.register_script("BORROW", [[
    local app_key = KEYS[1]
    local cluster_key = KEYS[2]
    local amount = tonumber(ARGV[1])
    local now = tonumber(ARGV[2])
    
    local max_borrow = tonumber(redis.call('HGET', app_key, 'max_borrow')) or 10000
    local current_borrowed = tonumber(redis.call('HGET', app_key, 'borrowed')) or 0
    
    if current_borrowed + amount > max_borrow then
        return {0, 'borrow_limit_exceeded', max_borrow - current_borrowed}
    end
    
    local cluster_available = tonumber(redis.call('GET', cluster_key .. ':available')) or 0
    local reserved_ratio = tonumber(redis.call('GET', cluster_key .. ':reserved_ratio')) or 0.1
    local cluster_capacity = tonumber(redis.call('GET', cluster_key .. ':capacity')) or 1000000
    
    local borrowable = cluster_available - cluster_capacity * reserved_ratio
    if borrowable < amount then
        return {0, 'cluster_insufficient', borrowable}
    end
    
    local debt_amount = math.ceil(amount * 1.2)
    redis.call('DECRBY', cluster_key .. ':available', amount)
    redis.call('HINCRBY', app_key, 'current_tokens', amount)
    redis.call('HINCRBY', app_key, 'borrowed', amount)
    redis.call('HINCRBY', app_key, 'debt', debt_amount)
    
    return {1, 'borrowed', amount, debt_amount}
]])

return _M
