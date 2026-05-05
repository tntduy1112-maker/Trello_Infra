# Lesson 07: Handlers & REST API

> Learn how to handle HTTP requests and build REST APIs with Gin.

---

## What You'll Learn

1. What are handlers?
2. Gin framework basics
3. Request parsing and validation
4. Response formatting
5. Routing and URL patterns
6. REST API conventions

---

## 1. What are Handlers?

Handlers are functions that **receive HTTP requests and return HTTP responses**.

```
HTTP Request
    │
    ▼
Handler ← YOU ARE HERE
    │
    ├── Parse request body
    ├── Validate input
    ├── Call service
    ├── Format response
    │
    ▼
HTTP Response
```

**Handler responsibilities:**
- Parse incoming JSON/form data
- Validate input format
- Call service methods
- Return appropriate HTTP status and response

**NOT handler responsibilities:**
- Business logic (that's in service)
- Database queries (that's in repository)

---

## 2. Handler Structure

**File:** `Backend/internal/handler/auth_handler.go`

```go
package handler

import (
    "net/http"

    "github.com/gin-gonic/gin"

    "github.com/codewebkhongkho/trello-agent/internal/dto/request"
    "github.com/codewebkhongkho/trello-agent/internal/dto/response"
    "github.com/codewebkhongkho/trello-agent/internal/service"
    "github.com/codewebkhongkho/trello-agent/pkg/apperror"
)

// Handler struct with service dependency
type AuthHandler struct {
    authService *service.AuthService
}

// Constructor
func NewAuthHandler(authService *service.AuthService) *AuthHandler {
    return &AuthHandler{authService: authService}
}
```

---

## 3. Parsing Request Body

### JSON Body

```go
func (h *AuthHandler) Register(c *gin.Context) {
    // Step 1: Parse JSON into struct
    var req request.RegisterRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        _ = c.Error(err)  // Let error middleware handle it
        return
    }

    // Step 2: Call service
    user, err := h.authService.Register(c.Request.Context(), &req)
    if err != nil {
        // Handle error (explained below)
    }

    // Step 3: Return response
    response.Success(c, http.StatusCreated, gin.H{
        "user":    user,
        "message": "Registration successful",
    })
}
```

### Request DTO with Validation

**File:** `Backend/internal/dto/request/auth_request.go`

```go
type RegisterRequest struct {
    Email    string `json:"email" binding:"required,email,max=255"`
    Password string `json:"password" binding:"required,min=8,max=128"`
    FullName string `json:"full_name" binding:"required,min=2,max=255"`
}
```

**Validation Tags:**

| Tag | Meaning |
|-----|---------|
| `binding:"required"` | Field must be present |
| `binding:"email"` | Must be valid email format |
| `binding:"min=8"` | Minimum length 8 |
| `binding:"max=255"` | Maximum length 255 |
| `binding:"omitempty"` | Validate only if present |

**If validation fails:** `c.ShouldBindJSON` returns an error.

---

## 4. URL Parameters and Query Strings

### URL Parameters

```go
// Route: /api/v1/users/:id
func (h *UserHandler) GetByID(c *gin.Context) {
    id := c.Param("id")  // Get :id from URL
    
    user, err := h.userService.GetByID(c.Request.Context(), id)
    // ...
}
```

### Query Parameters

```go
// URL: /api/v1/users?page=1&limit=20&search=john
func (h *UserHandler) List(c *gin.Context) {
    page := c.DefaultQuery("page", "1")      // Default if not provided
    limit := c.DefaultQuery("limit", "20")
    search := c.Query("search")               // Empty if not provided
    
    // Convert to int
    pageInt, _ := strconv.Atoi(page)
    limitInt, _ := strconv.Atoi(limit)
    
    users, err := h.userService.List(c.Request.Context(), pageInt, limitInt, search)
    // ...
}
```

---

## 5. Error Handling

### Pattern in Handlers

```go
func (h *AuthHandler) Login(c *gin.Context) {
    var req request.LoginRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        _ = c.Error(err)  // Validation error
        return
    }

    authResp, err := h.authService.Login(c.Request.Context(), &req, deviceInfo, ipAddress)
    if err != nil {
        // Check if it's our custom AppError
        if appErr, ok := err.(*apperror.AppError); ok {
            response.ErrorResponse(c, appErr)  // Return with proper status
            return
        }
        // Unknown error
        _ = c.Error(err)
        return
    }

    response.Success(c, http.StatusOK, authResp)
}
```

### Response Helper Functions

**File:** `Backend/internal/dto/response/response.go`

```go
package response

import (
    "github.com/gin-gonic/gin"
    "github.com/codewebkhongkho/trello-agent/pkg/apperror"
)

// Standard response structure
type Response struct {
    Success bool   `json:"success"`
    Data    any    `json:"data,omitempty"`
    Error   *Error `json:"error,omitempty"`
    Message string `json:"message,omitempty"`
}

type Error struct {
    Code    string `json:"code"`
    Message string `json:"message"`
    Details any    `json:"details,omitempty"`
}

// Success response
func Success(c *gin.Context, statusCode int, data any) {
    c.JSON(statusCode, Response{
        Success: true,
        Data:    data,
    })
}

// Success with message only
func SuccessMessage(c *gin.Context, statusCode int, message string) {
    c.JSON(statusCode, Response{
        Success: true,
        Message: message,
    })
}

// Error response
func ErrorResponse(c *gin.Context, err *apperror.AppError) {
    c.JSON(err.StatusCode, Response{
        Success: false,
        Error: &Error{
            Code:    err.Code,
            Message: err.Message,
            Details: err.Details,
        },
    })
}
```

---

## 6. Complete Handler Example

**File:** `Backend/internal/handler/auth_handler.go`

```go
func (h *AuthHandler) Register(c *gin.Context) {
    // 1. Parse and validate request
    var req request.RegisterRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        _ = c.Error(err)
        return
    }

    // 2. Call service (all business logic is there)
    user, err := h.authService.Register(c.Request.Context(), &req)
    if err != nil {
        if appErr, ok := err.(*apperror.AppError); ok {
            response.ErrorResponse(c, appErr)
            return
        }
        _ = c.Error(err)
        return
    }

    // 3. Return success response
    response.Success(c, http.StatusCreated, gin.H{
        "user":    user,
        "message": "Registration successful. Please check your email for verification code.",
    })
}

func (h *AuthHandler) Login(c *gin.Context) {
    var req request.LoginRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        _ = c.Error(err)
        return
    }

    // Get device info from headers
    deviceInfo := c.GetHeader("User-Agent")
    ipAddress := c.ClientIP()

    authResp, err := h.authService.Login(c.Request.Context(), &req, deviceInfo, ipAddress)
    if err != nil {
        if appErr, ok := err.(*apperror.AppError); ok {
            response.ErrorResponse(c, appErr)
            return
        }
        _ = c.Error(err)
        return
    }

    response.Success(c, http.StatusOK, authResp)
}

func (h *AuthHandler) GetMe(c *gin.Context) {
    // Get user ID from context (set by auth middleware)
    userID := middleware.GetUserID(c)
    if userID == "" {
        response.ErrorResponse(c, apperror.ErrUnauthorized)
        return
    }

    user, err := h.authService.GetCurrentUser(c.Request.Context(), userID)
    if err != nil {
        if appErr, ok := err.(*apperror.AppError); ok {
            response.ErrorResponse(c, appErr)
            return
        }
        _ = c.Error(err)
        return
    }

    response.Success(c, http.StatusOK, user)
}
```

---

## 7. Routing

**File:** `Backend/cmd/server/main.go`

```go
func main() {
    // Create Gin router
    r := gin.New()
    r.Use(gin.Recovery())
    r.Use(middleware.ErrorHandler())

    // API version group
    api := r.Group("/api/v1")
    {
        // Auth routes (no auth required)
        auth := api.Group("/auth")
        {
            auth.POST("/register", authHandler.Register)
            auth.POST("/login", authHandler.Login)
            auth.POST("/verify-email", authHandler.VerifyEmail)
            auth.POST("/refresh", authHandler.Refresh)
            auth.POST("/logout", authHandler.Logout)
        }

        // Protected routes (auth required)
        protected := api.Group("")
        protected.Use(middleware.Auth(jwtManager, authService))
        {
            // User profile
            protected.GET("/auth/me", authHandler.GetMe)
            protected.PUT("/auth/me", authHandler.UpdateMe)

            // Organizations
            orgs := protected.Group("/organizations")
            {
                orgs.POST("", orgHandler.Create)
                orgs.GET("", orgHandler.List)
                orgs.GET("/:slug", orgHandler.GetBySlug)
                orgs.PUT("/:slug", orgHandler.Update)
                orgs.DELETE("/:slug", orgHandler.Delete)
            }

            // Boards
            boards := protected.Group("/boards")
            {
                boards.GET("/:id", boardHandler.GetByID)
                boards.PUT("/:id", boardHandler.Update)
                boards.DELETE("/:id", boardHandler.Delete)
            }
        }
    }

    r.Run(":8080")
}
```

---

## 8. REST API Conventions

### HTTP Methods

| Method | Purpose | Example |
|--------|---------|---------|
| GET | Read resource | `GET /users/123` |
| POST | Create resource | `POST /users` |
| PUT | Replace resource | `PUT /users/123` |
| PATCH | Partial update | `PATCH /users/123` |
| DELETE | Delete resource | `DELETE /users/123` |

### URL Patterns

```
# Collection
GET    /api/v1/boards           # List all boards
POST   /api/v1/boards           # Create board

# Single resource
GET    /api/v1/boards/:id       # Get board
PUT    /api/v1/boards/:id       # Update board
DELETE /api/v1/boards/:id       # Delete board

# Nested resources
GET    /api/v1/boards/:id/lists           # Lists in board
POST   /api/v1/boards/:id/lists           # Create list in board

# Actions (when CRUD doesn't fit)
POST   /api/v1/boards/:id/close           # Close board
POST   /api/v1/boards/:id/reopen          # Reopen board
POST   /api/v1/cards/:id/archive          # Archive card
```

### HTTP Status Codes

| Code | Meaning | When to Use |
|:----:|---------|-------------|
| 200 | OK | Successful GET, PUT, PATCH |
| 201 | Created | Successful POST |
| 204 | No Content | Successful DELETE |
| 400 | Bad Request | Invalid request format |
| 401 | Unauthorized | Not logged in |
| 403 | Forbidden | No permission |
| 404 | Not Found | Resource doesn't exist |
| 409 | Conflict | Resource already exists |
| 422 | Unprocessable Entity | Validation failed |
| 429 | Too Many Requests | Rate limited |
| 500 | Internal Server Error | Server error |

---

## 9. Response Format

### Success Response

```json
{
  "success": true,
  "data": {
    "id": "abc123",
    "email": "user@example.com",
    "full_name": "John Doe"
  }
}
```

### Error Response

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Email is required",
    "details": [
      {"field": "email", "message": "required"}
    ]
  }
}
```

### Paginated Response

```json
{
  "success": true,
  "data": [
    {"id": "1", "title": "Board 1"},
    {"id": "2", "title": "Board 2"}
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 100,
    "total_pages": 5
  }
}
```

---

## 10. Headers

### Request Headers

```go
func (h *AuthHandler) Login(c *gin.Context) {
    // Get header value
    userAgent := c.GetHeader("User-Agent")
    authorization := c.GetHeader("Authorization")
    
    // Get client IP
    clientIP := c.ClientIP()
}
```

### Response Headers

```go
func (h *Handler) Export(c *gin.Context) {
    c.Header("Content-Type", "application/csv")
    c.Header("Content-Disposition", "attachment; filename=export.csv")
}
```

---

## Practice Exercises

### Exercise 1: Add Search

Add search functionality to board list:
- Accept `?search=keyword` query parameter
- Pass to service layer

### Exercise 2: Add Sorting

Add sorting to user list:
- Accept `?sortBy=created_at&order=desc`
- Validate allowed sort fields

---

## External Resources

| Resource | URL | Description |
|----------|-----|-------------|
| Gin Documentation | https://gin-gonic.com/docs/ | Official docs |
| REST API Design | https://restfulapi.net | Best practices |
| HTTP Status Codes | https://httpstatuses.com | All codes explained |

---

## Key Takeaways

1. **Handlers = HTTP boundary** — Parse request, return response
2. **No business logic** — Just call service methods
3. **Validate input** — Use binding tags on request structs
4. **Consistent responses** — Use helper functions
5. **Proper status codes** — Match code to situation
6. **RESTful patterns** — Use HTTP methods correctly

---

## Next Lesson

Continue to **[Lesson 08: Middleware](08_MIDDLEWARE.md)** to learn about authentication and rate limiting.
