# Lesson 02: Go Project Structure

> Learn how to organize a professional Go project based on your TaskFlow codebase.

---

## What You'll Learn

1. Standard Go project layout
2. The `cmd`, `internal`, and `pkg` directories
3. How your TaskFlow project is organized
4. Naming conventions and best practices

---

## 1. Standard Go Project Layout

Go has a community-standard way to organize projects:

```
project/
├── cmd/                    # Main applications
│   └── server/
│       └── main.go         # Entry point
│
├── internal/               # Private code (cannot be imported by other projects)
│   ├── config/             # Configuration
│   ├── domain/             # Business entities
│   ├── dto/                # Data Transfer Objects
│   ├── handler/            # HTTP handlers
│   ├── middleware/         # HTTP middleware
│   ├── repository/         # Data access
│   └── service/            # Business logic
│
├── pkg/                    # Public code (can be imported by other projects)
│   ├── apperror/           # Error handling
│   ├── cache/              # Redis client
│   ├── database/           # Database connection
│   └── jwt/                # JWT utilities
│
├── migrations/             # Database migrations
├── docs/                   # Documentation
├── go.mod                  # Go module definition
├── go.sum                  # Dependency checksums
└── Dockerfile              # Container build
```

---

## 2. Understanding Each Directory

### `cmd/` — Application Entry Points

Contains the `main.go` files — the starting points of your applications.

**File:** `Backend/cmd/server/main.go`

```go
package main

import (
    // imports...
)

func main() {
    // 1. Load configuration
    cfg, err := config.Load()
    
    // 2. Connect to databases
    db, err := database.NewPostgresPool(cfg.Database)
    redisClient, err := cache.NewRedisClient(cfg.Redis)
    
    // 3. Create repositories
    userRepo := repository.NewUserRepository(db)
    
    // 4. Create services
    authService := service.NewAuthService(...)
    
    // 5. Create handlers
    authHandler := handler.NewAuthHandler(authService)
    
    // 6. Setup routes
    r := gin.New()
    r.POST("/api/v1/auth/register", authHandler.Register)
    
    // 7. Start server
    srv.ListenAndServe()
}
```

**Key insight:** `main.go` is responsible for:
- Loading configuration
- Creating dependencies (dependency injection)
- Wiring everything together
- Starting the server

---

### `internal/` — Private Application Code

The `internal` directory is **special in Go**. Code here CANNOT be imported by other projects.

```
internal/
├── config/         # Configuration loading
├── domain/         # Business entities (User, Board, Card)
├── dto/            # Request/Response objects
│   ├── request/    # Input validation structs
│   └── response/   # API response structs
├── handler/        # HTTP request handlers
├── middleware/     # Auth, rate limiting, error handling
├── repository/     # Database operations
└── service/        # Business logic
```

#### Why `internal`?

- **Encapsulation**: Forces other packages to use public APIs
- **Refactoring freedom**: You can change internal code without breaking other projects
- **Clear boundaries**: Public vs private code is obvious

---

### `pkg/` — Reusable Packages

Code in `pkg/` can be imported by other projects. Put utilities here.

**Your TaskFlow pkg structure:**

```
pkg/
├── apperror/      # Custom error types
├── cache/         # Redis client wrapper
├── crypto/        # AES encryption
├── cuid/          # CUID ID generation
├── database/      # PostgreSQL connection
├── email/         # SMTP email service
├── hash/          # bcrypt password hashing
├── jwt/           # JWT token management
├── position/      # Float position for drag & drop
├── storage/       # MinIO file storage
└── validator/     # Input validation
```

**Example:** `pkg/cuid/cuid.go`

```go
package cuid

import "github.com/nrednav/cuid2"

func New() string {
    return cuid2.Generate()
}
```

This can be used anywhere:
```go
import "github.com/yourproject/pkg/cuid"

userID := cuid.New()  // "cjld2cjxh0000qzrmn831i7rn"
```

---

## 3. Your TaskFlow Project Structure

```
Backend/
├── cmd/
│   └── server/
│       ├── main.go           ← START HERE
│       └── swagger.yaml
│
├── internal/
│   ├── config/
│   │   └── config.go         ← Configuration
│   │
│   ├── domain/               ← Business Entities
│   │   ├── user.go
│   │   ├── board.go
│   │   ├── card.go
│   │   └── ...
│   │
│   ├── dto/
│   │   ├── request/          ← Input validation
│   │   │   ├── auth_request.go
│   │   │   ├── board_request.go
│   │   │   └── ...
│   │   └── response/         ← API responses
│   │       ├── response.go
│   │       ├── auth_response.go
│   │       └── ...
│   │
│   ├── handler/              ← HTTP Handlers
│   │   ├── auth_handler.go
│   │   ├── board_handler.go
│   │   └── ...
│   │
│   ├── middleware/           ← Middleware
│   │   ├── auth.go
│   │   ├── ratelimit.go
│   │   └── error_handler.go
│   │
│   ├── repository/           ← Data Access
│   │   ├── interfaces.go
│   │   ├── user_repository.go
│   │   └── ...
│   │
│   └── service/              ← Business Logic
│       ├── auth_service.go
│       ├── board_service.go
│       └── ...
│
├── pkg/                      ← Reusable Utilities
│   ├── apperror/
│   ├── cache/
│   ├── jwt/
│   └── ...
│
├── migrations/               ← Database Migrations
│   ├── 00001_create_users.sql
│   ├── 00002_create_refresh_tokens.sql
│   └── ...
│
├── docs/
│   └── swagger.yaml
│
├── go.mod
├── go.sum
└── Dockerfile
```

---

## 4. File Naming Conventions

### Go Files

| Pattern | Example | Use For |
|---------|---------|---------|
| `noun.go` | `user.go` | Domain models |
| `noun_repository.go` | `user_repository.go` | Repository implementations |
| `noun_service.go` | `auth_service.go` | Service implementations |
| `noun_handler.go` | `auth_handler.go` | HTTP handlers |
| `noun_request.go` | `auth_request.go` | Request DTOs |
| `noun_response.go` | `auth_response.go` | Response DTOs |

### Database Migrations

```
00001_create_users.sql
00002_create_refresh_tokens.sql
00003_create_email_verifications.sql
```

- Numbered prefix ensures order
- Descriptive name explains what it does
- `.sql` extension for SQL files

---

## 5. Package Naming

### Rules

1. **Lowercase only**: `package handler` not `package Handler`
2. **Short and concise**: `package auth` not `package authentication`
3. **No underscores**: `package userrepo` not `package user_repo`
4. **Singular**: `package user` not `package users`

### Examples from Your Project

```go
package main        // Entry point
package config      // Configuration
package domain      // Business entities
package handler     // HTTP handlers
package service     // Business logic
package repository  // Data access
package middleware  // HTTP middleware
package cache       // Redis utilities
package jwt         // JWT utilities
```

---

## 6. Import Paths

### Your Module Path

**File:** `Backend/go.mod`

```go
module github.com/codewebkhongkho/trello-agent
```

This is your module's **base path**. All imports are relative to this.

### Import Examples

```go
import (
    // Standard library (no prefix)
    "context"
    "net/http"
    
    // External packages (full GitHub path)
    "github.com/gin-gonic/gin"
    
    // Your internal packages
    "github.com/codewebkhongkho/trello-agent/internal/handler"
    "github.com/codewebkhongkho/trello-agent/internal/service"
    "github.com/codewebkhongkho/trello-agent/pkg/jwt"
)
```

---

## 7. The Request Flow

Understanding how a request flows through your project structure:

```
HTTP Request: POST /api/v1/auth/login
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│  cmd/server/main.go                                              │
│  Routes the request to the appropriate handler                   │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│  internal/middleware/auth.go                                     │
│  Rate limiting, authentication checks                            │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│  internal/handler/auth_handler.go                                │
│  - Parses request body into dto/request/auth_request.go         │
│  - Calls service method                                          │
│  - Returns response using dto/response/auth_response.go         │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│  internal/service/auth_service.go                                │
│  - Business logic (validation, rules)                            │
│  - Calls repository methods                                      │
│  - Returns domain objects                                        │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│  internal/repository/user_repository.go                          │
│  - SQL queries                                                   │
│  - Maps database rows to internal/domain/user.go                 │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│  PostgreSQL Database                                             │
└──────────────────────────────────────────────────────────────────┘
```

---

## 8. Best Practices

### Do's

1. **Keep `main.go` minimal** — Only initialization and wiring
2. **Use `internal/` for business code** — Protects your implementation
3. **Put reusable utilities in `pkg/`** — Can be shared across projects
4. **One package per directory** — Go rule
5. **Group related files** — `auth_handler.go`, `auth_service.go`, `auth_request.go`

### Don'ts

1. **Don't put business logic in `cmd/`** — Keep it clean
2. **Don't import `internal/` from `pkg/`** — Dependency direction matters
3. **Don't use circular imports** — Go doesn't allow them
4. **Don't create too many small packages** — Group related code

---

## Practice Exercises

### Exercise 1: Trace a Request

Follow a login request through the codebase:
1. Find the route definition in `main.go`
2. Find the handler in `auth_handler.go`
3. Find the service method in `auth_service.go`
4. Find the repository method in `user_repository.go`

### Exercise 2: Create a New Feature

If you wanted to add "Teams" functionality, which files would you create?
- Domain model: `internal/domain/team.go`
- Repository: `internal/repository/team_repository.go`
- Service: `internal/service/team_service.go`
- Handler: `internal/handler/team_handler.go`
- Request DTO: `internal/dto/request/team_request.go`
- Response DTO: `internal/dto/response/team_response.go`

---

## External Resources

| Resource | URL | Description |
|----------|-----|-------------|
| Go Project Layout | https://github.com/golang-standards/project-layout | Standard layout |
| Package Naming | https://go.dev/blog/package-names | Official guidelines |
| Organizing Go Code | https://go.dev/doc/code | How to organize |

---

## Key Takeaways

1. **`cmd/`** — Contains `main.go`, entry point only
2. **`internal/`** — Private code, cannot be imported externally
3. **`pkg/`** — Public reusable utilities
4. **Layered structure** — handler → service → repository
5. **Clear separation** — Each layer has one responsibility

---

## Next Lesson

Continue to **[Lesson 03: Clean Architecture](03_CLEAN_ARCHITECTURE.md)** to understand the layered architecture pattern.
