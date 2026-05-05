# TaskFlow — Error Codes Reference

> Single source of truth for all error codes across the API.

---

## Error Response Format

```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message",
    "details": []
  }
}
```

---

## Go Implementation

```go
// pkg/apperror/errors.go

type AppError struct {
    Code       string      `json:"code"`
    Message    string      `json:"message"`
    StatusCode int         `json:"-"`
    Details    interface{} `json:"details,omitempty"`
}

func (e *AppError) Error() string {
    return e.Message
}

// Constructor
func New(code, message string, statusCode int) *AppError {
    return &AppError{
        Code:       code,
        Message:    message,
        StatusCode: statusCode,
    }
}

func (e *AppError) WithDetails(details interface{}) *AppError {
    e.Details = details
    return e
}
```

---

## Authentication Errors (401)

| Code | Message | When |
|------|---------|------|
| `UNAUTHORIZED` | Authentication required | No Authorization header or invalid format |
| `INVALID_TOKEN` | Invalid or expired token | JWT verification failed |
| `TOKEN_EXPIRED` | Token has expired | JWT exp claim is past |
| `TOKEN_REVOKED` | Token has been revoked | jti found in Redis blacklist |
| `SESSION_INVALIDATED` | Session invalidated | `iat < user.tokens_valid_after` |
| `INVALID_CREDENTIALS` | Invalid email or password | Login with wrong credentials |
| `TOKEN_REUSE_DETECTED` | Security alert: Token reuse detected | Revoked refresh token was used again |

```go
var (
    ErrUnauthorized       = New("UNAUTHORIZED", "Authentication required", 401)
    ErrInvalidToken       = New("INVALID_TOKEN", "Invalid or expired token", 401)
    ErrTokenExpired       = New("TOKEN_EXPIRED", "Token has expired", 401)
    ErrTokenRevoked       = New("TOKEN_REVOKED", "Token has been revoked", 401)
    ErrSessionInvalidated = New("SESSION_INVALIDATED", "Session invalidated", 401)
    ErrInvalidCredentials = New("INVALID_CREDENTIALS", "Invalid email or password", 401)
    ErrTokenReuseDetected = New("TOKEN_REUSE_DETECTED", "Security alert: Token reuse detected. All sessions invalidated.", 401)
)
```

---

## Authorization Errors (403)

| Code | Message | When |
|------|---------|------|
| `FORBIDDEN` | Access denied | User lacks permission for action |
| `ACCOUNT_DISABLED` | Your account has been disabled | `user.is_active = false` |
| `EMAIL_NOT_VERIFIED` | Email verification required | Action requires verified email |
| `NOT_BOARD_MEMBER` | You are not a member of this board | Board access denied |
| `INSUFFICIENT_ROLE` | Insufficient permissions | Role doesn't allow action |

```go
var (
    ErrForbidden         = New("FORBIDDEN", "Access denied", 403)
    ErrAccountDisabled   = New("ACCOUNT_DISABLED", "Your account has been disabled", 403)
    ErrEmailNotVerified  = New("EMAIL_NOT_VERIFIED", "Email verification required", 403)
    ErrNotBoardMember    = New("NOT_BOARD_MEMBER", "You are not a member of this board", 403)
    ErrInsufficientRole  = New("INSUFFICIENT_ROLE", "Insufficient permissions", 403)
)
```

---

## Not Found Errors (404)

| Code | Message | When |
|------|---------|------|
| `NOT_FOUND` | Resource not found | Generic not found |
| `USER_NOT_FOUND` | User not found | User doesn't exist |
| `ORGANIZATION_NOT_FOUND` | Workspace not found | Organization doesn't exist |
| `BOARD_NOT_FOUND` | Board not found | Board doesn't exist |
| `LIST_NOT_FOUND` | List not found | List doesn't exist |
| `CARD_NOT_FOUND` | Card not found | Card doesn't exist |
| `COMMENT_NOT_FOUND` | Comment not found | Comment doesn't exist |
| `LABEL_NOT_FOUND` | Label not found | Label doesn't exist |
| `CHECKLIST_NOT_FOUND` | Checklist not found | Checklist doesn't exist |
| `ATTACHMENT_NOT_FOUND` | Attachment not found | Attachment doesn't exist |
| `INVITATION_NOT_FOUND` | Invitation not found | Invitation doesn't exist |

```go
var (
    ErrNotFound             = New("NOT_FOUND", "Resource not found", 404)
    ErrUserNotFound         = New("USER_NOT_FOUND", "User not found", 404)
    ErrOrganizationNotFound = New("ORGANIZATION_NOT_FOUND", "Workspace not found", 404)
    ErrBoardNotFound        = New("BOARD_NOT_FOUND", "Board not found", 404)
    ErrListNotFound         = New("LIST_NOT_FOUND", "List not found", 404)
    ErrCardNotFound         = New("CARD_NOT_FOUND", "Card not found", 404)
    ErrCommentNotFound      = New("COMMENT_NOT_FOUND", "Comment not found", 404)
    ErrLabelNotFound        = New("LABEL_NOT_FOUND", "Label not found", 404)
    ErrChecklistNotFound    = New("CHECKLIST_NOT_FOUND", "Checklist not found", 404)
    ErrAttachmentNotFound   = New("ATTACHMENT_NOT_FOUND", "Attachment not found", 404)
    ErrInvitationNotFound   = New("INVITATION_NOT_FOUND", "Invitation not found", 404)
)
```

---

## Conflict Errors (409)

| Code | Message | When |
|------|---------|------|
| `CONFLICT` | Resource already exists | Generic conflict |
| `EMAIL_EXISTS` | Email already registered | Registration with existing email |
| `SLUG_EXISTS` | Slug already taken | Organization slug conflict |
| `ALREADY_MEMBER` | User is already a member | Re-inviting existing member |
| `ALREADY_VERIFIED` | Email already verified | Verify/resend on verified account |

```go
var (
    ErrConflict        = New("CONFLICT", "Resource already exists", 409)
    ErrEmailExists     = New("EMAIL_EXISTS", "Email already registered", 409)
    ErrSlugExists      = New("SLUG_EXISTS", "Slug already taken", 409)
    ErrAlreadyMember   = New("ALREADY_MEMBER", "User is already a member", 409)
    ErrAlreadyVerified = New("ALREADY_VERIFIED", "Email already verified", 409)
)
```

---

## Validation Errors (400/422)

| Code | HTTP | Message | When |
|------|:----:|---------|------|
| `BAD_REQUEST` | 400 | Invalid request | Malformed JSON, missing body |
| `VALIDATION_ERROR` | 422 | Validation failed | Field validation errors |
| `INVALID_EMAIL` | 422 | Invalid email format | Email validation failed |
| `WEAK_PASSWORD` | 422 | Password too weak | Password doesn't meet requirements |
| `INVALID_OTP` | 400 | Invalid or expired verification code | OTP verification failed |
| `OTP_EXPIRED` | 400 | Verification code expired | OTP past expiry time |
| `OTP_ALREADY_USED` | 400 | Verification code already used | OTP `used_at` is set |
| `INVALID_RESET_TOKEN` | 400 | Invalid or expired reset token | Password reset token invalid |
| `MISSING_TOKEN` | 400 | Refresh token not provided | No cookie on /refresh |
| `INVALID_FILE_TYPE` | 400 | Invalid file type | File mimetype not allowed |
| `INVALID_COLOR` | 400 | Invalid color format | Color not matching #XXXXXX |

```go
var (
    ErrBadRequest       = New("BAD_REQUEST", "Invalid request", 400)
    ErrValidation       = New("VALIDATION_ERROR", "Validation failed", 422)
    ErrInvalidEmail     = New("INVALID_EMAIL", "Invalid email format", 422)
    ErrWeakPassword     = New("WEAK_PASSWORD", "Password must be at least 6 characters", 422)
    ErrInvalidOTP       = New("INVALID_OTP", "Invalid or expired verification code", 400)
    ErrOTPExpired       = New("OTP_EXPIRED", "Verification code expired", 400)
    ErrOTPAlreadyUsed   = New("OTP_ALREADY_USED", "Verification code already used", 400)
    ErrInvalidResetToken = New("INVALID_RESET_TOKEN", "Invalid or expired reset token", 400)
    ErrMissingToken     = New("MISSING_TOKEN", "Refresh token not provided", 400)
    ErrInvalidFileType  = New("INVALID_FILE_TYPE", "Invalid file type", 400)
    ErrInvalidColor     = New("INVALID_COLOR", "Invalid color format. Use #XXXXXX", 400)
)
```

### Validation Error Details Format

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Validation failed",
    "details": [
      {
        "field": "email",
        "message": "Invalid email format"
      },
      {
        "field": "password",
        "message": "Must be at least 6 characters"
      }
    ]
  }
}
```

---

## File Upload Errors (413)

| Code | Message | When |
|------|---------|------|
| `FILE_TOO_LARGE` | File exceeds maximum size | File > limit (10MB/2MB) |
| `AVATAR_TOO_LARGE` | Avatar must be less than 2MB | Avatar file > 2MB |
| `ATTACHMENT_TOO_LARGE` | Attachment must be less than 10MB | Attachment > 10MB |

```go
var (
    ErrFileTooLarge       = New("FILE_TOO_LARGE", "File exceeds maximum size", 413)
    ErrAvatarTooLarge     = New("AVATAR_TOO_LARGE", "Avatar must be less than 2MB", 413)
    ErrAttachmentTooLarge = New("ATTACHMENT_TOO_LARGE", "Attachment must be less than 10MB", 413)
)
```

---

## Rate Limit Errors (429)

| Code | Message | When |
|------|---------|------|
| `TOO_MANY_REQUESTS` | Rate limit exceeded | General rate limit hit |
| `TOO_MANY_LOGIN_ATTEMPTS` | Too many login attempts | Login rate limit |
| `TOO_MANY_OTP_ATTEMPTS` | Too many verification attempts | OTP brute force protection |

```go
var (
    ErrTooManyRequests      = New("TOO_MANY_REQUESTS", "Rate limit exceeded. Try again later.", 429)
    ErrTooManyLoginAttempts = New("TOO_MANY_LOGIN_ATTEMPTS", "Too many login attempts. Try again later.", 429)
    ErrTooManyOTPAttempts   = New("TOO_MANY_OTP_ATTEMPTS", "Too many verification attempts. Request a new code.", 429)
)
```

### Rate Limit Response Headers

```
Retry-After: 900
X-RateLimit-Limit: 5
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1714200000
```

---

## Server Errors (500)

| Code | Message | When |
|------|---------|------|
| `INTERNAL_ERROR` | An unexpected error occurred | Unhandled server error |
| `DATABASE_ERROR` | Database operation failed | DB query/connection error |
| `CACHE_ERROR` | Cache operation failed | Redis error |
| `STORAGE_ERROR` | File storage operation failed | MinIO error |
| `EMAIL_ERROR` | Failed to send email | SMTP error |

```go
var (
    ErrInternal    = New("INTERNAL_ERROR", "An unexpected error occurred", 500)
    ErrDatabase    = New("DATABASE_ERROR", "Database operation failed", 500)
    ErrCache       = New("CACHE_ERROR", "Cache operation failed", 500)
    ErrStorage     = New("STORAGE_ERROR", "File storage operation failed", 500)
    ErrEmail       = New("EMAIL_ERROR", "Failed to send email", 500)
)
```

---

## Business Logic Errors

### Board Operations

| Code | HTTP | Message |
|------|:----:|---------|
| `BOARD_CLOSED` | 400 | Board is closed |
| `CANNOT_REMOVE_OWNER` | 400 | Cannot remove the board owner |
| `CANNOT_LEAVE_AS_OWNER` | 400 | Owner cannot leave the board |

### Invitation Operations

| Code | HTTP | Message |
|------|:----:|---------|
| `INVITATION_EXPIRED` | 400 | Invitation has expired |
| `INVITATION_ALREADY_RESPONDED` | 400 | Invitation already responded |
| `SELF_INVITATION` | 400 | Cannot invite yourself |

### Card Operations

| Code | HTTP | Message |
|------|:----:|---------|
| `CARD_ARCHIVED` | 400 | Card is archived |
| `INVALID_DUE_DATE` | 400 | Due date must be in the future |

```go
// Board
var (
    ErrBoardClosed        = New("BOARD_CLOSED", "Board is closed", 400)
    ErrCannotRemoveOwner  = New("CANNOT_REMOVE_OWNER", "Cannot remove the board owner", 400)
    ErrCannotLeaveAsOwner = New("CANNOT_LEAVE_AS_OWNER", "Owner cannot leave the board", 400)
)

// Invitation
var (
    ErrInvitationExpired          = New("INVITATION_EXPIRED", "Invitation has expired", 400)
    ErrInvitationAlreadyResponded = New("INVITATION_ALREADY_RESPONDED", "Invitation already responded", 400)
    ErrSelfInvitation             = New("SELF_INVITATION", "Cannot invite yourself", 400)
)

// Card
var (
    ErrCardArchived   = New("CARD_ARCHIVED", "Card is archived", 400)
    ErrInvalidDueDate = New("INVALID_DUE_DATE", "Due date must be in the future", 400)
)
```

---

## Error Handling Middleware

```go
// internal/middleware/error_handler.go

func ErrorHandler() gin.HandlerFunc {
    return func(c *gin.Context) {
        c.Next()

        if len(c.Errors) == 0 {
            return
        }

        err := c.Errors.Last().Err

        // Handle AppError
        if appErr, ok := err.(*apperror.AppError); ok {
            c.JSON(appErr.StatusCode, gin.H{
                "success": false,
                "error":   appErr,
            })
            return
        }

        // Handle validation errors (go-playground/validator)
        if validationErrs, ok := err.(validator.ValidationErrors); ok {
            details := make([]map[string]string, 0, len(validationErrs))
            for _, e := range validationErrs {
                details = append(details, map[string]string{
                    "field":   e.Field(),
                    "message": getValidationMessage(e),
                })
            }
            c.JSON(422, gin.H{
                "success": false,
                "error": gin.H{
                    "code":    "VALIDATION_ERROR",
                    "message": "Validation failed",
                    "details": details,
                },
            })
            return
        }

        // Log unexpected errors
        log.Error().Err(err).Msg("Unexpected error")

        // Return generic error to client
        c.JSON(500, gin.H{
            "success": false,
            "error": gin.H{
                "code":    "INTERNAL_ERROR",
                "message": "An unexpected error occurred",
            },
        })
    }
}

func getValidationMessage(e validator.FieldError) string {
    switch e.Tag() {
    case "required":
        return fmt.Sprintf("%s is required", e.Field())
    case "email":
        return "Invalid email format"
    case "min":
        return fmt.Sprintf("Must be at least %s characters", e.Param())
    case "max":
        return fmt.Sprintf("Must be at most %s characters", e.Param())
    default:
        return fmt.Sprintf("Invalid value for %s", e.Field())
    }
}
```

---

## Frontend Error Handling

```javascript
// Frontend error handler example
function handleApiError(error) {
  const { code, message } = error.response?.data?.error || {};

  switch (code) {
    case 'UNAUTHORIZED':
    case 'INVALID_TOKEN':
    case 'TOKEN_EXPIRED':
    case 'TOKEN_REVOKED':
    case 'SESSION_INVALIDATED':
      // Redirect to login
      store.dispatch(logout());
      router.push('/login');
      break;

    case 'TOKEN_REUSE_DETECTED':
      // Security alert - force re-login
      toast.error('Security alert: Please login again');
      store.dispatch(logout());
      router.push('/login');
      break;

    case 'VALIDATION_ERROR':
      // Show field-specific errors
      const details = error.response?.data?.error?.details || [];
      details.forEach(({ field, message }) => {
        setFieldError(field, message);
      });
      break;

    case 'TOO_MANY_REQUESTS':
      const retryAfter = error.response?.headers?.['retry-after'];
      toast.error(`Rate limited. Try again in ${retryAfter}s`);
      break;

    case 'FORBIDDEN':
    case 'NOT_BOARD_MEMBER':
      toast.error('You do not have permission to perform this action');
      break;

    default:
      toast.error(message || 'An unexpected error occurred');
  }
}
```

---

## Error Code Quick Reference

| HTTP | Codes |
|:----:|-------|
| 400 | `BAD_REQUEST`, `INVALID_OTP`, `OTP_EXPIRED`, `INVALID_RESET_TOKEN`, `MISSING_TOKEN`, `BOARD_CLOSED`, `INVITATION_EXPIRED` |
| 401 | `UNAUTHORIZED`, `INVALID_TOKEN`, `TOKEN_EXPIRED`, `TOKEN_REVOKED`, `SESSION_INVALIDATED`, `INVALID_CREDENTIALS`, `TOKEN_REUSE_DETECTED` |
| 403 | `FORBIDDEN`, `ACCOUNT_DISABLED`, `EMAIL_NOT_VERIFIED`, `NOT_BOARD_MEMBER`, `INSUFFICIENT_ROLE` |
| 404 | `NOT_FOUND`, `USER_NOT_FOUND`, `BOARD_NOT_FOUND`, `CARD_NOT_FOUND`, etc. |
| 409 | `CONFLICT`, `EMAIL_EXISTS`, `SLUG_EXISTS`, `ALREADY_MEMBER`, `ALREADY_VERIFIED` |
| 413 | `FILE_TOO_LARGE`, `AVATAR_TOO_LARGE`, `ATTACHMENT_TOO_LARGE` |
| 422 | `VALIDATION_ERROR`, `INVALID_EMAIL`, `WEAK_PASSWORD` |
| 429 | `TOO_MANY_REQUESTS`, `TOO_MANY_LOGIN_ATTEMPTS`, `TOO_MANY_OTP_ATTEMPTS` |
| 500 | `INTERNAL_ERROR`, `DATABASE_ERROR`, `CACHE_ERROR`, `STORAGE_ERROR`, `EMAIL_ERROR` |
