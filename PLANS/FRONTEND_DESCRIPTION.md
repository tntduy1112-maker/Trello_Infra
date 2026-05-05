# TaskFlow — Frontend Description

> **Stack:** React 18 | JavaScript (JSX) | Tailwind CSS | Redux Toolkit | @dnd-kit | Axios  
> **Backend:** Go (Gin + GORM) — Đang xây dựng lại từ đầu

---

## Tổng quan

Frontend của **TaskFlow** là Single Page Application (SPA) theo phong cách Kanban board.  
Giao tiếp với Backend Go qua REST API tại `http://localhost:8080/api/v1` (có thể thay đổi).

Hỗ trợ kéo thả (@dnd-kit), JWT Authentication với auto-refresh token, và quản lý state bằng Redux Toolkit.

**Không sử dụng:** TypeScript, React Query, Zustand, React Hook Form, shadcn/ui, Radix UI.

---

## Kiến trúc thư mục (thực tế)

```
Frontend/src/
├── api/
│   └── axiosInstance.js      ← Axios + JWT interceptor + token refresh
├── components/
│   ├── layout/
│   │   ├── AppLayout.jsx
│   │   ├── AuthLayout.jsx
│   │   ├── Navbar.jsx
│   │   └── Sidebar.jsx
│   ├── board/
│   │   ├── ListColumn.jsx
│   │   ├── CardItem.jsx
│   │   ├── CardDetailModal.jsx
│   │   └── InviteMemberModal.jsx
│   └── ui/
│       ├── Avatar.jsx
│       ├── AvatarStack.jsx
│       ├── Badge.jsx
│       ├── Button.jsx
│       ├── ColorPicker.jsx
│       ├── Dropdown.jsx
│       ├── Input.jsx
│       ├── Modal.jsx
│       ├── NotificationDropdown.jsx
│       ├── ProgressBar.jsx
│       ├── Spinner.jsx
│       ├── Tooltip.jsx
│       └── HelpDrawer.jsx
├── hooks/
│   ├── useAuth.js
│   ├── useBoard.js
│   ├── useClickOutside.js
│   ├── useDebounce.js
│   ├── usePermission.js
│   └── useNotificationStream.js
├── pages/
│   ├── auth/
│   │   ├── LoginPage.jsx
│   │   ├── RegisterPage.jsx
│   │   ├── VerifyEmailPage.jsx
│   │   ├── ForgotPasswordPage.jsx
│   │   └── ResetPasswordPage.jsx
│   ├── workspaces/
│   │   ├── WorkspacesPage.jsx
│   │   ├── CreateWorkspacePage.jsx
│   │   ├── BoardListPage.jsx
│   │   └── WorkspaceSettingsPage.jsx
│   ├── boards/
│   │   ├── BoardPage.jsx
│   │   └── CreateBoardModal.jsx
│   ├── profile/
│   │   └── ProfilePage.jsx
│   └── invitations/
│       └── AcceptInvitePage.jsx
├── redux/
│   ├── store.js
│   └── slices/
│       ├── authSlice.js
│       ├── workspaceSlice.js
│       ├── boardSlice.js
│       └── notificationSlice.js
├── services/
│   ├── auth.service.js
│   ├── workspace.service.js
│   ├── board.service.js
│   ├── list.service.js
│   ├── card.service.js
│   ├── label.service.js
│   └── notification.service.js
├── utils/
│   └── helpers.js
├── App.jsx
└── main.jsx
```

---

## State Management

Sử dụng **Redux Toolkit** cho toàn bộ state.

- `authSlice`: user, token, refreshToken, isAuthenticated
- `workspaceSlice`: danh sách workspaces
- `boardSlice`: currentBoard, lists, cards, labels, comments, attachments, activity, openCardId...
- `notificationSlice`: notifications + unreadCount

Tất cả tương tác với Backend đều qua **async thunks**.

---

## API Layer (Go Backend)

```js
// axiosInstance.js
baseURL: import.meta.env.VITE_API_URL || 'http://localhost:8080/api/v1'
```

Tất cả service files (auth.service.js, board.service.js, ...) sẽ được viết lại để phù hợp với cấu trúc và response format của Go Backend.

---

## Routing

- **Public routes:** `/login`, `/register`, `/verify-email`, `/forgot-password`, `/reset-password`
- **Protected routes:** `/home`, `/workspaces/:slug`, `/board/:boardId`, `/profile`, ...
- **Default redirect:** `/` → `/home`

---

## Kế hoạch triển khai (Reset — Bắt đầu lại từ đầu)

### Phase 1 — Auth & Workspace

- [ ] Xây dựng 5 trang Auth (Login, Register, Verify Email, Forgot Password, Reset Password)
- [ ] Workspace list, tạo workspace, cài đặt workspace
- [ ] Invite member vào workspace
- [ ] Kết nối tất cả API Auth & Workspace với Go Backend

### Phase 2 — Board & Kanban

- [ ] Danh sách board + tạo board
- [ ] Kanban board layout (lists + cards)
- [ ] Drag & Drop lists và cards (@dnd-kit)
- [ ] Tạo list, tạo card
- [ ] Card Detail Modal (title, description, priority, due date, assignee)
- [ ] Lưu card + validation
- [ ] Persist vị trí Drag & Drop vào database
- [ ] Hệ thống Labels (tạo, gán, chỉnh sửa, xóa)

### Phase 3 — Advanced Card Features

- [ ] Comments (tạo, reply, edit, xóa)
- [ ] Activity Log (live update)
- [ ] Attachments (upload, download, set cover)
- [ ] Card completion toggle
- [ ] Checklists & checklist items (full CRUD)
- [ ] Board invitation flow

### Phase 4 — Notifications

- [ ] Notification bell + unread count
- [ ] Real-time notification (SSE hoặc WebSocket)
- [ ] Notification dropdown

### Phase 5 — Reactive Features

- [ ] Live Activity Stream trên card
- [ ] Optimistic updates & error rollback

### Phase 6 — Profile & Others

- [ ] Profile page (cập nhật tên, avatar)
- [ ] HelpDrawer + hướng dẫn sử dụng
- [ ] Context help trong Card Detail Modal


---

## Công nghệ sử dụng

| Thành phần | Công nghệ | Ghi chú |
|------------|-----------|---------|
| Framework | React | 18.3.x |
| Language | JavaScript (JSX) | Không dùng TypeScript |
| Build Tool | Vite | — |
| Styling | Tailwind CSS | 3.4.x |
| State Management | Redux Toolkit | 2.x |
| Drag & Drop | @dnd-kit/core + sortable | — |
| HTTP Client | Axios | — |
| Routing | React Router | v7 |
| Icons | Lucide React | — |