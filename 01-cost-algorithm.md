# Cost 归一化算法详解

## 一、算法概述

### 1.1 核心公式

```
Cost = C_base + (Size_body / Unit_quantum) × C_bw
```

| 参数 | 含义 | 默认值 |
|------|------|--------|
| C_base | 基础 IOPS 开销 | 按操作类型 |
| Size_body | 请求/响应体大小 (bytes) | 实际值 |
| Unit_quantum | 带宽量子单位 | 65536 (64KB) |
| C_bw | 带宽开销系数 | 1 |

### 1.2 设计目标

- **公平性**：大请求消耗更多配额
- **可预测性**：Cost 计算确定性
- **灵活性**：参数可调优

---

## 二、C_base 基础开销设计

### 2.1 操作类型映射表

```lua
local BASE_COST = {
    -- 读操作
    GET     = 1,    -- 单次读取
    HEAD    = 1,    -- 元数据读取
    
    -- 写操作
    PUT     = 5,    -- 写入 + 元数据 + 复制
    POST    = 5,    -- 同 PUT
    PATCH   = 3,    -- 部分更新
    
    -- 删除操作
    DELETE  = 2,    -- 标记删除 + 元数据
    
    -- 列举操作
    LIST    = 3,    -- 索引遍历，CPU 密集
    
    -- 复杂操作
    COPY    = 6,    -- 读 + 写
    MULTIPART_INIT     = 2,   -- 初始化分片
    MULTIPART_UPLOAD   = 4,   -- 上传分片
    MULTIPART_COMPLETE = 8,   -- 合并分片
    MULTIPART_ABORT    = 3,   -- 取消分片
}
```

### 2.2 设计原理

```
操作复杂度分析：

GET (C_base=1):
  └─ 单次磁盘/缓存读取
  └─ 最轻量操作，作为基准

PUT (C_base=5):
  └─ 写入数据块
  └─ 更新元数据索引
  └─ 触发副本同步 (2-3副本)
  └─ 可能触发 GC/Compaction

LIST (C_base=3):
  └─ 遍历 B+树索引
  └─ CPU 密集型
  └─ 可能跨多个分片

MULTIPART_COMPLETE (C_base=8):
  └─ 验证所有分片
  └─ 合并元数据
  └─ 触发后台合并任务
  └─ 清理临时数据
```

---

## 三、带宽开销计算

### 3.1 量子化设计

```
为什么用 64KB 作为量子单位？

1. 对齐存储系统：
   - 大多数存储系统块大小: 4KB - 64KB
   - 64KB 是常见的 IO 单位

2. 计算效率：
   - 65536 = 2^16，位运算高效
   - size >> 16 等价于 size / 65536

3. 精度平衡：
   - 太小：Cost 值过大，溢出风险
   - 太大：小文件区分度不够
```

### 3.2 计算示例

```
文件大小        带宽 Cost (C_bw=1)    总 Cost (GET)
─────────────────────────────────────────────────
1 KB            ceil(1024/65536) = 1       2
64 KB           ceil(65536/65536) = 1      2
100 KB          ceil(102400/65536) = 2     3
1 MB            ceil(1048576/65536) = 16   17
10 MB           ceil(10485760/65536) = 160 161
100 MB          1600                       1601
1 GB            16384                      16385
```

### 3.3 C_bw 系数调优

```lua
-- 不同场景的 C_bw 配置
local BW_PROFILES = {
    -- 标准配置
    standard = {
        c_bw = 1,
        description = "平衡 IOPS 和带宽"
    },
    
    -- IOPS 敏感型（如数据库）
    iops_sensitive = {
        c_bw = 0.5,
        description = "降低带宽权重，保护 IOPS"
    },
    
    -- 带宽敏感型（如视频流）
    bandwidth_sensitive = {
        c_bw = 2,
        description = "提高带宽权重，保护带宽"
    },
    
    -- 混合负载
    mixed = {
        c_bw = 1.5,
        description = "适度偏向带宽保护"
    }
}
```

---

## 四、完整 Lua 实现

### 4.1 核心计算模块

```lua
-- cost_calculator.lua
local _M = {}

-- 配置常量
local CONFIG = {
    UNIT_QUANTUM = 65536,  -- 64KB
    DEFAULT_C_BW = 1,
    MAX_COST = 1000000,    -- 防止溢出
}

-- 基础开销映射
local BASE_COST = {
    GET = 1, HEAD = 1,
    PUT = 5, POST = 5, PATCH = 3,
    DELETE = 2,
    LIST = 3,
    COPY = 6,
    MULTIPART_INIT = 2,
    MULTIPART_UPLOAD = 4,
    MULTIPART_COMPLETE = 8,
    MULTIPART_ABORT = 3,
}

-- 计算 Cost
function _M.calculate(method, body_size, c_bw)
    -- 参数校验
    method = string.upper(method or "GET")
    body_size = tonumber(body_size) or 0
    c_bw = tonumber(c_bw) or CONFIG.DEFAULT_C_BW
    
    -- 获取基础开销
    local c_base = BASE_COST[method] or 1
    
    -- 计算带宽开销
    local bw_units = 0
    if body_size > 0 then
        bw_units = math.ceil(body_size / CONFIG.UNIT_QUANTUM)
    end
    local c_bandwidth = bw_units * c_bw
    
    -- 计算总 Cost
    local total_cost = c_base + c_bandwidth
    
    -- 防止溢出
    if total_cost > CONFIG.MAX_COST then
        total_cost = CONFIG.MAX_COST
    end
    
    return total_cost, {
        c_base = c_base,
        c_bandwidth = c_bandwidth,
        bw_units = bw_units,
        method = method,
        body_size = body_size
    }
end

-- 批量计算
function _M.calculate_batch(requests)
    local results = {}
    local total = 0
    
    for i, req in ipairs(requests) do
        local cost = _M.calculate(req.method, req.body_size, req.c_bw)
        results[i] = cost
        total = total + cost
    end
    
    return total, results
end

-- 预估 Cost（用于预检）
function _M.estimate(method, content_length)
    return _M.calculate(method, content_length)
end

return _M
```

### 4.2 Nginx 集成

```lua
-- nginx_cost_handler.lua
local cost_calc = require("cost_calculator")

local function get_request_cost()
    local method = ngx.req.get_method()
    local content_length = tonumber(ngx.var.content_length) or 0
    
    -- 对于响应，使用 upstream 返回的 Content-Length
    local response_length = tonumber(ngx.var.upstream_content_length) or 0
    
    -- 取请求和响应的较大值
    local body_size = math.max(content_length, response_length)
    
    return cost_calc.calculate(method, body_size)
end

-- 在 access 阶段预检
local function access_phase_handler()
    local method = ngx.req.get_method()
    local content_length = tonumber(ngx.var.content_length) or 0
    
    local estimated_cost = cost_calc.estimate(method, content_length)
    
    -- 存储到请求上下文
    ngx.ctx.estimated_cost = estimated_cost
    
    return estimated_cost
end

-- 在 log 阶段记录实际 Cost
local function log_phase_handler()
    local actual_cost = get_request_cost()
    local estimated_cost = ngx.ctx.estimated_cost or 0
    
    -- 记录差异（用于调优）
    if math.abs(actual_cost - estimated_cost) > estimated_cost * 0.1 then
        ngx.log(ngx.WARN, "Cost estimation deviation: ",
            "estimated=", estimated_cost,
            " actual=", actual_cost)
    end
    
    return actual_cost
end

return {
    get_request_cost = get_request_cost,
    access_phase_handler = access_phase_handler,
    log_phase_handler = log_phase_handler,
}
```

---

## 五、边界情况处理

### 5.1 特殊场景

```lua
local function handle_special_cases(method, body_size, headers)
    -- 1. 分片上传：每个分片独立计算
    if headers["x-amz-copy-source"] then
        -- COPY 操作，源文件大小可能未知
        return calculate_copy_cost(headers)
    end
    
    -- 2. 压缩传输：使用原始大小
    if headers["content-encoding"] == "gzip" then
        local original_size = headers["x-uncompressed-size"]
        if original_size then
            body_size = tonumber(original_size)
        end
    end
    
    -- 3. 流式传输：使用 chunked 估算
    if headers["transfer-encoding"] == "chunked" then
        -- 无法预知大小，使用保守估计
        body_size = CONFIG.DEFAULT_CHUNKED_SIZE
    end
    
    -- 4. Range 请求：使用实际传输大小
    local range = headers["range"]
    if range then
        body_size = parse_range_size(range)
    end
    
    return cost_calc.calculate(method, body_size)
end
```

### 5.2 错误处理

```lua
local function safe_calculate(method, body_size)
    local ok, cost, details = pcall(function()
        return cost_calc.calculate(method, body_size)
    end)
    
    if not ok then
        ngx.log(ngx.ERR, "Cost calculation failed: ", cost)
        -- 返回保守默认值
        return CONFIG.DEFAULT_COST, {error = cost}
    end
    
    return cost, details
end
```

---

## 六、性能优化

### 6.1 计算缓存

```lua
local lrucache = require("resty.lrucache")
local cache = lrucache.new(1000)  -- 缓存 1000 个结果

local function cached_calculate(method, body_size)
    -- 对 body_size 进行分桶，减少缓存 key 数量
    local size_bucket = math.floor(body_size / CONFIG.UNIT_QUANTUM)
    local cache_key = method .. ":" .. size_bucket
    
    local cached = cache:get(cache_key)
    if cached then
        return cached
    end
    
    local cost = cost_calc.calculate(method, size_bucket * CONFIG.UNIT_QUANTUM)
    cache:set(cache_key, cost, 60)  -- 缓存 60 秒
    
    return cost
end
```

### 6.2 位运算优化

```lua
-- 使用位运算替代除法（仅当 UNIT_QUANTUM 是 2 的幂时）
local QUANTUM_SHIFT = 16  -- 65536 = 2^16

local function fast_calculate(method, body_size)
    local c_base = BASE_COST[method] or 1
    
    -- 位运算：body_size >> 16 等价于 body_size / 65536
    local bw_units = 0
    if body_size > 0 then
        bw_units = bit.rshift(body_size - 1, QUANTUM_SHIFT) + 1
    end
    
    return c_base + bw_units
end
```

---

## 七、监控与调优

### 7.1 Cost 分布统计

```lua
local function record_cost_metrics(cost, method, body_size)
    -- 记录到 Prometheus
    local labels = {
        method = method,
        cost_bucket = get_cost_bucket(cost)
    }
    
    prometheus:histogram_observe("request_cost", cost, labels)
    prometheus:counter_inc("request_total", labels)
end

local function get_cost_bucket(cost)
    if cost <= 5 then return "tiny" end
    if cost <= 20 then return "small" end
    if cost <= 100 then return "medium" end
    if cost <= 1000 then return "large" end
    return "huge"
end
```

### 7.2 调优建议

```
Cost 分布分析：

如果 tiny (<=5) 占比 > 80%:
  → 系统以小文件为主，可降低 C_bw

如果 huge (>1000) 占比 > 10%:
  → 大文件较多，考虑提高 C_bw 或设置单独配额

如果 PUT 的平均 Cost >> GET:
  → 写密集型负载，考虑提高 PUT 的 C_base
```
