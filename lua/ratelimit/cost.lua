-- ratelimit/cost.lua
-- Cost Calculator: 请求成本计算器
-- 将请求转换为统一的 Cost 值，实现 IOPS 和带宽的归一化

local _M = {
    _VERSION = '1.0.0'
}

-- 配置常量
local CONFIG = {
    UNIT_QUANTUM = 65536,      -- 64KB 量子单位
    DEFAULT_C_BW = 1,          -- 默认带宽系数
    MAX_COST = 1000000,        -- 最大 Cost 上限，防止溢出
}

-- HTTP 方法到 C_base 的映射
-- 基于操作复杂度和资源消耗定义
local BASE_COST = {
    -- 读操作
    GET = 1,
    HEAD = 1,
    OPTIONS = 1,
    
    -- 写操作
    PUT = 5,
    POST = 5,
    PATCH = 3,
    
    -- 删除操作
    DELETE = 2,
    
    -- 列表操作
    LIST = 3,
    
    -- 复制操作
    COPY = 6,
    
    -- 分片上传操作
    MULTIPART_INIT = 2,
    MULTIPART_UPLOAD = 4,
    MULTIPART_COMPLETE = 8,
    MULTIPART_ABORT = 3,
}

--- 获取 HTTP 方法的基础成本
--- @param method string HTTP 方法
--- @return number c_base 基础成本
local function get_base_cost(method)
    if not method then
        return 1
    end
    return BASE_COST[string.upper(method)] or 1
end

--- 计算带宽成本
--- @param body_size number 请求体大小 (bytes)
--- @param c_bw number 带宽系数
--- @return number bw_cost 带宽成本
--- @return number bw_units 带宽单位数
local function calculate_bandwidth_cost(body_size, c_bw)
    if not body_size or body_size <= 0 then
        return 0, 0
    end
    
    local bw_units = math.ceil(body_size / CONFIG.UNIT_QUANTUM)
    local bw_cost = bw_units * c_bw
    
    return bw_cost, bw_units
end

--- 计算请求的 Cost 值
--- 公式: Cost = C_base + ceil(body_size / Unit_quantum) × C_bw
--- @param method string HTTP 方法
--- @param body_size number 请求体大小 (bytes)
--- @param c_bw number 带宽系数 (可选，默认 1)
--- @return number cost 计算得到的 Cost 值
--- @return table details 计算详情
function _M.calculate(method, body_size, c_bw)
    -- 参数标准化
    method = string.upper(method or "GET")
    body_size = tonumber(body_size) or 0
    c_bw = tonumber(c_bw) or CONFIG.DEFAULT_C_BW
    
    -- 确保参数有效
    if body_size < 0 then
        body_size = 0
    end
    if c_bw < 0 then
        c_bw = CONFIG.DEFAULT_C_BW
    end
    
    -- 计算基础成本
    local c_base = get_base_cost(method)
    
    -- 计算带宽成本
    local c_bandwidth, bw_units = calculate_bandwidth_cost(body_size, c_bw)
    
    -- 计算总成本并应用上限
    local total_cost = c_base + c_bandwidth
    total_cost = math.min(total_cost, CONFIG.MAX_COST)
    
    -- 返回结果和详情
    return total_cost, {
        c_base = c_base,
        c_bandwidth = c_bandwidth,
        bw_units = bw_units,
        method = method,
        body_size = body_size,
        c_bw = c_bw,
        capped = (c_base + c_bandwidth) > CONFIG.MAX_COST
    }
end

--- 从 ngx 请求上下文计算 Cost
--- @param c_bw number 带宽系数 (可选)
--- @return number cost 计算得到的 Cost 值
--- @return table details 计算详情
function _M.calculate_from_request(c_bw)
    local method = ngx.req.get_method()
    local body_size = tonumber(ngx.var.content_length) or 0
    
    return _M.calculate(method, body_size, c_bw)
end

--- 获取方法的基础成本 (供外部查询)
--- @param method string HTTP 方法
--- @return number c_base 基础成本
function _M.get_method_cost(method)
    return get_base_cost(method)
end

--- 获取配置常量 (供测试使用)
--- @return table config 配置常量
function _M.get_config()
    return {
        UNIT_QUANTUM = CONFIG.UNIT_QUANTUM,
        DEFAULT_C_BW = CONFIG.DEFAULT_C_BW,
        MAX_COST = CONFIG.MAX_COST,
    }
end

--- 获取所有方法的基础成本映射 (供测试使用)
--- @return table base_costs 基础成本映射
function _M.get_base_costs()
    local copy = {}
    for k, v in pairs(BASE_COST) do
        copy[k] = v
    end
    return copy
end

return _M
