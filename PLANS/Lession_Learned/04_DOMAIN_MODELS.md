# Lesson 04: Domain Models

> Learn how to design business entities using Go structs.

---

## What You'll Learn

1. What are domain models?
2. Struct tags for JSON and validation
3. Common patterns (enums, optional fields, timestamps)
4. Methods on domain models
5. Relationships between entities

---

## 1. What are Domain Models?

Domain models are **Go structs that represent business entities**. They are the core of your application.

In your TaskFlow project:
- `User` — A person who uses the app
- `Board` — A kanban board
- `Card` — A task on a board
- `Organization` — A workspace containing boards

---

## 2. Basic Domain Model

**File:** `Backend/internal/domain/user.go`

```go
package domain

import (
    "time"
)

type User struct {
    ID               string     `json:"id"`
    Email            string     `json:"email"`
    PasswordHash     string     `json:"-"`              // Never expose in JSON
    FullName         string     `json:"full_name"`
    AvatarURL        *string    `json:"avatar_url,omitempty"`
    IsVerified       bool       `json:"is_verified"`
    IsActive         bool       `json:"is_active"`
    TokensValidAfter time.Time  `json:"-"`              // Internal use only
    CreatedAt        time.Time  `json:"created_at"`
    UpdatedAt        time.Time  `json:"updated_at"`
    DeletedAt        *time.Time `json:"-"`              // Soft delete
}
```

### Breaking It Down

| Field | Type | Purpose |
|-------|------|---------|
| `ID` | `string` | Unique identifier (CUID) |
| `Email` | `string` | Required, unique |
| `PasswordHash` | `string` | Bcrypt hash, never exposed |
| `AvatarURL` | `*string` | Optional (pointer = nullable) |
| `IsVerified` | `bool` | Email verified? |
| `CreatedAt` | `time.Time` | Audit timestamp |
| `DeletedAt` | `*time.Time` | Soft delete marker |

---

## 3. Struct Tags

Struct tags are metadata attached to fields.

### JSON Tags

```go
type User struct {
    Email        string  `json:"email"`           // Use "email" in JSON
    PasswordHash string  `json:"-"`               // NEVER include in JSON
    AvatarURL    *string `json:"avatar_url,omitempty"` // Omit if nil/empty
}
```

**Tag Options:**

| Tag | Meaning |
|-----|---------|
| `json:"field_name"` | JSON field name |
| `json:"-"` | Never include in JSON |
| `json:",omitempty"` | Omit if zero value |
| `json:"name,omitempty"` | Custom name + omit if empty |

### Result When Converting to JSON

```go
user := User{
    Email:        "test@example.com",
    PasswordHash: "secret123",      // Will NOT appear
    AvatarURL:    nil,              // Will NOT appear (omitempty)
}
```

JSON output:
```json
{
  "email": "test@example.com"
}
```

---

## 4. Optional Fields (Pointers)

Use pointers for fields that can be `nil` (null in database).

```go
type User struct {
    AvatarURL *string    `json:"avatar_url,omitempty"`  // Can be nil
    DeletedAt *time.Time `json:"-"`                     // Can be nil
}
```

**Why Pointers?**

```go
// Without pointer - empty string is confusing
type User struct {
    AvatarURL string  // Is "" intentional or missing?
}

// With pointer - nil means "not set"
type User struct {
    AvatarURL *string  // nil = no avatar, "" = empty avatar URL
}
```

**Using Optional Fields:**

```go
// Check if set
if user.AvatarURL != nil {
    fmt.Println(*user.AvatarURL)  // Dereference to get value
}

// Set a value
url := "https://example.com/avatar.png"
user.AvatarURL = &url  // Take address of variable
```

---

## 5. Enums (Custom Types)

Go doesn't have enums, but you can create type-safe constants.

**File:** `Backend/internal/domain/board.go`

```go
package domain

// 1. Define a custom type
type BoardVisibility string

// 2. Define allowed values as constants
const (
    VisibilityPrivate   BoardVisibility = "private"
    VisibilityWorkspace BoardVisibility = "workspace"
    VisibilityPublic    BoardVisibility = "public"
)

// 3. Validation method
func (v BoardVisibility) IsValid() bool {
    switch v {
    case VisibilityPrivate, VisibilityWorkspace, VisibilityPublic:
        return true
    }
    return false
}

// 4. Use in struct
type Board struct {
    Visibility BoardVisibility `json:"visibility"`
}
```

**Benefits:**
- Type safety — can't accidentally use wrong string
- Self-documenting — allowed values are clear
- Validation — `IsValid()` method checks if value is allowed

**Another Example (Card Priority):**

```go
type CardPriority string

const (
    PriorityNone   CardPriority = "none"
    PriorityLow    CardPriority = "low"
    PriorityMedium CardPriority = "medium"
    PriorityHigh   CardPriority = "high"
)
```

---

## 6. Common Timestamp Pattern

Most entities have audit timestamps:

```go
type BaseEntity struct {
    ID        string     `json:"id"`
    CreatedAt time.Time  `json:"created_at"`
    UpdatedAt time.Time  `json:"updated_at"`
    DeletedAt *time.Time `json:"-"`  // Soft delete
}
```

**Soft Delete Pattern:**

```go
// Instead of actually deleting:
DELETE FROM users WHERE id = '123'

// We set deleted_at:
UPDATE users SET deleted_at = NOW() WHERE id = '123'

// And always filter:
SELECT * FROM users WHERE deleted_at IS NULL
```

---

## 7. Methods on Domain Models

Add methods for common operations and validation.

**File:** `Backend/internal/domain/user.go`

```go
func (u *User) IsDeleted() bool {
    return u.DeletedAt != nil
}
```

**File:** `Backend/internal/domain/board.go`

```go
const DefaultBackgroundColor = "#0079bf"

func (b *Board) IsDeleted() bool {
    return b.DeletedAt != nil
}
```

**More Examples:**

```go
// Check if token is valid
type RefreshToken struct {
    ExpiresAt time.Time
    IsRevoked bool
}

func (t *RefreshToken) IsExpired() bool {
    return time.Now().After(t.ExpiresAt)
}

func (t *RefreshToken) IsValid() bool {
    return !t.IsRevoked && !t.IsExpired()
}
```

---

## 8. Relationships Between Entities

### One-to-Many: Organization → Boards

```go
type Organization struct {
    ID      string   `json:"id"`
    Name    string   `json:"name"`
    OwnerID string   `json:"owner_id"`    // FK to User
    
    // Populated when needed
    Owner   *User    `json:"owner,omitempty"`
    Boards  []Board  `json:"boards,omitempty"`
}
```

### One-to-Many: Board → Lists → Cards

```go
type Board struct {
    ID             string `json:"id"`
    OrganizationID string `json:"organization_id"`
    
    Organization *Organization `json:"organization,omitempty"`
    Lists        []List        `json:"lists,omitempty"`
}

type List struct {
    ID      string `json:"id"`
    BoardID string `json:"board_id"`
    Title   string `json:"title"`
    
    Cards []Card `json:"cards,omitempty"`
}

type Card struct {
    ID          string  `json:"id"`
    ListID      string  `json:"list_id"`
    Title       string  `json:"title"`
    Description *string `json:"description,omitempty"`
}
```

### Many-to-Many: Card ↔ Labels

Use a junction table:

```go
// Domain models
type Card struct {
    ID     string  `json:"id"`
    Labels []Label `json:"labels,omitempty"`
}

type Label struct {
    ID    string `json:"id"`
    Name  string `json:"name"`
    Color string `json:"color"`
}

// Junction model (usually not in domain, just in database)
type CardLabel struct {
    CardID     string
    LabelID    string
    AssignedAt time.Time
}
```

---

## 9. Complete Board Example

**File:** `Backend/internal/domain/board.go`

```go
package domain

import (
    "time"
)

type BoardVisibility string

const (
    VisibilityPrivate   BoardVisibility = "private"
    VisibilityWorkspace BoardVisibility = "workspace"
    VisibilityPublic    BoardVisibility = "public"
)

func (v BoardVisibility) IsValid() bool {
    switch v {
    case VisibilityPrivate, VisibilityWorkspace, VisibilityPublic:
        return true
    }
    return false
}

type Board struct {
    // Primary key
    ID string `json:"id"`
    
    // Foreign key
    OrganizationID string `json:"organization_id"`
    
    // Data fields
    Title           string          `json:"title"`
    Description     *string         `json:"description,omitempty"`
    BackgroundColor string          `json:"background_color"`
    BackgroundImage *string         `json:"background_image,omitempty"`
    Visibility      BoardVisibility `json:"visibility"`
    IsClosed        bool            `json:"is_closed"`
    
    // Owner (creator)
    OwnerID string `json:"owner_id"`
    
    // Timestamps
    CreatedAt time.Time  `json:"created_at"`
    UpdatedAt time.Time  `json:"updated_at"`
    ClosedAt  *time.Time `json:"closed_at,omitempty"`
    DeletedAt *time.Time `json:"-"`
    
    // Relations (populated when needed)
    Organization *Organization `json:"organization,omitempty"`
}

func (b *Board) IsDeleted() bool {
    return b.DeletedAt != nil
}

const DefaultBackgroundColor = "#0079bf"
```

---

## 10. Naming Conventions

| Item | Convention | Example |
|------|------------|---------|
| Struct name | PascalCase, singular | `User`, `Board`, `Card` |
| Field name | PascalCase | `FullName`, `CreatedAt` |
| JSON key | snake_case | `full_name`, `created_at` |
| Boolean | `Is`, `Has`, `Can` prefix | `IsActive`, `HasCover` |
| Foreign key | Entity + ID | `UserID`, `BoardID` |
| Timestamps | Event + At | `CreatedAt`, `DeletedAt` |

---

## Practice Exercises

### Exercise 1: Design a Comment Model

Design a `Comment` domain model with:
- ID, content, author
- Parent comment (for replies)
- Edit tracking
- Soft delete

### Exercise 2: Add Methods

Add these methods to `Board`:
- `IsOpen()` — returns true if not closed
- `IsPublic()` — returns true if visibility is public

### Exercise 3: Create an Enum

Create a `CardPriority` enum with:
- Values: none, low, medium, high
- `IsValid()` method
- `String()` method that returns display name

---

## External Resources

| Resource | URL | Description |
|----------|-----|-------------|
| Go Struct Tags | https://www.digitalocean.com/community/tutorials/how-to-use-struct-tags-in-go | Comprehensive guide |
| JSON in Go | https://go.dev/blog/json | Official blog |
| Domain-Driven Design | https://martinfowler.com/tags/domain%20driven%20design.html | Concepts |

---

## Key Takeaways

1. **Domain models = business entities** as Go structs
2. **Struct tags** control JSON serialization
3. **Pointers** for optional/nullable fields
4. **Custom types** for enums with validation
5. **Methods** for domain logic and validation
6. **Timestamps** for auditing (created, updated, deleted)

---

## Next Lesson

Continue to **[Lesson 05: Repository Pattern](05_REPOSITORY_PATTERN.md)** to learn how to persist domain models.
