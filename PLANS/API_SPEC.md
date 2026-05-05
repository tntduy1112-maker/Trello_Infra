# TaskFlow — API Specification

> OpenAPI-style specification for all REST endpoints. Version: 1.0.0

---

## Base Configuration

```yaml
openapi: 3.0.3
info:
  title: TaskFlow API
  version: 1.0.0
  description: Kanban board API built with Go

servers:
  - url: http://localhost:8080/api/v1
    description: Development
  - url: https://api.taskflow.example.com/api/v1
    description: Production

security:
  - BearerAuth: []

components:
  securitySchemes:
    BearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
```

---

## Response Envelope

All responses follow this envelope format:

```yaml
# Success Response
SuccessResponse:
  type: object
  properties:
    success:
      type: boolean
      example: true
    data:
      type: object
    message:
      type: string
      nullable: true

# Error Response
ErrorResponse:
  type: object
  properties:
    success:
      type: boolean
      example: false
    error:
      type: object
      properties:
        code:
          type: string
          example: "VALIDATION_ERROR"
        message:
          type: string
          example: "Email is required"
        details:
          type: array
          nullable: true

# Paginated Response
PaginatedResponse:
  type: object
  properties:
    success:
      type: boolean
    data:
      type: array
    pagination:
      type: object
      properties:
        page:
          type: integer
        limit:
          type: integer
        total:
          type: integer
        total_pages:
          type: integer
```

---

## Sprint 1: Authentication

### Schemas

```yaml
# User
User:
  type: object
  properties:
    id:
      type: string
      format: cuid
      example: "clx1234567890abcdef"
    email:
      type: string
      format: email
      example: "user@example.com"
    full_name:
      type: string
      example: "John Doe"
    avatar_url:
      type: string
      nullable: true
      example: "https://minio.example.com/avatars/abc123.jpg"
    is_verified:
      type: boolean
      example: true
    created_at:
      type: string
      format: date-time

# Token Response
TokenResponse:
  type: object
  properties:
    access_token:
      type: string
      description: JWT access token (15 min expiry)
    user:
      $ref: '#/components/schemas/User'
  # Note: refresh_token is set as httpOnly cookie, not in response body
```

---

### POST /auth/register

Create a new user account and send verification OTP.

```yaml
path: /auth/register
method: POST
auth: none
rate_limit: 3 requests / hour / IP

request:
  content-type: application/json
  body:
    type: object
    required:
      - email
      - password
      - full_name
    properties:
      email:
        type: string
        format: email
        maxLength: 255
        example: "user@example.com"
      password:
        type: string
        minLength: 6
        maxLength: 128
        example: "securePassword123"
      full_name:
        type: string
        minLength: 1
        maxLength: 255
        example: "John Doe"

responses:
  201:
    description: User created successfully
    body:
      success: true
      data:
        id: "clx1234567890abcdef"
        email: "user@example.com"
        full_name: "John Doe"
        avatar_url: null
        is_verified: false
        created_at: "2026-04-21T10:00:00Z"
      message: "Verification code sent to your email"

  400:
    description: Validation error
    body:
      success: false
      error:
        code: "VALIDATION_ERROR"
        message: "Invalid request body"
        details:
          - field: "email"
            message: "Invalid email format"

  409:
    description: Email already exists
    body:
      success: false
      error:
        code: "CONFLICT"
        message: "Email already registered"

  429:
    description: Rate limit exceeded
    headers:
      Retry-After: 3600
    body:
      success: false
      error:
        code: "TOO_MANY_REQUESTS"
        message: "Rate limit exceeded. Try again later."
```

---

### POST /auth/verify-email

Verify email address using OTP.

```yaml
path: /auth/verify-email
method: POST
auth: none
rate_limit: 5 attempts per OTP

request:
  content-type: application/json
  body:
    type: object
    required:
      - email
      - otp
    properties:
      email:
        type: string
        format: email
        example: "user@example.com"
      otp:
        type: string
        pattern: "^[0-9]{6}$"
        example: "123456"

responses:
  200:
    description: Email verified successfully
    body:
      success: true
      message: "Email verified successfully"

  400:
    description: Invalid or expired OTP
    body:
      success: false
      error:
        code: "INVALID_OTP"
        message: "Invalid or expired verification code"

  400:
    description: Already verified
    body:
      success: false
      error:
        code: "ALREADY_VERIFIED"
        message: "Email already verified"

  429:
    description: Too many attempts
    body:
      success: false
      error:
        code: "TOO_MANY_ATTEMPTS"
        message: "Too many failed attempts. Request a new code."
```

---

### POST /auth/resend-verification

Resend verification OTP to email.

```yaml
path: /auth/resend-verification
method: POST
auth: none
rate_limit: 3 requests / hour / email

request:
  content-type: application/json
  body:
    type: object
    required:
      - email
    properties:
      email:
        type: string
        format: email

responses:
  200:
    description: Verification email sent
    body:
      success: true
      message: "Verification code sent to your email"

  400:
    description: Already verified
    body:
      success: false
      error:
        code: "ALREADY_VERIFIED"
        message: "Email already verified"

  404:
    description: User not found
    body:
      success: false
      error:
        code: "NOT_FOUND"
        message: "User not found"
```

---

### POST /auth/login

Authenticate user and receive tokens.

```yaml
path: /auth/login
method: POST
auth: none
rate_limit: 5 requests / 15 min / IP

request:
  content-type: application/json
  headers:
    User-Agent: string  # Used for device tracking
  body:
    type: object
    required:
      - email
      - password
    properties:
      email:
        type: string
        format: email
        example: "user@example.com"
      password:
        type: string
        example: "securePassword123"

responses:
  200:
    description: Login successful
    headers:
      Set-Cookie: |
        refreshToken=<AES-256-GCM encrypted JWT>;
        HttpOnly; SameSite=Strict; Secure; Max-Age=604800; Path=/
    body:
      success: true
      data:
        access_token: "eyJhbGciOiJIUzI1NiIs..."
        user:
          id: "clx1234567890abcdef"
          email: "user@example.com"
          full_name: "John Doe"
          avatar_url: null
          is_verified: true
          created_at: "2026-04-21T10:00:00Z"

  401:
    description: Invalid credentials
    body:
      success: false
      error:
        code: "INVALID_CREDENTIALS"
        message: "Invalid email or password"

  403:
    description: Account disabled
    body:
      success: false
      error:
        code: "ACCOUNT_DISABLED"
        message: "Your account has been disabled"

  429:
    description: Rate limit exceeded
    headers:
      Retry-After: 900
    body:
      success: false
      error:
        code: "TOO_MANY_REQUESTS"
        message: "Too many login attempts. Try again later."
```

---

### POST /auth/refresh

Refresh access token using refresh token cookie.

```yaml
path: /auth/refresh
method: POST
auth: none (uses httpOnly cookie)
rate_limit: 30 requests / 15 min / user

request:
  cookies:
    refreshToken: string  # AES-256-GCM encrypted JWT

responses:
  200:
    description: Token refreshed successfully
    headers:
      Set-Cookie: |
        refreshToken=<NEW AES-256-GCM encrypted JWT>;
        HttpOnly; SameSite=Strict; Secure; Max-Age=604800; Path=/
    body:
      success: true
      data:
        access_token: "eyJhbGciOiJIUzI1NiIs..."

  400:
    description: No refresh token cookie
    body:
      success: false
      error:
        code: "MISSING_TOKEN"
        message: "Refresh token not provided"

  401:
    description: Invalid or expired token
    body:
      success: false
      error:
        code: "INVALID_TOKEN"
        message: "Invalid or expired refresh token"

  401:
    description: Token reuse detected (security alert)
    body:
      success: false
      error:
        code: "TOKEN_REUSE_DETECTED"
        message: "Security alert: Token reuse detected. All sessions invalidated."
```

---

### POST /auth/logout

Logout current session.

```yaml
path: /auth/logout
method: POST
auth: optional (best-effort AT extraction for blacklisting)

request:
  headers:
    Authorization: Bearer <access_token>  # Optional
  cookies:
    refreshToken: string

responses:
  200:
    description: Logged out successfully
    headers:
      Set-Cookie: |
        refreshToken=; HttpOnly; SameSite=Strict; Secure; Max-Age=0; Path=/
    body:
      success: true
      message: "Logged out successfully"
```

---

### POST /auth/logout-all

Logout from all devices.

```yaml
path: /auth/logout-all
method: POST
auth: required

request:
  headers:
    Authorization: Bearer <access_token>

responses:
  200:
    description: Logged out from all devices
    headers:
      Set-Cookie: |
        refreshToken=; HttpOnly; SameSite=Strict; Secure; Max-Age=0; Path=/
    body:
      success: true
      message: "Logged out from all devices"

  401:
    description: Unauthorized
    body:
      success: false
      error:
        code: "UNAUTHORIZED"
        message: "Authentication required"
```

---

### POST /auth/forgot-password

Request password reset email.

```yaml
path: /auth/forgot-password
method: POST
auth: none
rate_limit: 5 requests / 15 min / IP

request:
  content-type: application/json
  body:
    type: object
    required:
      - email
    properties:
      email:
        type: string
        format: email

responses:
  200:
    description: Reset email sent (same response whether email exists or not)
    body:
      success: true
      message: "If the email exists, a reset link has been sent"
```

---

### POST /auth/reset-password

Reset password using token from email.

```yaml
path: /auth/reset-password
method: POST
auth: none
rate_limit: 5 requests / 15 min / IP

request:
  content-type: application/json
  body:
    type: object
    required:
      - token
      - password
    properties:
      token:
        type: string
        description: 64-char hex token from email link
        example: "a1b2c3d4..."
      password:
        type: string
        minLength: 6
        maxLength: 128

responses:
  200:
    description: Password reset successfully
    body:
      success: true
      message: "Password reset successfully. Please login again."

  400:
    description: Invalid or expired token
    body:
      success: false
      error:
        code: "INVALID_RESET_TOKEN"
        message: "Invalid or expired reset token"
```

---

### GET /auth/me

Get current authenticated user.

```yaml
path: /auth/me
method: GET
auth: required

request:
  headers:
    Authorization: Bearer <access_token>

responses:
  200:
    description: Current user info
    body:
      success: true
      data:
        id: "clx1234567890abcdef"
        email: "user@example.com"
        full_name: "John Doe"
        avatar_url: "https://minio.example.com/avatars/abc123.jpg"
        is_verified: true
        created_at: "2026-04-21T10:00:00Z"

  401:
    description: Unauthorized
    body:
      success: false
      error:
        code: "UNAUTHORIZED"
        message: "Authentication required"
```

---

### PUT /auth/me

Update current user profile.

```yaml
path: /auth/me
method: PUT
auth: required

request:
  headers:
    Authorization: Bearer <access_token>
  content-type: multipart/form-data
  body:
    type: object
    properties:
      full_name:
        type: string
        minLength: 1
        maxLength: 255
      avatar:
        type: string
        format: binary
        description: Image file (max 2MB, image/* only)

responses:
  200:
    description: Profile updated
    body:
      success: true
      data:
        id: "clx1234567890abcdef"
        email: "user@example.com"
        full_name: "Jane Doe"
        avatar_url: "https://minio.example.com/avatars/new123.jpg"
        is_verified: true
        created_at: "2026-04-21T10:00:00Z"

  400:
    description: Validation error
    body:
      success: false
      error:
        code: "VALIDATION_ERROR"
        message: "Invalid file type"

  413:
    description: File too large
    body:
      success: false
      error:
        code: "FILE_TOO_LARGE"
        message: "Avatar must be less than 2MB"
```

---

## Sprint 2: Organizations & Boards

### GET /organizations

List user's organizations.

```yaml
path: /organizations
method: GET
auth: required

responses:
  200:
    body:
      success: true
      data:
        - id: "clx_org_123"
          name: "My Workspace"
          slug: "my-workspace"
          logo_url: null
          role: "owner"
          boards_count: 5
          members_count: 3
```

---

### POST /organizations

Create new organization.

```yaml
path: /organizations
method: POST
auth: required

request:
  body:
    type: object
    required:
      - name
    properties:
      name:
        type: string
        minLength: 1
        maxLength: 255
      description:
        type: string
        nullable: true

responses:
  201:
    body:
      success: true
      data:
        id: "clx_org_123"
        name: "My Workspace"
        slug: "my-workspace"
        description: null
        logo_url: null
        owner_id: "clx_user_123"
        created_at: "2026-04-21T10:00:00Z"
```

---

### GET /organizations/:slug

Get organization details.

```yaml
path: /organizations/{slug}
method: GET
auth: required

responses:
  200:
    body:
      success: true
      data:
        id: "clx_org_123"
        name: "My Workspace"
        slug: "my-workspace"
        description: "Team workspace"
        logo_url: null
        owner:
          id: "clx_user_123"
          full_name: "John Doe"
          avatar_url: null
        members_count: 3
        boards_count: 5
        my_role: "owner"

  403:
    body:
      success: false
      error:
        code: "FORBIDDEN"
        message: "You don't have access to this workspace"

  404:
    body:
      success: false
      error:
        code: "NOT_FOUND"
        message: "Workspace not found"
```

---

### GET /organizations/:slug/boards

List boards in organization.

```yaml
path: /organizations/{slug}/boards
method: GET
auth: required

query:
  page:
    type: integer
    default: 1
  limit:
    type: integer
    default: 20
    maximum: 100

responses:
  200:
    body:
      success: true
      data:
        - id: "clx_board_123"
          title: "Project Alpha"
          background_color: "#0079bf"
          visibility: "workspace"
          is_closed: false
          lists_count: 4
          cards_count: 23
          my_role: "admin"
      pagination:
        page: 1
        limit: 20
        total: 5
        total_pages: 1
```

---

### POST /organizations/:slug/boards

Create board in organization.

```yaml
path: /organizations/{slug}/boards
method: POST
auth: required
permission: org member or higher

request:
  body:
    type: object
    required:
      - title
    properties:
      title:
        type: string
        minLength: 1
        maxLength: 255
      description:
        type: string
        nullable: true
      background_color:
        type: string
        pattern: "^#[0-9A-Fa-f]{6}$"
        default: "#0079bf"
      visibility:
        type: string
        enum: ["private", "workspace", "public"]
        default: "workspace"

responses:
  201:
    body:
      success: true
      data:
        id: "clx_board_123"
        title: "Project Alpha"
        description: null
        background_color: "#0079bf"
        visibility: "workspace"
        organization_id: "clx_org_123"
        owner_id: "clx_user_123"
        is_closed: false
        created_at: "2026-04-21T10:00:00Z"
```

---

### GET /boards/:id

Get board with lists and cards.

```yaml
path: /boards/{id}
method: GET
auth: required
permission: board viewer or higher

responses:
  200:
    body:
      success: true
      data:
        id: "clx_board_123"
        title: "Project Alpha"
        description: "Main project board"
        background_color: "#0079bf"
        visibility: "workspace"
        is_closed: false
        my_role: "admin"
        organization:
          id: "clx_org_123"
          name: "My Workspace"
          slug: "my-workspace"
        lists:
          - id: "clx_list_1"
            title: "To Do"
            position: 65536
            cards:
              - id: "clx_card_1"
                title: "Task 1"
                position: 65536
                description: null
                priority: "medium"
                due_date: "2026-04-30T00:00:00Z"
                is_completed: false
                assignee:
                  id: "clx_user_123"
                  full_name: "John Doe"
                  avatar_url: null
                labels:
                  - id: "clx_label_1"
                    name: "Bug"
                    color: "#eb5a46"
                comments_count: 3
                attachments_count: 1
                checklists_progress:
                  completed: 2
                  total: 5
        labels:
          - id: "clx_label_1"
            name: "Bug"
            color: "#eb5a46"
          - id: "clx_label_2"
            name: "Feature"
            color: "#61bd4f"
        members:
          - id: "clx_user_123"
            full_name: "John Doe"
            avatar_url: null
            role: "owner"
```

---

## Sprint 3: Lists & Cards

### POST /boards/:boardId/lists

Create list in board.

```yaml
path: /boards/{boardId}/lists
method: POST
auth: required
permission: board member or higher

request:
  body:
    type: object
    required:
      - title
    properties:
      title:
        type: string
        minLength: 1
        maxLength: 255

responses:
  201:
    body:
      success: true
      data:
        id: "clx_list_123"
        title: "New List"
        position: 131072
        board_id: "clx_board_123"
        is_archived: false
        created_at: "2026-04-21T10:00:00Z"
```

---

### PUT /lists/:id/move

Move/reorder list.

```yaml
path: /lists/{id}/move
method: PUT
auth: required
permission: board member or higher

request:
  body:
    type: object
    required:
      - position
    properties:
      position:
        type: number
        format: float
        description: New position value

responses:
  200:
    body:
      success: true
      data:
        id: "clx_list_123"
        position: 98304
```

---

### POST /lists/:listId/cards

Create card in list.

```yaml
path: /lists/{listId}/cards
method: POST
auth: required
permission: board member or higher

request:
  body:
    type: object
    required:
      - title
    properties:
      title:
        type: string
        minLength: 1
        maxLength: 255

responses:
  201:
    body:
      success: true
      data:
        id: "clx_card_123"
        title: "New Card"
        description: null
        position: 65536
        list_id: "clx_list_123"
        priority: "none"
        due_date: null
        is_completed: false
        assignee: null
        labels: []
        created_at: "2026-04-21T10:00:00Z"
```

---

### PUT /cards/:id/move

Move card to different list or position.

```yaml
path: /cards/{id}/move
method: PUT
auth: required
permission: board member or higher

request:
  body:
    type: object
    required:
      - list_id
      - position
    properties:
      list_id:
        type: string
        format: cuid
      position:
        type: number
        format: float

responses:
  200:
    body:
      success: true
      data:
        id: "clx_card_123"
        list_id: "clx_list_456"
        position: 32768
```

---

## Sprint 4: Advanced Card Features

### GET /cards/:id

Get full card details.

```yaml
path: /cards/{id}
method: GET
auth: required
permission: board viewer or higher

responses:
  200:
    body:
      success: true
      data:
        id: "clx_card_123"
        title: "Task Title"
        description: "Detailed description in markdown"
        position: 65536
        priority: "high"
        due_date: "2026-04-30T00:00:00Z"
        is_completed: false
        cover_url: "https://minio.example.com/attachments/cover.jpg"
        list:
          id: "clx_list_123"
          title: "In Progress"
        assignee:
          id: "clx_user_123"
          full_name: "John Doe"
          avatar_url: null
        labels:
          - id: "clx_label_1"
            name: "Bug"
            color: "#eb5a46"
        checklists:
          - id: "clx_checklist_1"
            title: "Requirements"
            position: 65536
            items:
              - id: "clx_item_1"
                title: "Design mockup"
                is_completed: true
                assignee: null
                due_date: null
        comments:
          - id: "clx_comment_1"
            content: "This looks good!"
            author:
              id: "clx_user_456"
              full_name: "Jane Doe"
              avatar_url: null
            created_at: "2026-04-21T10:00:00Z"
            is_edited: false
        attachments:
          - id: "clx_attachment_1"
            filename: "design.pdf"
            url: "https://minio.example.com/attachments/design.pdf"
            mime_type: "application/pdf"
            file_size: 1048576
            is_cover: false
            created_at: "2026-04-21T10:00:00Z"
        activity:
          - id: "clx_activity_1"
            action: "card_created"
            description: "John Doe created this card"
            user:
              id: "clx_user_123"
              full_name: "John Doe"
            created_at: "2026-04-21T10:00:00Z"
            metadata: {}
```

---

### POST /cards/:cardId/comments

Add comment to card.

```yaml
path: /cards/{cardId}/comments
method: POST
auth: required
permission: board member or higher

request:
  body:
    type: object
    required:
      - content
    properties:
      content:
        type: string
        minLength: 1
        maxLength: 10000

responses:
  201:
    body:
      success: true
      data:
        id: "clx_comment_123"
        content: "Comment text"
        author:
          id: "clx_user_123"
          full_name: "John Doe"
          avatar_url: null
        created_at: "2026-04-21T10:00:00Z"
        is_edited: false
```

---

### POST /cards/:cardId/attachments

Upload attachment to card.

```yaml
path: /cards/{cardId}/attachments
method: POST
auth: required
permission: board member or higher

request:
  content-type: multipart/form-data
  body:
    type: object
    required:
      - file
    properties:
      file:
        type: string
        format: binary
        description: Max 10MB

responses:
  201:
    body:
      success: true
      data:
        id: "clx_attachment_123"
        filename: "document.pdf"
        original_name: "document.pdf"
        url: "https://minio.example.com/attachments/abc123.pdf"
        mime_type: "application/pdf"
        file_size: 1048576
        is_cover: false
        created_at: "2026-04-21T10:00:00Z"

  413:
    body:
      success: false
      error:
        code: "FILE_TOO_LARGE"
        message: "File must be less than 10MB"
```

---

## Sprint 5: Notifications

### GET /notifications

List user notifications.

```yaml
path: /notifications
method: GET
auth: required

query:
  page:
    type: integer
    default: 1
  limit:
    type: integer
    default: 20
  unread_only:
    type: boolean
    default: false

responses:
  200:
    body:
      success: true
      data:
        - id: "clx_notif_123"
          type: "card_assigned"
          title: "You were assigned to a card"
          message: "John Doe assigned you to 'Fix login bug'"
          is_read: false
          created_at: "2026-04-21T10:00:00Z"
          board:
            id: "clx_board_123"
            title: "Project Alpha"
          card:
            id: "clx_card_123"
            title: "Fix login bug"
          actor:
            id: "clx_user_456"
            full_name: "John Doe"
            avatar_url: null
      pagination:
        page: 1
        limit: 20
        total: 15
        total_pages: 1
```

---

### GET /notifications/unread-count

Get unread notification count.

```yaml
path: /notifications/unread-count
method: GET
auth: required

responses:
  200:
    body:
      success: true
      data:
        count: 5
```

---

### GET /notifications/stream

SSE stream for real-time notifications.

```yaml
path: /notifications/stream
method: GET
auth: required
content-type: text/event-stream

responses:
  200:
    description: SSE event stream
    content-type: text/event-stream
    events:
      - event: notification
        data: |
          {
            "type": "card_assigned",
            "card_id": "clx_card_123",
            "message": "You were assigned to 'Fix bug'"
          }

      - event: card_updated
        data: |
          {
            "card_id": "clx_card_123",
            "changes": {"title": "New Title"}
          }

      - event: activity
        data: |
          {
            "card_id": "clx_card_123",
            "activity": {
              "action": "comment_added",
              "user": "John Doe"
            }
          }
```

---

## Common Headers

### Request Headers

| Header | Required | Description |
|--------|:--------:|-------------|
| `Authorization` | For protected routes | `Bearer <access_token>` |
| `Content-Type` | For POST/PUT | `application/json` or `multipart/form-data` |
| `User-Agent` | Recommended | Used for device tracking on login |

### Response Headers

| Header | When |
|--------|------|
| `Set-Cookie` | Login, refresh, logout |
| `Retry-After` | 429 responses |
| `X-RateLimit-Limit` | All requests |
| `X-RateLimit-Remaining` | All requests |
| `X-RateLimit-Reset` | All requests |

---

## HTTP Status Codes

| Code | Meaning |
|:----:|---------|
| 200 | OK — Successful GET/PUT/PATCH |
| 201 | Created — Successful POST |
| 204 | No Content — Successful DELETE |
| 400 | Bad Request — Invalid input |
| 401 | Unauthorized — Not authenticated |
| 403 | Forbidden — No permission |
| 404 | Not Found |
| 409 | Conflict — Resource already exists |
| 413 | Payload Too Large — File too big |
| 422 | Unprocessable Entity — Validation failed |
| 429 | Too Many Requests — Rate limited |
| 500 | Internal Server Error |

---

## Rate Limits Summary

| Endpoint | Limit | Window | Key |
|----------|:-----:|:------:|-----|
| `/auth/register` | 3 | 1 hour | IP |
| `/auth/login` | 5 | 15 min | IP |
| `/auth/refresh` | 30 | 15 min | user |
| `/auth/forgot-password` | 5 | 15 min | IP |
| `/auth/reset-password` | 5 | 15 min | IP |
| `/auth/verify-email` | 5 | per OTP | email |
| All other endpoints | 100 | 1 min | user |
