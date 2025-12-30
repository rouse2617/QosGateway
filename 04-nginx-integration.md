# Nginx 集成方案

## 一、架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                      Nginx + OpenResty                       │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ access_by   │  │ content_by  │  │ log_by      │         │
│  │ _lua_block  │→ │ _lua_block  │→ │ _lua_block  │         │
│  │ (限流检查)   │  │ (业务处理)   │  │ (指标上报)   │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│         │                                   │               │
│         ▼                                   ▼               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              lua_shared_dict (100MB)                 │   │
│  │  • token_cache: 令牌缓存                             │   │
│  │  • batch_accumulator: 批量累加器                     │   │
│  │  • config_cache: 配置缓存                            │   │
│  └─────────────────────────────────────────────────────┘   │
│         │                                                   │
│         ▼                                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Redis Connection Pool                   │   │
│  │              (keepalive 50 connections)              │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  Redis Cluster  │
                    └─────────────────┘
```

---

## 二、完整 nginx.conf 配置

```nginx
# nginx.conf - 流控系统完整配置

#===============================================
# 全局配置
#===============================================
worker_processes auto;
worker_rlimit_nofile 100000;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 10000;
    use epoll;
    multi_accept on;
}

http {
    #===========================================
    # 基础配置
    #===========================================
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    
    # 日志格式
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time cost=$ratelimit_cost';
    
    access_log /var/log/nginx/access.log main;

    #===========================================
    # Lua 共享内存配置
    #===========================================
    lua_shared_dict ratelimit 100m;           # 主限流缓存
    lua_shared_dict ratelimit_locks 1m;       # 锁
    lua_shared_dict ratelimit_metrics 10m;    # 指标缓存
    lua_shared_dict config_cache 10m;         # 配置缓存
    
    #===========================================
    # Lua 包路径
    #===========================================
    lua_package_path "/etc/nginx/lua/?.lua;/etc/nginx/lua/?/init.lua;;";
    lua_package_cpath "/etc/nginx/lua/?.so;;";
    
    #===========================================
    # Lua 代码缓存（生产环境开启）
    #===========================================
    lua_code_cache on;
    
    #===========================================
    # 初始化脚本
    #===========================================
    init_by_lua_block {
        -- 加载模块
        require("ratelimit.init")
        
        -- 全局配置
        RATELIMIT_CONFIG = {
            redis_host = os.getenv("REDIS_HOST") or "127.0.0.1",
            redis_port = tonumber(os.getenv("REDIS_PORT")) or 6379,
            redis_timeout = 1000,
            redis_pool_size = 50,
            
            -- L3 配置
            local_reserve = 1000,
            refill_threshold = 0.2,
            sync_interval = 0.1,
            batch_threshold = 1000,
            
            -- 降级配置
            fail_open_tokens = 100,
            fail_open_duration = 60,
        }
    }
    
    init_worker_by_lua_block {
        local ratelimit = require("ratelimit.init")
        local timer = require("ratelimit.timer")
        
        -- 初始化限流模块
        ratelimit.init()
        
        -- 只在 worker 0 启动定时任务
        if ngx.worker.id() == 0 then
            timer.start_refill_timer()
            timer.start_reconcile_timer()
            timer.start_emergency_check_timer()
        end
    }
    
    #===========================================
    # Redis 上游配置
    #===========================================
    upstream redis_cluster {
        server redis-node1:6379 max_fails=3 fail_timeout=30s;
        server redis-node2:6379 max_fails=3 fail_timeout=30s backup;
        server redis-node3:6379 max_fails=3 fail_timeout=30s backup;
        
        keepalive 50;
        keepalive_requests 100000;
        keepalive_timeout 60s;
    }
    
    #===========================================
    # 后端服务上游
    #===========================================
    upstream storage_backend {
        server storage-node1:8080 weight=5;
        server storage-node2:8080 weight=5;
        server storage-node3:8080 weight=5;
        
        keepalive 100;
    }
    
    #===========================================
    # 限流变量
    #===========================================
    map $http_x_app_id $app_id {
        default "default";
        ~^(.+)$ $1;
    }
    
    map $http_x_user_id $user_id {
        default "anonymous";
        ~^(.+)$ $1;
    }
    
    # 用于日志的限流 Cost
    map $sent_http_x_ratelimit_cost $ratelimit_cost {
        default "-";
        ~^(.+)$ $1;
    }
    
    #===========================================
    # 主服务器配置
    #===========================================
    server {
        listen 80;
        listen 443 ssl http2;
        server_name api.example.com;
        
        # SSL 配置
        ssl_certificate /etc/nginx/ssl/server.crt;
        ssl_certificate_key /etc/nginx/ssl/server.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
        
        # 客户端配置
        client_max_body_size 5g;
        client_body_buffer_size 128k;
        
        #=======================================
        # 健康检查端点（不限流）
        #=======================================
        location /health {
            access_log off;
            return 200 'OK';
        }
        
        #=======================================
        # 指标端点（不限流）
        #=======================================
        location /metrics {
            access_log off;
            content_by_lua_block {
                local metrics = require("ratelimit.metrics")
                ngx.say(metrics.export_prometheus())
            }
        }
        
        #=======================================
        # 管理端点
        #=======================================
        location /admin/ {
            # 限制访问
            allow 10.0.0.0/8;
            deny all;
            
            location /admin/ratelimit/status {
                content_by_lua_block {
                    local cjson = require("cjson")
                    local shared = ngx.shared.ratelimit
                    
                    local status = {
                        mode = shared:get("mode") or "normal",
                        emergency = shared:get("emergency_mode") or false,
                        initialized = shared:get("initialized") or false,
                    }
                    
                    ngx.header["Content-Type"] = "application/json"
                    ngx.say(cjson.encode(status))
                }
            }
            
            location /admin/ratelimit/emergency {
                content_by_lua_block {
                    local cjson = require("cjson")
                    local redis_client = require("ratelimit.redis")
                    
                    if ngx.req.get_method() == "POST" then
                        ngx.req.read_body()
                        local body = cjson.decode(ngx.req.get_body_data())
                        
                        if body.enable then
                            redis_client.activate_emergency(body.reason, body.operator)
                            ngx.say('{"status": "emergency_activated"}')
                        else
                            redis_client.deactivate_emergency(body.operator)
                            ngx.say('{"status": "emergency_deactivated"}')
                        end
                    else
                        local is_emergency = redis_client.check_emergency()
                        ngx.say(cjson.encode({emergency = is_emergency}))
                    end
                }
            }
        }
        
        #=======================================
        # 存储 API（需要限流）
        #=======================================
        location /api/v1/ {
            # 限流检查
            access_by_lua_block {
                local ratelimit = require("ratelimit.init")
                ratelimit.check(ngx.var.app_id, ngx.var.user_id)
            }
            
            # 代理到后端
            proxy_pass http://storage_backend;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            
            # 超时配置
            proxy_connect_timeout 5s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
            
            # 缓冲配置
            proxy_buffering on;
            proxy_buffer_size 4k;
            proxy_buffers 8 32k;
            
            # 日志阶段处理
            log_by_lua_block {
                local ratelimit = require("ratelimit.init")
                ratelimit.log()
            }
        }
        
        #=======================================
        # 对象存储 API
        #=======================================
        location ~ ^/v1/(?<bucket>[^/]+)/(?<object>.*)$ {
            set $app_id $http_x_app_id;
            set $user_id $http_x_user_id;
            
            # 限流检查
            access_by_lua_block {
                local ratelimit = require("ratelimit.init")
                ratelimit.check(ngx.var.app_id, ngx.var.user_id)
            }
            
            # 根据方法路由
            if ($request_method = GET) {
                proxy_pass http://storage_backend/get/$bucket/$object;
            }
            if ($request_method = PUT) {
                proxy_pass http://storage_backend/put/$bucket/$object;
            }
            if ($request_method = DELETE) {
                proxy_pass http://storage_backend/delete/$bucket/$object;
            }
            
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            
            log_by_lua_block {
                local ratelimit = require("ratelimit.init")
                ratelimit.log()
            }
        }
        
        #=======================================
        # 错误页面
        #=======================================
        error_page 429 @ratelimit_exceeded;
        location @ratelimit_exceeded {
            default_type application/json;
            return 429 '{"error": "rate_limit_exceeded", "message": "Too many requests"}';
        }
        
        error_page 500 502 503 504 @backend_error;
        location @backend_error {
            default_type application/json;
            return 503 '{"error": "service_unavailable", "message": "Backend service error"}';
        }
    }
}
```


---

## 三、Lua 模块目录结构

```
/etc/nginx/lua/
├── ratelimit/
│   ├── init.lua           # 主入口模块
│   ├── cost.lua           # Cost 计算模块
│   ├── l3_bucket.lua      # L3 本地令牌桶
│   ├── redis.lua          # Redis 客户端
│   ├── metrics.lua        # 指标收集
│   ├── timer.lua          # 定时任务
│   └── utils.lua          # 工具函数
└── lib/
    ├── resty/
    │   ├── redis.lua      # lua-resty-redis
    │   └── lock.lua       # lua-resty-lock
    └── cjson.so           # cjson 库
```

---

## 四、环境变量配置

```bash
# /etc/nginx/env.conf

# Redis 配置
REDIS_HOST=redis-cluster.internal
REDIS_PORT=6379
REDIS_PASSWORD=your_password

# 限流配置
RATELIMIT_LOCAL_RESERVE=1000
RATELIMIT_SYNC_INTERVAL=100
RATELIMIT_BATCH_THRESHOLD=1000

# 降级配置
RATELIMIT_FAIL_OPEN_TOKENS=100
RATELIMIT_FAIL_OPEN_DURATION=60

# 监控配置
METRICS_ENABLED=true
METRICS_PORT=9145
```

---

## 五、Docker 部署配置

### 5.1 Dockerfile

```dockerfile
# Dockerfile
FROM openresty/openresty:1.21.4.1-alpine

# 安装依赖
RUN apk add --no-cache \
    curl \
    ca-certificates

# 复制配置
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY lua/ /etc/nginx/lua/
COPY ssl/ /etc/nginx/ssl/

# 创建日志目录
RUN mkdir -p /var/log/nginx

# 健康检查
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

EXPOSE 80 443 9145

CMD ["openresty", "-g", "daemon off;"]
```

### 5.2 docker-compose.yml

```yaml
version: '3.8'

services:
  nginx-gateway:
    build: .
    ports:
      - "80:80"
      - "443:443"
      - "9145:9145"
    environment:
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - RATELIMIT_LOCAL_RESERVE=1000
    volumes:
      - ./logs:/var/log/nginx
      - ./lua:/etc/nginx/lua:ro
    depends_on:
      - redis
    deploy:
      replicas: 3
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G
    networks:
      - ratelimit-net

  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes --maxmemory 1gb --maxmemory-policy allkeys-lru
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    networks:
      - ratelimit-net

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    networks:
      - ratelimit-net

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/dashboards:/etc/grafana/provisioning/dashboards
    networks:
      - ratelimit-net

volumes:
  redis-data:
  prometheus-data:
  grafana-data:

networks:
  ratelimit-net:
    driver: bridge
```

---

## 六、Kubernetes 部署配置

### 6.1 Deployment

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-ratelimit-gateway
  labels:
    app: nginx-gateway
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-gateway
  template:
    metadata:
      labels:
        app: nginx-gateway
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9145"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: nginx
        image: nginx-ratelimit:latest
        ports:
        - containerPort: 80
          name: http
        - containerPort: 443
          name: https
        - containerPort: 9145
          name: metrics
        env:
        - name: REDIS_HOST
          valueFrom:
            configMapKeyRef:
              name: ratelimit-config
              key: redis_host
        - name: REDIS_PORT
          valueFrom:
            configMapKeyRef:
              name: ratelimit-config
              key: redis_port
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "2000m"
            memory: "2Gi"
        livenessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        volumeMounts:
        - name: lua-scripts
          mountPath: /etc/nginx/lua
          readOnly: true
        - name: nginx-config
          mountPath: /usr/local/openresty/nginx/conf/nginx.conf
          subPath: nginx.conf
          readOnly: true
      volumes:
      - name: lua-scripts
        configMap:
          name: lua-scripts
      - name: nginx-config
        configMap:
          name: nginx-config
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-gateway
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
    name: http
  - port: 443
    targetPort: 443
    name: https
  selector:
    app: nginx-gateway
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: nginx-gateway-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx-ratelimit-gateway
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### 6.2 ConfigMap

```yaml
# k8s/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ratelimit-config
data:
  redis_host: "redis-cluster.redis.svc.cluster.local"
  redis_port: "6379"
  local_reserve: "1000"
  sync_interval: "100"
  batch_threshold: "1000"
```
