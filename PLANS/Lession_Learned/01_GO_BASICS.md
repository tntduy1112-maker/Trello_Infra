# Lesson 01: Go Language Basics

> Learn the fundamentals of Go through examples from your TaskFlow project.

---

## What You'll Learn

1. Variables and data types
2. Functions and methods
3. Structs (like classes in other languages)
4. Interfaces (Go's way of achieving polymorphism)
5. Error handling (Go's unique approach)
6. Packages and imports

---

## 1. Variables and Data Types

### Basic Types in Go

```go
// String
var name string = "TaskFlow"

// Integer
var port int = 8080

// Boolean
var isActive bool = true

// Float
var position float64 = 65536.0

// Short declaration (most common)
name := "TaskFlow"    // Go infers the type
port := 8080
```

### Example from Your Project

**File:** `Backend/internal/service/auth_service.go`

```go
const (
    otpExpiresIn        = 15 * time.Minute    // Duration constant
    resetTokenExpiresIn = 1 * time.Hour
    maxOTPAttempts      = 5                    // Integer constant
)
```

**What's happening:**
- `const` declares constants (values that never change)
- `time.Minute` and `time.Hour` are built-in time durations
- Constants are named in `camelCase` (Go convention)

### Pointers

Pointers hold the memory address of a value.

**File:** `Backend/internal/domain/user.go`

```go
type User struct {
    AvatarURL *string    `json:"avatar_url,omitempty"`  // Pointer - can be nil
    DeletedAt *time.Time `json:"-"`                     // Pointer - can be nil
}
```

**Why pointers?**
- `*string` means "pointer to string" — can be `nil` (no value)
- `string` (without `*`) must always have a value
- Use pointers when a field is optional (can be empty)

---

## 2. Functions

### Basic Function Syntax

```go
// Function with parameters and return value
func add(a int, b int) int {
    return a + b
}

// Multiple return values (very common in Go)
func divide(a, b int) (int, error) {
    if b == 0 {
        return 0, errors.New("cannot divide by zero")
    }
    return a / b, nil
}
```

### Example from Your Project

**File:** `Backend/internal/repository/user_repository.go`

```go
func NewUserRepository(db *pgxpool.Pool) UserRepository {
    return &userRepository{db: db}
}
```

**What's happening:**
- `NewUserRepository` is a **constructor function** (creates and returns an object)
- `db *pgxpool.Pool` — takes a pointer to a database pool as parameter
- `UserRepository` — returns an interface type
- `&userRepository{db: db}` — creates a new struct and returns its address

### Functions with Multiple Returns

**File:** `Backend/internal/repository/user_repository.go`

```go
func (r *userRepository) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
    // ... query database ...
    if err != nil {
        if errors.Is(err, pgx.ErrNoRows) {
            return nil, nil    // User not found, no error
        }
        return nil, err        // Database error
    }
    return &user, nil          // Success: return user, no error
}
```

**What's happening:**
- Returns TWO values: `(*domain.User, error)`
- First return: the result (User pointer, or `nil` if not found)
- Second return: error (or `nil` if no error)
- This is the **Go error handling pattern**

---

## 3. Structs

Structs are Go's way of creating custom data types (similar to classes).

### Basic Struct

```go
type Person struct {
    Name string
    Age  int
}

// Create a struct
person := Person{
    Name: "John",
    Age:  30,
}

// Access fields
fmt.Println(person.Name)  // "John"
```

### Example from Your Project

**File:** `Backend/internal/domain/user.go`

```go
type User struct {
    ID               string     `json:"id"`
    Email            string     `json:"email"`
    PasswordHash     string     `json:"-"`              // "-" means don't include in JSON
    FullName         string     `json:"full_name"`
    AvatarURL        *string    `json:"avatar_url,omitempty"`
    IsVerified       bool       `json:"is_verified"`
    IsActive         bool       `json:"is_active"`
    TokensValidAfter time.Time  `json:"-"`
    CreatedAt        time.Time  `json:"created_at"`
    UpdatedAt        time.Time  `json:"updated_at"`
    DeletedAt        *time.Time `json:"-"`
}
```

**What's happening:**
- `type User struct` — defines a new type called `User`
- Backticks contain **struct tags** — metadata for JSON serialization
- `json:"email"` — when converted to JSON, this field becomes "email"
- `json:"-"` — never include this field in JSON (security: hide password hash)
- `json:"avatar_url,omitempty"` — omit from JSON if the value is empty/nil

### Methods on Structs

Methods are functions attached to a struct.

**File:** `Backend/internal/domain/user.go`

```go
func (u *User) IsDeleted() bool {
    return u.DeletedAt != nil
}
```

**What's happening:**
- `(u *User)` is the **receiver** — this method belongs to `User`
- `u` is like `this` or `self` in other languages
- `*User` (pointer receiver) means the method can modify the user

**Using the method:**
```go
user := &User{DeletedAt: nil}
fmt.Println(user.IsDeleted())  // false
```

---

## 4. Interfaces

Interfaces define behavior (what methods a type must have).

### Basic Interface

```go
// Define an interface
type Writer interface {
    Write(data []byte) error
}

// Any type that has a Write method "implements" Writer
// No explicit "implements" keyword needed!
```

### Example from Your Project

**File:** `Backend/internal/repository/interfaces.go`

```go
type UserRepository interface {
    Create(ctx context.Context, user *domain.User) error
    FindByID(ctx context.Context, id string) (*domain.User, error)
    FindByEmail(ctx context.Context, email string) (*domain.User, error)
    Update(ctx context.Context, user *domain.User) error
    SoftDelete(ctx context.Context, id string) error
    UpdateTokensValidAfter(ctx context.Context, id string) error
}
```

**What's happening:**
- `UserRepository` is an interface — a contract
- Any struct that has ALL these methods "implements" this interface
- The actual implementation is in `user_repository.go`

### Why Interfaces?

1. **Flexibility** — You can swap implementations without changing code
2. **Testing** — You can create mock implementations for testing
3. **Loose coupling** — Code depends on behavior, not specific types

**File:** `Backend/internal/service/auth_service.go`

```go
type AuthService struct {
    userRepo UserRepository  // Uses interface, not concrete type
    // ...
}
```

**Benefit:** You can pass ANY type that implements `UserRepository`:
- Real database repository
- Mock repository for testing
- Cache-enabled repository

---

## 5. Error Handling

Go has NO exceptions. Instead, functions return errors explicitly.

### The Error Pattern

```go
result, err := someFunction()
if err != nil {
    // Handle error
    return err
}
// Use result
```

### Example from Your Project

**File:** `Backend/internal/service/auth_service.go`

```go
func (s *AuthService) Register(ctx context.Context, req *request.RegisterRequest) (*response.UserResponse, error) {
    // Step 1: Check if email exists
    existingUser, err := s.userRepo.FindByEmail(ctx, req.Email)
    if err != nil {
        return nil, apperror.Wrap(err, apperror.ErrInternal)
    }
    if existingUser != nil {
        return nil, apperror.ErrEmailAlreadyExists
    }

    // Step 2: Hash password
    passwordHash, err := hash.HashPassword(req.Password)
    if err != nil {
        return nil, apperror.Wrap(err, apperror.ErrInternal)
    }

    // Step 3: Create user
    user := &domain.User{
        Email:        req.Email,
        PasswordHash: passwordHash,
        FullName:     req.FullName,
        IsVerified:   false,
        IsActive:     true,
    }

    if err := s.userRepo.Create(ctx, user); err != nil {
        return nil, apperror.Wrap(err, apperror.ErrInternal)
    }

    return response.ToUserResponse(user), nil
}
```

**What's happening:**
- Every operation that can fail returns `error`
- We check `err != nil` immediately after each operation
- If error occurs, we return early with the error
- `nil` as the second return means "success, no error"

### Custom Errors

**File:** `Backend/pkg/apperror/apperror.go` (example pattern)

```go
type AppError struct {
    Code       string
    Message    string
    StatusCode int
}

var ErrEmailAlreadyExists = &AppError{
    Code:       "EMAIL_EXISTS",
    Message:    "Email already exists",
    StatusCode: 409,
}
```

---

## 6. Packages and Imports

### Package Declaration

Every Go file starts with a package declaration.

```go
package main          // Executable program entry point
package service       // Library package named "service"
package handler       // Library package named "handler"
```

### Imports

**File:** `Backend/cmd/server/main.go`

```go
import (
    "context"           // Standard library
    "net/http"          // Standard library
    "os"                // Standard library
    "time"              // Standard library

    "github.com/gin-gonic/gin"     // External package
    "github.com/rs/zerolog"        // External package

    "github.com/codewebkhongkho/trello-agent/internal/config"      // Internal package
    "github.com/codewebkhongkho/trello-agent/internal/handler"     // Internal package
    "github.com/codewebkhongkho/trello-agent/internal/service"     // Internal package
)
```

**Convention:**
1. Standard library imports first
2. External packages second
3. Internal project packages last
4. Blank line between groups

### Exported vs Unexported

In Go, visibility is controlled by **capitalization**:

```go
// Exported (public) - starts with UPPERCASE
func NewUserRepository() {}   // Can be used by other packages
type User struct {}           // Can be used by other packages

// Unexported (private) - starts with lowercase
func hashPassword() {}        // Only usable within this package
type userRepository struct {} // Only usable within this package
```

**Example from your project:**

```go
// Exported (public API)
type AuthHandler struct { ... }
func NewAuthHandler() *AuthHandler { ... }

// Unexported (internal implementation)
func (h *AuthHandler) generateAuthResponse() { ... }
```

---

## 7. Context

Context is used to pass request-scoped values and handle cancellation.

**File:** `Backend/internal/repository/user_repository.go`

```go
func (r *userRepository) FindByID(ctx context.Context, id string) (*domain.User, error) {
    query := `SELECT ... FROM users WHERE id = $1`
    err := r.db.QueryRow(ctx, query, id).Scan(...)  // ctx passed to database
    // ...
}
```

**Why Context?**
- Carries deadlines (timeout after X seconds)
- Carries cancellation signals (stop if client disconnects)
- Carries request-specific values (user ID, trace ID)
- Should be the FIRST parameter of functions

---

## Practice Exercises

### Exercise 1: Understand Struct Tags
Look at `Backend/internal/domain/board.go` and answer:
1. Which fields are hidden from JSON?
2. Which fields are optional (can be `nil`)?

### Exercise 2: Trace the Error Flow
In `Backend/internal/service/auth_service.go`, follow the `Login` function:
1. How many places can an error occur?
2. What error is returned for invalid credentials?

### Exercise 3: Find Interfaces
In `Backend/internal/repository/interfaces.go`:
1. List all repository interfaces
2. Find where each interface is implemented

---

## External Resources

| Resource | URL | Description |
|----------|-----|-------------|
| Go Tour | https://go.dev/tour | Interactive tutorial |
| Go by Example | https://gobyexample.com | Practical examples |
| Effective Go | https://go.dev/doc/effective_go | Best practices |
| Go Playground | https://go.dev/play | Try code online |

### Videos

| Topic | URL |
|-------|-----|
| Go in 100 Seconds | https://www.youtube.com/watch?v=446E-r0rXHI |
| Learn Go in 12 Minutes | https://www.youtube.com/watch?v=C8LgvuEBraI |

---

## Key Takeaways

1. **Variables**: Use `:=` for short declaration, `var` for explicit type
2. **Functions**: Can return multiple values (result + error)
3. **Structs**: Go's way to create custom types (like classes)
4. **Interfaces**: Define behavior, not implementation
5. **Errors**: Always check `err != nil` after operations
6. **Packages**: Capital letter = exported (public)

---

## Next Lesson

Continue to **[Lesson 02: Project Structure](02_PROJECT_STRUCTURE.md)** to learn how Go projects are organized.
