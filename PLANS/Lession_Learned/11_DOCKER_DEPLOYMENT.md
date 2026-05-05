# Lesson 11: Docker & Deployment

> Learn how to containerize and deploy your Go application.

---

## What You'll Learn

1. What is Docker?
2. Dockerfile for Go applications
3. Docker Compose for development
4. Environment variables
5. Production deployment considerations

---

## 1. What is Docker?

Docker packages your application and its dependencies into a **container** — a lightweight, portable unit that runs the same everywhere.

**Benefits:**
- "Works on my machine" → Works everywhere
- Easy to deploy
- Consistent environments
- Isolated services

---

## 2. Dockerfile

**File:** `Backend/Dockerfile`

```dockerfile
# Build stage
FROM golang:1.25-alpine AS builder

WORKDIR /app

# Copy dependency files first (caching)
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux go build -o main ./cmd/server

# Production stage (minimal image)
FROM alpine:3.19

WORKDIR /app

# Install certificates for HTTPS
RUN apk --no-cache add ca-certificates

# Copy binary from builder
COPY --from=builder /app/main .

# Expose port
EXPOSE 8080

# Run the application
CMD ["./main"]
```

### Understanding Multi-Stage Builds

1. **Build stage** (golang:1.25-alpine)
   - Full Go toolchain
   - Compiles your code
   - ~500MB image

2. **Production stage** (alpine:3.19)
   - Minimal OS
   - Just your binary
   - ~15MB image

### Build Commands

```bash
# Build image
docker build -t taskflow-backend ./Backend

# Run container
docker run -p 8080:8080 taskflow-backend

# Build with tag
docker build -t taskflow-backend:v1.0.0 ./Backend
```

---

## 3. Docker Compose

**File:** `docker-compose.yml`

```yaml
services:
  # PostgreSQL Database
  postgres:
    image: postgres:16-alpine
    container_name: trello-agent-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${DB_USER:-trello_agent}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-trello_agent_secret}
      POSTGRES_DB: ${DB_NAME:-trello_agent}
    ports:
      - "${DB_PORT:-5432}:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-trello_agent}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - trello-agent-network

  # Redis Cache
  redis:
    image: redis:7-alpine
    container_name: trello-agent-redis
    restart: unless-stopped
    command: >
      redis-server
      --requirepass ${REDIS_PASSWORD:-redis_secret}
      --maxmemory 128mb
      --maxmemory-policy allkeys-lru
      --appendonly yes
    ports:
      - "${REDIS_PORT:-6379}:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD:-redis_secret}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - trello-agent-network

  # MinIO Object Storage
  minio:
    image: minio/minio:latest
    container_name: trello-agent-minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER:-minioadmin}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD:-minioadmin123}
    ports:
      - "${MINIO_PORT:-9000}:9000"
      - "${MINIO_CONSOLE_PORT:-9001}:9001"
    volumes:
      - minio_data:/data
    networks:
      - trello-agent-network

  # Go API Server
  api:
    build:
      context: ./Backend
      dockerfile: Dockerfile
    container_name: trello-agent-api
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      minio:
        condition: service_healthy
    environment:
      APP_ENV: development
      APP_PORT: 8080
      DATABASE_URL: postgres://${DB_USER:-trello_agent}:${DB_PASSWORD:-trello_agent_secret}@postgres:5432/${DB_NAME:-trello_agent}?sslmode=disable
      REDIS_URL: redis://:${REDIS_PASSWORD:-redis_secret}@redis:6379/0
      JWT_ACCESS_SECRET: ${JWT_ACCESS_SECRET:-your-super-secret-key}
      JWT_REFRESH_SECRET: ${JWT_REFRESH_SECRET:-your-super-refresh-key}
      MINIO_ENDPOINT: minio:9000
      MINIO_ACCESS_KEY: ${MINIO_ROOT_USER:-minioadmin}
      MINIO_SECRET_KEY: ${MINIO_ROOT_PASSWORD:-minioadmin123}
      FRONTEND_URL: ${FRONTEND_URL:-http://localhost:5173}
    ports:
      - "${API_PORT:-8080}:8080"
    networks:
      - trello-agent-network

  # MailHog (Development email testing)
  mailhog:
    image: mailhog/mailhog:latest
    container_name: trello-agent-mailhog
    restart: unless-stopped
    ports:
      - "${MAILHOG_SMTP_PORT:-1025}:1025"
      - "${MAILHOG_UI_PORT:-8025}:8025"
    networks:
      - trello-agent-network

networks:
  trello-agent-network:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
  minio_data:
```

### Docker Compose Commands

```bash
# Start all services
docker compose up -d

# View logs
docker compose logs -f api

# Stop all services
docker compose down

# Stop and remove volumes (DELETES DATA)
docker compose down -v

# Rebuild and start
docker compose up -d --build

# View running containers
docker compose ps
```

---

## 4. Environment Variables

**File:** `.env` (don't commit to git!)

```env
# App
APP_ENV=development
APP_PORT=8080
FRONTEND_URL=http://localhost:5173

# Database
DB_USER=trello_agent
DB_PASSWORD=super_secret_password
DB_NAME=trello_agent
DB_PORT=5432

# Redis
REDIS_PASSWORD=redis_secret
REDIS_PORT=6379

# JWT (generate random strings!)
JWT_ACCESS_SECRET=your-32-char-minimum-access-secret-key
JWT_REFRESH_SECRET=your-32-char-minimum-refresh-secret-key

# MinIO
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin123

# API Port
API_PORT=8080
```

### Loading Environment Variables

**File:** `Backend/internal/config/config.go`

```go
package config

import (
    "os"
    "time"
)

type Config struct {
    App      AppConfig
    Database DatabaseConfig
    Redis    RedisConfig
    JWT      JWTConfig
    MinIO    MinIOConfig
}

type AppConfig struct {
    Env  string
    Port string
    URL  string
}

func Load() (*Config, error) {
    return &Config{
        App: AppConfig{
            Env:  getEnv("APP_ENV", "development"),
            Port: getEnv("APP_PORT", "8080"),
            URL:  getEnv("APP_URL", "http://localhost:8080"),
        },
        Database: DatabaseConfig{
            URL:     getEnv("DATABASE_URL", ""),
            PoolMax: getEnvInt("DB_POOL_MAX", 10),
        },
        Redis: RedisConfig{
            URL: getEnv("REDIS_URL", "redis://localhost:6379"),
        },
        JWT: JWTConfig{
            AccessSecret:     getEnv("JWT_ACCESS_SECRET", ""),
            RefreshSecret:    getEnv("JWT_REFRESH_SECRET", ""),
            AccessExpiresIn:  getEnvDuration("JWT_ACCESS_EXPIRY", 15*time.Minute),
            RefreshExpiresIn: getEnvDuration("JWT_REFRESH_EXPIRY", 168*time.Hour),
        },
    }, nil
}

func getEnv(key, defaultValue string) string {
    if value := os.Getenv(key); value != "" {
        return value
    }
    return defaultValue
}
```

---

## 5. Service Dependencies

### Health Checks

```yaml
postgres:
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-trello_agent}"]
    interval: 10s
    timeout: 5s
    retries: 5
```

### Dependency Order

```yaml
api:
  depends_on:
    postgres:
      condition: service_healthy
    redis:
      condition: service_healthy
```

**Result:** API waits for PostgreSQL and Redis to be ready before starting.

---

## 6. Development Workflow

### Start Development Environment

```bash
# Start all services
docker compose up -d

# Run migrations
goose -dir Backend/migrations postgres \
  "postgres://trello_agent:trello_agent_secret@localhost:5432/trello_agent?sslmode=disable" up

# View API logs
docker compose logs -f api

# View all logs
docker compose logs -f
```

### Access Services

| Service | URL |
|---------|-----|
| API | http://localhost:8080 |
| API Docs | http://localhost:8080/api/docs |
| PostgreSQL | localhost:5432 |
| Redis | localhost:6379 |
| MinIO Console | http://localhost:9001 |
| MailHog | http://localhost:8025 |

---

## 7. Production Considerations

### Production Dockerfile

```dockerfile
FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# Add version info
ARG VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w -X main.Version=${VERSION}" \
    -o main ./cmd/server

FROM alpine:3.19
RUN apk --no-cache add ca-certificates tzdata
WORKDIR /app
COPY --from=builder /app/main .

# Non-root user
RUN adduser -D -g '' appuser
USER appuser

EXPOSE 8080
CMD ["./main"]
```

### Production docker-compose.prod.yml

```yaml
services:
  api:
    image: your-registry/taskflow-api:${VERSION:-latest}
    restart: always
    environment:
      APP_ENV: production
      # Use secrets management in production!
    deploy:
      replicas: 3
      resources:
        limits:
          cpus: '1'
          memory: 512M
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### Security Checklist

- [ ] Use HTTPS (terminate at load balancer)
- [ ] Set strong JWT secrets (32+ characters)
- [ ] Use secrets management (not .env files)
- [ ] Run as non-root user
- [ ] Enable database SSL
- [ ] Set proper CORS origins
- [ ] Enable rate limiting
- [ ] Set up logging and monitoring

---

## 8. Useful Docker Commands

```bash
# View running containers
docker ps

# View all containers
docker ps -a

# Enter container shell
docker exec -it trello-agent-api sh

# View container logs
docker logs trello-agent-api

# Inspect container
docker inspect trello-agent-api

# Remove unused images
docker image prune

# Remove all stopped containers
docker container prune

# View resource usage
docker stats
```

---

## 9. Database Backup

```bash
# Backup PostgreSQL
docker exec trello-agent-postgres \
  pg_dump -U trello_agent trello_agent > backup.sql

# Restore PostgreSQL
docker exec -i trello-agent-postgres \
  psql -U trello_agent trello_agent < backup.sql
```

---

## 10. CI/CD Pipeline (Example)

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build Docker image
        run: |
          docker build -t myapp:${{ github.sha }} ./Backend
          
      - name: Push to registry
        run: |
          docker push myregistry/myapp:${{ github.sha }}
          
      - name: Deploy
        run: |
          # SSH to server and pull new image
          ssh user@server "cd /app && docker compose pull && docker compose up -d"
```

---

## Practice Exercises

### Exercise 1: Add a Service

Add a new service to docker-compose.yml:
- Prometheus for metrics
- Port 9090
- Depends on API

### Exercise 2: Optimize Dockerfile

Improve the Dockerfile:
- Add build caching
- Reduce image size
- Add health check

---

## External Resources

| Resource | URL | Description |
|----------|-----|-------------|
| Docker Docs | https://docs.docker.com | Official docs |
| Docker Compose | https://docs.docker.com/compose | Compose docs |
| Best Practices | https://docs.docker.com/develop/dev-best-practices | Official guide |

---

## Key Takeaways

1. **Multi-stage builds** — Small production images
2. **Docker Compose** — Orchestrate multiple services
3. **Environment variables** — Configuration without code changes
4. **Health checks** — Ensure services are ready
5. **Volumes** — Persist data across restarts
6. **Networks** — Services communicate by name

---

## Congratulations!

You've completed the learning curriculum! You now understand:

- Go language fundamentals
- Project structure and architecture
- Domain models and repositories
- Services and handlers
- Middleware and authentication
- Database design and migrations
- Docker deployment

**Next Steps:**
1. Build a small feature end-to-end
2. Write tests for existing code
3. Deploy to a cloud provider
4. Add monitoring and logging

Good luck on your coding journey!
