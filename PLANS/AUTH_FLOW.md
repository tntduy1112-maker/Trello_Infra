# Authentication Flow — TaskFlow

> Tài liệu mô tả toàn bộ luồng xác thực trong hệ thống.

---

## Go Migration Note

| Node.js (Legacy) | Go (New) | Package |
|------------------|----------|---------|
| `authenticate.js` | `middleware/auth.go` | `gin.HandlerFunc` |
| `auth.service.js` | `internal/auth/service.go` | Clean Architecture |
| `jwt.js` | `pkg/jwt/jwt.go` | `golang-jwt/jwt/v5` |
| `bcrypt.js` | `pkg/hash/bcrypt.go` | `golang.org/x/crypto/bcrypt` |
| `tokenCrypto.js` | `pkg/crypto/aes.go` | `crypto/aes`, `crypto/cipher` |
| `Multer` | `c.FormFile()` | Gin built-in |
| `express-rate-limit` | `middleware/ratelimit.go` | `go-redis/redis_rate` |

---

## Tổng quan các thành phần

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐     ┌──────────────┐
│   Client    │     │  auth middleware │     │  auth.service   │     │  PostgreSQL  │
│  (Frontend) │     │  (Gin/Fiber)     │     │  + repository   │     │  (Database)  │
└─────────────┘     └──────────────────┘     └─────────────────┘     └──────────────┘
                                                      │                      │
                                             ┌────────┴────────┐    ┌────────┴────────┐
                                             │   pkg/          │    │     Redis        │
                                             │  ├── jwt/       │    │  blacklist:<jti> │
                                             │  ├── hash/      │    │  ratelimit:*     │
                                             │  ├── email/     │    │  TTL = AT expiry │
                                             │  └── crypto/    │    │  O(1) EXISTS     │
                                             └─────────────────┘    └─────────────────┘

Tokens:
  accessToken   → JWT, secret: JWT_ACCESS_SECRET,  TTL: 15 phút
                  Payload: { userId, email, jti (UUID), iat, exp }
                  Blacklist: jti lưu vào Redis (key: blacklist:<jti>) khi logout/revoke
  refreshToken  → JWT, secret: JWT_REFRESH_SECRET, TTL: 7 ngày
                  Payload: { userId, email, jti (UUID), iat, exp }
                  Cookie: AES-256-GCM encrypted (không phải raw JWT)
                  httpOnly; SameSite=Lax; Secure (prod); MaxAge=7d
                  DB: SHA-256 hash của raw token (không lưu raw)
                  Rotation: mỗi lần /refresh → RT cũ bị revoke, RT mới được cấp

Lớp bảo vệ (defense in depth):
  ── Refresh Token ──
  1. httpOnly cookie         → JS không đọc được (chống XSS)
  2. SameSite=Strict         → chống CSRF (không gửi cookie từ external sites)
  3. Secure (prod)           → chỉ gửi qua HTTPS
  4. AES-256-GCM encrypt     → cookie bị đánh cắp vẫn vô dụng (max 3KB payload)
  5. SHA-256 hash trong DB   → DB bị dump vẫn không dùng được token
  6. Rotation + Reuse detect → RT bị dùng lại → nuke toàn bộ session user
  ── Access Token ──
  7. jti blacklist           → logout/revoke tức thì, không chờ hết hạn
  8. tokens_valid_after      → mass revocation (reuse/reset password/disable)
  ── Rate Limiting ──
  9. /login: 5 req/15min/IP  → chống brute force
  10. /register: 3 req/hour/IP → chống spam accounts
  11. /refresh: 30 req/15min/user → chống token flooding
  12. /verify-email: 5 attempts/OTP → chống OTP brute force
```

---

## 1. Đăng ký (Register)

**Endpoint:** `POST /api/v1/auth/register`
**Rate limit:** 3 requests / hour / IP — 429 nếu vượt quá

```
Client                        Middleware              Service                  DB / Email
  │                               │                      │                        │
  │── POST /register ────────────▶│                      │                        │
  │   {email, password, fullName} │                      │                        │
  │                               │                      │                        │
  │                          validate.js                 │                        │
  │                     (Joi: email, min pw 6,           │                        │
  │                           fullName 1-255)            │                        │
  │                               │                      │                        │
  │                               │── gọi controller ───▶│                        │
  │                               │                      │                        │
  │                               │              findUserByEmail(email)           │
  │                               │                      │──────────────────────▶│
  │                               │                      │◀── null (chưa tồn tại)│
  │                               │                      │                        │
  │                               │              hashPassword(password)           │
  │                               │              [bcrypt, 10 rounds]              │
  │                               │                      │                        │
  │                               │              createUser(email, hash, name)    │
  │                               │                      │──────────────────────▶│
  │                               │                      │◀── user {id, email, …} │
  │                               │                      │                        │
  │                               │              generateOTP() → 6 chữ số         │
  │                               │              expiresAt = now + 15 phút        │
  │                               │              createEmailVerification(         │
  │                               │                userId, otp, 'verify_email')   │
  │                               │                      │──────────────────────▶│
  │                               │                      │                        │
  │                               │              sendVerificationEmail()          │
  │                               │              [non-blocking, fire-and-forget] ──────▶ SMTP
  │                               │                      │                        │
  │◀──── 201 { user } ────────────│                      │                        │
  │  "Check email to verify"      │                      │                        │

Lỗi có thể xảy ra:
  409 Conflict  → Email đã tồn tại
  400 Bad Request → Validation thất bại (Joi)
```

---

## 2. Xác thực Email (Verify Email)

**Endpoint:** `POST /api/v1/auth/verify-email`
**Rate limit:** 5 attempts per OTP — 429 sau 5 lần sai (chống brute force 6-digit OTP)

```
Client                              Service                              DB / Redis
  │                                    │                                  │
  │── POST /verify-email ─────────────▶│                                  │
  │   {email, otp}                     │                                  │
  │                                    │                                  │
  │                           [0] checkOTPAttempts(email)                 │
  │                           [Redis GET otp_attempts:<email>]            │
  │                           → >= 5 attempts → 429 "Too many attempts"   │
  │                                    │                                  │
  │                           findUserByEmail(email)                      │
  │                                    │─────────────────────────────────▶│
  │                                    │◀──────────── user                │
  │                                    │                                  │
  │                            Kiểm tra: user.is_verified?                │
  │                            → true  → 400 "Already verified"           │
  │                                    │                                  │
  │                           findEmailVerification(otp, 'verify_email')  │
  │                                    │─────────────────────────────────▶│
  │                                    │◀──────────── record              │
  │                                    │                                  │
  │                            Kiểm tra tuần tự:                          │
  │                            1. record tồn tại AND user_id khớp?        │
  │                               → không → incrementAttempts(email)      │
  │                               → 400 "Invalid OTP"                     │
  │                            2. record.used_at IS NOT NULL?              │
  │                               → có   → 400 "OTP already used"         │
  │                            3. record.expires_at < now?                 │
  │                               → có   → 400 "OTP expired"              │
  │                                    │                                  │
  │                            markEmailVerificationUsed(record.id)       │
  │                            updateUser(userId, {is_verified: true})    │
  │                                    │─────────────────────────────────▶│
  │                                    │                                  │
  │◀──── 200 "Email verified" ─────────│                                  │
```

---

## 3. Gửi lại OTP (Resend Verification)

**Endpoint:** `POST /api/v1/auth/resend-verification`

```
Client                              Service                              DB / Email
  │                                    │                                     │
  │── POST /resend-verification ──────▶│                                     │
  │   {email}                          │                                     │
  │                                    │                                     │
  │                           findUserByEmail(email)                         │
  │                            → 404 nếu không tồn tại                      │
  │                            → 400 nếu đã verified                        │
  │                                    │                                     │
  │                            generateOTP() → OTP mới                       │
  │                            createEmailVerification(...) → INSERT mới     │
  │                            [record cũ KHÔNG bị xóa, dùng token mới nhất]│
  │                                    │                                     │
  │                            sendVerificationEmail() [non-blocking] ──────▶ SMTP
  │                                    │                                     │
  │◀──── 200 "Verification email resent" ──────────────────────────────────  │
```

---

## 4. Đăng nhập (Login)

**Endpoint:** `POST /api/v1/auth/login`
**Rate limit:** 5 requests / 15 min / IP — 429 nếu vượt quá (chống brute force)

```
Client                        Middleware              Service                  DB
  │                               │                      │                     │
  │── POST /login ───────────────▶│                      │                     │
  │   {email, password}           │                      │                     │
  │   User-Agent header           │                      │                     │
  │                          validate.js                 │                     │
  │                     (Joi: email, password required)  │                     │
  │                               │                      │                     │
  │                               │── gọi controller ───▶│                     │
  │                               │                      │                     │
  │                               │              findUserByEmail(email)        │
  │                               │                      │───────────────────▶│
  │                               │                      │◀── user             │
  │                               │                      │                     │
  │                               │              Kiểm tra:                     │
  │                               │              1. user tồn tại?              │
  │                               │                 → không → 401              │
  │                               │              2. user.is_active?            │
  │                               │                 → false → 403 "Disabled"   │
  │                               │                      │                     │
  │                               │              comparePassword(              │
  │                               │                password, user.password_hash)
  │                               │              [bcrypt.compare]              │
  │                               │              → không khớp → 401            │
  │                               │                      │                     │
  │                               │              generateAccessToken(payload)  │
  │                               │              [JWT, 15m, ACCESS_SECRET,     │
  │                               │               jti: randomUUID()]           │
  │                               │                      │                     │
  │                               │              generateRefreshToken(payload) │
  │                               │              [JWT, 7d, REFRESH_SECRET,     │
  │                               │               jti: randomUUID()]           │
  │                               │                      │                     │
  │                               │              tokenHash = sha256(rawToken)  │
  │                               │              [crypto.createHash('sha256')] │
  │                               │                      │                     │
  │                               │              createRefreshToken(           │
  │                               │                userId, tokenHash,          │
  │                               │                expiresAt, deviceInfo)      │
  │                               │                      │───────────────────▶│
  │                               │                      │  INSERT refresh_tokens
  │                               │                      │  (token_hash, ...)  │
  │                               │                      │                     │
  │                               │              encryptedToken =              │
  │                               │              AES-256-GCM(rawToken, KEY)    │
  │                               │              [tokenCrypto.encrypt()]       │
  │                               │                      │                     │
  │◀──── 200 ─────────────────────│                      │                     │
  │  {                            │                      │                     │
  │    accessToken,  (15 phút)    │                      │                     │
  │    user: { id, email, … }     │                      │                     │
  │  }  [password_hash bị loại]   │                      │                     │
  │                               │                      │                     │
  │  Set-Cookie: refreshToken=    │                      │                     │
  │    <AES-256-GCM blob>         │                      │                     │
  │  [httpOnly; SameSite=Lax;     │                      │                     │
  │   Secure (prod); MaxAge=7d]   │                      │                     │

Lưu ý: payload = { userId, email, jti }  ← jti = crypto.randomUUID()
        deviceInfo lấy từ User-Agent header
        refreshToken KHÔNG trả trong body — chỉ qua httpOnly cookie
        Cookie chứa AES-256-GCM encrypted blob (không phải raw JWT)
        DB lưu SHA-256 hash của raw JWT (không lưu raw, không lưu encrypted)
```

---

## 5. Gọi API được bảo vệ (Authenticated Request)

**Áp dụng cho tất cả endpoint yêu cầu auth (middleware `authenticate.js`)**

```
Client                      authenticate.js (async)            Handler
  │                               │                               │
  │── GET /auth/me ──────────────▶│                               │
  │   Authorization: Bearer <AT>  │                               │
  │                               │                               │
  │                        Kiểm tra header:                       │
  │                        startsWith("Bearer ")?                 │
  │                        → không → 401 "Unauthorized"           │
  │                               │                               │
  │                        [1] verifyAccessToken(token)           │
  │                        [jwt.verify(token, ACCESS_SECRET)]     │
  │                        → lỗi/hết hạn → 401 "Invalid token"   │
  │                               │                               │
  │                        [2] isBlacklisted(decoded.jti)         │
  │                        [Redis EXISTS blacklist:<jti>]         │
  │                        → true → 401 "Token has been revoked"  │
  │                               │                               │
  │                        [3] findUserById(decoded.userId)       │
  │                        → is_active = false → 401              │
  │                        → tokens_valid_after > decoded.iat     │
  │                           → 401 "Session invalidated"         │
  │                               │                               │
  │                        req.user = { userId, email, jti, … }  │
  │                               │                               │
  │                               │────── next() ────────────────▶│
  │◀──── 200 { user } ────────────│                               │

Ghi chú: authenticate.js giờ là async — mỗi request thực hiện:
         [Redis] EXISTS blacklist:<jti>  (~0.1ms, in-memory)
         [DB]    findUserById(userId)    (kiểm tra is_active + tokens_valid_after)
```

---

## 6. Làm mới Token (Refresh Token)

**Endpoint:** `POST /api/v1/auth/refresh`

```
Client                              Service                              DB
  │                                    │                                  │
  │── POST /refresh ──────────────────▶│                                  │
  │   Cookie: refreshToken=<encrypted> │                                  │
  │   [tự động gửi bởi browser]        │                                  │
  │                                    │                                  │
  │                           encrypted = req.cookies.refreshToken        │
  │                           → không có cookie → 400                     │
  │                                    │                                  │
  │                           rawToken = AES-256-GCM-decrypt(encrypted)   │
  │                           [tokenCrypto.decrypt()]                     │
  │                           → tampered/invalid → throw (→ 500/401)      │
  │                                    │                                  │
  │                           verifyRefreshToken(rawToken)                │
  │                           [jwt.verify(rawToken, REFRESH_SECRET)]      │
  │                           → lỗi → 401 "Invalid or expired"            │
  │                                    │                                  │
  │                           findRefreshToken(sha256(rawToken))          │
  │                           [lookup bằng hash, không phải raw]          │
  │                                    │─────────────────────────────────▶│
  │                                    │◀──────────── stored record        │
  │                                    │                                  │
  │                            [1] record tồn tại?                        │
  │                               → không → 401                           │
  │                                    │                                  │
  │                            [2] stored.is_revoked = true?              │
  │                               → REUSE DETECTED ──────────────────────▶│
  │                                 revokeAllUserTokens(user_id)          │
  │                                 invalidateAllUserTokens(user_id)      │
  │                                 [tokens_valid_after = NOW()]          │
  │                               → 401 "Security alert: reuse detected"  │
  │                                    │                                  │
  │                            [3] stored.expires_at < now?               │
  │                               → 401 "Token expired"                   │
  │                                    │                                  │
  │                           findUserById(decoded.userId)                │
  │                            → không tồn tại / inactive → 401          │
  │                                    │                                  │
  │                           ── Rotation ──────────────────────────────  │
  │                           revokeRefreshToken(sha256(oldToken))        │
  │                           newRT = generateRefreshToken(payload)       │
  │                           createRefreshToken(sha256(newRT), ...)      │
  │                                    │─────────────────────────────────▶│
  │                                    │                                  │
  │                           newAT = generateAccessToken(payload)        │
  │                                    │                                  │
  │◀──── 200 { accessToken } ──────────│                                  │
  │   Set-Cookie: refreshToken=        │                                  │
  │     encrypt(newRT)  ← RT MỚI       │                                  │

Ghi chú: Mỗi lần /refresh → RT cũ bị revoke, RT mới được cấp (rotation).
         RT cũ bị dùng lại (is_revoked=true) → security alert → nuke all sessions.
         tokens_valid_after invalidates mọi AT đang bay trong không trung.
```

---

## 7. Đăng xuất (Logout)

**Endpoint:** `POST /api/v1/auth/logout`

```
Client                              Service                              DB
  │                                    │                                  │
  │── POST /logout ───────────────────▶│                                  │
  │   Authorization: Bearer <AT>       │                                  │
  │   Cookie: refreshToken=<encrypted> │                                  │
  │                                    │                                  │
  │                           [1] decode AT từ Authorization header       │
  │                           (best-effort, không throw nếu expired)      │
  │                                    │                                  │
  │                           [2] decrypt(cookie) → rawToken              │
  │                           revokeRefreshToken(sha256(rawToken))        │
  │                           [cookie tampered? → bỏ qua]                │
  │                                    │─────────────────────────────────▶│
  │                                    │  is_revoked = true               │
  │                                    │                                  │
  │                           [3] addToBlacklist(                         │
  │                                AT.jti, userId,                        │
  │                                'logout', AT.exp)                      │
  │                           [non-blocking — không fail logout]          │
  │                                    │                                  │
  │                           Redis SET blacklist:<jti> "logout"          │
  │                                    EX <ttl_seconds> NX               │
  │                           [TTL = thời gian còn lại của AT;            │
  │                            Redis auto-xóa khi hết TTL]               │
  │                                    │                                  │
  │                           res.clearCookie('refreshToken')             │
  │                                    │                                  │
  │◀──── 200 "Logged out" ─────────────│                                  │
  │   Set-Cookie: refreshToken=;       │                                  │
  │   Expires=Thu, 01 Jan 1970 ...     │                                  │

Ghi chú:
  - RT bị revoke trong DB (is_revoked = true) + cookie bị xóa khỏi browser.
  - AT bị blacklist ngay lập tức trong Redis theo jti → không cần chờ 15 phút.
  - Redis tự xóa key khi TTL hết — không cần cleanup job.
  - Chỉ revoke session hiện tại (1 thiết bị).
```

---

## 7.1 Đăng xuất tất cả thiết bị (Logout All)

**Endpoint:** `POST /api/v1/auth/logout-all`

```
Client                              Service                              DB / Redis
  │                                    │                                  │
  │── POST /logout-all ────────────────▶│                                  │
  │   Authorization: Bearer <AT>       │                                  │
  │                                    │                                  │
  │                           [1] Authenticate middleware                 │
  │                           [Verify AT, check blacklist]                │
  │                                    │                                  │
  │                           [2] revokeAllUserTokens(userId)             │
  │                           [UPDATE refresh_tokens                      │
  │                            SET is_revoked = true                      │
  │                            WHERE user_id = ? AND is_revoked = false]  │
  │                                    │─────────────────────────────────▶│
  │                                    │                                  │
  │                           [3] invalidateAllUserTokens(userId)         │
  │                           [UPDATE users                               │
  │                            SET tokens_valid_after = NOW()             │
  │                            WHERE id = ?]                              │
  │                                    │─────────────────────────────────▶│
  │                                    │                                  │
  │                           [4] clearCookie('refreshToken')             │
  │                                    │                                  │
  │◀──── 200 "Logged out from all devices" ─────────────────────────────  │

Ghi chú:
  - TẤT CẢ refresh tokens của user bị revoke (mọi thiết bị).
  - tokens_valid_after = NOW() → mọi AT đang bay đều bị từ chối.
  - User phải login lại trên tất cả các thiết bị.
  - Use case: nghi ngờ bị hack, đổi mật khẩu, xóa tài khoản.
```

---

## 8. Quên mật khẩu (Forgot Password)

**Endpoint:** `POST /api/v1/auth/forgot-password`
**Rate limit:** 5 requests / 15 phút / IP (`express-rate-limit`) — 429 nếu vượt quá

```
Client                              Service                          DB / Email
  │                                    │                                │
  │── POST /forgot-password ──────────▶│                                │
  │   {email}                          │                                │
  │                                    │                                │
  │                           findUserByEmail(email)                    │
  │                            → không tồn tại: RETURN SILENTLY         │
  │                              (không tiết lộ email có hay không)     │
  │                                    │                                │
  │                           token = crypto.randomBytes(32).hex()      │
  │                           [64 ký tự hex, KHÔNG phải JWT]            │
  │                           expiresAt = now + 1 giờ                   │
  │                                    │                                │
  │                           createEmailVerification(                  │
  │                             userId, token, 'reset_password')        │
  │                                    │──────────────────────────────▶│
  │                                    │                                │
  │                           sendPasswordResetEmail()                  │
  │                           [non-blocking] ──────────────────────────▶ SMTP
  │                           URL trong email:                          │
  │                           {FRONTEND_URL}/reset-password?token=...   │
  │                                    │                                │
  │◀──── 200 "If email exists, link sent" ──────────────────────────── │
  │      [Response giống nhau dù email có tồn tại hay không]            │
```

---

## 9. Đặt lại mật khẩu (Reset Password)

**Endpoint:** `POST /api/v1/auth/reset-password`
**Rate limit:** 5 requests / 15 phút / IP (cùng limiter với forgot-password)

```
Client                              Service                              DB
  │                                    │                                  │
  │── POST /reset-password ───────────▶│                                  │
  │   {token, password}                │                                  │
  │                                    │                                  │
  │                           findEmailVerification(                      │
  │                             token, 'reset_password')                  │
  │                                    │─────────────────────────────────▶│
  │                                    │◀──────────── record               │
  │                                    │                                  │
  │                            Kiểm tra tuần tự:                          │
  │                            1. record tồn tại?                         │
  │                               → không → 400 "Invalid reset token"     │
  │                            2. record.used_at IS NOT NULL?              │
  │                               → có   → 400 "Token already used"       │
  │                            3. record.expires_at < now?                 │
  │                               → có   → 400 "Token expired"            │
  │                                    │                                  │
  │                           hashPassword(newPassword)                   │
  │                           [bcrypt, password min 6 ký tự]             │
  │                                    │                                  │
  │                           markEmailVerificationUsed(record.id)        │
  │                           updateUser(userId, {password_hash})         │
  │                           revokeAllUserTokens(userId)                 │
  │                           [Thu hồi TẤT CẢ refresh tokens của user]   │
  │                           invalidateAllUserTokens(userId)             │
  │                           [tokens_valid_after = NOW()                 │
  │                            → AT cũ bị vô hiệu tức thì]               │
  │                                    │─────────────────────────────────▶│
  │                                    │                                  │
  │◀──── 200 "Password reset. Login again." ───────────────────────────── │
```

---

## 10. Sơ đồ trạng thái Token

```
                        ┌─────────────────────────────────┐
                        │           CHƯA ĐĂNG NHẬP        │
                        └──────────────────┬──────────────┘
                                           │ POST /login (thành công)
                                           ▼
                        ┌─────────────────────────────────┐
                        │  CÓ accessToken (15m) +          │
                        │  CÓ refreshToken (7d, DB)        │
                        └────┬────────────────────────┬───┘
                             │                        │
            accessToken hết hạn (401)                 │ POST /logout
                             │                        │
                             ▼                        ▼
              ┌──────────────────────┐   ┌───────────────────────────┐
              │ POST /auth/refresh   │   │  refreshToken.is_revoked  │
              │ Cookie: encrypted    │   │  = true trong DB          │
              │                      │   │  → Client xóa localStorage│
              │ Kiểm tra:            │   └───────────────────────────┘
              │ 0. decrypt cookie    │
              │ 1. JWT hợp lệ?       │
              │ 2. is_revoked?       │──── YES → REUSE DETECTED ──────────▶ ┌──────────────────────────┐
              │ 3. expires_at > now? │                                       │ revokeAllUserTokens()    │
              └──────┬───────────────┘                                       │ invalidateAllUserTokens()│
                     │ thành công                                            │ 401 Security Alert       │
                     ▼                                                       └──────────────────────────┘
              ┌──────────────────────┐
              │  accessToken mới     │
              │  (15 phút, jti mới)  │
              │  refreshToken MỚI    │  ← Rotation: RT cũ revoked
              │  (cookie cập nhật)   │
              └──────────────────────┘

Khi logout:
  → revokeRefreshToken() → RT thiết bị hiện tại bị thu hồi
  → addToBlacklist(AT.jti) → AT bị vô hiệu ngay lập tức

Khi reset-password:
  → revokeAllUserTokens()    → TẤT CẢ RT bị thu hồi
  → invalidateAllUserTokens() → tokens_valid_after = NOW()
  → AT cũ trên mọi thiết bị bị vô hiệu tức thì
```

---

## 11. Bảng tóm tắt Endpoint

| Endpoint | Method | Auth | Rate Limit | Mô tả |
|---|---|:---:|:---:|---|
| `/auth/register` | POST | ❌ | 3/hour/IP | Tạo tài khoản, gửi OTP email |
| `/auth/verify-email` | POST | ❌ | 5 attempts/OTP | Xác thực email bằng OTP 6 chữ số |
| `/auth/resend-verification` | POST | ❌ | 3/hour/email | Gửi lại OTP mới (TTL 15 phút) |
| `/auth/login` | POST | ❌ | 5/15m/IP | Đăng nhập, nhận accessToken + refreshToken cookie |
| `/auth/refresh` | POST | ❌ | 30/15m/user | Lấy accessToken mới từ refreshToken cookie |
| `/auth/logout` | POST | ❌* | — | Revoke RT + blacklist AT (best-effort, không fail) |
| `/auth/logout-all` | POST | ✅ JWT | — | Revoke TẤT CẢ RT + invalidate mọi AT |
| `/auth/me` | GET | ✅ JWT | — | Thông tin user đang đăng nhập |
| `/auth/me` | PUT | ✅ JWT | — | Cập nhật tên + avatar (multipart, 2MB, MinIO) |
| `/auth/forgot-password` | POST | ❌ | 5/15m/IP | Gửi link reset mật khẩu vào email |
| `/auth/reset-password` | POST | ❌ | 5/15m/IP | Đổi mật khẩu, revoke tất cả tokens |

> `*` `/auth/logout` không require JWT nhưng đọc AT từ Authorization header (best-effort) để blacklist jti.

---

## 12. Storage liên quan đến Auth

### PostgreSQL

| Bảng | Vai trò trong Auth |
|---|---|
| `users` | Lưu tài khoản: `email`, `password_hash`, `is_verified`, `is_active`, `tokens_valid_after` |
| `refresh_tokens` | Lưu refresh token: `token_hash` (SHA-256, VARCHAR 64), `expires_at`, `is_revoked`, `device_info` |
| `email_verifications` | Lưu OTP/reset-token: `token`, `type` (`verify_email` / `reset_password`), `expires_at`, `used_at` |

**`users.tokens_valid_after`**: timestamp mass revocation — mọi AT có `iat < tokens_valid_after` đều bị từ chối.
Được set khi: reuse detected, reset password, admin disable account.

### Redis

| Key pattern | Value | TTL | Mục đích |
|---|---|---|---|
| `blacklist:<jti>` | `"logout"` / `"admin_revoke"` | Thời gian còn lại của AT | Blacklist AT tức thì sau logout/revoke |
| `ratelimit:login:<ip>` | request count | 15 min | Chống brute force login |
| `ratelimit:register:<ip>` | request count | 1 hour | Chống spam accounts |
| `ratelimit:refresh:<user_id>` | request count | 15 min | Chống token flooding |
| `otp_attempts:<email>` | attempt count | 15 min (OTP expiry) | Chống brute force OTP |

**Tại sao Redis thay vì Postgres cho blacklist + rate limit?**
- **Tốc độ**: O(1) EXISTS/INCR ~0.1ms (in-memory) vs ~1-5ms (disk I/O)
- **Tự dọn dẹp**: TTL auto-expire, không cần `DELETE WHERE expires_at < NOW()` định kỳ
- **Scale**: 15 phút TTL × traffic cao = triệu rows trong Postgres; Redis xử lý nhẹ nhàng
- **Atomic**: INCR + EXPIRE trong 1 command — không race condition

**Cấu hình Redis** (`config/redis.go`, `docker-compose.yml`):
- Image: `redis:7-alpine`, port `6379`, password required
- `maxmemory 128mb`, policy `allkeys-lru` (xóa key ít dùng nhất khi hết RAM)
- Persistent: `redis_data` volume, `appendonly yes`

---

## 13. Luồng Frontend (Axios Interceptor)

```
Frontend (axiosInstance.js)
  │
  ├── Cấu hình: withCredentials: true
  │     └── Browser tự đính kèm httpOnly cookie vào mọi request đến cùng origin
  │
  ├── Request Interceptor
  │     └── Thêm header: Authorization: Bearer <accessToken từ localStorage>
  │
  └── Response Interceptor
        └── Nhận lỗi 401?
              │
              ├── Đã đang refresh? → Đưa request vào hàng đợi (queue)
              │
              └── Chưa refresh → POST /auth/refresh {}
                    │  [không cần body — browser tự gửi cookie]
                    ├── Thành công → Lưu accessToken mới vào localStorage
                    │               → Retry toàn bộ queue
                    └── Thất bại   → Xóa token + user khỏi localStorage
                                    → Redirect /login

Lưu ý lưu trữ:
  localStorage    → accessToken, user (readable by JS, cần thiết cho app)
  httpOnly cookie → refreshToken dạng AES-256-GCM encrypted blob
                    KHÔNG readable by JS (chống XSS)
                    KHÔNG phải raw JWT (chống browser malware/cookie theft)
  KHÔNG còn refreshToken trong localStorage
```

---

## 14. Cập nhật hồ sơ cá nhân (Profile Update)

**Endpoint:** `PUT /api/v1/auth/me`  **Status: ✅ Hoàn thành**

```
Client                   Multer          auth.service            MinIO / DB
  │                        │                  │                      │
  │── PUT /auth/me ────────▶│                  │                      │
  │   Authorization: Bearer │                  │                      │
  │   Content-Type: multi   │                  │                      │
  │   part/form-data        │                  │                      │
  │   ├── full_name (text)  │                  │                      │
  │   └── avatar  (file?)   │                  │                      │
  │                         │                  │                      │
  │                   avatarUpload.single('avatar')                   │
  │                   fileFilter: image/* only                        │
  │                   limits.fileSize: 2MB                            │
  │                   storage: memoryStorage()                        │
  │                         │                  │                      │
  │                         │── req.file ──────▶│                      │
  │                         │   req.body ───────▶│                      │
  │                                             │                      │
  │                                    findUserById(userId)            │
  │                                             │──────────────────────▶│ DB
  │                                             │◀───── user            │
  │                                             │                      │
  │                                    [nếu có req.file]              │
  │                                    uploadFile({                   │
  │                                      buffer, mimetype,            │
  │                                      folder: 'avatars',           │
  │                                      filename: originalname        │
  │                                    })                             │
  │                                             │──────────────────────▶│ MinIO PUT
  │                                             │◀─── objectName        │
  │                                             │                      │
  │                                    [nếu user.avatar_url tồn tại]  │
  │                                    deleteFile(oldObjectName)      │
  │                                    [fire-and-forget, catch noop]  │
  │                                             │──────────────────────▶│ MinIO DELETE
  │                                             │                      │
  │                                    fields.avatar_url =            │
  │                                      getPublicUrl(objectName)     │
  │                                             │                      │
  │                                    updateUser(userId, fields)     │
  │                                             │──────────────────────▶│ DB
  │                                             │◀─── updatedUser       │
  │                                             │                      │
  │◀──── 200 { user: updatedUser } ─────────────│                      │

Lỗi có thể xảy ra:
  400 → Multer fileFilter: file không phải image/*
  413 → Multer limits: file > 2MB
  404 → User không tồn tại

Frontend (ProfilePage.jsx):
  handleAvatarChange → lưu file vào avatarFileRef.current
  handleSaveProfile:
    const formData = new FormData()
    formData.append('full_name', profileForm.full_name)
    if (avatarFileRef.current) formData.append('avatar', avatarFileRef.current)
    dispatch(updateProfileThunk(formData))
      → updateMe(formData) — axios PUT với Content-Type: multipart/form-data
      → fulfilled: state.user merge, localStorage.setItem('user', ...)
      → rejected: profileError state hiển thị lỗi
```

---

## 15. Go Implementation Details

### Middleware Chain (Gin)

```go
// internal/middleware/auth.go
func AuthMiddleware(jwtService jwt.Service, redis *redis.Client, userRepo user.Repository) gin.HandlerFunc {
    return func(c *gin.Context) {
        // 1. Extract token from Authorization header
        token := extractBearerToken(c.GetHeader("Authorization"))
        if token == "" {
            c.AbortWithStatusJSON(401, ErrorResponse{Code: "UNAUTHORIZED"})
            return
        }

        // 2. Verify JWT
        claims, err := jwtService.VerifyAccessToken(token)
        if err != nil {
            c.AbortWithStatusJSON(401, ErrorResponse{Code: "INVALID_TOKEN"})
            return
        }

        // 3. Check Redis blacklist
        if isBlacklisted(redis, claims.JTI) {
            c.AbortWithStatusJSON(401, ErrorResponse{Code: "TOKEN_REVOKED"})
            return
        }

        // 4. Load user and check tokens_valid_after
        user, err := userRepo.FindByID(c.Request.Context(), claims.UserID)
        if err != nil || !user.IsActive {
            c.AbortWithStatusJSON(401, ErrorResponse{Code: "USER_INACTIVE"})
            return
        }
        if user.TokensValidAfter.After(time.Unix(claims.IssuedAt, 0)) {
            c.AbortWithStatusJSON(401, ErrorResponse{Code: "SESSION_INVALIDATED"})
            return
        }

        // 5. Set user in context
        c.Set("user", user)
        c.Set("claims", claims)
        c.Next()
    }
}
```

### Context Propagation

```go
// Helper functions for handlers
func GetCurrentUser(c *gin.Context) (*model.User, bool) {
    user, exists := c.Get("user")
    if !exists {
        return nil, false
    }
    return user.(*model.User), true
}

func GetClaims(c *gin.Context) (*jwt.Claims, bool) {
    claims, exists := c.Get("claims")
    if !exists {
        return nil, false
    }
    return claims.(*jwt.Claims), true
}
```

### Error Types Mapping

```go
// internal/apperror/errors.go
type AppError struct {
    Code       string `json:"code"`
    Message    string `json:"message"`
    StatusCode int    `json:"-"`
}

var (
    ErrUnauthorized     = &AppError{"UNAUTHORIZED", "Authentication required", 401}
    ErrInvalidToken     = &AppError{"INVALID_TOKEN", "Invalid or expired token", 401}
    ErrTokenRevoked     = &AppError{"TOKEN_REVOKED", "Token has been revoked", 401}
    ErrSessionInvalid   = &AppError{"SESSION_INVALIDATED", "Session invalidated", 401}
    ErrForbidden        = &AppError{"FORBIDDEN", "Access denied", 403}
    ErrNotFound         = &AppError{"NOT_FOUND", "Resource not found", 404}
    ErrConflict         = &AppError{"CONFLICT", "Resource already exists", 409}
    ErrValidation       = &AppError{"VALIDATION_ERROR", "Validation failed", 422}
    ErrTooManyRequests  = &AppError{"TOO_MANY_REQUESTS", "Rate limit exceeded", 429}
    ErrInternal         = &AppError{"INTERNAL_ERROR", "Internal server error", 500}
)

// Global error handler middleware
func ErrorHandler() gin.HandlerFunc {
    return func(c *gin.Context) {
        c.Next()
        if len(c.Errors) > 0 {
            err := c.Errors.Last().Err
            if appErr, ok := err.(*AppError); ok {
                c.JSON(appErr.StatusCode, gin.H{
                    "success": false,
                    "error":   appErr,
                })
                return
            }
            c.JSON(500, gin.H{
                "success": false,
                "error":   ErrInternal,
            })
        }
    }
}
```

### Rate Limiting (go-redis/redis_rate)

```go
// internal/middleware/ratelimit.go
func RateLimitMiddleware(limiter *redis_rate.Limiter, key string, limit redis_rate.Limit) gin.HandlerFunc {
    return func(c *gin.Context) {
        identifier := c.ClientIP() // or user ID for authenticated routes
        result, err := limiter.Allow(c.Request.Context(), key+":"+identifier, limit)
        if err != nil {
            c.AbortWithStatusJSON(500, ErrInternal)
            return
        }
        if result.Allowed == 0 {
            c.Header("Retry-After", strconv.Itoa(int(result.RetryAfter.Seconds())))
            c.AbortWithStatusJSON(429, ErrTooManyRequests)
            return
        }
        c.Next()
    }
}

// Usage in router
authGroup := r.Group("/api/v1/auth")
authGroup.POST("/login", RateLimitMiddleware(limiter, "login", redis_rate.PerMinute(5)), authHandler.Login)
authGroup.POST("/register", RateLimitMiddleware(limiter, "register", redis_rate.PerHour(3)), authHandler.Register)
```

### Cookie Configuration

```go
// pkg/cookie/cookie.go
const (
    RefreshTokenCookie = "refreshToken"
    MaxCookieSize      = 4096 // 4KB browser limit
    MaxPayloadSize     = 3072 // 3KB safe limit after encryption overhead
)

func SetRefreshTokenCookie(c *gin.Context, encryptedToken string, maxAge int) {
    c.SetSameSite(http.SameSiteStrictMode) // Strict for CSRF protection
    c.SetCookie(
        RefreshTokenCookie,
        encryptedToken,
        maxAge,
        "/",
        "",    // domain
        true,  // secure (HTTPS only in prod)
        true,  // httpOnly
    )
}

func ClearRefreshTokenCookie(c *gin.Context) {
    c.SetCookie(RefreshTokenCookie, "", -1, "/", "", true, true)
}
```