# TaskFlow — Database Design

> PostgreSQL 16 schema cho ứng dụng Kanban board multi-tenant.

---

## Tổng quan

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DATABASE SCHEMA                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────┐      ┌──────────────────┐      ┌─────────────────┐            │
│  │  users  │──────│ refresh_tokens   │      │ email_verifications │        │
│  └────┬────┘      └──────────────────┘      └─────────────────┘            │
│       │                                                                     │
│       │ 1:N                                                                 │
│       ▼                                                                     │
│  ┌──────────────┐                                                          │
│  │ organizations │ (workspaces)                                            │
│  └───────┬──────┘                                                          │
│          │                                                                  │
│    ┌─────┴─────┐                                                           │
│    │           │                                                            │
│    ▼           ▼                                                            │
│ ┌────────────────────┐    ┌────────┐                                       │
│ │ organization_members│    │ boards │                                       │
│ └────────────────────┘    └───┬────┘                                       │
│                               │                                             │
│         ┌─────────────────────┼─────────────────────┐                      │
│         │                     │                     │                       │
│         ▼                     ▼                     ▼                       │
│  ┌──────────────┐      ┌───────────┐      ┌─────────────────┐              │
│  │ board_members│      │   lists   │      │ board_invitations│              │
│  └──────────────┘      └─────┬─────┘      └─────────────────┘              │
│                              │                                              │
│         ┌────────────────────┼────────────────────┐                        │
│         │                    │                    │                         │
│         ▼                    ▼                    ▼                         │
│    ┌─────────┐         ┌─────────┐         ┌───────────┐                   │
│    │  cards  │─────────│ labels  │         │ notifications│                │
│    └────┬────┘         └─────────┘         └───────────┘                   │
│         │                                                                   │
│    ┌────┴────┬────────────┬────────────┬────────────┐                      │
│    │         │            │            │            │                       │
│    ▼         ▼            ▼            ▼            ▼                       │
│ ┌────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐ ┌──────────────┐        │
│ │comments│ │checklists│ │attachments│ │card_labels│ │activity_logs │        │
│ └────────┘ └────┬─────┘ └──────────┘ └───────────┘ └──────────────┘        │
│                 │                                                           │
│                 ▼                                                           │
│          ┌─────────────────┐                                               │
│          │ checklist_items │                                               │
│          └─────────────────┘                                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Quy ước đặt tên

| Loại | Quy tắc | Ví dụ |
|------|---------|-------|
| Tables | snake_case, plural | `users`, `organization_members` |
| Columns | snake_case | `created_at`, `user_id` |
| Primary Key | `id` (CUID) | `id VARCHAR(25)` |
| Foreign Key | `{table_singular}_id` | `user_id`, `board_id` |
| Indexes | `idx_{table}_{columns}` | `idx_users_email` |
| Unique | `uniq_{table}_{columns}` | `uniq_users_email` |
| Foreign Key Constraint | `fk_{child}_{parent}` | `fk_cards_lists` |
| Timestamps | `{event}_at` | `created_at`, `deleted_at` |
| Booleans | `is_`, `has_`, `can_` | `is_active`, `has_cover` |

---

## 1. Authentication Tables

### 1.1 users

```sql
CREATE TABLE users (
    id                  VARCHAR(25) PRIMARY KEY,  -- CUID
    email               VARCHAR(255) NOT NULL,
    password_hash       VARCHAR(255) NOT NULL,
    full_name           VARCHAR(255) NOT NULL,
    avatar_url          TEXT,
    
    -- Status flags
    is_verified         BOOLEAN DEFAULT FALSE,
    is_active           BOOLEAN DEFAULT TRUE,
    
    -- Security: mass token invalidation
    tokens_valid_after  TIMESTAMPTZ DEFAULT NOW(),
    
    -- Timestamps
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ,              -- Soft delete
    
    CONSTRAINT uniq_users_email UNIQUE (email)
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_deleted_at ON users(deleted_at) WHERE deleted_at IS NULL;
```

**Ghi chú:**
- `tokens_valid_after`: Khi set = NOW(), tất cả AT có `iat < tokens_valid_after` bị từ chối
- Dùng cho: reuse detection, reset password, admin disable account

---

### 1.2 refresh_tokens

```sql
CREATE TABLE refresh_tokens (
    id              VARCHAR(25) PRIMARY KEY,
    user_id         VARCHAR(25) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Token storage (SHA-256 hash, NOT raw token)
    token_hash      VARCHAR(64) NOT NULL,         -- SHA-256 = 64 hex chars
    
    -- Metadata
    device_info     VARCHAR(255),                 -- User-Agent
    ip_address      VARCHAR(45),                  -- IPv6 max length
    
    -- Status
    is_revoked      BOOLEAN DEFAULT FALSE,
    expires_at      TIMESTAMPTZ NOT NULL,
    
    -- Timestamps
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    revoked_at      TIMESTAMPTZ,
    
    CONSTRAINT uniq_refresh_tokens_hash UNIQUE (token_hash)
);

CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at) 
    WHERE is_revoked = FALSE;
```

**Ghi chú:**
- Lưu SHA-256 hash của raw JWT, KHÔNG lưu raw token
- `is_revoked = true` + token bị dùng lại → trigger reuse detection

---

### 1.3 email_verifications

```sql
CREATE TABLE email_verifications (
    id          VARCHAR(25) PRIMARY KEY,
    user_id     VARCHAR(25) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Token/OTP
    token       VARCHAR(64) NOT NULL,             -- OTP (6 digits) hoặc reset token (64 hex)
    type        VARCHAR(20) NOT NULL,             -- 'verify_email' | 'reset_password'
    
    -- Status
    expires_at  TIMESTAMPTZ NOT NULL,
    used_at     TIMESTAMPTZ,                      -- NULL = chưa dùng
    
    -- Timestamps
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_email_verifications_user_type ON email_verifications(user_id, type);
CREATE INDEX idx_email_verifications_token ON email_verifications(token, type);
```

---

## 2. Organization (Workspace) Tables

### 2.1 organizations

```sql
CREATE TABLE organizations (
    id              VARCHAR(25) PRIMARY KEY,
    name            VARCHAR(255) NOT NULL,
    slug            VARCHAR(100) NOT NULL,        -- URL-friendly unique identifier
    description     TEXT,
    logo_url        TEXT,
    
    -- Owner (creator)
    owner_id        VARCHAR(25) NOT NULL REFERENCES users(id),
    
    -- Timestamps
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ,
    
    CONSTRAINT uniq_organizations_slug UNIQUE (slug)
);

CREATE INDEX idx_organizations_slug ON organizations(slug);
CREATE INDEX idx_organizations_owner ON organizations(owner_id);
CREATE INDEX idx_organizations_deleted ON organizations(deleted_at) WHERE deleted_at IS NULL;
```

---

### 2.2 organization_members

```sql
CREATE TYPE org_role AS ENUM ('owner', 'admin', 'member');

CREATE TABLE organization_members (
    id              VARCHAR(25) PRIMARY KEY,
    organization_id VARCHAR(25) NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id         VARCHAR(25) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    role            org_role NOT NULL DEFAULT 'member',
    
    -- Timestamps
    joined_at       TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT uniq_org_member UNIQUE (organization_id, user_id)
);

CREATE INDEX idx_org_members_org ON organization_members(organization_id);
CREATE INDEX idx_org_members_user ON organization_members(user_id);
```

**Permission Matrix:**

| Action | Owner | Admin | Member |
|--------|:-----:|:-----:|:------:|
| View workspace | ✅ | ✅ | ✅ |
| Create board | ✅ | ✅ | ✅ |
| Edit workspace settings | ✅ | ✅ | ❌ |
| Invite members | ✅ | ✅ | ❌ |
| Remove members | ✅ | ✅ | ❌ |
| Delete workspace | ✅ | ❌ | ❌ |
| Transfer ownership | ✅ | ❌ | ❌ |

---

## 3. Board Tables

### 3.1 boards

```sql
CREATE TYPE board_visibility AS ENUM ('private', 'workspace', 'public');

CREATE TABLE boards (
    id                  VARCHAR(25) PRIMARY KEY,
    organization_id     VARCHAR(25) NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    
    title               VARCHAR(255) NOT NULL,
    description         TEXT,
    background_color    VARCHAR(7) DEFAULT '#0079bf',  -- Hex color
    background_image    TEXT,                          -- MinIO URL
    
    visibility          board_visibility DEFAULT 'workspace',
    is_closed           BOOLEAN DEFAULT FALSE,
    
    -- Owner (creator)
    owner_id            VARCHAR(25) NOT NULL REFERENCES users(id),
    
    -- Timestamps
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    closed_at           TIMESTAMPTZ,
    deleted_at          TIMESTAMPTZ,
    
    CONSTRAINT fk_boards_organizations FOREIGN KEY (organization_id) 
        REFERENCES organizations(id) ON DELETE CASCADE
);

CREATE INDEX idx_boards_org ON boards(organization_id);
CREATE INDEX idx_boards_owner ON boards(owner_id);
CREATE INDEX idx_boards_visibility ON boards(visibility);
CREATE INDEX idx_boards_deleted ON boards(deleted_at) WHERE deleted_at IS NULL;
```

---

### 3.2 board_members

```sql
CREATE TYPE board_role AS ENUM ('owner', 'admin', 'member', 'viewer');

CREATE TABLE board_members (
    id          VARCHAR(25) PRIMARY KEY,
    board_id    VARCHAR(25) NOT NULL REFERENCES boards(id) ON DELETE CASCADE,
    user_id     VARCHAR(25) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    role        board_role NOT NULL DEFAULT 'member',
    
    -- Timestamps
    joined_at   TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT uniq_board_member UNIQUE (board_id, user_id)
);

CREATE INDEX idx_board_members_board ON board_members(board_id);
CREATE INDEX idx_board_members_user ON board_members(user_id);
```

**Permission Matrix:**

| Action | Owner | Admin | Member | Viewer |
|--------|:-----:|:-----:|:------:|:------:|
| View board | ✅ | ✅ | ✅ | ✅ |
| Create/edit cards | ✅ | ✅ | ✅ | ❌ |
| Create/edit lists | ✅ | ✅ | ✅ | ❌ |
| Manage labels | ✅ | ✅ | ❌ | ❌ |
| Invite members | ✅ | ✅ | ❌ | ❌ |
| Edit board settings | ✅ | ✅ | ❌ | ❌ |
| Delete board | ✅ | ❌ | ❌ | ❌ |

---

### 3.3 board_invitations

```sql
CREATE TYPE invitation_status AS ENUM ('pending', 'accepted', 'declined', 'expired');

CREATE TABLE board_invitations (
    id              VARCHAR(25) PRIMARY KEY,
    board_id        VARCHAR(25) NOT NULL REFERENCES boards(id) ON DELETE CASCADE,
    
    -- Inviter
    inviter_id      VARCHAR(25) NOT NULL REFERENCES users(id),
    
    -- Invitee (có thể là existing user hoặc email mới)
    invitee_id      VARCHAR(25) REFERENCES users(id),     -- NULL nếu user chưa tồn tại
    invitee_email   VARCHAR(255) NOT NULL,
    
    -- Invitation details
    role            board_role NOT NULL DEFAULT 'member',
    token           VARCHAR(64) NOT NULL,                  -- Invite link token
    message         TEXT,
    
    -- Status
    status          invitation_status DEFAULT 'pending',
    expires_at      TIMESTAMPTZ NOT NULL,
    
    -- Timestamps
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    responded_at    TIMESTAMPTZ,
    
    CONSTRAINT uniq_board_invitation UNIQUE (board_id, invitee_email, status)
);

CREATE INDEX idx_board_invitations_board ON board_invitations(board_id);
CREATE INDEX idx_board_invitations_email ON board_invitations(invitee_email);
CREATE INDEX idx_board_invitations_token ON board_invitations(token);
CREATE INDEX idx_board_invitations_status ON board_invitations(status) WHERE status = 'pending';
```

---

## 4. List & Card Tables

### 4.1 lists

```sql
CREATE TABLE lists (
    id          VARCHAR(25) PRIMARY KEY,
    board_id    VARCHAR(25) NOT NULL REFERENCES boards(id) ON DELETE CASCADE,
    
    title       VARCHAR(255) NOT NULL,
    position    DOUBLE PRECISION NOT NULL,        -- Float for O(1) reorder
    
    is_archived BOOLEAN DEFAULT FALSE,
    
    -- Timestamps
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW(),
    archived_at TIMESTAMPTZ
);

CREATE INDEX idx_lists_board ON lists(board_id);
CREATE INDEX idx_lists_position ON lists(board_id, position);
CREATE INDEX idx_lists_archived ON lists(is_archived) WHERE is_archived = FALSE;
```

**Position Strategy:**
- Khi tạo mới: `position = MAX(position) + 65536`
- Khi insert giữa A và B: `position = (A.position + B.position) / 2`
- Rebalance khi `|A - B| < 1`: set lại toàn bộ position trong board

---

### 4.2 cards

```sql
CREATE TYPE card_priority AS ENUM ('none', 'low', 'medium', 'high');

CREATE TABLE cards (
    id              VARCHAR(25) PRIMARY KEY,
    list_id         VARCHAR(25) NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
    
    -- Content
    title           VARCHAR(255) NOT NULL,
    description     TEXT,
    
    -- Position (float for O(1) reorder)
    position        DOUBLE PRECISION NOT NULL,
    
    -- Assignment & status
    assignee_id     VARCHAR(25) REFERENCES users(id) ON DELETE SET NULL,
    priority        card_priority DEFAULT 'none',
    due_date        TIMESTAMPTZ,
    is_completed    BOOLEAN DEFAULT FALSE,
    completed_at    TIMESTAMPTZ,
    
    -- Cover image (from attachments)
    cover_attachment_id VARCHAR(25),              -- FK added later
    
    -- Archive
    is_archived     BOOLEAN DEFAULT FALSE,
    
    -- Timestamps
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    archived_at     TIMESTAMPTZ,
    
    -- Creator
    created_by      VARCHAR(25) REFERENCES users(id)
);

CREATE INDEX idx_cards_list ON cards(list_id);
CREATE INDEX idx_cards_position ON cards(list_id, position);
CREATE INDEX idx_cards_assignee ON cards(assignee_id);
CREATE INDEX idx_cards_due_date ON cards(due_date) WHERE due_date IS NOT NULL;
CREATE INDEX idx_cards_archived ON cards(is_archived) WHERE is_archived = FALSE;
```

---

### 4.3 card_members (watchers)

```sql
CREATE TABLE card_members (
    id          VARCHAR(25) PRIMARY KEY,
    card_id     VARCHAR(25) NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    user_id     VARCHAR(25) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    added_at    TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT uniq_card_member UNIQUE (card_id, user_id)
);

CREATE INDEX idx_card_members_card ON card_members(card_id);
CREATE INDEX idx_card_members_user ON card_members(user_id);
```

---

## 5. Labels

### 5.1 labels

```sql
CREATE TABLE labels (
    id          VARCHAR(25) PRIMARY KEY,
    board_id    VARCHAR(25) NOT NULL REFERENCES boards(id) ON DELETE CASCADE,
    
    name        VARCHAR(100),
    color       VARCHAR(7) NOT NULL,              -- Hex color (#FF0000)
    
    -- Timestamps
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_labels_board ON labels(board_id);
```

---

### 5.2 card_labels

```sql
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

---

## 6. Checklists

### 6.1 checklists

```sql
CREATE TABLE checklists (
    id          VARCHAR(25) PRIMARY KEY,
    card_id     VARCHAR(25) NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    
    title       VARCHAR(255) NOT NULL,
    position    DOUBLE PRECISION NOT NULL,
    
    -- Timestamps
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_checklists_card ON checklists(card_id);
CREATE INDEX idx_checklists_position ON checklists(card_id, position);
```

---

### 6.2 checklist_items

```sql
CREATE TABLE checklist_items (
    id              VARCHAR(25) PRIMARY KEY,
    checklist_id    VARCHAR(25) NOT NULL REFERENCES checklists(id) ON DELETE CASCADE,
    
    title           VARCHAR(500) NOT NULL,
    position        DOUBLE PRECISION NOT NULL,
    
    -- Status
    is_completed    BOOLEAN DEFAULT FALSE,
    completed_at    TIMESTAMPTZ,
    completed_by    VARCHAR(25) REFERENCES users(id),
    
    -- Optional assignment
    assignee_id     VARCHAR(25) REFERENCES users(id) ON DELETE SET NULL,
    due_date        TIMESTAMPTZ,
    
    -- Timestamps
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_checklist_items_checklist ON checklist_items(checklist_id);
CREATE INDEX idx_checklist_items_position ON checklist_items(checklist_id, position);
CREATE INDEX idx_checklist_items_assignee ON checklist_items(assignee_id);
```

---

## 7. Comments

```sql
CREATE TABLE comments (
    id          VARCHAR(25) PRIMARY KEY,
    card_id     VARCHAR(25) NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    
    -- Author
    author_id   VARCHAR(25) NOT NULL REFERENCES users(id),
    
    -- Content
    content     TEXT NOT NULL,
    
    -- Threading (1-level only)
    parent_id   VARCHAR(25) REFERENCES comments(id) ON DELETE CASCADE,
    
    -- Edit tracking
    is_edited   BOOLEAN DEFAULT FALSE,
    
    -- Timestamps
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ                       -- Soft delete
);

CREATE INDEX idx_comments_card ON comments(card_id);
CREATE INDEX idx_comments_author ON comments(author_id);
CREATE INDEX idx_comments_parent ON comments(parent_id);
CREATE INDEX idx_comments_deleted ON comments(deleted_at) WHERE deleted_at IS NULL;
```

---

## 8. Attachments

```sql
CREATE TABLE attachments (
    id              VARCHAR(25) PRIMARY KEY,
    card_id         VARCHAR(25) NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    
    -- Uploader
    uploaded_by     VARCHAR(25) NOT NULL REFERENCES users(id),
    
    -- File info
    filename        VARCHAR(255) NOT NULL,
    original_name   VARCHAR(255) NOT NULL,
    mime_type       VARCHAR(100) NOT NULL,
    file_size       BIGINT NOT NULL,              -- Bytes
    
    -- MinIO storage
    object_key      VARCHAR(500) NOT NULL,        -- MinIO object path
    url             TEXT NOT NULL,                -- Public/signed URL
    
    -- Cover flag
    is_cover        BOOLEAN DEFAULT FALSE,
    
    -- Timestamps
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_attachments_card ON attachments(card_id);
CREATE INDEX idx_attachments_uploader ON attachments(uploaded_by);
CREATE INDEX idx_attachments_cover ON attachments(card_id, is_cover) WHERE is_cover = TRUE;

-- Add FK to cards for cover
ALTER TABLE cards 
    ADD CONSTRAINT fk_cards_cover_attachment 
    FOREIGN KEY (cover_attachment_id) REFERENCES attachments(id) ON DELETE SET NULL;
```

---

## 9. Activity Logs

```sql
CREATE TYPE activity_action AS ENUM (
    -- Card actions
    'card_created', 'card_updated', 'card_moved', 'card_archived', 'card_deleted',
    'card_assigned', 'card_unassigned', 'card_completed', 'card_reopened',
    'card_due_date_set', 'card_due_date_removed',
    
    -- List actions
    'list_created', 'list_renamed', 'list_moved', 'list_archived',
    
    -- Label actions
    'label_added', 'label_removed',
    
    -- Checklist actions
    'checklist_created', 'checklist_deleted',
    'checklist_item_completed', 'checklist_item_uncompleted',
    
    -- Comment actions
    'comment_added', 'comment_edited', 'comment_deleted',
    
    -- Attachment actions
    'attachment_added', 'attachment_deleted', 'cover_set', 'cover_removed',
    
    -- Member actions
    'member_added', 'member_removed'
);

CREATE TABLE activity_logs (
    id          VARCHAR(25) PRIMARY KEY,
    
    -- Context
    board_id    VARCHAR(25) NOT NULL REFERENCES boards(id) ON DELETE CASCADE,
    card_id     VARCHAR(25) REFERENCES cards(id) ON DELETE SET NULL,
    list_id     VARCHAR(25) REFERENCES lists(id) ON DELETE SET NULL,
    
    -- Actor
    user_id     VARCHAR(25) NOT NULL REFERENCES users(id),
    
    -- Action
    action      activity_action NOT NULL,
    
    -- Flexible metadata (JSONB for various action details)
    metadata    JSONB DEFAULT '{}',
    
    -- Human-readable (pre-rendered, Vietnamese)
    description TEXT,
    
    -- Timestamp
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_activity_logs_board ON activity_logs(board_id);
CREATE INDEX idx_activity_logs_card ON activity_logs(card_id);
CREATE INDEX idx_activity_logs_user ON activity_logs(user_id);
CREATE INDEX idx_activity_logs_created ON activity_logs(created_at DESC);
CREATE INDEX idx_activity_logs_metadata ON activity_logs USING GIN (metadata);
```

**Metadata Examples:**

```json
// card_moved
{
  "from_list_id": "...",
  "from_list_title": "To Do",
  "to_list_id": "...",
  "to_list_title": "In Progress"
}

// card_assigned
{
  "assignee_id": "...",
  "assignee_name": "Nguyen Van A"
}

// label_added
{
  "label_id": "...",
  "label_name": "Bug",
  "label_color": "#FF0000"
}
```

---

## 10. Notifications

```sql
CREATE TYPE notification_type AS ENUM (
    'card_assigned',
    'card_due_soon',
    'card_overdue',
    'comment_added',
    'comment_reply',
    'mentioned',
    'board_invitation',
    'checklist_item_assigned'
);

CREATE TABLE notifications (
    id              VARCHAR(25) PRIMARY KEY,
    user_id         VARCHAR(25) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Type and content
    type            notification_type NOT NULL,
    title           VARCHAR(255) NOT NULL,
    message         TEXT,
    
    -- Related entities
    board_id        VARCHAR(25) REFERENCES boards(id) ON DELETE CASCADE,
    card_id         VARCHAR(25) REFERENCES cards(id) ON DELETE CASCADE,
    
    -- Actor (who triggered this notification)
    actor_id        VARCHAR(25) REFERENCES users(id) ON DELETE SET NULL,
    
    -- Status
    is_read         BOOLEAN DEFAULT FALSE,
    read_at         TIMESTAMPTZ,
    
    -- Metadata
    metadata        JSONB DEFAULT '{}',
    
    -- Timestamps
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_unread ON notifications(user_id, is_read) WHERE is_read = FALSE;
CREATE INDEX idx_notifications_created ON notifications(created_at DESC);
CREATE INDEX idx_notifications_type ON notifications(type);
```

---

## 11. Indexes Summary

### Performance-Critical Indexes

| Table | Index | Purpose |
|-------|-------|---------|
| `users` | `idx_users_email` | Login lookup |
| `refresh_tokens` | `idx_refresh_tokens_hash` | Token validation |
| `lists` | `idx_lists_position` | Board rendering |
| `cards` | `idx_cards_position` | List rendering |
| `cards` | `idx_cards_due_date` | Due date reminders |
| `activity_logs` | `idx_activity_logs_created` | Activity stream |
| `notifications` | `idx_notifications_unread` | Unread count |

### Partial Indexes (Performance Optimization)

```sql
-- Only non-deleted records
CREATE INDEX idx_users_active ON users(id) WHERE deleted_at IS NULL AND is_active = TRUE;

-- Only pending invitations
CREATE INDEX idx_invitations_pending ON board_invitations(token) WHERE status = 'pending';

-- Only non-archived cards
CREATE INDEX idx_cards_active ON cards(list_id, position) WHERE is_archived = FALSE;

-- Only unread notifications
CREATE INDEX idx_notifications_unread ON notifications(user_id) WHERE is_read = FALSE;
```

---

## 12. Migration Strategy

### Migration Files (Goose)

```
migrations/
├── 00001_create_users.sql
├── 00002_create_refresh_tokens.sql
├── 00003_create_email_verifications.sql
├── 00004_create_organizations.sql
├── 00005_create_organization_members.sql
├── 00006_create_boards.sql
├── 00007_create_board_members.sql
├── 00008_create_board_invitations.sql
├── 00009_create_lists.sql
├── 00010_create_cards.sql
├── 00011_create_card_members.sql
├── 00012_create_labels.sql
├── 00013_create_card_labels.sql
├── 00014_create_checklists.sql
├── 00015_create_checklist_items.sql
├── 00016_create_comments.sql
├── 00017_create_attachments.sql
├── 00018_create_activity_logs.sql
├── 00019_create_notifications.sql
└── 00020_add_indexes.sql
```

### Commands

```bash
# Create new migration
goose -dir migrations create add_feature sql

# Apply migrations
goose -dir migrations postgres "$DATABASE_URL" up

# Rollback last migration
goose -dir migrations postgres "$DATABASE_URL" down

# Check status
goose -dir migrations postgres "$DATABASE_URL" status
```

---

## 13. CUID Generation (Go)

```go
// pkg/cuid/cuid.go
import "github.com/nrednav/cuid2"

func New() string {
    return cuid2.Generate()
}

// Usage in repository
func (r *UserRepository) Create(ctx context.Context, user *model.User) error {
    user.ID = cuid.New()
    // ...
}
```

---

## 14. Soft Delete Pattern

```go
// Soft delete query
UPDATE users SET deleted_at = NOW() WHERE id = $1

// Query with soft delete filter
SELECT * FROM users WHERE id = $1 AND deleted_at IS NULL

// sqlc annotation
-- name: GetUser :one
SELECT * FROM users WHERE id = $1 AND deleted_at IS NULL;
```

---

## 15. Position Rebalancing

```go
// pkg/position/position.go
const (
    InitialGap = 65536.0
    MinGap     = 1.0
)

func Initial() float64 {
    return InitialGap
}

func Between(a, b float64) float64 {
    return (a + b) / 2
}

func NeedsRebalance(a, b float64) bool {
    return math.Abs(a-b) < MinGap
}

// Rebalance all positions in a list
func Rebalance(items []Positionable) {
    for i, item := range items {
        item.SetPosition(float64(i+1) * InitialGap)
    }
}
```

---

## 16. Redis Keys (Auth Related)

| Key Pattern | Value | TTL | Purpose |
|-------------|-------|-----|---------|
| `blacklist:<jti>` | `"logout"` / `"revoked"` | AT remaining TTL | JWT blacklist |
| `ratelimit:login:<ip>` | count | 15 min | Login rate limit |
| `ratelimit:register:<ip>` | count | 1 hour | Register rate limit |
| `otp_attempts:<email>` | count | 15 min | OTP brute force protection |
| `sse:user:<user_id>` | connection info | 30 min | SSE connection tracking |

---

## 17. ERD Relationships Summary

| Parent | Child | Relationship | On Delete |
|--------|-------|--------------|-----------|
| users | refresh_tokens | 1:N | CASCADE |
| users | email_verifications | 1:N | CASCADE |
| users | organizations (owner) | 1:N | RESTRICT |
| organizations | organization_members | 1:N | CASCADE |
| organizations | boards | 1:N | CASCADE |
| boards | board_members | 1:N | CASCADE |
| boards | board_invitations | 1:N | CASCADE |
| boards | lists | 1:N | CASCADE |
| boards | labels | 1:N | CASCADE |
| lists | cards | 1:N | CASCADE |
| cards | card_members | 1:N | CASCADE |
| cards | card_labels | 1:N | CASCADE |
| cards | checklists | 1:N | CASCADE |
| cards | comments | 1:N | CASCADE |
| cards | attachments | 1:N | CASCADE |
| cards | activity_logs | 1:N | SET NULL |
| checklists | checklist_items | 1:N | CASCADE |
| users | notifications | 1:N | CASCADE |

---

## 18. Table Statistics (Estimated)

| Table | Est. Rows/User | Est. Total (10k users) |
|-------|---------------:|----------------------:|
| users | 1 | 10,000 |
| organizations | 2 | 20,000 |
| boards | 10 | 100,000 |
| lists | 50 | 500,000 |
| cards | 200 | 2,000,000 |
| comments | 500 | 5,000,000 |
| activity_logs | 1,000 | 10,000,000 |
| notifications | 500 | 5,000,000 |

**Recommendations:**
- Partition `activity_logs` by `created_at` (monthly)
- Archive old notifications after 90 days
- Use read replicas for dashboard queries
