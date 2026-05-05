# Lesson 05: Repository Pattern

> Learn how to access databases using the repository pattern with PostgreSQL.

---

## What You'll Learn

1. What is the repository pattern?
2. Repository interfaces
3. PostgreSQL with pgx driver
4. CRUD operations
5. Parameterized queries
6. Error handling

---

## 1. What is the Repository Pattern?

The repository pattern **abstracts data access** behind an interface.

**Benefits:**
- Business logic doesn't know about database specifics
- Easy to swap databases (PostgreSQL → MongoDB)
- Easy to test (use mock repository)

```
┌─────────────────────┐
│       Service       │  ← Knows about UserRepository interface
└─────────────────────┘
          │
          ▼
┌─────────────────────┐
│  UserRepository     │  ← Interface (contract)
│    (Interface)      │
└─────────────────────┘
          │
          ▼
┌─────────────────────┐
│   userRepository    │  ← Implementation (PostgreSQL)
│  (Implementation)   │
└─────────────────────┘
          │
          ▼
┌─────────────────────┐
│     PostgreSQL      │  ← Actual database
└─────────────────────┘
```

---

## 2. Repository Interfaces

**File:** `Backend/internal/repository/interfaces.go`

```go
package repository

import (
    "context"
    "github.com/codewebkhongkho/trello-agent/internal/domain"
)

type UserRepository interface {
    Create(ctx context.Context, user *domain.User) error
    FindByID(ctx context.Context, id string) (*domain.User, error)
    FindByEmail(ctx context.Context, email string) (*domain.User, error)
    Update(ctx context.Context, user *domain.User) error
    SoftDelete(ctx context.Context, id string) error
    UpdateTokensValidAfter(ctx context.Context, id string) error
}

type TokenRepository interface {
    CreateRefreshToken(ctx context.Context, token *domain.RefreshToken) error
    FindByHash(ctx context.Context, hash string) (*domain.RefreshToken, error)
    RevokeToken(ctx context.Context, hash string) error
    RevokeAllUserTokens(ctx context.Context, userID string) error
}
```

**Key Points:**
- Interface defines WHAT operations are available
- Implementation defines HOW they work
- All methods take `context.Context` as first parameter
- Methods return `error` for failure handling

---

## 3. Repository Implementation

**File:** `Backend/internal/repository/user_repository.go`

```go
package repository

import (
    "context"
    "errors"
    "time"

    "github.com/jackc/pgx/v5"
    "github.com/jackc/pgx/v5/pgxpool"

    "github.com/codewebkhongkho/trello-agent/internal/domain"
    "github.com/codewebkhongkho/trello-agent/pkg/cuid"
)

// Private struct - implementation detail
type userRepository struct {
    db *pgxpool.Pool
}

// Constructor - returns the interface type
func NewUserRepository(db *pgxpool.Pool) UserRepository {
    return &userRepository{db: db}
}
```

**Note:**
- `userRepository` (lowercase) — private, not exported
- `NewUserRepository` — public constructor
- Returns `UserRepository` interface, not concrete type

---

## 4. CRUD Operations

### Create

```go
func (r *userRepository) Create(ctx context.Context, user *domain.User) error {
    // Generate ID if not provided
    if user.ID == "" {
        user.ID = cuid.New()
    }
    
    // Set timestamps
    now := time.Now()
    user.CreatedAt = now
    user.UpdatedAt = now
    user.TokensValidAfter = now

    // SQL INSERT with parameterized query
    query := `
        INSERT INTO users (id, email, password_hash, full_name, avatar_url, 
                          is_verified, is_active, tokens_valid_after, 
                          created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
    `
    
    _, err := r.db.Exec(ctx, query,
        user.ID,              // $1
        user.Email,           // $2
        user.PasswordHash,    // $3
        user.FullName,        // $4
        user.AvatarURL,       // $5
        user.IsVerified,      // $6
        user.IsActive,        // $7
        user.TokensValidAfter,// $8
        user.CreatedAt,       // $9
        user.UpdatedAt,       // $10
    )
    return err
}
```

**Key Points:**
- `$1, $2, $3...` — PostgreSQL parameterized placeholders
- **NEVER** concatenate user input into SQL (SQL injection risk!)
- `Exec` for INSERT/UPDATE/DELETE (no return rows)

### Read (Single Row)

```go
func (r *userRepository) FindByID(ctx context.Context, id string) (*domain.User, error) {
    query := `
        SELECT id, email, password_hash, full_name, avatar_url, 
               is_verified, is_active, tokens_valid_after, 
               created_at, updated_at, deleted_at
        FROM users
        WHERE id = $1 AND deleted_at IS NULL
    `
    
    var user domain.User
    err := r.db.QueryRow(ctx, query, id).Scan(
        &user.ID,
        &user.Email,
        &user.PasswordHash,
        &user.FullName,
        &user.AvatarURL,
        &user.IsVerified,
        &user.IsActive,
        &user.TokensValidAfter,
        &user.CreatedAt,
        &user.UpdatedAt,
        &user.DeletedAt,
    )
    
    if err != nil {
        if errors.Is(err, pgx.ErrNoRows) {
            return nil, nil  // Not found = return nil, no error
        }
        return nil, err  // Actual error
    }
    
    return &user, nil
}
```

**Key Points:**
- `QueryRow` for single row queries
- `Scan` maps columns to struct fields (in order!)
- `pgx.ErrNoRows` — no record found (not an error, just empty)
- `&user.Field` — pointer to field for Scan to write into

### Read (Multiple Rows)

```go
func (r *userRepository) FindAll(ctx context.Context) ([]*domain.User, error) {
    query := `
        SELECT id, email, full_name, created_at
        FROM users
        WHERE deleted_at IS NULL
        ORDER BY created_at DESC
    `
    
    rows, err := r.db.Query(ctx, query)
    if err != nil {
        return nil, err
    }
    defer rows.Close()  // Always close rows!
    
    var users []*domain.User
    for rows.Next() {
        var user domain.User
        err := rows.Scan(
            &user.ID,
            &user.Email,
            &user.FullName,
            &user.CreatedAt,
        )
        if err != nil {
            return nil, err
        }
        users = append(users, &user)
    }
    
    // Check for errors during iteration
    if err := rows.Err(); err != nil {
        return nil, err
    }
    
    return users, nil
}
```

**Key Points:**
- `Query` for multiple rows
- `defer rows.Close()` — always close when done
- Loop with `rows.Next()` to iterate
- Check `rows.Err()` after loop

### Update

```go
func (r *userRepository) Update(ctx context.Context, user *domain.User) error {
    user.UpdatedAt = time.Now()
    
    query := `
        UPDATE users
        SET email = $2, full_name = $3, avatar_url = $4, 
            is_verified = $5, is_active = $6, updated_at = $7
        WHERE id = $1 AND deleted_at IS NULL
    `
    
    _, err := r.db.Exec(ctx, query,
        user.ID,
        user.Email,
        user.FullName,
        user.AvatarURL,
        user.IsVerified,
        user.IsActive,
        user.UpdatedAt,
    )
    return err
}
```

### Delete (Soft Delete)

```go
func (r *userRepository) SoftDelete(ctx context.Context, id string) error {
    query := `
        UPDATE users 
        SET deleted_at = NOW() 
        WHERE id = $1 AND deleted_at IS NULL
    `
    _, err := r.db.Exec(ctx, query, id)
    return err
}
```

**Why Soft Delete?**
- Data is never truly deleted
- Can recover accidentally deleted records
- Audit trail preserved
- Related data remains valid

---

## 5. Connection Pool

**File:** `Backend/pkg/database/postgres.go`

```go
package database

import (
    "context"
    "github.com/jackc/pgx/v5/pgxpool"
)

func NewPostgresPool(cfg Config) (*pgxpool.Pool, error) {
    poolConfig, err := pgxpool.ParseConfig(cfg.URL)
    if err != nil {
        return nil, err
    }
    
    // Connection pool settings
    poolConfig.MaxConns = int32(cfg.PoolMax)  // Max connections
    poolConfig.MinConns = int32(cfg.PoolMin)  // Min idle connections
    
    pool, err := pgxpool.NewWithConfig(context.Background(), poolConfig)
    if err != nil {
        return nil, err
    }
    
    // Test connection
    if err := pool.Ping(context.Background()); err != nil {
        return nil, err
    }
    
    return pool, nil
}
```

**Why Connection Pool?**
- Reuses database connections (creating is expensive)
- Limits max connections (prevents overload)
- Handles connection lifecycle automatically

---

## 6. Parameterized Queries

**ALWAYS use parameterized queries to prevent SQL injection!**

```go
// ✅ GOOD - Parameterized
query := `SELECT * FROM users WHERE email = $1`
db.QueryRow(ctx, query, email)

// ❌ BAD - String concatenation (SQL INJECTION RISK!)
query := `SELECT * FROM users WHERE email = '` + email + `'`
db.QueryRow(ctx, query)
```

**What is SQL Injection?**

If `email = "'; DROP TABLE users; --"`, the bad query becomes:
```sql
SELECT * FROM users WHERE email = ''; DROP TABLE users; --'
```
This would delete your entire users table!

---

## 7. Error Handling Patterns

```go
func (r *userRepository) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
    var user domain.User
    err := r.db.QueryRow(ctx, query, email).Scan(...)
    
    if err != nil {
        // Not found - return nil, nil (not an error)
        if errors.Is(err, pgx.ErrNoRows) {
            return nil, nil
        }
        // Actual database error
        return nil, err
    }
    
    return &user, nil
}
```

**Pattern:**
- `nil, nil` = not found (expected case)
- `nil, err` = database error (unexpected)
- `&user, nil` = found successfully

**In Service Layer:**

```go
func (s *AuthService) Login(ctx context.Context, email string) error {
    user, err := s.userRepo.FindByEmail(ctx, email)
    if err != nil {
        return apperror.ErrInternal  // Database error
    }
    if user == nil {
        return apperror.ErrUserNotFound  // Not found
    }
    // Continue with user...
}
```

---

## 8. Transactions

For operations that must succeed or fail together:

```go
func (r *boardRepository) CreateWithLists(ctx context.Context, board *domain.Board, lists []string) error {
    // Start transaction
    tx, err := r.db.Begin(ctx)
    if err != nil {
        return err
    }
    // Rollback if we return with error
    defer tx.Rollback(ctx)
    
    // Create board
    _, err = tx.Exec(ctx, `INSERT INTO boards ...`, board.ID, board.Title)
    if err != nil {
        return err  // Rollback happens via defer
    }
    
    // Create default lists
    for _, title := range lists {
        _, err = tx.Exec(ctx, `INSERT INTO lists ...`, cuid.New(), board.ID, title)
        if err != nil {
            return err  // Rollback happens via defer
        }
    }
    
    // Commit transaction
    return tx.Commit(ctx)
}
```

**Transaction guarantees:**
- All operations succeed → Commit
- Any operation fails → Rollback (undo everything)

---

## 9. Complete Repository Example

**File:** `Backend/internal/repository/user_repository.go`

```go
package repository

import (
    "context"
    "errors"
    "time"

    "github.com/jackc/pgx/v5"
    "github.com/jackc/pgx/v5/pgxpool"

    "github.com/codewebkhongkho/trello-agent/internal/domain"
    "github.com/codewebkhongkho/trello-agent/pkg/cuid"
)

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
    now := time.Now()
    user.CreatedAt = now
    user.UpdatedAt = now
    user.TokensValidAfter = now

    query := `
        INSERT INTO users (id, email, password_hash, full_name, avatar_url, 
                          is_verified, is_active, tokens_valid_after, 
                          created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
    `
    _, err := r.db.Exec(ctx, query,
        user.ID, user.Email, user.PasswordHash, user.FullName, user.AvatarURL,
        user.IsVerified, user.IsActive, user.TokensValidAfter,
        user.CreatedAt, user.UpdatedAt,
    )
    return err
}

func (r *userRepository) FindByID(ctx context.Context, id string) (*domain.User, error) {
    query := `
        SELECT id, email, password_hash, full_name, avatar_url, 
               is_verified, is_active, tokens_valid_after, 
               created_at, updated_at, deleted_at
        FROM users
        WHERE id = $1 AND deleted_at IS NULL
    `
    var user domain.User
    err := r.db.QueryRow(ctx, query, id).Scan(
        &user.ID, &user.Email, &user.PasswordHash, &user.FullName, &user.AvatarURL,
        &user.IsVerified, &user.IsActive, &user.TokensValidAfter,
        &user.CreatedAt, &user.UpdatedAt, &user.DeletedAt,
    )
    if err != nil {
        if errors.Is(err, pgx.ErrNoRows) {
            return nil, nil
        }
        return nil, err
    }
    return &user, nil
}

func (r *userRepository) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
    query := `
        SELECT id, email, password_hash, full_name, avatar_url, 
               is_verified, is_active, tokens_valid_after, 
               created_at, updated_at, deleted_at
        FROM users
        WHERE email = $1 AND deleted_at IS NULL
    `
    var user domain.User
    err := r.db.QueryRow(ctx, query, email).Scan(
        &user.ID, &user.Email, &user.PasswordHash, &user.FullName, &user.AvatarURL,
        &user.IsVerified, &user.IsActive, &user.TokensValidAfter,
        &user.CreatedAt, &user.UpdatedAt, &user.DeletedAt,
    )
    if err != nil {
        if errors.Is(err, pgx.ErrNoRows) {
            return nil, nil
        }
        return nil, err
    }
    return &user, nil
}

func (r *userRepository) Update(ctx context.Context, user *domain.User) error {
    user.UpdatedAt = time.Now()
    query := `
        UPDATE users
        SET email = $2, full_name = $3, avatar_url = $4, 
            is_verified = $5, is_active = $6, updated_at = $7
        WHERE id = $1 AND deleted_at IS NULL
    `
    _, err := r.db.Exec(ctx, query,
        user.ID, user.Email, user.FullName, user.AvatarURL,
        user.IsVerified, user.IsActive, user.UpdatedAt,
    )
    return err
}

func (r *userRepository) SoftDelete(ctx context.Context, id string) error {
    query := `UPDATE users SET deleted_at = NOW() WHERE id = $1 AND deleted_at IS NULL`
    _, err := r.db.Exec(ctx, query, id)
    return err
}

func (r *userRepository) UpdateTokensValidAfter(ctx context.Context, id string) error {
    query := `UPDATE users SET tokens_valid_after = NOW(), updated_at = NOW() WHERE id = $1`
    _, err := r.db.Exec(ctx, query, id)
    return err
}
```

---

## Practice Exercises

### Exercise 1: Add Pagination

Modify `FindAll` to support pagination:
```go
func (r *userRepository) FindAll(ctx context.Context, page, limit int) ([]*domain.User, int, error)
```

Hint: Use `LIMIT $1 OFFSET $2` and `COUNT(*) OVER()` for total.

### Exercise 2: Create BoardRepository

Create a repository for boards with:
- `Create`, `FindByID`, `FindByOrgID`, `Update`, `SoftDelete`

---

## External Resources

| Resource | URL | Description |
|----------|-----|-------------|
| pgx Documentation | https://github.com/jackc/pgx | PostgreSQL driver |
| SQL Tutorial | https://www.w3schools.com/sql/ | SQL basics |
| Repository Pattern | https://martinfowler.com/eaaCatalog/repository.html | Pattern description |

---

## Key Takeaways

1. **Interface + Implementation** — Hide database details behind interface
2. **Parameterized queries** — ALWAYS use `$1, $2...` placeholders
3. **Connection pool** — Reuse connections for performance
4. **Soft delete** — Set `deleted_at` instead of DELETE
5. **Error handling** — `nil, nil` for not found, `nil, err` for errors
6. **Transactions** — Use for multi-step operations

---

## Next Lesson

Continue to **[Lesson 06: Service Layer](06_SERVICE_LAYER.md)** to learn how to implement business logic.
