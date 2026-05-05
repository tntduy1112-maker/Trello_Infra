# Lesson 06: Service Layer

> Learn how to implement business logic in the service layer.

---

## What You'll Learn

1. What is the service layer?
2. Business logic vs data access
3. Service structure and dependency injection
4. Error handling and validation
5. Orchestrating multiple operations

---

## 1. What is the Service Layer?

The service layer contains **business logic** — the rules that make your application unique.

```
Handler (HTTP)
    │
    ▼
Service (Business Logic) ← YOU ARE HERE
    │
    ▼
Repository (Data Access)
```

**Examples of business logic:**
- Users must verify email before login
- Only board owners can delete boards
- Cards can only be moved within the same board
- Password must be hashed before saving

---

## 2. Service Structure

**File:** `Backend/internal/service/auth_service.go`

```go
package service

import (
    "context"
    "time"

    "github.com/codewebkhongkho/trello-agent/internal/domain"
    "github.com/codewebkhongkho/trello-agent/internal/dto/request"
    "github.com/codewebkhongkho/trello-agent/internal/dto/response"
    "github.com/codewebkhongkho/trello-agent/internal/repository"
    "github.com/codewebkhongkho/trello-agent/pkg/apperror"
    "github.com/codewebkhongkho/trello-agent/pkg/email"
    "github.com/codewebkhongkho/trello-agent/pkg/hash"
    "github.com/codewebkhongkho/trello-agent/pkg/jwt"
)

// Constants for business rules
const (
    otpExpiresIn        = 15 * time.Minute
    resetTokenExpiresIn = 1 * time.Hour
    maxOTPAttempts      = 5
)

// Service struct with dependencies
type AuthService struct {
    userRepo         repository.UserRepository      // Interface, not implementation
    tokenRepo        repository.TokenRepository
    verificationRepo repository.VerificationRepository
    jwtManager       *jwt.Manager
    emailService     *email.Service
    cache            *cache.RedisClient
    frontendURL      string
}

// Configuration struct for cleaner constructor
type AuthServiceConfig struct {
    UserRepo         repository.UserRepository
    TokenRepo        repository.TokenRepository
    VerificationRepo repository.VerificationRepository
    JWTManager       *jwt.Manager
    EmailService     *email.Service
    Cache            *cache.RedisClient
    FrontendURL      string
}

// Constructor - dependencies are injected
func NewAuthService(cfg AuthServiceConfig) *AuthService {
    return &AuthService{
        userRepo:         cfg.UserRepo,
        tokenRepo:        cfg.TokenRepo,
        verificationRepo: cfg.VerificationRepo,
        jwtManager:       cfg.JWTManager,
        emailService:     cfg.EmailService,
        cache:            cfg.Cache,
        frontendURL:      cfg.FrontendURL,
    }
}
```

**Key Points:**
- Service depends on **interfaces**, not concrete types
- Dependencies are **injected** via constructor
- Configuration struct makes many parameters cleaner
- Constants define business rules

---

## 3. Implementing Business Logic

### Registration Flow

**File:** `Backend/internal/service/auth_service.go`

```go
func (s *AuthService) Register(ctx context.Context, req *request.RegisterRequest) (*response.UserResponse, error) {
    // RULE 1: Email must be unique
    existingUser, err := s.userRepo.FindByEmail(ctx, req.Email)
    if err != nil {
        return nil, apperror.Wrap(err, apperror.ErrInternal)
    }
    if existingUser != nil {
        return nil, apperror.ErrEmailAlreadyExists
    }

    // RULE 2: Password must be hashed
    passwordHash, err := hash.HashPassword(req.Password)
    if err != nil {
        return nil, apperror.Wrap(err, apperror.ErrInternal)
    }

    // RULE 3: New users start unverified
    user := &domain.User{
        Email:        req.Email,
        PasswordHash: passwordHash,
        FullName:     req.FullName,
        IsVerified:   false,  // Must verify email
        IsActive:     true,
    }

    // Save to database
    if err := s.userRepo.Create(ctx, user); err != nil {
        return nil, apperror.Wrap(err, apperror.ErrInternal)
    }

    // RULE 4: Send verification email
    if err := s.sendVerificationOTP(ctx, user); err != nil {
        return nil, err
    }

    // Return response (not domain model directly)
    return response.ToUserResponse(user), nil
}
```

**Business Rules Implemented:**
1. Email uniqueness check
2. Password hashing (never store plain text!)
3. Users start unverified
4. Verification email sent automatically

---

### Login Flow

```go
func (s *AuthService) Login(ctx context.Context, req *request.LoginRequest, deviceInfo, ipAddress string) (*response.AuthResponse, error) {
    // RULE 1: User must exist
    user, err := s.userRepo.FindByEmail(ctx, req.Email)
    if err != nil {
        return nil, apperror.Wrap(err, apperror.ErrInternal)
    }
    if user == nil {
        return nil, apperror.ErrInvalidCredentials  // Don't reveal "user not found"
    }

    // RULE 2: Password must match
    if !hash.ComparePassword(user.PasswordHash, req.Password) {
        return nil, apperror.ErrInvalidCredentials
    }

    // RULE 3: Account must be active
    if !user.IsActive {
        return nil, apperror.ErrAccountDisabled
    }

    // RULE 4: Email must be verified
    if !user.IsVerified {
        return nil, apperror.ErrEmailNotVerified
    }

    // Generate tokens and return
    return s.generateAuthResponse(ctx, user, deviceInfo, ipAddress)
}
```

**Security Best Practice:**
- Return same error for "user not found" and "wrong password"
- Prevents attackers from discovering valid emails

---

### Email Verification with Brute Force Protection

```go
func (s *AuthService) VerifyEmail(ctx context.Context, req *request.VerifyEmailRequest) error {
    // RULE: Limit OTP attempts (brute force protection)
    attemptsKey := "otp_attempts:" + req.Email
    attempts, _ := s.cache.Incr(ctx, attemptsKey)
    
    if attempts == 1 {
        _ = s.cache.Expire(ctx, attemptsKey, 15*time.Minute)
    }
    
    if attempts > maxOTPAttempts {  // maxOTPAttempts = 5
        return apperror.ErrOTPMaxAttempts
    }

    // Find user
    user, err := s.userRepo.FindByEmail(ctx, req.Email)
    if err != nil {
        return apperror.Wrap(err, apperror.ErrInternal)
    }
    if user == nil {
        return apperror.ErrUserNotFound
    }
    
    // Already verified? Success
    if user.IsVerified {
        return nil
    }

    // Validate OTP
    verification, err := s.verificationRepo.FindByToken(ctx, req.OTP, domain.VerificationTypeEmail)
    if err != nil {
        return apperror.Wrap(err, apperror.ErrInternal)
    }
    if verification == nil || verification.UserID != user.ID {
        return apperror.ErrOTPInvalid
    }
    if !verification.IsValid() {
        if verification.IsExpired() {
            return apperror.ErrOTPExpired
        }
        return apperror.ErrOTPInvalid
    }

    // Mark OTP as used
    if err := s.verificationRepo.MarkUsed(ctx, verification.ID); err != nil {
        return apperror.Wrap(err, apperror.ErrInternal)
    }

    // Mark user as verified
    user.IsVerified = true
    if err := s.userRepo.Update(ctx, user); err != nil {
        return apperror.Wrap(err, apperror.ErrInternal)
    }

    // Clear attempts counter
    _ = s.cache.Delete(ctx, attemptsKey)
    return nil
}
```

**Security Features:**
- Rate limiting OTP attempts (5 per 15 minutes)
- Uses Redis for fast attempt counting
- Clears counter on success

---

## 4. Error Handling Pattern

**File:** `Backend/pkg/apperror/apperror.go`

```go
package apperror

type AppError struct {
    Code       string
    Message    string
    StatusCode int
    Details    any
}

func (e *AppError) Error() string {
    return e.Message
}

// Pre-defined errors
var (
    ErrInternal           = &AppError{"INTERNAL_ERROR", "Internal server error", 500, nil}
    ErrUnauthorized       = &AppError{"UNAUTHORIZED", "Unauthorized", 401, nil}
    ErrInvalidCredentials = &AppError{"INVALID_CREDENTIALS", "Invalid email or password", 401, nil}
    ErrEmailAlreadyExists = &AppError{"EMAIL_EXISTS", "Email already exists", 409, nil}
    ErrUserNotFound       = &AppError{"USER_NOT_FOUND", "User not found", 404, nil}
    ErrEmailNotVerified   = &AppError{"EMAIL_NOT_VERIFIED", "Please verify your email", 403, nil}
    ErrOTPInvalid         = &AppError{"OTP_INVALID", "Invalid verification code", 400, nil}
    ErrOTPExpired         = &AppError{"OTP_EXPIRED", "Verification code expired", 400, nil}
    ErrOTPMaxAttempts     = &AppError{"OTP_MAX_ATTEMPTS", "Too many attempts", 429, nil}
)

// Wrap adds context to errors
func Wrap(original error, appErr *AppError) error {
    return appErr  // In production, log original error
}
```

**Usage Pattern:**

```go
// In service
if err := s.userRepo.Create(ctx, user); err != nil {
    return nil, apperror.Wrap(err, apperror.ErrInternal)
}

// In handler
if appErr, ok := err.(*apperror.AppError); ok {
    response.ErrorResponse(c, appErr)  // Returns proper HTTP status
    return
}
```

---

## 5. Orchestrating Multiple Operations

Services often coordinate multiple steps:

```go
func (s *AuthService) generateAuthResponse(ctx context.Context, user *domain.User, deviceInfo, ipAddress string) (*response.AuthResponse, error) {
    // Step 1: Generate JWT tokens
    tokenPair, err := s.jwtManager.GenerateTokenPair(user.ID, user.Email)
    if err != nil {
        return nil, apperror.Wrap(err, apperror.ErrInternal)
    }

    // Step 2: Hash refresh token for storage
    refreshTokenHash := hash.SHA256(tokenPair.RefreshToken)
    
    // Step 3: Prepare device info
    var deviceInfoPtr, ipAddressPtr *string
    if deviceInfo != "" {
        deviceInfoPtr = &deviceInfo
    }
    if ipAddress != "" {
        ipAddressPtr = &ipAddress
    }

    // Step 4: Store refresh token in database
    storedToken := &domain.RefreshToken{
        UserID:     user.ID,
        TokenHash:  refreshTokenHash,
        DeviceInfo: deviceInfoPtr,
        IPAddress:  ipAddressPtr,
        ExpiresAt:  tokenPair.ExpiresAt,
    }

    if err := s.tokenRepo.CreateRefreshToken(ctx, storedToken); err != nil {
        return nil, apperror.Wrap(err, apperror.ErrInternal)
    }

    // Step 5: Build response
    return &response.AuthResponse{
        User:         response.ToUserResponse(user),
        AccessToken:  tokenPair.AccessToken,
        RefreshToken: tokenPair.RefreshToken,
        ExpiresIn:    int64(time.Until(tokenPair.ExpiresAt).Seconds()),
    }, nil
}
```

---

## 6. Helper Methods

Private methods for internal use:

```go
func (s *AuthService) sendVerificationOTP(ctx context.Context, user *domain.User) error {
    // Generate 6-digit OTP
    otp, err := jwt.GenerateOTP()
    if err != nil {
        return apperror.Wrap(err, apperror.ErrInternal)
    }

    // Delete existing OTPs
    _ = s.verificationRepo.DeleteByUserAndType(ctx, user.ID, domain.VerificationTypeEmail)

    // Create new verification
    verification := &domain.EmailVerification{
        UserID:    user.ID,
        Token:     otp,
        Type:      domain.VerificationTypeEmail,
        ExpiresAt: time.Now().Add(otpExpiresIn),
    }

    if err := s.verificationRepo.Create(ctx, verification); err != nil {
        return apperror.Wrap(err, apperror.ErrInternal)
    }

    // Send email
    if err := s.emailService.SendVerificationEmail(user.Email, otp); err != nil {
        return apperror.Wrap(err, apperror.ErrInternal)
    }

    return nil
}
```

---

## 7. Service Best Practices

### Do's

1. **Single Responsibility** — Each service handles one domain
2. **Use interfaces** — Depend on repository interfaces
3. **Return DTOs** — Don't return domain models directly to handlers
4. **Wrap errors** — Add context when propagating errors
5. **Define constants** — Business rules as named constants

### Don'ts

1. **Don't use gin.Context** — Service shouldn't know about HTTP
2. **Don't write SQL** — That's repository's job
3. **Don't handle HTTP responses** — That's handler's job
4. **Don't leak implementation details** — Return clean errors

---

## 8. Testing Services

Services are easy to test with mock repositories:

```go
// Mock repository
type mockUserRepo struct {
    users map[string]*domain.User
}

func (m *mockUserRepo) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
    return m.users[email], nil
}

// Test
func TestRegister_EmailExists(t *testing.T) {
    mockRepo := &mockUserRepo{
        users: map[string]*domain.User{
            "existing@test.com": {ID: "1", Email: "existing@test.com"},
        },
    }
    
    service := NewAuthService(AuthServiceConfig{UserRepo: mockRepo})
    
    _, err := service.Register(ctx, &request.RegisterRequest{
        Email: "existing@test.com",
    })
    
    assert.Equal(t, apperror.ErrEmailAlreadyExists, err)
}
```

---

## Practice Exercises

### Exercise 1: Add Password Change

Implement `ChangePassword`:
- Validate current password
- Hash new password
- Invalidate all tokens

### Exercise 2: Add Account Deletion

Implement `DeleteAccount`:
- Soft delete user
- Revoke all tokens
- (Optionally) delete user data

---

## External Resources

| Resource | URL | Description |
|----------|-----|-------------|
| Clean Architecture Services | https://blog.cleancoder.com | Uncle Bob |
| Domain-Driven Design | https://martinfowler.com/tags/domain%20driven%20design.html | Concepts |

---

## Key Takeaways

1. **Business logic lives here** — Validation, rules, orchestration
2. **Depend on interfaces** — Not concrete repository implementations
3. **Use DTOs** — Transform domain models for responses
4. **Handle errors properly** — Wrap with context, return AppError
5. **No HTTP knowledge** — Service doesn't know about HTTP
6. **Easy to test** — Mock repositories for unit testing

---

## Next Lesson

Continue to **[Lesson 07: Handlers & REST API](07_HANDLERS_API.md)** to learn how to handle HTTP requests.
