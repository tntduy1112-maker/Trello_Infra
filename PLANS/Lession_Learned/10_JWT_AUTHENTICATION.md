# Lesson 10: JWT Authentication

> Learn how to implement secure token-based authentication.

---

## What You'll Learn

1. What is JWT?
2. Access tokens vs refresh tokens
3. Token generation and validation
4. Secure token storage
5. Token rotation and revocation

---

## 1. What is JWT?

JWT (JSON Web Token) is a secure way to transmit information between parties.

### JWT Structure

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
```

**Three parts separated by dots:**

1. **Header** — Algorithm and type
   ```json
   {"alg": "HS256", "typ": "JWT"}
   ```

2. **Payload** — Claims (data)
   ```json
   {
     "sub": "user123",
     "email": "user@example.com",
     "exp": 1715000900
   }
   ```

3. **Signature** — Verification
   ```
   HMACSHA256(base64(header) + "." + base64(payload), secret)
   ```

---

## 2. Access Token vs Refresh Token

### Two-Token System

| Token | Purpose | Lifetime | Storage |
|-------|---------|:--------:|---------|
| **Access Token** | Authenticate requests | 15 min | Memory/localStorage |
| **Refresh Token** | Get new access token | 7 days | HttpOnly cookie/secure storage |

### Why Two Tokens?

- **Access token** is short-lived → If stolen, limited damage
- **Refresh token** is long-lived → Stored securely, used rarely
- **Token rotation** → Each refresh gives new pair

---

## 3. JWT Claims in Your Project

### Access Token

```json
{
  "jti": "unique-token-id",    // JWT ID (for blacklist)
  "sub": "user-cuid",          // Subject (user ID)
  "email": "user@example.com",
  "iat": 1715000000,           // Issued at
  "exp": 1715000900,           // Expires (15 min later)
  "type": "access"
}
```

### Refresh Token

```json
{
  "jti": "unique-token-id",
  "sub": "user-cuid",
  "iat": 1715000000,
  "exp": 1715604800,           // Expires (7 days later)
  "type": "refresh"
}
```

---

## 4. JWT Manager Implementation

**File:** `Backend/pkg/jwt/jwt.go`

```go
package jwt

import (
    "errors"
    "time"

    "github.com/golang-jwt/jwt/v5"
    "github.com/google/uuid"
)

var (
    ErrTokenExpired = errors.New("token has expired")
    ErrTokenInvalid = errors.New("token is invalid")
)

type Config struct {
    AccessSecret     string
    RefreshSecret    string
    AccessExpiresIn  time.Duration
    RefreshExpiresIn time.Duration
}

type Manager struct {
    accessSecret     []byte
    refreshSecret    []byte
    accessExpiresIn  time.Duration
    refreshExpiresIn time.Duration
}

type Claims struct {
    jwt.RegisteredClaims
    UserID string `json:"user_id"`
    Email  string `json:"email"`
    Type   string `json:"type"`
}

type TokenPair struct {
    AccessToken  string
    RefreshToken string
    ExpiresAt    time.Time
}

func NewManager(cfg Config) *Manager {
    return &Manager{
        accessSecret:     []byte(cfg.AccessSecret),
        refreshSecret:    []byte(cfg.RefreshSecret),
        accessExpiresIn:  cfg.AccessExpiresIn,
        refreshExpiresIn: cfg.RefreshExpiresIn,
    }
}

// Generate both access and refresh tokens
func (m *Manager) GenerateTokenPair(userID, email string) (*TokenPair, error) {
    now := time.Now()
    
    // Access token
    accessClaims := &Claims{
        RegisteredClaims: jwt.RegisteredClaims{
            ID:        uuid.NewString(),              // Unique ID
            Subject:   userID,
            IssuedAt:  jwt.NewNumericDate(now),
            ExpiresAt: jwt.NewNumericDate(now.Add(m.accessExpiresIn)),
        },
        UserID: userID,
        Email:  email,
        Type:   "access",
    }
    
    accessToken := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims)
    accessString, err := accessToken.SignedString(m.accessSecret)
    if err != nil {
        return nil, err
    }

    // Refresh token
    refreshExpiry := now.Add(m.refreshExpiresIn)
    refreshClaims := &Claims{
        RegisteredClaims: jwt.RegisteredClaims{
            ID:        uuid.NewString(),
            Subject:   userID,
            IssuedAt:  jwt.NewNumericDate(now),
            ExpiresAt: jwt.NewNumericDate(refreshExpiry),
        },
        UserID: userID,
        Type:   "refresh",
    }
    
    refreshToken := jwt.NewWithClaims(jwt.SigningMethodHS256, refreshClaims)
    refreshString, err := refreshToken.SignedString(m.refreshSecret)
    if err != nil {
        return nil, err
    }

    return &TokenPair{
        AccessToken:  accessString,
        RefreshToken: refreshString,
        ExpiresAt:    refreshExpiry,
    }, nil
}

// Validate access token
func (m *Manager) ValidateAccessToken(tokenString string) (*Claims, error) {
    return m.validateToken(tokenString, m.accessSecret, "access")
}

// Validate refresh token
func (m *Manager) ValidateRefreshToken(tokenString string) (*Claims, error) {
    return m.validateToken(tokenString, m.refreshSecret, "refresh")
}

func (m *Manager) validateToken(tokenString string, secret []byte, expectedType string) (*Claims, error) {
    token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
        if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
            return nil, ErrTokenInvalid
        }
        return secret, nil
    })

    if err != nil {
        if errors.Is(err, jwt.ErrTokenExpired) {
            return nil, ErrTokenExpired
        }
        return nil, ErrTokenInvalid
    }

    claims, ok := token.Claims.(*Claims)
    if !ok || !token.Valid {
        return nil, ErrTokenInvalid
    }

    if claims.Type != expectedType {
        return nil, ErrTokenInvalid
    }

    return claims, nil
}
```

---

## 5. Authentication Flow

### Login Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              LOGIN FLOW                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. User sends credentials                                                  │
│     POST /auth/login                                                        │
│     { "email": "...", "password": "..." }                                   │
│                                                                             │
│  2. Server validates credentials                                            │
│     - Check user exists                                                     │
│     - Compare password hash (bcrypt)                                        │
│     - Check is_verified = true                                              │
│     - Check is_active = true                                                │
│                                                                             │
│  3. Server generates tokens                                                 │
│     - Access token (15 min)                                                 │
│     - Refresh token (7 days)                                                │
│                                                                             │
│  4. Server stores refresh token hash in database                            │
│     INSERT INTO refresh_tokens (token_hash, user_id, expires_at, ...)      │
│                                                                             │
│  5. Server returns tokens to client                                         │
│     { "access_token": "...", "refresh_token": "...", "expires_in": 900 }   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Token Refresh Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TOKEN REFRESH FLOW                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. Access token expires (after 15 min)                                     │
│                                                                             │
│  2. Client sends refresh token                                              │
│     POST /auth/refresh                                                      │
│     { "refresh_token": "..." }                                              │
│                                                                             │
│  3. Server validates refresh token                                          │
│     - Verify JWT signature                                                  │
│     - Check token exists in DB                                              │
│     - Check not revoked                                                     │
│     - Check not expired                                                     │
│                                                                             │
│  4. CRITICAL: Revoke old refresh token                                      │
│     UPDATE refresh_tokens SET is_revoked = true WHERE hash = ...           │
│                                                                             │
│  5. Generate NEW token pair                                                 │
│     - New access token                                                      │
│     - New refresh token (rotation!)                                         │
│                                                                             │
│  6. Store new refresh token in DB                                           │
│                                                                             │
│  7. Return new tokens to client                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Why Token Rotation?

If an attacker steals a refresh token:
1. They use it to get new tokens
2. Real user tries to refresh → **Token already used!**
3. System detects reuse → **Revoke ALL user tokens**
4. Both attacker and user are logged out
5. User logs in again with password

---

## 6. Refresh Token Storage (Database)

**File:** `Backend/migrations/00002_create_refresh_tokens.sql`

```sql
CREATE TABLE refresh_tokens (
    id              VARCHAR(25) PRIMARY KEY,
    user_id         VARCHAR(25) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Store HASH of token, not raw token
    token_hash      VARCHAR(64) NOT NULL,    -- SHA-256 = 64 hex chars
    
    -- Metadata
    device_info     VARCHAR(255),            -- User-Agent
    ip_address      VARCHAR(45),             -- IPv6 max length
    
    -- Status
    is_revoked      BOOLEAN DEFAULT FALSE,
    expires_at      TIMESTAMPTZ NOT NULL,
    
    -- Timestamps
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    revoked_at      TIMESTAMPTZ,
    
    CONSTRAINT uniq_refresh_tokens_hash UNIQUE (token_hash)
);
```

**Why store hash, not raw token?**
- If database is compromised, attacker can't use hashes
- Same reason we hash passwords

---

## 7. Token Blacklisting (Redis)

When user logs out, we blacklist the access token:

```go
func (s *AuthService) Logout(ctx context.Context, accessToken, refreshToken string) error {
    // 1. Blacklist access token in Redis
    if accessToken != "" {
        claims, err := s.jwtManager.GetClaimsFromExpiredToken(accessToken)
        if err == nil && claims.ID != "" {
            ttl := time.Until(claims.ExpiresAt.Time)
            if ttl > 0 {
                // Store until token would naturally expire
                _ = s.cache.Set(ctx, "blacklist:"+claims.ID, "logout", ttl)
            }
        }
    }

    // 2. Revoke refresh token in database
    if refreshToken != "" {
        tokenHash := hash.SHA256(refreshToken)
        _ = s.tokenRepo.RevokeToken(ctx, tokenHash)
    }

    return nil
}

// Check if token is blacklisted
func (s *AuthService) IsTokenBlacklisted(ctx context.Context, jti string) (bool, error) {
    return s.cache.Exists(ctx, "blacklist:"+jti)
}
```

---

## 8. Security Best Practices

### Password Hashing

```go
import "golang.org/x/crypto/bcrypt"

const bcryptCost = 12

func HashPassword(password string) (string, error) {
    bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcryptCost)
    return string(bytes), err
}

func ComparePassword(hash, password string) bool {
    err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
    return err == nil
}
```

### Token Secrets

```env
# .env - NEVER commit to git!
JWT_ACCESS_SECRET=your-super-secret-access-key-min-32-chars
JWT_REFRESH_SECRET=your-super-secret-refresh-key-min-32-chars
```

**Requirements:**
- At least 32 characters
- Random (use password generator)
- Different for access and refresh
- Different per environment (dev/prod)

### Reuse Detection

```go
func (s *AuthService) RefreshToken(ctx context.Context, refreshToken string) (*response.AuthResponse, error) {
    tokenHash := hash.SHA256(refreshToken)
    storedToken, err := s.tokenRepo.FindByHash(ctx, tokenHash)
    
    if storedToken == nil {
        return nil, apperror.ErrInvalidToken
    }

    // CRITICAL: Check if already revoked (reuse attack!)
    if storedToken.IsRevoked {
        // Someone is trying to use an already-used token
        // Revoke ALL tokens for this user!
        _ = s.tokenRepo.RevokeAllUserTokens(ctx, storedToken.UserID)
        _ = s.userRepo.UpdateTokensValidAfter(ctx, storedToken.UserID)
        return nil, apperror.ErrTokenRevoked
    }

    // Continue with refresh...
}
```

---

## 9. Auth Middleware

**File:** `Backend/internal/middleware/auth.go`

```go
func Auth(jwtManager *jwt.Manager, authService *service.AuthService) gin.HandlerFunc {
    return func(c *gin.Context) {
        // 1. Extract token from header
        authHeader := c.GetHeader("Authorization")
        if !strings.HasPrefix(authHeader, "Bearer ") {
            response.ErrorResponse(c, apperror.ErrUnauthorized)
            c.Abort()
            return
        }
        tokenString := strings.TrimPrefix(authHeader, "Bearer ")

        // 2. Validate JWT signature and expiry
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

        // 3. Check blacklist (logout)
        isBlacklisted, _ := authService.IsTokenBlacklisted(c.Request.Context(), claims.ID)
        if isBlacklisted {
            response.ErrorResponse(c, apperror.ErrTokenRevoked)
            c.Abort()
            return
        }

        // 4. Set user info for handlers
        c.Set("user_id", claims.UserID)
        c.Set("user_email", claims.Email)
        c.Next()
    }
}
```

---

## 10. Complete Login Implementation

**File:** `Backend/internal/service/auth_service.go`

```go
func (s *AuthService) Login(ctx context.Context, req *request.LoginRequest, deviceInfo, ipAddress string) (*response.AuthResponse, error) {
    // 1. Find user
    user, err := s.userRepo.FindByEmail(ctx, req.Email)
    if err != nil {
        return nil, apperror.Wrap(err, apperror.ErrInternal)
    }
    if user == nil {
        return nil, apperror.ErrInvalidCredentials
    }

    // 2. Verify password
    if !hash.ComparePassword(user.PasswordHash, req.Password) {
        return nil, apperror.ErrInvalidCredentials
    }

    // 3. Check account status
    if !user.IsActive {
        return nil, apperror.ErrAccountDisabled
    }
    if !user.IsVerified {
        return nil, apperror.ErrEmailNotVerified
    }

    // 4. Generate tokens
    tokenPair, err := s.jwtManager.GenerateTokenPair(user.ID, user.Email)
    if err != nil {
        return nil, apperror.Wrap(err, apperror.ErrInternal)
    }

    // 5. Store refresh token hash
    storedToken := &domain.RefreshToken{
        UserID:     user.ID,
        TokenHash:  hash.SHA256(tokenPair.RefreshToken),
        DeviceInfo: &deviceInfo,
        IPAddress:  &ipAddress,
        ExpiresAt:  tokenPair.ExpiresAt,
    }
    if err := s.tokenRepo.CreateRefreshToken(ctx, storedToken); err != nil {
        return nil, apperror.Wrap(err, apperror.ErrInternal)
    }

    // 6. Return response
    return &response.AuthResponse{
        User:         response.ToUserResponse(user),
        AccessToken:  tokenPair.AccessToken,
        RefreshToken: tokenPair.RefreshToken,
        ExpiresIn:    int64(s.jwtManager.AccessExpiresIn().Seconds()),
    }, nil
}
```

---

## Practice Exercises

### Exercise 1: Implement Logout All

Implement a "logout all devices" feature that:
- Revokes all refresh tokens
- Updates `tokens_valid_after` timestamp

### Exercise 2: Add Device Tracking

Enhance refresh tokens to:
- Store device name
- Allow users to view active sessions
- Allow revoking specific sessions

---

## External Resources

| Resource | URL | Description |
|----------|-----|-------------|
| JWT Introduction | https://jwt.io/introduction | Official docs |
| JWT Best Practices | https://auth0.com/blog/jwt-handbook/ | Security guide |
| golang-jwt | https://github.com/golang-jwt/jwt | Go library |

---

## Key Takeaways

1. **Two tokens** — Short-lived access + long-lived refresh
2. **Token rotation** — Each refresh issues new pair
3. **Store hash** — Never store raw tokens in database
4. **Blacklist on logout** — Use Redis for fast lookup
5. **Reuse detection** — If used token is reused, revoke all
6. **Different secrets** — Access and refresh use different keys

---

## Next Lesson

Continue to **[Lesson 11: Docker & Deployment](11_DOCKER_DEPLOYMENT.md)** to learn about containerization.
