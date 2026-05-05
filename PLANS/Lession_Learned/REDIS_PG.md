# Redis & PostgreSQL Contribution Analysis

> Analysis of how Redis and PostgreSQL are used in the TaskFlow (Trello Agent) project.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              APPLICATION LAYER                                   │
│                                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐      │
│  │   Handler   │───▶│   Service   │───▶│ Repository  │───▶│  Database   │      │
│  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘      │
│         │                 │                                      │              │
│         │                 │                                      ▼              │
│         │                 │                              ┌───────────────┐      │
│         │                 │                              │  PostgreSQL   │      │
│         │                 │                              │  (Primary DB) │      │
│         │                 │                              └───────────────┘      │
│         │                 │                                                     │
│         ▼                 ▼                                                     │
│  ┌─────────────────────────────┐                                               │
│  │        Middleware           │                                               │
│  │  - Rate Limiting            │──────────────────────────▶┌───────────────┐   │
│  │  - Auth (JWT Blacklist)     │                           │     Redis     │   │
│  └─────────────────────────────┘                           │    (Cache)    │   │
│                                                            └───────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. PostgreSQL — Primary Database

### Role
PostgreSQL serves as the **single source of truth** for all persistent business data. It stores all domain entities with full ACID compliance.

### Tables Managed

| Category | Tables | Purpose |
|----------|--------|---------|
| **Authentication** | `users`, `refresh_tokens`, `email_verifications` | User accounts, session management, email verification |
| **Organizations** | `organizations`, `organization_members` | Multi-tenant workspaces |
| **Boards** | `boards`, `board_members`, `board_invitations` | Kanban boards and access control |
| **Lists & Cards** | `lists`, `cards`, `card_members` | Kanban columns and tasks |
| **Features** | `labels`, `card_labels`, `checklists`, `checklist_items` | Task metadata |
| **Collaboration** | `comments`, `attachments` | Team collaboration |
| **Tracking** | `activity_logs`, `notifications` | Audit trail and user notifications |

### Implementation Pattern

All repositories use `pgxpool.Pool` for connection pooling:

```go
// internal/repository/user_repository.go
type userRepository struct {
    db *pgxpool.Pool
}

func (r *userRepository) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
    query := `
        SELECT id, email, password_hash, full_name, avatar_url, is_verified, is_active, 
               tokens_valid_after, created_at, updated_at, deleted_at
        FROM users
        WHERE email = $1 AND deleted_at IS NULL
    `
    var user domain.User
    err := r.db.QueryRow(ctx, query, email).Scan(...)
    // ...
}
```

### Connection Configuration

```go
// internal/config/config.go
type DatabaseConfig struct {
    URL      string
    Host     string
    Port     string
    User     string
    Password string
    Name     string
    SSLMode  string
    PoolMin  int  // Default: 2
    PoolMax  int  // Default: 10
}
```

### Docker Setup (Development)

```yaml
# docker-compose.yml
postgres:
  image: postgres:16-alpine
  environment:
    POSTGRES_USER: trello_agent
    POSTGRES_PASSWORD: trello_agent_secret
    POSTGRES_DB: trello_agent
  volumes:
    - postgres_data:/var/lib/postgresql/data
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U trello_agent -d trello_agent"]
```

### Key PostgreSQL Features Used

1. **Soft Delete** — `deleted_at IS NULL` pattern for all queries
2. **Partial Indexes** — For performance on filtered queries
3. **CUID Primary Keys** — Distributed-friendly IDs
4. **ENUM Types** — For role-based permissions (`org_role`, `board_role`, etc.)
5. **JSONB Columns** — For flexible metadata in `activity_logs`

---

## 2. Redis — Caching & Session Management

### Role
Redis is used for **fast, ephemeral data** that requires sub-millisecond access and automatic expiration.

### Use Cases

| Use Case | Key Pattern | TTL | Purpose |
|----------|-------------|-----|---------|
| **JWT Blacklist** | `blacklist:{jti}` | Remaining token TTL | Invalidate logged-out access tokens |
| **Rate Limiting** | `ratelimit:{action}:{ip}` | 15 min - 1 hour | Prevent abuse on auth endpoints |
| **OTP Attempts** | `otp_attempts:{email}` | 15 min | Brute-force protection for email verification |

### Implementation

#### Redis Client Setup

```go
// pkg/cache/redis.go
type RedisClient struct {
    client *redis.Client
}

func NewRedisClient(cfg config.RedisConfig) (*RedisClient, error) {
    opts, err := redis.ParseURL(cfg.URL)
    opts.DialTimeout = 5 * time.Second
    opts.ReadTimeout = 3 * time.Second
    opts.WriteTimeout = 3 * time.Second
    opts.PoolSize = 10
    opts.MinIdleConns = 2
    
    client := redis.NewClient(opts)
    // Ping to verify connection...
}
```

#### Rate Limiting Middleware

```go
// internal/middleware/ratelimit.go
func RateLimit(cache *cache.RedisClient, config RateLimitConfig) gin.HandlerFunc {
    return func(c *gin.Context) {
        key := fmt.Sprintf("ratelimit:%s:%s", config.KeyPrefix, c.ClientIP())
        
        count, err := cache.Incr(c.Request.Context(), key)
        if count == 1 {
            _ = cache.Expire(c.Request.Context(), key, config.Window)
        }
        
        if count > int64(config.MaxRequests) {
            response.ErrorResponse(c, apperror.ErrTooManyRequests)
            c.Abort()
            return
        }
        c.Next()
    }
}
```

#### JWT Blacklist on Logout

```go
// internal/service/auth_service.go
func (s *AuthService) Logout(ctx context.Context, accessToken, refreshToken string) error {
    if accessToken != "" {
        claims, err := s.jwtManager.GetClaimsFromExpiredToken(accessToken)
        if err == nil && claims.ID != "" {
            ttl := time.Until(claims.ExpiresAt.Time)
            if ttl > 0 {
                // Store in Redis with TTL matching token expiry
                _ = s.cache.Set(ctx, "blacklist:"+claims.ID, "logout", ttl)
            }
        }
    }
    // ...
}

func (s *AuthService) IsTokenBlacklisted(ctx context.Context, jti string) (bool, error) {
    return s.cache.Exists(ctx, "blacklist:"+jti)
}
```

#### OTP Brute-Force Protection

```go
// internal/service/auth_service.go
func (s *AuthService) VerifyEmail(ctx context.Context, req *request.VerifyEmailRequest) error {
    attemptsKey := "otp_attempts:" + req.Email
    attempts, _ := s.cache.Incr(ctx, attemptsKey)
    
    if attempts == 1 {
        _ = s.cache.Expire(ctx, attemptsKey, 15*time.Minute)
    }
    
    if attempts > maxOTPAttempts { // maxOTPAttempts = 5
        return apperror.ErrOTPMaxAttempts
    }
    // Continue with verification...
}
```

### Rate Limit Configuration by Endpoint

```go
// cmd/server/main.go
auth.POST("/register", middleware.RateLimit(redisClient, middleware.RateLimitConfig{
    MaxRequests: 3,      // 3 attempts
    Window:      time.Hour,
    KeyPrefix:   "register",
}), authHandler.Register)

auth.POST("/login", middleware.RateLimit(redisClient, middleware.RateLimitConfig{
    MaxRequests: 50,     // 50 attempts
    Window:      15 * time.Minute,
    KeyPrefix:   "login",
}), authHandler.Login)

auth.POST("/forgot-password", middleware.RateLimit(redisClient, middleware.RateLimitConfig{
    MaxRequests: 5,      // 5 attempts
    Window:      15 * time.Minute,
    KeyPrefix:   "forgot_password",
}), authHandler.ForgotPassword)
```

### Docker Setup (Development)

```yaml
# docker-compose.yml
redis:
  image: redis:7-alpine
  command: >
    redis-server
    --requirepass redis_secret
    --maxmemory 128mb
    --maxmemory-policy allkeys-lru
    --appendonly yes
  volumes:
    - redis_data:/data
  healthcheck:
    test: ["CMD", "redis-cli", "-a", "redis_secret", "ping"]
```

---

## 3. Comparison: When to Use Which

| Criteria | PostgreSQL | Redis |
|----------|------------|-------|
| **Data Type** | Structured, relational | Key-value, ephemeral |
| **Persistence** | Durable, ACID | Optional (AOF enabled) |
| **Access Pattern** | Complex queries, JOINs | Simple get/set, counters |
| **TTL Support** | Manual (soft delete) | Native TTL per key |
| **Latency** | ~1-10ms | ~0.5ms |
| **Use For** | Business data, audit logs | Sessions, rate limits, cache |

---

## 4. Data Flow Examples

### Login Flow

```
1. User submits credentials
   ↓
2. Rate limit check (Redis: ratelimit:login:{ip})
   ↓
3. User lookup (PostgreSQL: SELECT * FROM users WHERE email = ?)
   ↓
4. Password verification
   ↓
5. Create refresh token (PostgreSQL: INSERT INTO refresh_tokens)
   ↓
6. Return JWT access token + refresh token
```

### Logout Flow

```
1. User requests logout with access token
   ↓
2. Extract JTI from token
   ↓
3. Blacklist access token (Redis: SET blacklist:{jti} = "logout" EX {remaining_ttl})
   ↓
4. Revoke refresh token (PostgreSQL: UPDATE refresh_tokens SET is_revoked = true)
```

### Protected Request Flow

```
1. Request with Authorization: Bearer {token}
   ↓
2. Validate JWT signature
   ↓
3. Check blacklist (Redis: EXISTS blacklist:{jti})
   ↓
4. If not blacklisted, allow request
   ↓
5. Business logic with PostgreSQL queries
```

---

## 5. Key Patterns & Best Practices

### PostgreSQL Patterns

1. **Connection Pooling** — `pgxpool.Pool` with min/max connections
2. **Parameterized Queries** — Prevent SQL injection
3. **Soft Delete** — `deleted_at IS NULL` in all queries
4. **CUID IDs** — Distributed-friendly unique identifiers
5. **Repository Pattern** — Clean separation of data access

### Redis Patterns

1. **Key Naming Convention** — `{action}:{identifier}:{sub-id}`
2. **TTL Management** — Auto-expire temporary data
3. **INCR for Counters** — Atomic rate limit tracking
4. **Graceful Degradation** — Don't fail if Redis is unavailable (for rate limiting)

---

## 6. Environment Configuration

```env
# PostgreSQL
DATABASE_URL=postgres://trello_agent:secret@postgres:5432/trello_agent?sslmode=disable
DB_POOL_MIN=2
DB_POOL_MAX=10

# Redis
REDIS_URL=redis://:redis_secret@redis:6379/0
```

---

## 7. Summary

| Component | PostgreSQL | Redis |
|-----------|------------|-------|
| **Total Tables** | 19 tables | N/A (key-value) |
| **Primary Use** | All business data | Auth security |
| **Connection Pool** | 2-10 connections | 2-10 connections |
| **Data Volume** | Millions of rows | Thousands of keys |
| **Durability** | Full ACID | AOF persistence |
| **Critical For** | Data integrity | Security (rate limit, blacklist) |

### Redis Key Space Summary

| Key Pattern | Count (Est.) | Purpose |
|-------------|--------------|---------|
| `blacklist:*` | ~1K active | Logged-out JWT tokens |
| `ratelimit:*` | ~5K active | IP-based rate limits |
| `otp_attempts:*` | ~100 active | OTP brute-force protection |

### PostgreSQL Table Statistics (Est. 10K users)

| Table | Est. Rows |
|-------|-----------|
| `users` | 10,000 |
| `cards` | 2,000,000 |
| `activity_logs` | 10,000,000 |
| `notifications` | 5,000,000 |

---

## 8. Lessons Learned

1. **Redis for short-lived, security-critical data** — JWT blacklist and rate limiting benefit from Redis's sub-millisecond latency and native TTL.

2. **PostgreSQL for everything persistent** — All business entities, relationships, and audit trails belong in PostgreSQL.

3. **Graceful degradation** — If Redis fails, rate limiting continues (returns `c.Next()`) rather than blocking all requests.

4. **Key naming consistency** — Using structured key patterns (`ratelimit:{action}:{identifier}`) makes debugging and monitoring easier.

5. **Connection pooling is essential** — Both PostgreSQL and Redis use connection pools to handle concurrent requests efficiently.
