# TaskFlow — Project Overview (Go Edition)

> Ứng dụng quản lý công việc theo phong cách Kanban (Trello-style), xây dựng Full-Stack với **Go + React**.
> Dự án được **reset và tái xây dựng** từ đầu với backend hoàn toàn mới bằng Go.

---

## Thông tin dự án

| Mục | Chi tiết |
|---|---|
| **Tên dự án** | TaskFlow |
| **Mô hình** | Kanban board — Multi-tenant Workspace |
| **Trạng thái** | 🔄 Đang tái xây dựng |
| **Backend** | Go (Gin / Fiber hoặc Echo) |
| **Frontend** | React 18 SPA (giữ nguyên) |
| **Repository** | git@github.com:tntduy1112-maker/Trello_Backend_Golang_1st.git |

---

## Technology Decision: Go over Node.js

| Criterion | Go | Node.js |
|-----------|-----|---------|
| **Concurrency** | Native goroutines, lightweight | Event loop, single-threaded |
| **Performance** | Compiled, low latency (~2-5ms P99) | Interpreted, higher latency |
| **Type Safety** | Static typing at compile time | Runtime errors (even with TS) |
| **Memory** | ~10-20MB per instance | ~50-100MB per instance |
| **Deployment** | Single binary, no runtime deps | Requires Node.js + node_modules |
| **Scaling** | Better CPU utilization for SSE fan-out | Good but GC pauses under load |

**Decision**: Go chosen for performance-critical real-time features (SSE, 80+ handlers, multi-tenant workspaces). The existing React frontend remains unchanged.

---

## Tech Stack

### Frontend (Giữ nguyên)
| Công nghệ | Mục đích |
|---|---|
| React 18 | UI framework |
| Redux Toolkit | Global state + async thunks |
| React Router v7 | Client-side routing |
| @dnd-kit | Drag & Drop (list + card reorder) |
| Axios | HTTP client + JWT interceptor + refresh queue |
| Tailwind CSS | Utility-first styling |
| Vite 6 | Build tool + dev server (:5173) |
| Lucide React | Icon library |
| react-markdown | Markdown rendering (HelpDrawer) |

### Backend (Mới — Go)
| Công nghệ | Mục đích |
|---|---|
| Go 1.23+ | Runtime |
| Gin / Fiber / Echo | HTTP framework (khuyến nghị: **Gin** hoặc **Fiber**) |
| sqlc + pgx | Type-safe SQL & database access |
| GORM (optional) | ORM nếu muốn rapid development |
| JWT (golang-jwt/jwt) | Access & Refresh Token |
| bcrypt | Password hashing |
| godotenv / Viper | Configuration |
| MinIO Go SDK | S3-compatible object storage |
| Redis Go client (go-redis) | Token blacklist + rate limiting |
| Goose / Atlas | Database migration |
| Swagger / Swaggo | API documentation |
| Zap / Zerolog | Structured logging |
| Asynq / Machinery | Background jobs (email, due date reminder) |

### Infrastructure
| Công nghệ | Mục đích |
|---|---|
| PostgreSQL 16 | Primary database (Docker :5432) |
| MinIO | S3-compatible object storage (Docker :9000) |
| Redis | Token blacklist + rate limiting + SSE session (Docker :6379) |
| Docker + Docker Compose | Containerization |
| Nginx (optional) | Reverse proxy + static serving |

---

## Kiến trúc hệ thống

```
Browser (React SPA :5173)
│  REST/JSON (Axios + JWT Bearer)
│  SSE (EventSource)
▼
Go API Server (:8080)
├── Middleware
│     ├── JWT Auth + Redis blacklist
│     ├── Rate limiting
│     └── Request validation (validator.v10)
│
├── 12 Modules (Clean Architecture / Layered)
│     ├── Handler → Service → Repository → Model
│     └── Background Workers (email, notifications, reminders)
│
├── PostgreSQL 16   (primary data + JSONB)
├── MinIO           (attachments + avatars)
└── Redis           (JWT blacklist, rate limit, SSE connections)
```

### Mô hình dữ liệu (Giữ nguyên logic)

```
Users
└── Organizations (Workspaces)
    ├── organization_members (owner | admin | member)
    └── Boards
        ├── board_members (owner | admin | member | viewer)
        ├── board_invitations
        ├── Labels
        └── Lists
            └── Cards
                ├── card_members
                ├── card_labels
                ├── Checklists → checklist_items
                ├── Comments
                ├── Attachments (MinIO)
                └── Activity Logs (JSONB)
└── Notifications
```



---

## Tính năng chính (Giữ nguyên đầy đủ)

### 1. Xác thực & Bảo mật ✅ (sẽ triển khai)
- Đăng ký + xác minh email OTP
- Đăng nhập với Access Token (15 phút) + Refresh Token (7 ngày, httpOnly cookie)
- Refresh token rotation + reuse detection
- Token blacklist bằng Redis (jti)
- AES-256-GCM encrypt cookie (raw JWT không lưu plain)
- Quên mật khẩu / Reset password qua email
- Rate limiting & secure headers

### 2. Cập nhật hồ sơ cá nhân
- Upload avatar (Multer → MinIO Go SDK)

### 3. Workspace (Organizations)
- CRUD workspace + unique slug
- Role-based access: Owner / Admin / Member

### 4. Boards
- CRUD board + background color
- Visibility: private / workspace / public
- 4-level permission: Owner / Admin / Member / Viewer
- Smart invitation flow (existing user + new user via token)

### 5. Lists (Columns)
- CRUD + inline rename
- Drag & Drop reorder với position (float) — O(1) insert

### 6. Cards (Tasks)
- CRUD + Drag & Drop giữa các list
- Due date, Priority (4 levels), Single Assignee, Completion status
- Cover image từ attachment

### 7. Labels
- Custom color labels per board
- Assign/unassign multiple labels

### 8. Checklists
- Multiple checklists per card
- Checklist items với assignee + due date
- Progress bar & badge

### 9. Comments
- 1-level threaded comments + edit/delete

### 10. Attachments
- Upload (image, PDF, docs, zip…) lên MinIO
- Download + Set as cover

### 11. Activity Logs
- Automatic logging với JSONB metadata
- Human-readable tiếng Việt

### 12. Notifications & Real-time
- SSE (Server-Sent Events) real-time
- Triggers: card assigned, new comment, due date reminder
- Unread count badge

### 13. Reactive Activity Stream
- Live activity feed trong Card Detail
- Optimistic updates + SSE fan-out

### 14. Help System
- HelpDrawer + USER_GUIDE.md (tiếng Việt)

---

## Backend — Modules (Go)

| Module | Route Prefix | Số Handler dự kiến |
|---|---|:---:|
| Auth | `/api/v1/auth` | 10+ |
| Organizations | `/api/v1/organizations` | 9 |
| Boards | `/api/v1/boards` | 10+ |
| Lists | `/api/v1/lists` | 5 |
| Cards | `/api/v1/cards` | 8 |
| Labels | `/api/v1/labels` | 7 |
| Comments | `/api/v1/comments` | 5 |
| Checklists | `/api/v1/checklists` | 8 |
| Attachments | `/api/v1/attachments` | 5 |
| Activity | `/api/v1/activity` | 3 |
| Notifications | `/api/v1/notifications` | 6 |
| Invitations | `/api/v1/invitations` | 3 |
| **Tổng** | | **~80 handlers** |

**Kiến trúc Go khuyến nghị:**
- Clean Architecture hoặc Layered Architecture (Handler → Service → Repository)
- Repository pattern với sqlc cho type safety
- Dependency Injection (wire hoặc manual)
- Background workers cho email & cron jobs

---

## Kế hoạch triển khai (Go Edition)

| Phase | Nội dung | Duration | Trạng thái |
|---|---|:---:|:---:|
| **Phase 1** | Project setup, Docker, Auth (OTP, JWT, Refresh rotation, Redis blacklist), Profile | 2 weeks | 🔄 |
| **Phase 2** | Workspace + Board + Permission system | 1.5 weeks | ⏳ |
| **Phase 3** | Lists, Cards, Drag & Drop, Labels | 1.5 weeks | ⏳ |
| **Phase 4** | Checklists, Comments, Attachments, Activity Logs | 2 weeks | ⏳ |
| **Phase 5** | Notifications SSE + Real-time Activity Stream | 1 week | ⏳ |
| **Phase 6** | Polish, Testing, Documentation, Production readiness | 1.5 weeks | ⏳ |

**Total estimated duration**: ~10 weeks

---

## Real-time: SSE vs WebSocket

| Criterion | SSE | WebSocket |
|-----------|-----|-----------|
| **Direction** | Server → Client only | Bidirectional |
| **Protocol** | HTTP/1.1 or HTTP/2 | Separate protocol (ws://) |
| **Reconnection** | Built-in auto-reconnect | Manual implementation |
| **Load balancer** | Standard HTTP routing | Sticky sessions required |
| **Use case fit** | Notifications, activity feeds | Chat, collaborative editing |

**Decision**: SSE chosen because TaskFlow's real-time features are server-to-client only (notifications, activity stream). No bidirectional communication needed. Simpler to implement and scale behind standard load balancers.

---

## Testing Strategy

| Layer | Tool | Coverage Target |
|-------|------|:---------------:|
| **Unit Tests** | Go testing + testify | 80% |
| **Integration Tests** | testcontainers-go (PG, Redis) | Critical paths |
| **E2E Tests** | Playwright (existing React tests) | Happy paths |
| **API Contract** | Swagger validation | 100% endpoints |

**Test commands:**
```bash
go test ./...                    # Run all tests
go test -cover ./...             # With coverage
go test -race ./...              # Race condition detection
go test -v ./internal/auth/...   # Specific module
```

---

## Error Handling (API Response Envelope)

Go errors map to standard API envelope format:

```go
// Standard error response (matches api-conventions.md)
type ErrorResponse struct {
    Success bool        `json:"success"`           // always false
    Error   ErrorDetail `json:"error"`
}

type ErrorDetail struct {
    Code    string      `json:"code"`              // e.g., "VALIDATION_ERROR"
    Message string      `json:"message"`           // Human-readable
    Details interface{} `json:"details,omitempty"` // Optional field errors
}
```

**Error code mapping:**
| Go Error | HTTP Status | Code |
|----------|:-----------:|------|
| `ErrNotFound` | 404 | `NOT_FOUND` |
| `ErrUnauthorized` | 401 | `UNAUTHORIZED` |
| `ErrForbidden` | 403 | `FORBIDDEN` |
| `ErrValidation` | 422 | `VALIDATION_ERROR` |
| `ErrConflict` | 409 | `CONFLICT` |
| `ErrInternal` | 500 | `INTERNAL_ERROR` |

---

## Tài liệu liên quan (sẽ cập nhật)

| File | Nội dung |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Kiến trúc Go backend chi tiết |
| [AUTH_FLOW.md](AUTH_FLOW.md) | Luồng xác thực (JWT + Refresh Token) |
| [DATABASE_DESIGN.md](DATABASE_DESIGN.md) | PostgreSQL schema |
| [API_SPEC.md](API_SPEC.md) | OpenAPI/Swagger specification |
| [USER_GUIDE.md](USER_GUIDE.md) | Hướng dẫn sử dụng (tiếng Việt) |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Docker + Production deployment |

---

**Mục tiêu:**  
Xây dựng lại TaskFlow với backend **Go** nhanh hơn, hiệu suất cao hơn, dễ scale hơn và code dễ bảo trì hơn so với phiên bản Node.js trước.