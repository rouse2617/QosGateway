# Admin Backend

A production-ready Go backend service for managing distributed rate limiting configurations with Redis storage.

## Features

- **RESTful API**: Complete CRUD operations for applications and clusters
- **JWT Authentication**: Secure token-based authentication with refresh tokens
- **Rate Limiting**: Built-in rate limiting middleware with configurable windows
- **WebSocket Support**: Real-time metrics and event streaming
- **Structured Logging**: JSON logging with Zap for production environments
- **Graceful Shutdown**: Proper cleanup of connections and resources
- **Request Tracing**: Unique request IDs for distributed tracing
- **Input Validation**: Comprehensive validation layer for all inputs
- **Health Checks**: Dedicated health check endpoint with dependency monitoring
- **Configuration Management**: Environment-based configuration with validation

## Project Structure

```
admin-backend/
├── config/           # Configuration loading and validation
├── errors/           # Custom error types and error handling
├── handlers/         # HTTP request handlers
├── logger/           # Structured logging wrapper
├── middleware/       # HTTP middleware (auth, CORS, rate limiting, etc.)
├── models/           # Data models and DTOs
├── storage/          # Storage interface and Redis implementation
├── validation/       # Input validation functions
└── main.go           # Application entry point
```

## Environment Variables

### Required Variables

| Variable | Description | Example | Default |
|----------|-------------|---------|---------|
| `JWT_SECRET` | JWT signing secret (min 32 chars) | `your-very-secret-jwt-key-min-32-chars` | **Required** |

### Optional Variables

#### Server Configuration

| Variable | Description | Example | Default |
|----------|-------------|---------|---------|
| `PORT` | HTTP server port | `8081` | `8081` |
| `SERVER_READ_TIMEOUT` | Maximum request read duration | `15s` | `15s` |
| `SERVER_WRITE_TIMEOUT` | Maximum response write duration | `15s` | `15s` |
| `SERVER_SHUTDOWN_TIMEOUT` | Graceful shutdown timeout | `30s` | `30s` |

#### Redis Configuration

| Variable | Description | Example | Default |
|----------|-------------|---------|---------|
| `REDIS_ADDR` | Redis server address | `localhost:6379` | `localhost:6379` |
| `REDIS_PASSWORD` | Redis password | `mypassword` | `` (empty) |
| `REDIS_DB` | Redis database number | `0` | `0` |
| `REDIS_POOL_SIZE` | Maximum number of connections | `10` | `10` |
| `REDIS_MIN_IDLE_CONNS` | Minimum number of idle connections | `5` | `5` |
| `REDIS_MAX_RETRIES` | Maximum number of retries | `3` | `3` |
| `REDIS_DIAL_TIMEOUT` | Connection timeout | `5s` | `5s` |
| `REDIS_READ_TIMEOUT` | Read operation timeout | `3s` | `3s` |
| `REDIS_WRITE_TIMEOUT` | Write operation timeout | `3s` | `3s` |
| `REDIS_POOL_TIMEOUT` | Connection pool timeout | `4s` | `4s` |

#### JWT Configuration

| Variable | Description | Example | Default |
|----------|-------------|---------|---------|
| `JWT_ACCESS_EXPIRATION` | Access token lifetime | `1h` | `1h` |
| `JWT_REFRESH_EXPIRATION` | Refresh token lifetime | `168h` | `168h` (7 days) |
| `JWT_ISSUER` | JWT issuer claim | `qos-gateway-admin` | `qos-gateway-admin` |

#### CORS Configuration

| Variable | Description | Example | Default |
|----------|-------------|---------|---------|
| `CORS_ALLOWED_ORIGINS` | Allowed origins (comma-separated) | `https://example.com,https://api.example.com` | `*` |
| `CORS_ALLOWED_METHODS` | Allowed HTTP methods | `GET,POST,PUT,DELETE` | `GET,POST,PUT,DELETE,OPTIONS` |
| `CORS_ALLOWED_HEADERS` | Allowed headers | `Content-Type,Authorization` | `Origin,Content-Type,Authorization` |
| `CORS_EXPOSED_HEADERS` | Headers exposed to browser | `X-Request-ID` | `` (empty) |
| `CORS_ALLOW_CREDENTIALS` | Allow credentials | `true` | `false` |
| `CORS_MAX_AGE` | Preflight cache duration | `86400s` | `86400s` (24 hours) |

#### Rate Limiting Configuration

| Variable | Description | Example | Default |
|----------|-------------|---------|---------|
| `RATE_LIMIT_ENABLED` | Enable rate limiting | `true` | `true` |
| `RATE_LIMIT_REQUESTS` | Max requests per window | `100` | `100` |
| `RATE_LIMIT_WINDOW` | Rate limit time window | `1m` | `1m` (1 minute) |
| `RATE_LIMIT_CLEANUP_INTERVAL` | Cleanup interval for old entries | `5m` | `5m` (5 minutes) |

#### Logging Configuration

| Variable | Description | Example | Default |
|----------|-------------|---------|---------|
| `LOG_LEVEL` | Minimum log level | `info` | `info` |
| `LOG_FORMAT` | Log format (json or console) | `json` | `console` |
| `LOG_OUTPUT_PATH` | Log file path (empty for stdout) | `/var/log/admin-backend.log` | `` (stdout) |

## Quick Start

### Prerequisites

- Go 1.21 or higher
- Redis 6.0 or higher

### Installation

1. Clone the repository:
```bash
cd admin-backend
```

2. Install dependencies:
```bash
go mod download
```

3. Set environment variables:
```bash
export JWT_SECRET="your-very-secret-jwt-key-min-32-characters-long"
export REDIS_ADDR="localhost:6379"
```

4. Build the application:
```bash
go build -o admin-backend
```

5. Run the application:
```bash
./admin-backend
```

### Docker

```bash
docker build -t admin-backend .
docker run -p 8081:8081 \
  -e JWT_SECRET="your-very-secret-jwt-key-min-32-characters-long" \
  -e REDIS_ADDR="redis:6379" \
  admin-backend
```

### Docker Compose

```yaml
version: '3.8'
services:
  admin-backend:
    build: .
    ports:
      - "8081:8081"
    environment:
      - JWT_SECRET=your-very-secret-jwt-key-min-32-characters-long
      - REDIS_ADDR=redis:6379
      - LOG_LEVEL=info
      - LOG_FORMAT=json
    depends_on:
      - redis

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
```

## API Documentation

### Health Check

```
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": 1703145600
}
```

### Authentication

#### Login
```
POST /api/v1/auth/login
Content-Type: application/json

{
  "username": "admin",
  "password": "admin123"
}
```

**Response:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
  "expires_in": 3600
}
```

#### Refresh Token
```
POST /api/v1/auth/refresh
Content-Type: application/json

{
  "refresh_token": "eyJhbGciOiJIUzI1NiIs..."
}
```

### Application Management

#### List Applications
```
GET /api/v1/apps
Authorization: Bearer <access_token>
```

#### Create Application
```
POST /api/v1/apps
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "app_id": "app1",
  "guaranteed_quota": 1000,
  "burst_quota": 5000,
  "priority": 1,
  "max_borrow": 1000,
  "max_connections": 1000
}
```

#### Get Application
```
GET /api/v1/apps/:id
Authorization: Bearer <access_token>
```

#### Update Application
```
PUT /api/v1/apps/:id
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "app_id": "app1",
  "guaranteed_quota": 2000,
  "burst_quota": 10000,
  "priority": 2,
  "max_borrow": 2000,
  "max_connections": 2000
}
```

#### Delete Application
```
DELETE /api/v1/apps/:id
Authorization: Bearer <access_token>
```

### Cluster Management

#### List Clusters
```
GET /api/v1/clusters
Authorization: Bearer <access_token>
```

#### Get Cluster
```
GET /api/v1/clusters/:id
Authorization: Bearer <access_token>
```

#### Update Cluster
```
PUT /api/v1/clusters/:id
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "cluster_id": "cluster1",
  "max_capacity": 100000,
  "reserved_ratio": 0.1,
  "emergency_threshold": 0.95,
  "max_connections": 5000
}
```

### Emergency Mode

#### Get Emergency Status
```
GET /api/v1/emergency
Authorization: Bearer <access_token>
```

#### Activate Emergency Mode
```
POST /api/v1/emergency/activate
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "reason": "Manual activation for testing",
  "duration": 300
}
```

#### Deactivate Emergency Mode
```
POST /api/v1/emergency/deactivate
Authorization: Bearer <access_token>
```

### Metrics

#### Get System Metrics
```
GET /api/v1/metrics
Authorization: Bearer <access_token>
```

**Response:**
```json
{
  "requests_total": 50000,
  "rejected_total": 500,
  "l3_hits": 45000,
  "cache_hit_ratio": 0.9,
  "emergency_active": false,
  "degradation_level": "normal",
  "reconcile_corrections": 10
}
```

#### Get Application Metrics
```
GET /api/v1/metrics/apps/:id
Authorization: Bearer <access_token>
```

### WebSocket

Connect to the WebSocket endpoint for real-time updates:

```
ws://localhost:8081/ws
Authorization: Bearer <access_token>
```

**Message Format:**
```json
{
  "type": "metrics|event",
  "data": {...},
  "timestamp": "2024-01-01T00:00:00Z"
}
```

## Development

### Running Tests

```bash
go test ./...
```

### Code Quality

```bash
# Format code
go fmt ./...

# Lint
golangci-lint run

# Run with race detection
go run -race main.go
```

### Adding New Features

1. Add models in `models/` package
2. Implement storage interface methods in `storage/redis.go`
3. Add handlers in `handlers/handlers.go`
4. Register routes in `main.go`
5. Add validation in `validation/validation.go`
6. Update README with API documentation

## Production Checklist

- [ ] Set strong JWT_SECRET (at least 32 characters)
- [ ] Configure CORS_ALLOWED_ORIGINS to specific domains
- [ ] Enable rate limiting (RATE_LIMIT_ENABLED=true)
- [ ] Use JSON logging format (LOG_FORMAT=json)
- [ ] Configure log output to file (LOG_OUTPUT_PATH)
- [ ] Set appropriate timeouts for Redis operations
- [ ] Configure TLS/HTTPS
- [ ] Set up monitoring and alerting
- [ ] Configure backup strategy for Redis
- [ ] Review and adjust rate limit thresholds

## License

MIT

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request
