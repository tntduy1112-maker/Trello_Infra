# Lesson 03: Clean Architecture

> Learn the layered architecture pattern used in your TaskFlow project.

---

## What You'll Learn

1. What is Clean Architecture?
2. The layers: Handler → Service → Repository
3. Dependency direction
4. How this applies to your project

---

## 1. What is Clean Architecture?

Clean Architecture is a way to organize code so that:

- **Business logic is independent** of frameworks, databases, and UI
- **Code is testable** — each layer can be tested in isolation
- **Code is maintainable** — changes in one layer don't break others

### The Core Idea

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│    "The inner layers should NOT know about the outer layers"                │
│                                                                             │
│    Domain ← Service ← Repository ← Handler ← HTTP Framework                │
│                                                                             │
│    (Business rules don't care about databases or web frameworks)           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. The Layers in Your Project

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         HTTP Request (Gin Framework)                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  HANDLER LAYER (internal/handler/)                                          │
│  ─────────────────────────────────                                          │
│  • Receives HTTP requests                                                   │
│  • Validates input (using DTOs)                                             │
│  • Calls service methods                                                    │
│  • Returns HTTP responses                                                   │
│                                                                             │
│  Files: auth_handler.go, board_handler.go, card_handler.go                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  SERVICE LAYER (internal/service/)                                          │
│  ─────────────────────────────────                                          │
│  • Contains business logic                                                  │
│  • Orchestrates operations                                                  │
│  • Enforces business rules                                                  │
│  • Doesn't know about HTTP                                                  │
│                                                                             │
│  Files: auth_service.go, board_service.go, card_service.go                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  REPOSITORY LAYER (internal/repository/)                                    │
│  ───────────────────────────────────────                                    │
│  • Handles data persistence                                                 │
│  • SQL queries                                                              │
│  • Maps database rows to domain objects                                     │
│  • Doesn't know about business rules                                        │
│                                                                             │
│  Files: user_repository.go, board_repository.go, card_repository.go        │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  DOMAIN LAYER (internal/domain/)                                            │
│  ───────────────────────────────                                            │
│  • Pure business entities                                                   │
│  • No dependencies on anything                                              │
│  • Just data structures and validation                                      │
│                                                                             │
│  Files: user.go, board.go, card.go                                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              PostgreSQL Database                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Layer Responsibilities

### Layer 1: Domain (internal/domain/)

**Responsibility:** Define business entities

**File:** `Backend/internal/domain/user.go`

```go
package domain

type User struct {
    ID           string     `json:"id"`
    Email        string     `json:"email"`
    PasswordHash string     `json:"-"`
    FullName     string     `json:"full_name"`
    IsVerified   bool       `json:"is_verified"`
    IsActive     bool       `json:"is_active"`
    CreatedAt    time.Time  `json:"created_at"`
}

func (u *User) IsDeleted() bool {
    return u.DeletedAt != nil
}
```

**Rules:**
- NO imports from other layers
- Pure data structures
- Simple validation methods

---

### Layer 2: Repository (internal/repository/)

**Responsibility:** Data access (CRUD operations)

**File:** `Backend/internal/repository/user_repository.go`

```go
package repository

type userRepository struct {
    db *pgxpool.Pool
}

func NewUserRepository(db *pgxpool.Pool) UserRepository {
    return &userRepository{db: db}
}

func (r *userRepository) Create(ctx context.Context, user *domain.User) error {
    if user.ID == "" {
        user.ID = cuid.New()
    }
    
    query := `
        INSERT INTO users (id, email, password_hash, full_name, is_verified, is_active)
        VALUES ($1, $2, $3, $4, $5, $6)
    `
    _, err := r.db.Exec(ctx, query,
        user.ID,
        user.Email,
        user.PasswordHash,
        user.FullName,
        user.IsVerified,
        user.IsActive,
    )
    return err
}

func (r *userRepository) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
    query := `SELECT id, email, ... FROM users WHERE email = $1`
    // Execute query and map to domain.User
}
```

**Rules:**
- Only knows about database and domain models
- NO business logic
- Returns domain objects
- Uses interfaces for abstraction

---

### Layer 3: Service (internal/service/)

**Responsibility:** Business logic and orchestration

**File:** `Backend/internal/service/auth_service.go`

```go
package service

type AuthService struct {
    userRepo    repository.UserRepository   // Uses interface, not concrete type
    tokenRepo   repository.TokenRepository
    jwtManager  *jwt.Manager
    emailService *email.Service
}

func (s *AuthService) Register(ctx context.Context, req *request.RegisterRequest) (*response.UserResponse, error) {
    // BUSINESS RULE: Check if email already exists
    existingUser, err := s.userRepo.FindByEmail(ctx, req.Email)
    if err != nil {
        return nil, apperror.Wrap(err, apperror.ErrInternal)
    }
    if existingUser != nil {
        return nil, apperror.ErrEmailAlreadyExists  // Business rule violation
    }

    // BUSINESS RULE: Hash the password
    passwordHash, err := hash.HashPassword(req.Password)
    if err != nil {
        return nil, apperror.Wrap(err, apperror.ErrInternal)
    }

    // Create user
    user := &domain.User{
        Email:        req.Email,
        PasswordHash: passwordHash,
        FullName:     req.FullName,
        IsVerified:   false,
        IsActive:     true,
    }

    // BUSINESS RULE: Save to database
    if err := s.userRepo.Create(ctx, user); err != nil {
        return nil, apperror.Wrap(err, apperror.ErrInternal)
    }

    // BUSINESS RULE: Send verification email
    if err := s.sendVerificationOTP(ctx, user); err != nil {
        return nil, err
    }

    return response.ToUserResponse(user), nil
}
```

**Rules:**
- Contains ALL business logic
- Uses repository interfaces (not implementations)
- Orchestrates multiple operations
- NO HTTP knowledge (doesn't use `gin.Context`)

---

### Layer 4: Handler (internal/handler/)

**Responsibility:** HTTP request/response handling

**File:** `Backend/internal/handler/auth_handler.go`

```go
package handler

type AuthHandler struct {
    authService *service.AuthService
}

func NewAuthHandler(authService *service.AuthService) *AuthHandler {
    return &AuthHandler{authService: authService}
}

func (h *AuthHandler) Register(c *gin.Context) {
    // 1. Parse and validate request
    var req request.RegisterRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        _ = c.Error(err)
        return
    }

    // 2. Call service (NO business logic here!)
    user, err := h.authService.Register(c.Request.Context(), &req)
    if err != nil {
        if appErr, ok := err.(*apperror.AppError); ok {
            response.ErrorResponse(c, appErr)
            return
        }
        _ = c.Error(err)
        return
    }

    // 3. Return response
    response.Success(c, http.StatusCreated, gin.H{
        "user":    user,
        "message": "Registration successful. Please check your email.",
    })
}
```

**Rules:**
- Only HTTP concerns (parse request, return response)
- NO business logic
- Calls service methods
- Handles HTTP status codes and response format

---

## 4. Why This Structure?

### Benefit 1: Testability

Each layer can be tested independently:

```go
// Test service with mock repository
mockRepo := &MockUserRepository{}
service := NewAuthService(mockRepo, ...)
result, err := service.Register(ctx, request)
```

### Benefit 2: Flexibility

You can swap implementations without changing code:

```go
// Current: PostgreSQL
userRepo := repository.NewUserRepository(pgPool)

// Future: Could be MongoDB, Redis, or any database
userRepo := repository.NewMongoUserRepository(mongoClient)

// Service doesn't change!
authService := service.NewAuthService(userRepo, ...)
```

### Benefit 3: Maintainability

- Handler changes don't affect business logic
- Database changes don't affect HTTP responses
- Business rules are in one place

---

## 5. Dependency Injection

Dependencies are "injected" from the outside, not created inside.

**File:** `Backend/cmd/server/main.go`

```go
func main() {
    // 1. Create infrastructure
    db, _ := database.NewPostgresPool(cfg.Database)
    redisClient, _ := cache.NewRedisClient(cfg.Redis)

    // 2. Create repositories (data layer)
    userRepo := repository.NewUserRepository(db)
    tokenRepo := repository.NewTokenRepository(db)

    // 3. Create services (business layer)
    authService := service.NewAuthService(service.AuthServiceConfig{
        UserRepo:     userRepo,       // Inject repository
        TokenRepo:    tokenRepo,      // Inject repository
        JWTManager:   jwtManager,     // Inject utility
        EmailService: emailService,   // Inject utility
    })

    // 4. Create handlers (HTTP layer)
    authHandler := handler.NewAuthHandler(authService)  // Inject service

    // 5. Setup routes
    r.POST("/api/v1/auth/register", authHandler.Register)
}
```

**Why Dependency Injection?**
- **Testability**: Pass mock dependencies for testing
- **Flexibility**: Easy to swap implementations
- **Clarity**: Dependencies are explicit, not hidden

---

## 6. The Interface Pattern

Interfaces allow layers to depend on abstractions, not implementations.

**File:** `Backend/internal/repository/interfaces.go`

```go
package repository

type UserRepository interface {
    Create(ctx context.Context, user *domain.User) error
    FindByID(ctx context.Context, id string) (*domain.User, error)
    FindByEmail(ctx context.Context, email string) (*domain.User, error)
    Update(ctx context.Context, user *domain.User) error
    SoftDelete(ctx context.Context, id string) error
}
```

**Service uses the interface:**

```go
type AuthService struct {
    userRepo UserRepository  // Interface, not *userRepository
}
```

**Benefits:**
1. Service doesn't know if it's PostgreSQL, MongoDB, or a mock
2. Can easily switch implementations
3. Testing is straightforward

---

## 7. Data Transfer Objects (DTOs)

DTOs separate external API format from internal domain models.

### Request DTO

**File:** `Backend/internal/dto/request/auth_request.go`

```go
type RegisterRequest struct {
    Email    string `json:"email" binding:"required,email,max=255"`
    Password string `json:"password" binding:"required,min=8,max=128"`
    FullName string `json:"full_name" binding:"required,min=2,max=255"`
}
```

### Response DTO

**File:** `Backend/internal/dto/response/auth_response.go`

```go
type UserResponse struct {
    ID         string    `json:"id"`
    Email      string    `json:"email"`
    FullName   string    `json:"full_name"`
    IsVerified bool      `json:"is_verified"`
    CreatedAt  time.Time `json:"created_at"`
}

func ToUserResponse(user *domain.User) *UserResponse {
    return &UserResponse{
        ID:         user.ID,
        Email:      user.Email,
        FullName:   user.FullName,
        IsVerified: user.IsVerified,
        CreatedAt:  user.CreatedAt,
    }
}
```

**Why DTOs?**
- **Security**: Don't expose internal fields (like PasswordHash)
- **Flexibility**: API format can differ from database format
- **Validation**: Input validation happens at the boundary

---

## 8. Summary: Layer Rules

| Layer | Knows About | Doesn't Know About |
|-------|-------------|-------------------|
| **Domain** | Nothing | Everything |
| **Repository** | Domain, Database | Services, Handlers, HTTP |
| **Service** | Domain, Repository interfaces | Handlers, HTTP |
| **Handler** | Domain, Service, DTOs, HTTP | Database |

---

## Practice Exercises

### Exercise 1: Trace the Data Flow

For a login request:
1. Where does the JSON get parsed?
2. Where does password validation happen?
3. Where is the database queried?
4. Where does the JWT get created?

### Exercise 2: Identify Layer Violations

Which of these would be a layer violation?
1. Handler calling repository directly (skipping service)
2. Service returning `gin.Context`
3. Repository containing validation rules

Answer: All three are violations!

---

## External Resources

| Resource | URL | Description |
|----------|-----|-------------|
| Clean Architecture | https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html | Uncle Bob's original |
| Go Clean Architecture | https://github.com/bxcodec/go-clean-arch | Example project |

---

## Key Takeaways

1. **Domain**: Pure business entities, no dependencies
2. **Repository**: Data access only, returns domain objects
3. **Service**: Business logic, uses repository interfaces
4. **Handler**: HTTP concerns only, delegates to service
5. **DTOs**: Separate API format from internal models
6. **Dependency Injection**: Pass dependencies from outside

---

## Next Lesson

Continue to **[Lesson 04: Domain Models](04_DOMAIN_MODELS.md)** to learn how to design business entities.
