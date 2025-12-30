#!/usr/bin/env lua
-- run_integration_check.lua
-- 运行集成验证脚本

-- 设置 Lua 路径
package.path = package.path .. ";../lua/?.lua;../lua/?/init.lua"

-- 模拟 ngx 全局对象（用于非 OpenResty 环境测试）
if not ngx then
    ngx = {
        shared = {
            ratelimit_dict = {
                get = function() return nil end,
                set = function() return true end,
                incr = function() return 0 end,
                safe_add = function() return true end,
                get_keys = function() return {} end,
                delete = function() return true end,
            },
            connlimit_dict = {
                get = function() return nil end,
                set = function() return true end,
                incr = function() return 0 end,
                safe_add = function() return true end,
                get_keys = function() return {} end,
            },
            config_dict = {
                get = function() return nil end,
                set = function() return true end,
            },
        },
        now = function() return os.time() end,
        log = function() end,
        timer = {
            at = function() return true end,
        },
        worker = {
            id = function() return 0 end,
        },
        var = {
            uri = "/",
            remote_addr = "127.0.0.1",
            server_addr = "127.0.0.1",
            connection = "1",
            content_length = "0",
        },
        req = {
            get_method = function() return "GET" end,
            get_headers = function() return {} end,
            read_body = function() end,
            get_body_data = function() return "{}" end,
        },
        header = {},
        ctx = {},
        status = 200,
        say = function(s) print(s) end,
        exit = function() end,
        md5 = function(s) return string.rep("0", 32) end,
        INFO = 6,
        NOTICE = 5,
        WARN = 4,
        ERR = 3,
        sleep = function() end,
    }
end

-- 模拟 cjson
if not pcall(require, "cjson.safe") then
    package.loaded["cjson.safe"] = {
        encode = function(t)
            if type(t) ~= "table" then return tostring(t) end
            local parts = {}
            for k, v in pairs(t) do
                table.insert(parts, string.format('"%s":%s', k, 
                    type(v) == "string" and ('"' .. v .. '"') or tostring(v)))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end,
        decode = function(s)
            return {}
        end,
    }
    package.loaded["cjson"] = package.loaded["cjson.safe"]
end

-- 模拟 resty.redis
if not pcall(require, "resty.redis") then
    local redis_mock = {}
    redis_mock.__index = redis_mock
    function redis_mock:new()
        return setmetatable({}, redis_mock)
    end
    function redis_mock:set_timeout() end
    function redis_mock:connect() return nil, "mock" end
    function redis_mock:auth() return true end
    function redis_mock:select() return true end
    function redis_mock:ping() return nil, "mock" end
    function redis_mock:set_keepalive() return true end
    function redis_mock:close() end
    function redis_mock:get() return nil end
    function redis_mock:set() return true end
    function redis_mock:hget() return nil end
    function redis_mock:hgetall() return {} end
    function redis_mock:hmset() return true end
    function redis_mock:hsetnx() return true end
    function redis_mock:hincrby() return 0 end
    function redis_mock:hincrbyfloat() return 0 end
    function redis_mock:incr() return 0 end
    function redis_mock:incrby() return 0 end
    function redis_mock:decrby() return 0 end
    function redis_mock:del() return 1 end
    function redis_mock:keys() return {} end
    function redis_mock:lpush() return 1 end
    function redis_mock:ltrim() return true end
    function redis_mock:lrange() return {} end
    function redis_mock:expire() return true end
    function redis_mock:setnx() return true end
    function redis_mock:publish() return 1 end
    function redis_mock:script() return "mock_sha" end
    function redis_mock:evalsha() return {1, 1000, 0} end
    function redis_mock:init_pipeline() end
    function redis_mock:commit_pipeline() return {} end
    
    package.loaded["resty.redis"] = redis_mock
end

-- 运行集成检查
local integration_check = require "integration_check"
integration_check.run_all_checks()
local success = integration_check.print_report()

-- 返回退出码
os.exit(success and 0 or 1)
