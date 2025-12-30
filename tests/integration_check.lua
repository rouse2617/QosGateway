-- integration_check.lua
-- 完整系统集成验证脚本
-- 验证所有模块正确集成、监控指标和配置 API

local _M = {
    _VERSION = '1.0.0'
}

local cjson = require "cjson.safe"

-- 测试结果收集
local results = {
    passed = 0,
    failed = 0,
    tests = {}
}

--- 记录测试结果
local function record_test(name, passed, message)
    table.insert(results.tests, {
        name = name,
        passed = passed,
        message = message or ""
    })
    if passed then
        results.passed = results.passed + 1
    else
        results.failed = results.failed + 1
    end
end

--- 验证模块可加载
local function check_module_loadable(module_name)
    local ok, mod = pcall(require, module_name)
    if ok and mod then
        record_test("Module Load: " .. module_name, true, "Loaded successfully")
        return mod
    else
        record_test("Module Load: " .. module_name, false, tostring(mod))
        return nil
    end
end

--- 验证模块版本
local function check_module_version(mod, module_name)
    if mod and mod._VERSION then
        record_test("Module Version: " .. module_name, true, "Version: " .. mod._VERSION)
        return true
    else
        record_test("Module Version: " .. module_name, false, "No version defined")
        return false
    end
end

--- 验证函数存在
local function check_function_exists(mod, func_name, module_name)
    if mod and type(mod[func_name]) == "function" then
        record_test("Function: " .. module_name .. "." .. func_name, true, "Exists")
        return true
    else
        record_test("Function: " .. module_name .. "." .. func_name, false, "Missing")
        return false
    end
end

--- 1. 验证所有核心模块可加载
function _M.check_all_modules()
    local modules = {
        "ratelimit.cost",
        "ratelimit.l3_bucket",
        "ratelimit.l2_bucket",
        "ratelimit.l1_cluster",
        "ratelimit.borrow",
        "ratelimit.emergency",
        "ratelimit.reconciler",
        "ratelimit.connection_limiter",
        "ratelimit.reservation",
        "ratelimit.config_validator",
        "ratelimit.degradation",
        "ratelimit.metrics",
        "ratelimit.config_api",
        "ratelimit.redis",
        "ratelimit.init",
    }
    
    local loaded_modules = {}
    for _, module_name in ipairs(modules) do
        local mod = check_module_loadable(module_name)
        if mod then
            loaded_modules[module_name] = mod
            check_module_version(mod, module_name)
        end
    end
    
    return loaded_modules
end

--- 2. 验证 Cost Calculator 接口
function _M.check_cost_calculator()
    local cost = require "ratelimit.cost"
    
    check_function_exists(cost, "calculate", "cost")
    
    -- 测试计算功能
    local result, details = cost.calculate("GET", 0)
    if result == 1 then
        record_test("Cost: GET base cost", true, "Cost = 1")
    else
        record_test("Cost: GET base cost", false, "Expected 1, got " .. tostring(result))
    end
    
    result, details = cost.calculate("PUT", 65536)
    if result == 6 then  -- 5 (base) + 1 (bandwidth)
        record_test("Cost: PUT with body", true, "Cost = 6")
    else
        record_test("Cost: PUT with body", false, "Expected 6, got " .. tostring(result))
    end
end

--- 3. 验证 L3 Bucket 接口
function _M.check_l3_bucket()
    local l3 = require "ratelimit.l3_bucket"
    
    check_function_exists(l3, "acquire", "l3_bucket")
    check_function_exists(l3, "rollback", "l3_bucket")
    check_function_exists(l3, "init_bucket", "l3_bucket")
    check_function_exists(l3, "get_status", "l3_bucket")
    check_function_exists(l3, "set_mode", "l3_bucket")
    check_function_exists(l3, "handle_fail_open", "l3_bucket")
    check_function_exists(l3, "async_refill", "l3_bucket")
    check_function_exists(l3, "batch_sync", "l3_bucket")
end

--- 4. 验证 L2 Bucket 接口
function _M.check_l2_bucket()
    local l2 = require "ratelimit.l2_bucket"
    
    check_function_exists(l2, "acquire", "l2_bucket")
    check_function_exists(l2, "acquire_batch", "l2_bucket")
    check_function_exists(l2, "report_consumption", "l2_bucket")
    check_function_exists(l2, "get_config", "l2_bucket")
    check_function_exists(l2, "set_config", "l2_bucket")
    check_function_exists(l2, "init_bucket", "l2_bucket")
    check_function_exists(l2, "list_apps", "l2_bucket")
end

--- 5. 验证 L1 Cluster 接口
function _M.check_l1_cluster()
    local l1 = require "ratelimit.l1_cluster"
    
    check_function_exists(l1, "init_cluster", "l1_cluster")
    check_function_exists(l1, "get_status", "l1_cluster")
    check_function_exists(l1, "activate_emergency", "l1_cluster")
    check_function_exists(l1, "deactivate_emergency", "l1_cluster")
    check_function_exists(l1, "allocate_quota", "l1_cluster")
    check_function_exists(l1, "return_quota", "l1_cluster")
    check_function_exists(l1, "reconcile", "l1_cluster")
end

--- 6. 验证 Borrow Manager 接口
function _M.check_borrow_manager()
    local borrow = require "ratelimit.borrow"
    
    check_function_exists(borrow, "borrow", "borrow")
    check_function_exists(borrow, "repay", "borrow")
    check_function_exists(borrow, "get_status", "borrow")
    check_function_exists(borrow, "get_history", "borrow")
    check_function_exists(borrow, "record_history", "borrow")
end

--- 7. 验证 Emergency Manager 接口
function _M.check_emergency_manager()
    local emergency = require "ratelimit.emergency"
    
    check_function_exists(emergency, "activate", "emergency")
    check_function_exists(emergency, "deactivate", "emergency")
    check_function_exists(emergency, "get_status", "emergency")
    check_function_exists(emergency, "check_emergency_request", "emergency")
    check_function_exists(emergency, "get_app_priority", "emergency")
    check_function_exists(emergency, "get_quota_ratio", "emergency")
end

--- 8. 验证 Reconciler 接口
function _M.check_reconciler()
    local reconciler = require "ratelimit.reconciler"
    
    check_function_exists(reconciler, "reconcile_app", "reconciler")
    check_function_exists(reconciler, "reconcile_all", "reconciler")
    check_function_exists(reconciler, "start_timer", "reconciler")
    check_function_exists(reconciler, "get_stats", "reconciler")
    check_function_exists(reconciler, "record_correction", "reconciler")
end

--- 9. 验证 Connection Limiter 接口
function _M.check_connection_limiter()
    local conn = require "ratelimit.connection_limiter"
    
    check_function_exists(conn, "init", "connection_limiter")
    check_function_exists(conn, "acquire", "connection_limiter")
    check_function_exists(conn, "release", "connection_limiter")
    check_function_exists(conn, "heartbeat", "connection_limiter")
    check_function_exists(conn, "cleanup_leaked_connections", "connection_limiter")
    check_function_exists(conn, "get_stats", "connection_limiter")
    check_function_exists(conn, "set_app_limit", "connection_limiter")
    check_function_exists(conn, "set_cluster_limit", "connection_limiter")
    check_function_exists(conn, "start_cleanup_timer", "connection_limiter")
end

--- 10. 验证 Reservation Manager 接口
function _M.check_reservation_manager()
    local reservation = require "ratelimit.reservation"
    
    check_function_exists(reservation, "create", "reservation")
    check_function_exists(reservation, "complete", "reservation")
    check_function_exists(reservation, "cancel", "reservation")
    check_function_exists(reservation, "get_status", "reservation")
    check_function_exists(reservation, "cleanup_expired", "reservation")
    check_function_exists(reservation, "start_cleanup_timer", "reservation")
end

--- 11. 验证 Config Validator 接口
function _M.check_config_validator()
    local validator = require "ratelimit.config_validator"
    
    check_function_exists(validator, "validate_app_config", "config_validator")
    check_function_exists(validator, "validate_cluster_capacity", "config_validator")
    check_function_exists(validator, "validate_cluster_config", "config_validator")
    check_function_exists(validator, "dry_run", "config_validator")
    check_function_exists(validator, "validate_batch", "config_validator")
    
    -- 测试验证功能
    local valid, errors = validator.validate_app_config({
        app_id = "test-app",
        guaranteed_quota = 1000,
        burst_quota = 5000,
        priority = 2
    })
    if valid then
        record_test("Config Validator: valid config", true, "Validation passed")
    else
        record_test("Config Validator: valid config", false, table.concat(errors, "; "))
    end
    
    -- 测试无效配置
    valid, errors = validator.validate_app_config({
        app_id = "",
        guaranteed_quota = -1
    })
    if not valid and #errors > 0 then
        record_test("Config Validator: invalid config", true, "Correctly rejected")
    else
        record_test("Config Validator: invalid config", false, "Should have rejected")
    end
end

--- 12. 验证 Degradation Manager 接口
function _M.check_degradation_manager()
    local degradation = require "ratelimit.degradation"
    
    check_function_exists(degradation, "get_level", "degradation")
    check_function_exists(degradation, "evaluate", "degradation")
    check_function_exists(degradation, "check_redis_health", "degradation")
    check_function_exists(degradation, "get_strategy_params", "degradation")
    check_function_exists(degradation, "is_fail_open", "degradation")
    check_function_exists(degradation, "get_status", "degradation")
    check_function_exists(degradation, "start_health_timer", "degradation")
    
    -- 验证降级级别常量
    if degradation.LEVELS then
        record_test("Degradation: LEVELS defined", true, "Has LEVELS constant")
    else
        record_test("Degradation: LEVELS defined", false, "Missing LEVELS")
    end
end

--- 13. 验证 Metrics Collector 接口
function _M.check_metrics_collector()
    local metrics = require "ratelimit.metrics"
    
    check_function_exists(metrics, "prometheus", "metrics")
    check_function_exists(metrics, "serve_prometheus", "metrics")
    check_function_exists(metrics, "get_summary", "metrics")
    check_function_exists(metrics, "incr_request", "metrics")
    check_function_exists(metrics, "record_l3_hit", "metrics")
    check_function_exists(metrics, "report_to_redis", "metrics")
    check_function_exists(metrics, "start_report_timer", "metrics")
    check_function_exists(metrics, "add_counter_metrics", "metrics")
    check_function_exists(metrics, "add_token_metrics", "metrics")
    check_function_exists(metrics, "add_connection_metrics", "metrics")
end

--- 14. 验证 Config API 接口
function _M.check_config_api()
    local config_api = require "ratelimit.config_api"
    
    check_function_exists(config_api, "get_app_config", "config_api")
    check_function_exists(config_api, "set_app_config", "config_api")
    check_function_exists(config_api, "delete_app_config", "config_api")
    check_function_exists(config_api, "list_app_configs", "config_api")
    check_function_exists(config_api, "set_cluster_config", "config_api")
    check_function_exists(config_api, "set_connection_limit", "config_api")
    check_function_exists(config_api, "activate_emergency", "config_api")
    check_function_exists(config_api, "deactivate_emergency", "config_api")
    check_function_exists(config_api, "get_emergency_status", "config_api")
    check_function_exists(config_api, "get_metrics", "config_api")
    check_function_exists(config_api, "get_app_metrics", "config_api")
    check_function_exists(config_api, "handle_request", "config_api")
end

--- 15. 验证 Redis Client 接口
function _M.check_redis_client()
    local redis = require "ratelimit.redis"
    
    check_function_exists(redis, "get_connection", "redis")
    check_function_exists(redis, "release_connection", "redis")
    check_function_exists(redis, "execute", "redis")
    check_function_exists(redis, "eval_script", "redis")
    check_function_exists(redis, "register_script", "redis")
    check_function_exists(redis, "preload_scripts", "redis")
    check_function_exists(redis, "health_check", "redis")
end

--- 16. 验证 Init 模块接口
function _M.check_init_module()
    local init = require "ratelimit.init"
    
    check_function_exists(init, "init", "init")
    check_function_exists(init, "check", "init")
    check_function_exists(init, "log", "init")
    check_function_exists(init, "health", "init")
    check_function_exists(init, "reject", "init")
    check_function_exists(init, "set_response_headers", "init")
    check_function_exists(init, "create_reservation", "init")
    check_function_exists(init, "complete_reservation", "init")
    check_function_exists(init, "cancel_reservation", "init")
    check_function_exists(init, "rollback", "init")
end

--- 17. 验证模块间依赖关系
function _M.check_module_dependencies()
    -- init 模块应该能加载所有依赖
    local init = require "ratelimit.init"
    if init then
        record_test("Dependencies: init loads all", true, "All dependencies resolved")
    else
        record_test("Dependencies: init loads all", false, "Failed to load")
    end
    
    -- emergency 依赖 l1_cluster
    local emergency = require "ratelimit.emergency"
    local l1 = require "ratelimit.l1_cluster"
    if emergency and l1 then
        record_test("Dependencies: emergency -> l1_cluster", true, "Dependency OK")
    else
        record_test("Dependencies: emergency -> l1_cluster", false, "Missing dependency")
    end
    
    -- reconciler 依赖 l2_bucket 和 l1_cluster
    local reconciler = require "ratelimit.reconciler"
    local l2 = require "ratelimit.l2_bucket"
    if reconciler and l2 and l1 then
        record_test("Dependencies: reconciler -> l2/l1", true, "Dependencies OK")
    else
        record_test("Dependencies: reconciler -> l2/l1", false, "Missing dependencies")
    end
end

--- 运行所有检查
function _M.run_all_checks()
    print("\n========================================")
    print("分布式三层令牌桶限流系统 - 集成验证")
    print("========================================\n")
    
    -- 1. 检查所有模块可加载
    print("1. 检查模块加载...")
    _M.check_all_modules()
    
    -- 2. 检查各模块接口
    print("\n2. 检查 Cost Calculator...")
    _M.check_cost_calculator()
    
    print("\n3. 检查 L3 Bucket...")
    _M.check_l3_bucket()
    
    print("\n4. 检查 L2 Bucket...")
    _M.check_l2_bucket()
    
    print("\n5. 检查 L1 Cluster...")
    _M.check_l1_cluster()
    
    print("\n6. 检查 Borrow Manager...")
    _M.check_borrow_manager()
    
    print("\n7. 检查 Emergency Manager...")
    _M.check_emergency_manager()
    
    print("\n8. 检查 Reconciler...")
    _M.check_reconciler()
    
    print("\n9. 检查 Connection Limiter...")
    _M.check_connection_limiter()
    
    print("\n10. 检查 Reservation Manager...")
    _M.check_reservation_manager()
    
    print("\n11. 检查 Config Validator...")
    _M.check_config_validator()
    
    print("\n12. 检查 Degradation Manager...")
    _M.check_degradation_manager()
    
    print("\n13. 检查 Metrics Collector...")
    _M.check_metrics_collector()
    
    print("\n14. 检查 Config API...")
    _M.check_config_api()
    
    print("\n15. 检查 Redis Client...")
    _M.check_redis_client()
    
    print("\n16. 检查 Init Module...")
    _M.check_init_module()
    
    print("\n17. 检查模块依赖关系...")
    _M.check_module_dependencies()
    
    return results
end

--- 打印测试报告
function _M.print_report()
    print("\n========================================")
    print("测试报告")
    print("========================================")
    print(string.format("通过: %d", results.passed))
    print(string.format("失败: %d", results.failed))
    print(string.format("总计: %d", results.passed + results.failed))
    print("----------------------------------------")
    
    -- 打印失败的测试
    if results.failed > 0 then
        print("\n失败的测试:")
        for _, test in ipairs(results.tests) do
            if not test.passed then
                print(string.format("  ✗ %s: %s", test.name, test.message))
            end
        end
    end
    
    print("\n========================================")
    if results.failed == 0 then
        print("✓ 所有集成检查通过!")
    else
        print("✗ 存在失败的检查，请修复后重试")
    end
    print("========================================\n")
    
    return results.failed == 0
end

--- 获取结果
function _M.get_results()
    return results
end

return _M
