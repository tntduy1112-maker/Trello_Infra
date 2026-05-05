# Lesson 08: Middleware

> Learn how to implement authentication, rate limiting, and error handling middleware.

---

## What You'll Learn

1. What is middleware?
2. Authentication middleware (JWT)
3. Rate limiting middleware
4. Error handling middleware
5. How middleware chains work

---

## 1. What is Middleware?

Middleware is code that runs **before** (or after) your handlers.

```
HTTP Request
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│                         MIDDLEWARE                               │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────────────┐   │
│  │ Error Handler  │→ │  Rate Limit    │→ │ Authentication   │   │
│  └────────────────┘  └────────────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
    │
    ▼
Handler (your code)
    │
    ▼
HTTP Response
```

**Common uses:**
- Authentication (verify JWT token)
- Rate limiting (prevent abuse)
- Logging (log all requests)
- Error handling (catch panics)
- CORS (cross-origin requests)

---

## 2. Gin Middleware Basics

```go
// Middleware function signature
func MyMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        // Code BEFORE handler
        fmt.Println("Before handler")
        
        // Call next handler
        c.Next()
        
        // Code AFTER handler
        fmt.Println("After handler")
    }
}

// Using middleware
r := gin.New()
r.Use(MyMiddleware())          // Apply to all routes
r.GET("/test", handler)
```

---

## 3. Authentication Middleware

**File:** `Backend/internal/middleware/auth.go`

```go
package middleware

import (
    "strings"

    "github.com/gin-gonic/gin"

    "github.com/codewebkhongkho/trello-agent/internal/dto/response"
    "github.com/codewebkhongkho/trello-agent/internal/service"
    "github.com/codewebkhongkho/trello-agent/pkg/apperror"
    "github.com/codewebkhongkho/trello-agent/pkg/jwt"
)

const (
    AuthorizationHeader = "Authorization"
    BearerPrefix        = "Bearer "
    UserIDKey           = "user_id"
    UserEmailKey        = "user_email"
    JTIKey              = "jti"
)

func Auth(jwtManager *jwt.Manager, authService *service.AuthService) gin.HandlerFunc {
    return func(c *gin.Context) {
        var tokenString string

        // 1. Extract token from Authorization header
        authHeader := c.GetHeader(AuthorizationHeader)
        if authHeader != "" && strings.HasPrefix(authHeader, BearerPrefix) {
            tokenString = strings.TrimPrefix(authHeader, BearerPrefix)
        }

        // 2. Fallback to query parameter (for SSE/WebSocket)
        if tokenString == "" {
            tokenString = c.Query("token")
        }

        // 3. No token? Unauthorized
        if tokenString == "" {
            response.ErrorResponse(c, apperror.ErrUnauthorized)
            c.Abort()  // Stop processing
            return
        }

        // 4. Validate JWT signature and expiry
        claims, err := jwtManager.ValidateAccessToken(tokenString)
        if err != nil {
            if err == jwt.ErrTokenExpired {
                response.ErrorResponse(c, apperror.ErrTokenExpired)
            } else {
                response.ErrorResponse(c, apperror.ErrInvalidToken)
            }
            c.Abort()
            return
        }

        // 5. Check if token is blacklisted (logout)
        isBlacklisted, err := authService.IsTokenBlacklisted(c.Request.Context(), claims.ID)
        if err != nil {
            response.ErrorResponse(c, apperror.ErrInternal)
            c.Abort()
            return
        }
        if isBlacklisted {
            response.ErrorResponse(c, apperror.ErrTokenRevoked)
            c.Abort()
            return
        }

        // 6. Store user info in context for handlers
        c.Set(UserIDKey, claims.UserID)
        c.Set(UserEmailKey, claims.Email)
        c.Set(JTIKey, claims.ID)
        
        // 7. Continue to handler
        c.Next()
    }
}
```

### Getting User Info in Handlers

```go
// Helper functions
func GetUserID(c *gin.Context) string {
    userID, exists := c.Get(UserIDKey)
    if !exists {
        return ""
    }
    return userID.(string)
}

func GetUserEmail(c *gin.Context) string {
    email, exists := c.Get(UserEmailKey)
    if !exists {
        return ""
    }
    return email.(string)
}
```

**In handler:**

```go
func (h *AuthHandler) GetMe(c *gin.Context) {
    userID := middleware.GetUserID(c)  // Get from context
    if userID == "" {
        response.ErrorResponse(c, apperror.ErrUnauthorized)
        return
    }
    
    user, err := h.authService.GetCurrentUser(c.Request.Context(), userID)
    // ...
}
```

---

## 4. Rate Limiting Middleware

**File:** `Backend/internal/middleware/ratelimit.go`

```go
package middleware

import (
    "fmt"
    "time"

    "github.com/gin-gonic/gin"

    "github.com/codewebkhongkho/trello-agent/internal/dto/response"
    "github.com/codewebkhongkho/trello-agent/pkg/apperror"
    "github.com/codewebkhongkho/trello-agent/pkg/cache"
)

type RateLimitConfig struct {
    MaxRequests int           // Max requests allowed
    Window      time.Duration // Time window
    KeyPrefix   string        // Redis key prefix
}

func RateLimit(redisClient *cache.RedisClient, config RateLimitConfig) gin.HandlerFunc {
    return func(c *gin.Context) {
        // 1. Create unique key for this client + endpoint
        key := fmt.Sprintf("ratelimit:%s:%s", config.KeyPrefix, c.ClientIP())

        // 2. Increment counter in Redis
        count, err := redisClient.Incr(c.Request.Context(), key)
        if err != nil {
            // Redis error - allow request (fail open)
            c.Next()
            return
        }

        // 3. Set expiry on first request
        if count == 1 {
            _ = redisClient.Expire(c.Request.Context(), key, config.Window)
        }

        // 4. Check if over limit
        if count > int64(config.MaxRequests) {
            response.ErrorResponse(c, apperror.ErrTooManyRequests)
            c.Abort()
            return
        }

        // 5. Continue
        c.Next()
    }
}
```

### Using Rate Limit

**File:** `Backend/cmd/server/main.go`

```go
auth := api.Group("/auth")
{
    // 3 registrations per hour per IP
    auth.POST("/register",
        middleware.RateLimit(redisClient, middleware.RateLimitConfig{
            MaxRequests: 3,
            Window:      time.Hour,
            KeyPrefix:   "register",
        }),
        authHandler.Register,
    )

    // 50 login attempts per 15 minutes per IP
    auth.POST("/login",
        middleware.RateLimit(redisClient, middleware.RateLimitConfig{
            MaxRequests: 50,
            Window:      15 * time.Minute,
            KeyPrefix:   "login",
        }),
        authHandler.Login,
    )
}
```

**Rate Limits in Your Project:**

| Endpoint | Limit | Window |
|----------|:-----:|:------:|
| `/auth/register` | 3 | 1 hour |
| `/auth/login` | 50 | 15 min |
| `/auth/refresh` | 30 | 15 min |
| `/auth/verify-email` | 10 | 15 min |
| `/auth/forgot-password` | 5 | 15 min |

---

## 5. Error Handler Middleware

**File:** `Backend/internal/middleware/error_handler.go`

```go
package middleware

import (
    "net/http"

    "github.com/gin-gonic/gin"
    "github.com/go-playground/validator/v10"

    "github.com/codewebkhongkho/trello-agent/internal/dto/response"
)

func ErrorHandler() gin.HandlerFunc {
    return func(c *gin.Context) {
        // Execute handler first
        c.Next()

        // Check if there were any errors
        if len(c.Errors) == 0 {
            return
        }

        // Get the last error
        err := c.Errors.Last().Err

        // Handle validation errors
        if validationErrs, ok := err.(validator.ValidationErrors); ok {
            details := make([]gin.H, 0)
            for _, e := range validationErrs {
                details = append(details, gin.H{
                    "field":   e.Field(),
                    "message": formatValidationError(e),
                })
            }
            c.JSON(http.StatusUnprocessableEntity, response.Response{
                Success: false,
                Error: &response.Error{
                    Code:    "VALIDATION_ERROR",
                    Message: "Validation failed",
                    Details: details,
                },
            })
            return
        }

        // Handle other errors
        c.JSON(http.StatusInternalServerError, response.Response{
            Success: false,
            Error: &response.Error{
                Code:    "INTERNAL_ERROR",
                Message: "An unexpected error occurred",
            },
        })
    }
}

func formatValidationError(e validator.FieldError) string {
    switch e.Tag() {
    case "required":
        return "This field is required"
    case "email":
        return "Invalid email format"
    case "min":
        return fmt.Sprintf("Minimum length is %s", e.Param())
    case "max":
        return fmt.Sprintf("Maximum length is %s", e.Param())
    default:
        return "Invalid value"
    }
}
```

### How It Works

```go
// In handler - push error to Gin
func (h *AuthHandler) Register(c *gin.Context) {
    var req request.RegisterRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        _ = c.Error(err)  // Push error
        return            // Don't write response
    }
    // ...
}

// Error handler middleware picks it up
// and formats a proper response
```

---

## 6. Request Logger Middleware

**File:** `Backend/cmd/server/main.go`

```go
func requestLogger() gin.HandlerFunc {
    return func(c *gin.Context) {
        // Record start time
        start := time.Now()
        
        // Process request
        c.Next()
        
        // Log after request completes
        log.Info().
            Str("method", c.Request.Method).
            Str("path", c.Request.URL.Path).
            Int("status", c.Writer.Status()).
            Dur("latency", time.Since(start)).
            Msg("")
    }
}

// Usage
r := gin.New()
r.Use(gin.Recovery())     // Recover from panics
r.Use(requestLogger())    // Log all requests
r.Use(middleware.ErrorHandler())
```

---

## 7. Middleware Chains

Middleware executes in order:

```go
r := gin.New()

// Global middleware (all routes)
r.Use(gin.Recovery())
r.Use(requestLogger())
r.Use(middleware.ErrorHandler())

// Public routes (no auth)
public := r.Group("/api/v1")
{
    public.POST("/auth/login", authHandler.Login)
}

// Protected routes (auth required)
protected := r.Group("/api/v1")
protected.Use(middleware.Auth(jwtManager, authService))  // Auth middleware
{
    protected.GET("/auth/me", authHandler.GetMe)
}

// Rate limited routes
rateLimited := r.Group("/api/v1/auth")
rateLimited.Use(middleware.RateLimit(redis, config))
{
    rateLimited.POST("/register", authHandler.Register)
}
```

**Execution order for `POST /api/v1/auth/register`:**

1. `gin.Recovery()` — Catch panics
2. `requestLogger()` — Log request
3. `middleware.ErrorHandler()` — Handle errors
4. `middleware.RateLimit()` — Check rate limit
5. `authHandler.Register` — Actual handler

---

## 8. Optional Auth Middleware

For routes that work with or without authentication:

```go
func OptionalAuth(jwtManager *jwt.Manager, authService *service.AuthService) gin.HandlerFunc {
    return func(c *gin.Context) {
        authHeader := c.GetHeader(AuthorizationHeader)
        
        // No token? That's okay, continue
        if authHeader == "" {
            c.Next()
            return
        }

        // Has token? Validate it
        if !strings.HasPrefix(authHeader, BearerPrefix) {
            c.Next()
            return
        }

        tokenString := strings.TrimPrefix(authHeader, BearerPrefix)
        claims, err := jwtManager.ValidateAccessToken(tokenString)
        if err != nil {
            c.Next()  // Invalid token, but continue anyway
            return
        }

        // Valid token - set user info
        c.Set(UserIDKey, claims.UserID)
        c.Set(UserEmailKey, claims.Email)
        c.Next()
    }
}
```

---

## 9. CORS Middleware

**File:** `Backend/cmd/server/main.go`

```go
import "github.com/gin-contrib/cors"

r.Use(cors.New(cors.Config{
    AllowOrigins:     []string{
        "http://localhost:5173",  // Vite dev server
        "http://localhost:3000",  // Create React App
        cfg.App.URL,              // Production URL
    },
    AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
    AllowHeaders:     []string{"Origin", "Content-Type", "Accept", "Authorization"},
    ExposeHeaders:    []string{"Content-Length"},
    AllowCredentials: true,
    MaxAge:           12 * time.Hour,
}))
```

---

## 10. Custom Middleware Pattern

```go
// Middleware that requires configuration
func RequireRole(roles ...string) gin.HandlerFunc {
    return func(c *gin.Context) {
        userRole := c.GetString("user_role")
        
        for _, role := range roles {
            if userRole == role {
                c.Next()
                return
            }
        }
        
        response.ErrorResponse(c, apperror.ErrForbidden)
        c.Abort()
    }
}

// Usage
admin := r.Group("/admin")
admin.Use(middleware.Auth(jwtManager, authService))
admin.Use(middleware.RequireRole("admin", "superadmin"))
{
    admin.DELETE("/users/:id", adminHandler.DeleteUser)
}
```

---

## Practice Exercises

### Exercise 1: Request ID Middleware

Create middleware that:
- Generates a unique request ID
- Adds it to response headers
- Makes it available to handlers

### Exercise 2: Timing Middleware

Create middleware that:
- Measures handler execution time
- Adds `X-Response-Time` header to response

---

## External Resources

| Resource | URL | Description |
|----------|-----|-------------|
| Gin Middleware | https://gin-gonic.com/docs/examples/custom-middleware/ | Official docs |
| JWT Best Practices | https://auth0.com/blog/jwt-handbook/ | Security guide |

---

## Key Takeaways

1. **Middleware = pre/post processing** — Runs before and after handlers
2. **`c.Next()`** — Continues to next middleware/handler
3. **`c.Abort()`** — Stops chain, returns immediately
4. **`c.Set()`/`c.Get()`** — Pass data to handlers
5. **Order matters** — Middleware executes in registration order
6. **Fail open** — Rate limiting should allow if Redis fails

---

## Next Lesson

Continue to **[Lesson 09: PostgreSQL & Migrations](09_DATABASE_POSTGRESQL.md)** to learn about database design.
