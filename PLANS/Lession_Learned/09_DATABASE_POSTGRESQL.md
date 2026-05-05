# Lesson 09: PostgreSQL & Migrations

> Learn database design, SQL, and migration management.

---

## What You'll Learn

1. PostgreSQL basics
2. Database schema design
3. SQL CRUD operations
4. Database migrations with Goose
5. Indexes and performance

---

## 1. PostgreSQL Basics

PostgreSQL is a powerful, open-source relational database.

**Key concepts:**
- **Tables** — Store data in rows and columns
- **Columns** — Define data types (VARCHAR, INTEGER, BOOLEAN, etc.)
- **Primary Key** — Unique identifier for each row
- **Foreign Key** — Reference to another table
- **Indexes** — Speed up queries

---

## 2. Data Types

### Common PostgreSQL Types

| Type | Description | Example |
|------|-------------|---------|
| `VARCHAR(255)` | Variable-length string | Email, name |
| `TEXT` | Unlimited text | Description |
| `INTEGER` | Whole number | Count, age |
| `BIGINT` | Large number | File size in bytes |
| `BOOLEAN` | True/false | is_active |
| `TIMESTAMPTZ` | Date + time + timezone | created_at |
| `DOUBLE PRECISION` | Floating point | Position |
| `JSONB` | Binary JSON | Metadata |

### In Your Project

**File:** `Backend/migrations/00001_create_users.sql`

```sql
CREATE TABLE users (
    id                  VARCHAR(25) PRIMARY KEY,     -- CUID
    email               VARCHAR(255) NOT NULL,       -- Required string
    password_hash       VARCHAR(255) NOT NULL,       -- Required string
    full_name           VARCHAR(255) NOT NULL,       -- Required string
    avatar_url          TEXT,                        -- Optional (nullable)
    
    is_verified         BOOLEAN DEFAULT FALSE,       -- Boolean with default
    is_active           BOOLEAN DEFAULT TRUE,
    
    tokens_valid_after  TIMESTAMPTZ DEFAULT NOW(),   -- Timestamp
    
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ,                 -- Nullable (soft delete)
    
    CONSTRAINT uniq_users_email UNIQUE (email)       -- Unique constraint
);
```

---

## 3. Creating Tables

### Basic Table

```sql
CREATE TABLE boards (
    id                  VARCHAR(25) PRIMARY KEY,
    organization_id     VARCHAR(25) NOT NULL,
    
    title               VARCHAR(255) NOT NULL,
    description         TEXT,
    background_color    VARCHAR(7) DEFAULT '#0079bf',
    
    visibility          VARCHAR(20) DEFAULT 'workspace',
    is_closed           BOOLEAN DEFAULT FALSE,
    
    owner_id            VARCHAR(25) NOT NULL,
    
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ,
    
    -- Foreign keys
    CONSTRAINT fk_boards_organizations 
        FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
    CONSTRAINT fk_boards_owner 
        FOREIGN KEY (owner_id) REFERENCES users(id)
);
```

### Foreign Key Actions

| Action | Meaning |
|--------|---------|
| `ON DELETE CASCADE` | Delete child when parent deleted |
| `ON DELETE SET NULL` | Set to NULL when parent deleted |
| `ON DELETE RESTRICT` | Prevent deletion if children exist |

---

## 4. ENUM Types

PostgreSQL supports custom enum types:

**File:** `Backend/migrations/00004_create_organizations.sql`

```sql
-- Create enum type
CREATE TYPE org_role AS ENUM ('owner', 'admin', 'member');

-- Use in table
CREATE TABLE organization_members (
    id              VARCHAR(25) PRIMARY KEY,
    organization_id VARCHAR(25) NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id         VARCHAR(25) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    role            org_role NOT NULL DEFAULT 'member',  -- Uses enum
    
    joined_at       TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT uniq_org_member UNIQUE (organization_id, user_id)
);
```

---

## 5. Indexes

Indexes speed up queries but slow down writes.

### When to Create Indexes

```sql
-- 1. Primary keys (automatic)
id VARCHAR(25) PRIMARY KEY

-- 2. Foreign keys (always index)
CREATE INDEX idx_boards_org ON boards(organization_id);
CREATE INDEX idx_boards_owner ON boards(owner_id);

-- 3. Columns used in WHERE clauses
CREATE INDEX idx_users_email ON users(email);

-- 4. Columns used in ORDER BY
CREATE INDEX idx_lists_position ON lists(board_id, position);

-- 5. Unique constraints (automatic)
CONSTRAINT uniq_users_email UNIQUE (email)
```

### Partial Indexes

Only index rows that match a condition:

```sql
-- Only index non-deleted users
CREATE INDEX idx_users_active ON users(id) 
    WHERE deleted_at IS NULL AND is_active = TRUE;

-- Only index pending invitations
CREATE INDEX idx_invitations_pending ON board_invitations(token) 
    WHERE status = 'pending';

-- Only index unread notifications
CREATE INDEX idx_notifications_unread ON notifications(user_id) 
    WHERE is_read = FALSE;
```

---

## 6. SQL CRUD Operations

### Create (INSERT)

```sql
INSERT INTO users (id, email, password_hash, full_name, is_verified, is_active)
VALUES ($1, $2, $3, $4, $5, $6);
```

### Read (SELECT)

```sql
-- Single row
SELECT id, email, full_name, created_at
FROM users
WHERE id = $1 AND deleted_at IS NULL;

-- Multiple rows with filter
SELECT id, title, position
FROM lists
WHERE board_id = $1 AND is_archived = FALSE
ORDER BY position ASC;

-- With JOIN
SELECT b.*, o.name as organization_name
FROM boards b
JOIN organizations o ON o.id = b.organization_id
WHERE b.id = $1;
```

### Update

```sql
UPDATE users
SET email = $2, full_name = $3, updated_at = NOW()
WHERE id = $1 AND deleted_at IS NULL;
```

### Delete (Soft Delete)

```sql
-- Soft delete (preferred)
UPDATE users 
SET deleted_at = NOW() 
WHERE id = $1 AND deleted_at IS NULL;

-- Hard delete (avoid)
DELETE FROM users WHERE id = $1;
```

---

## 7. Database Migrations

Migrations are version-controlled changes to your database schema.

### Migration Files

**Directory:** `Backend/migrations/`

```
00001_create_users.sql
00002_create_refresh_tokens.sql
00003_create_email_verifications.sql
00004_create_organizations.sql
00005_create_organization_members.sql
...
```

### Migration File Format

**File:** `Backend/migrations/00001_create_users.sql`

```sql
-- +goose Up
-- +goose StatementBegin
CREATE TABLE users (
    id                  VARCHAR(25) PRIMARY KEY,
    email               VARCHAR(255) NOT NULL,
    password_hash       VARCHAR(255) NOT NULL,
    full_name           VARCHAR(255) NOT NULL,
    avatar_url          TEXT,
    is_verified         BOOLEAN DEFAULT FALSE,
    is_active           BOOLEAN DEFAULT TRUE,
    tokens_valid_after  TIMESTAMPTZ DEFAULT NOW(),
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ,
    CONSTRAINT uniq_users_email UNIQUE (email)
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_deleted_at ON users(deleted_at) WHERE deleted_at IS NULL;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS users;
-- +goose StatementEnd
```

### Goose Commands

```bash
# Create new migration
goose -dir migrations create add_user_role sql

# Apply all pending migrations
goose -dir migrations postgres "$DATABASE_URL" up

# Rollback last migration
goose -dir migrations postgres "$DATABASE_URL" down

# Check migration status
goose -dir migrations postgres "$DATABASE_URL" status

# Go to specific version
goose -dir migrations postgres "$DATABASE_URL" goto 20231225120000
```

---

## 8. Junction Tables (Many-to-Many)

For many-to-many relationships:

**Example:** Cards can have multiple Labels, Labels can be on multiple Cards

```sql
-- Labels table
CREATE TABLE labels (
    id          VARCHAR(25) PRIMARY KEY,
    board_id    VARCHAR(25) NOT NULL REFERENCES boards(id) ON DELETE CASCADE,
    name        VARCHAR(100),
    color       VARCHAR(7) NOT NULL
);

-- Junction table
CREATE TABLE card_labels (
    id          VARCHAR(25) PRIMARY KEY,
    card_id     VARCHAR(25) NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    label_id    VARCHAR(25) NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT uniq_card_label UNIQUE (card_id, label_id)
);

CREATE INDEX idx_card_labels_card ON card_labels(card_id);
CREATE INDEX idx_card_labels_label ON card_labels(label_id);
```

### Querying Many-to-Many

```sql
-- Get all labels for a card
SELECT l.*
FROM labels l
JOIN card_labels cl ON cl.label_id = l.id
WHERE cl.card_id = $1;

-- Get all cards with a specific label
SELECT c.*
FROM cards c
JOIN card_labels cl ON cl.card_id = c.id
WHERE cl.label_id = $1;
```

---

## 9. Position/Ordering Pattern

For drag-and-drop ordering (lists, cards):

```sql
CREATE TABLE lists (
    id          VARCHAR(25) PRIMARY KEY,
    board_id    VARCHAR(25) NOT NULL REFERENCES boards(id) ON DELETE CASCADE,
    title       VARCHAR(255) NOT NULL,
    position    DOUBLE PRECISION NOT NULL,  -- Float for easy reordering
    is_archived BOOLEAN DEFAULT FALSE,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_lists_position ON lists(board_id, position);
```

**Position Strategy:**
- Initial position: 65536, 131072, 196608...
- Insert between A and B: `(A + B) / 2`
- Rebalance when gap becomes too small

---

## 10. JSONB for Flexible Data

For unstructured or variable data:

```sql
CREATE TABLE activity_logs (
    id          VARCHAR(25) PRIMARY KEY,
    board_id    VARCHAR(25) NOT NULL REFERENCES boards(id),
    user_id     VARCHAR(25) NOT NULL REFERENCES users(id),
    action      VARCHAR(50) NOT NULL,
    
    -- Flexible metadata
    metadata    JSONB DEFAULT '{}',
    
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Index for querying JSONB
CREATE INDEX idx_activity_logs_metadata ON activity_logs USING GIN (metadata);
```

**Example metadata:**

```json
{
  "from_list_id": "list123",
  "from_list_title": "To Do",
  "to_list_id": "list456",
  "to_list_title": "In Progress"
}
```

**Querying JSONB:**

```sql
-- Get activities where card was moved to specific list
SELECT * FROM activity_logs
WHERE metadata->>'to_list_id' = 'list456';
```

---

## 11. Database Connection Pool

**File:** `Backend/pkg/database/postgres.go`

```go
import "github.com/jackc/pgx/v5/pgxpool"

func NewPostgresPool(cfg Config) (*pgxpool.Pool, error) {
    poolConfig, err := pgxpool.ParseConfig(cfg.URL)
    if err != nil {
        return nil, err
    }
    
    // Pool settings
    poolConfig.MaxConns = 10       // Maximum connections
    poolConfig.MinConns = 2        // Minimum idle connections
    
    pool, err := pgxpool.NewWithConfig(context.Background(), poolConfig)
    if err != nil {
        return nil, err
    }
    
    // Verify connection
    if err := pool.Ping(context.Background()); err != nil {
        return nil, err
    }
    
    return pool, nil
}
```

---

## 12. Your Database Schema

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DATABASE SCHEMA                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  users ──────────────────┬────────────────────────────────────────────────  │
│    │                     │                                                  │
│    ├── refresh_tokens    ├── organizations ────── organization_members     │
│    │                     │       │                                          │
│    └── email_verifications       └── boards ─────┬── board_members         │
│                                      │           ├── board_invitations     │
│                                      │           └── labels                 │
│                                      │                   │                  │
│                                      └── lists           │                  │
│                                           │              │                  │
│                                           └── cards ─────┼── card_labels   │
│                                               │          │                  │
│                                               ├── comments                  │
│                                               ├── checklists ── items       │
│                                               ├── attachments               │
│                                               ├── card_members              │
│                                               └── activity_logs             │
│                                                                             │
│  notifications (standalone, linked to users)                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Practice Exercises

### Exercise 1: Write a Migration

Create a migration for a `tags` table with:
- id, name, color
- belongs to organization
- soft delete support

### Exercise 2: Write Queries

Write SQL for:
1. Get all cards due this week
2. Get user's unread notification count
3. Get board members with their roles

---

## External Resources

| Resource | URL | Description |
|----------|-----|-------------|
| PostgreSQL Tutorial | https://www.postgresqltutorial.com | Comprehensive |
| SQL Tutorial | https://www.w3schools.com/sql/ | Basics |
| pgx Driver | https://github.com/jackc/pgx | Go driver |
| Goose | https://github.com/pressly/goose | Migrations |

---

## Key Takeaways

1. **Use appropriate types** — VARCHAR for bounded, TEXT for unbounded
2. **Always index foreign keys** — And columns in WHERE/ORDER BY
3. **Soft delete** — Use `deleted_at` instead of DELETE
4. **Migrations** — Version control your schema
5. **JSONB** — For flexible/metadata fields
6. **Connection pooling** — Essential for production

---

## Next Lesson

Continue to **[Lesson 10: JWT Authentication](10_JWT_AUTHENTICATION.md)** to learn about token-based authentication.
