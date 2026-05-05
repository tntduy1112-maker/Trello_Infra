# TaskFlow — Backend Description

> **Stack:** Go 1.25 | Gin | pgx (PostgreSQL) | go-redis | MinIO | JWT | zerolog  
> **Architecture:** Clean Architecture (Handler → Service → Repository)

---

## Overview

Backend của **TaskFlow** là REST API server viết bằng Go, theo kiến trúc Layered/Clean Architecture.  
Server chạy tại `http://localhost:8080` với API prefix `/api/v1`.

Hỗ trợ JWT Authentication với refresh token rotation, rate limiting bằng Redis, file upload qua MinIO, và real-time notifications qua SSE.

---

## Project Structure

```
Backend/
├── cmd/
│   └── server/
│       ├── main.go              ← Entry point + dependency injection
│       └── swagger.yaml         ← Embedded API documentation
│
├── internal/
│   ├── config/
│   │   └── config.go            ← Viper-based configuration
│   │
│   ├── domain/                  ← Entity/Model definitions
│   │   ├── user.go
│   │   ├── organization.go
│   │   ├── board.go
│   │   ├── list.go
│   │   ├── card.go
│   │   ├── label.go
│   │   ├── comment.go
│   │   ├── checklist.go
│   │   ├── attachment.go
│   │   ├── activity.go
│   │   └── notification.go
│   │
│   ├── dto/                     ← Data Transfer Objects (Request/Response)
│   │   ├── request.go
│   │   └── response.go
│   │
│   ├── handler/                 ← HTTP handlers (Controllers)
│   │   ├── auth_handler.go
│   │   ├── organization_handler.go
│   │   ├── board_handler.go
│   │   ├── list_handler.go
│   │   ├── card_handler.go
│   │   ├── label_handler.go
│   │   ├── comment_handler.go
│   │   ├── checklist_handler.go
│   │   ├── attachment_handler.go
│   │   ├── activity_handler.go
│   │   ├── notification_handler.go
│   │   ├── invitation_handler.go
│   │   └── swagger_handler.go
│   │
│   ├── middleware/
│   │   ├── auth.go              ← JWT authentication middleware
│   │   ├── ratelimit.go         ← Redis-based rate limiting
│   │   └── error_handler.go     ← Global error handler
│   │
│   ├── repository/              ← Data access layer (PostgreSQL)
│   │   ├── interfaces.go        ← Repository interfaces
│   │   ├── user_repository.go
│   │   ├── token_repository.go
│   │   ├── verification_repository.go
│   │   ├── organization_repository.go
│   │   ├── board_repository.go
│   │   ├── list_repository.go
│   │   ├── card_repository.go
│   │   ├── label_repository.go
│   │   ├── comment_repository.go
│   │   ├── checklist_repository.go
│   │   ├── attachment_repository.go
│   │   ├── activity_repository.go
│   │   ├── notification_repository.go
│   │   └── invitation_repository.go
│   │
│   └── service/                 ← Business logic layer
│       ├── auth_service.go
│       ├── organization_service.go
│       ├── board_service.go
│       ├── list_service.go
│       ├── card_service.go
│       ├── label_service.go
│       ├── comment_service.go
│       ├── checklist_service.go
│       ├── attachment_service.go
│       ├── activity_service.go
│       ├── notification_service.go
│       ├── invitation_service.go
│       └── sse_manager.go       ← SSE connection management
│
├── pkg/                         ← Reusable packages
│   ├── apperror/                ← Custom error types
│   ├── cache/                   ← Redis client wrapper
│   ├── crypto/                  ← AES encryption utilities
│   ├── cuid/                    ← CUID2 ID generation
│   ├── database/                ← PostgreSQL connection pool
│   ├── email/                   ← SMTP email service
│   ├── hash/                    ← bcrypt password hashing
│   ├── jwt/                     ← JWT token management
│   ├── position/                ← Float position for drag & drop
│   ├── storage/                 ← MinIO file storage
│   └── validator/               ← Request validation
│
├── migrations/                  ← Goose SQL migrations
│   ├── 00001_create_users.sql
│   ├── 00002_create_refresh_tokens.sql
│   ├── ...
│   └── 00019_create_notifications.sql
│
├── docs/
│   └── swagger.yaml             ← OpenAPI 3.0 specification
│
├── go.mod
├── go.sum
├── Dockerfile
└── .air.toml                    ← Hot reload config
```

---

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                          HTTP Request                           │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Middleware                               │
│  ┌──────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ Error Handler│  │   CORS      │  │ Rate Limit (Redis)      │ │
│  └──────────────┘  └─────────────┘  └─────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │               JWT Auth + Token Validation                    │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                          Handler Layer                           │
│  • Parse request (JSON body, URL params, query strings)         │
│  • Validate input using validator.v10                           │
│  • Call service methods                                         │
│  • Format response (success/error envelope)                     │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Service Layer                            │
│  • Business logic & orchestration                               │
│  • Authorization checks (role, ownership)                       │
│  • Cross-cutting concerns (notifications, activity logs)        │
│  • Transaction coordination                                     │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Repository Layer                          │
│  • Data access (PostgreSQL via pgx)                             │
│  • SQL queries (parameterized)                                  │
│  • Domain model mapping                                         │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Infrastructure                           │
│  ┌──────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ PostgreSQL   │  │   Redis     │  │        MinIO            │ │
│  │ (pgx pool)   │  │ (go-redis)  │  │  (minio-go SDK)         │ │
│  └──────────────┘  └─────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Technology Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Language** | Go 1.25 | Runtime |
| **HTTP Framework** | Gin 1.9 | Routing, middleware, JSON binding |
| **Database** | PostgreSQL 16 | Primary data store |
| **Database Driver** | pgx/v5 | High-performance PostgreSQL driver |
| **Cache** | Redis (go-redis) | Token blacklist, rate limiting, SSE tracking |
| **Object Storage** | MinIO (minio-go) | File attachments, avatars |
| **Authentication** | golang-jwt/jwt/v5 | JWT access & refresh tokens |
| **Validation** | go-playground/validator/v10 | Request validation |
| **Configuration** | Viper | Environment & config management |
| **Logging** | zerolog | Structured JSON logging |
| **Password Hashing** | bcrypt (golang.org/x/crypto) | Secure password storage |
| **ID Generation** | cuid2 | Collision-resistant unique IDs |
| **Migrations** | Goose | Database schema migrations |
| **API Docs** | Swagger/OpenAPI 3.0 | API documentation |
| **Hot Reload** | Air | Development live reload |

---

## API Modules & Endpoints

### Authentication (`/api/v1/auth`)

| Method | Endpoint | Description | Rate Limit |
|--------|----------|-------------|------------|
| POST | `/register` | Register new user | 3/hour |
| POST | `/verify-email` | Verify OTP | 10/15min |
| POST | `/resend-verification` | Resend OTP | 3/hour |
| POST | `/login` | Login (returns tokens) | 50/15min |
| POST | `/refresh` | Refresh access token | 30/15min |
| POST | `/logout` | Logout (revoke token) | — |
| POST | `/logout-all` | Logout all sessions | Auth required |
| POST | `/forgot-password` | Request password reset | 5/15min |
| POST | `/reset-password` | Reset with token | 5/15min |
| GET | `/me` | Get current user | Auth required |
| PUT | `/me` | Update profile | Auth required |

### Organizations (`/api/v1/organizations`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/` | Create organization |
| GET | `/` | List user's organizations |
| GET | `/:slug` | Get by slug |
| PUT | `/:slug` | Update organization |
| DELETE | `/:slug` | Delete organization |
| GET | `/:slug/members` | List members |
| POST | `/:slug/members` | Invite member |
| PUT | `/:slug/members/:userId` | Update member role |
| DELETE | `/:slug/members/:userId` | Remove member |
| POST | `/:slug/leave` | Leave organization |
| POST | `/:slug/boards` | Create board |
| GET | `/:slug/boards` | List boards |

### Boards (`/api/v1/boards`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/:id` | Get board with lists & cards |
| PUT | `/:id` | Update board |
| DELETE | `/:id` | Delete board |
| POST | `/:id/close` | Close board |
| POST | `/:id/reopen` | Reopen board |
| GET | `/:id/members` | List board members |
| POST | `/:id/members` | Invite to board |
| PUT | `/:id/members/:userId` | Update member role |
| DELETE | `/:id/members/:userId` | Remove member |
| POST | `/:id/leave` | Leave board |
| POST | `/:id/lists` | Create list |
| GET | `/:id/labels` | List labels |
| POST | `/:id/labels` | Create label |
| GET | `/:id/activity` | Board activity log |

### Lists (`/api/v1/lists`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| PUT | `/:id` | Update list (title, position) |
| POST | `/:id/archive` | Archive list |
| POST | `/:id/restore` | Restore list |
| POST | `/:id/move` | Move to another board |
| POST | `/:id/copy` | Copy list |
| POST | `/:id/cards` | Create card |

### Cards (`/api/v1/cards`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/:id` | Get card details |
| PUT | `/:id` | Update card |
| POST | `/:id/archive` | Archive card |
| POST | `/:id/restore` | Restore card |
| POST | `/:id/move` | Move to list/board |
| POST | `/:id/assign` | Assign user |
| POST | `/:id/unassign` | Unassign user |
| POST | `/:id/complete` | Mark complete |
| POST | `/:id/incomplete` | Mark incomplete |
| POST | `/:id/labels/:labelId` | Add label |
| DELETE | `/:id/labels/:labelId` | Remove label |
| GET | `/:id/comments` | List comments |
| POST | `/:id/comments` | Create comment |
| GET | `/:id/checklists` | List checklists |
| POST | `/:id/checklists` | Create checklist |
| GET | `/:id/attachments` | List attachments |
| POST | `/:id/attachments` | Upload attachment |
| DELETE | `/:id/cover` | Remove cover |
| GET | `/:id/activity` | Card activity log |

### Labels (`/api/v1/labels`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| PUT | `/:id` | Update label |
| DELETE | `/:id` | Delete label |

### Comments (`/api/v1/comments`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| PUT | `/:id` | Edit comment |
| DELETE | `/:id` | Delete comment |

### Checklists (`/api/v1/checklists`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| PUT | `/:id` | Update checklist |
| DELETE | `/:id` | Delete checklist |
| POST | `/:id/items` | Create item |

### Checklist Items (`/api/v1/checklist-items`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| PUT | `/:id` | Update item |
| DELETE | `/:id` | Delete item |
| POST | `/:id/toggle` | Toggle completion |

### Attachments (`/api/v1/attachments`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| DELETE | `/:id` | Delete attachment |
| POST | `/:id/cover` | Set as card cover |
| GET | `/:id/download` | Download file |

### Notifications (`/api/v1/notifications`)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | List notifications |
| GET | `/unread-count` | Get unread count |
| GET | `/stream` | SSE real-time stream |
| POST | `/:id/read` | Mark as read |
| POST | `/read-all` | Mark all as read |
| DELETE | `/:id` | Delete notification |

### Invitations (Public)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/invitations/:token` | Get invitation info |
| POST | `/invitations/:token/accept` | Accept (auth required) |
| POST | `/invitations/:token/accept-with-password` | Accept + register |
| POST | `/invitations/:token/decline` | Decline |

---

## API Response Format

### Success Response

```json
{
  "success": true,
  "data": { ... },
  "message": "Optional message"
}
```

### Paginated Response

```json
{
  "success": true,
  "data": [ ... ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 100,
    "totalPages": 5
  }
}
```

### Error Response

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Human readable message",
    "details": [ ... ]
  }
}
```

---

## Error Codes

| HTTP Status | Code | Description |
|:-----------:|------|-------------|
| 400 | `BAD_REQUEST` | Invalid request format |
| 401 | `UNAUTHORIZED` | Missing or invalid token |
| 401 | `TOKEN_EXPIRED` | Access token expired |
| 401 | `TOKEN_REVOKED` | Token has been revoked |
| 403 | `FORBIDDEN` | No permission for action |
| 404 | `NOT_FOUND` | Resource not found |
| 409 | `CONFLICT` | Resource already exists |
| 422 | `VALIDATION_ERROR` | Input validation failed |
| 429 | `RATE_LIMITED` | Too many requests |
| 500 | `INTERNAL_ERROR` | Server error |

---

## Authentication Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         Registration                             │
├─────────────────────────────────────────────────────────────────┤
│  POST /auth/register                                            │
│  ├─> Create user (is_verified=false)                           │
│  ├─> Generate 6-digit OTP                                       │
│  ├─> Store OTP hash in email_verifications                      │
│  └─> Send verification email                                    │
│                                                                  │
│  POST /auth/verify-email                                        │
│  ├─> Validate OTP                                               │
│  ├─> Set is_verified=true                                       │
│  └─> Return success                                             │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                            Login                                 │
├─────────────────────────────────────────────────────────────────┤
│  POST /auth/login                                               │
│  ├─> Validate credentials (bcrypt)                              │
│  ├─> Check is_verified=true                                     │
│  ├─> Generate Access Token (15 min)                             │
│  ├─> Generate Refresh Token (7 days)                            │
│  ├─> Store Refresh Token hash in DB                             │
│  └─> Return tokens                                              │
│                                                                  │
│  Response:                                                       │
│  {                                                               │
│    "access_token": "eyJ...",                                    │
│    "refresh_token": "eyJ...",                                   │
│    "expires_in": 900,                                           │
│    "user": { ... }                                              │
│  }                                                               │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                       Token Refresh                              │
├─────────────────────────────────────────────────────────────────┤
│  POST /auth/refresh                                             │
│  ├─> Validate refresh token signature                           │
│  ├─> Check token exists in DB                                   │
│  ├─> Check token not revoked                                    │
│  ├─> Check user.tokens_valid_after                              │
│  ├─> Revoke old refresh token                                   │
│  ├─> Issue new access token                                     │
│  └─> Issue new refresh token (rotation)                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## JWT Token Structure

### Access Token (15 min)

```json
{
  "jti": "unique-token-id",
  "sub": "user-cuid",
  "iat": 1715000000,
  "exp": 1715000900,
  "type": "access"
}
```

### Refresh Token (7 days)

```json
{
  "jti": "unique-token-id",
  "sub": "user-cuid",
  "iat": 1715000000,
  "exp": 1715604800,
  "type": "refresh"
}
```

---

## Real-time: SSE (Server-Sent Events)

```
GET /api/v1/notifications/stream
Authorization: Bearer <access_token>

┌──────────────┐                    ┌──────────────┐
│   Client     │                    │   Server     │
│  (Frontend)  │                    │    (Go)      │
└──────┬───────┘                    └──────┬───────┘
       │                                   │
       │ ─── EventSource connect ────────► │
       │                                   │
       │ ◄─────── Connected ─────────────  │
       │                                   │
       │ ◄─ event: notification ─────────  │
       │    data: {"type":"card_assigned"} │
       │                                   │
       │ ◄─ event: notification ─────────  │
       │    data: {"type":"comment_added"} │
       │                                   │
       │ ◄───── :keepalive ──────────────  │
       │        (every 30s)                │
       │                                   │
```

**SSE Manager:**
- Tracks connections per user
- Fan-out notifications to all user sessions
- Automatic cleanup on disconnect
- Heartbeat every 30 seconds

---

## Rate Limiting

| Endpoint | Limit | Window |
|----------|:-----:|:------:|
| `/auth/register` | 3 | 1 hour |
| `/auth/login` | 50 | 15 min |
| `/auth/refresh` | 30 | 15 min |
| `/auth/verify-email` | 10 | 15 min |
| `/auth/resend-verification` | 3 | 1 hour |
| `/auth/forgot-password` | 5 | 15 min |
| `/auth/reset-password` | 5 | 15 min |

Redis key format: `ratelimit:{prefix}:{ip}`

---

## Configuration

Environment variables (via `.env` or Docker):

```bash
# App
APP_ENV=development
APP_PORT=8080
APP_URL=http://localhost:8080
FRONTEND_URL=http://localhost:5173

# Database
DB_HOST=localhost
DB_PORT=5432
DB_NAME=taskflow
DB_USER=postgres
DB_PASSWORD=secret
DB_SSLMODE=disable
DB_MAX_CONNECTIONS=25

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0

# JWT
JWT_ACCESS_SECRET=your-access-secret
JWT_REFRESH_SECRET=your-refresh-secret
JWT_ACCESS_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=168h

# MinIO
MINIO_ENDPOINT=localhost:9000
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin
MINIO_BUCKET=taskflow
MINIO_USE_SSL=false
MINIO_PUBLIC_HOST=http://localhost:9000

# SMTP
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password
SMTP_FROM=TaskFlow <noreply@taskflow.com>
```

---

## Running the Server

### Development

```bash
# Start dependencies
docker-compose up -d postgres redis minio

# Run migrations
goose -dir migrations postgres "postgres://postgres:secret@localhost:5432/taskflow?sslmode=disable" up

# Run with hot reload
air

# Or without hot reload
go run cmd/server/main.go
```

### Production (Docker)

```bash
# Build
docker build -t taskflow-backend .

# Run
docker run -p 8080:8080 \
  -e APP_ENV=production \
  -e DB_HOST=postgres \
  ... \
  taskflow-backend
```

---

## Health Check

```
GET /health

{
  "status": "ok",
  "version": "1.0.0"
}
```

---

## API Documentation

Swagger UI available at: `http://localhost:8080/api/docs`

- Interactive API testing
- Request/response schemas
- Authentication flows
- Error codes reference

---

## Key Implementation Patterns

### Dependency Injection (Manual)

```go
// main.go
userRepo := repository.NewUserRepository(db)
authService := service.NewAuthService(userRepo, jwtManager, ...)
authHandler := handler.NewAuthHandler(authService)
```

### Repository Interface Pattern

```go
// repository/interfaces.go
type UserRepository interface {
    Create(ctx context.Context, user *domain.User) error
    FindByID(ctx context.Context, id string) (*domain.User, error)
    FindByEmail(ctx context.Context, email string) (*domain.User, error)
    Update(ctx context.Context, user *domain.User) error
    Delete(ctx context.Context, id string) error
}
```

### Position-based Ordering

```go
// Float positions for O(1) reorder
// Initial: 65536, 131072, 196608
// Insert between A and B: (A + B) / 2
// Rebalance when |A - B| < 1
```

### Activity Logging

```go
// Automatic activity log creation in services
activityService.Log(ctx, ActivityLogParams{
    BoardID:  boardID,
    CardID:   &cardID,
    UserID:   userID,
    Action:   "card_moved",
    Metadata: map[string]any{
        "from_list_id": fromListID,
        "to_list_id":   toListID,
    },
})
```

---

## Module Summary

| Module | Handlers | Services | Repositories |
|--------|:--------:|:--------:|:------------:|
| Auth | 10 | 1 | 3 (user, token, verification) |
| Organizations | 11 | 1 | 1 |
| Boards | 12 | 1 | 1 |
| Lists | 6 | 1 | 1 |
| Cards | 14 | 1 | 1 |
| Labels | 5 | 1 | 1 |
| Comments | 3 | 1 | 1 |
| Checklists | 7 | 1 | 1 |
| Attachments | 4 | 1 | 1 |
| Activity | 2 | 1 | 1 |
| Notifications | 6 | 1 | 1 |
| Invitations | 4 | 1 | 1 |
| **Total** | **~84** | **12** | **14** |

---

## Related Documentation

| File | Description |
|------|-------------|
| [PROJECT_DESCRIPTION.md](PROJECT_DESCRIPTION.md) | Project overview |
| [DATABASE_DESIGN.md](DATABASE_DESIGN.md) | PostgreSQL schema |
| [AUTH_FLOW.md](AUTH_FLOW.md) | Authentication details |
| [API_SPEC.md](API_SPEC.md) | OpenAPI specification |
| [FRONTEND_DESCRIPTION.md](FRONTEND_DESCRIPTION.md) | React frontend docs |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Production deployment |
