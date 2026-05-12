# Domain & SSL Setup - productcon.vn

**Date:** 2026-05-12

---

## 1. Domain Registration (tenten.vn)

- Domain: `productcon.vn`, hạn đến 2027-05-13
- Cập nhật Nameserver sang Cloudflare:
  - NS1: `jaxson.ns.cloudflare.com`
  - NS2: `nia.ns.cloudflare.com`

---

## 2. DNS Records (Cloudflare)

| Type  | Name                                       | Content                                                                                          | Proxy    |
|-------|--------------------------------------------|--------------------------------------------------------------------------------------------------|----------|
| A     | `dev`                                      | VPS Dev IP (ask owner)                                                                           | Proxied  |
| A     | `productcon.vn`                            | VPS Prod IP (ask owner)                                                                          | Proxied  |
| A     | `www`                                      | VPS Prod IP (ask owner)                                                                          | Proxied  |
| CNAME | `_d12e3ab251056e6a16b79d5985356913`        | `245aa7f42c9201600b3c40915d1470ea.6720d91ed3926aafbece323705cffe34.nTVopd3O.sectigo.com`        | DNS only |

---

## 3. VPS Servers (Cloudfly)

| Name               | IP          | Purpose    | Specs           |
|--------------------|-------------|------------|-----------------|
| trello_server_prod | ask owner   | Production | Standard-1-2-20 |
| trello_server_dev  | ask owner   | Dev        | Standard-1-2-20 |

Hạn: đến 23:59 ngày 05-06-2026

---

## 4. SSL Certificate (Cloudfly)

- Gói: **Positive SSL** (Sectigo)
- Domain: `productcon.vn` + `www.productcon.vn`
- Tổng phí: 216,000đ
- Trạng thái: ACTIVE
- Phương thức verify: **CNAME certification method**
- **Hết hạn: 2026-11-26** — gia hạn trước ngày này

### Files certificate (gitignored - không commit)

| File | Vị trí trên VPS |
|------|-----------------|
| `fullchain.pem` (cert + CA chain) | `/opt/trello/Trello_Infra/nginx/ssl/fullchain.pem` |
| `privkey.pem` (private key) | `/opt/trello/Trello_Infra/nginx/ssl/privkey.pem` |

### Renew SSL

```bash
# Khi có cert mới từ Cloudfly, upload và chạy:
scp certificate.crt deploy-prod@<VPS_PROD_IP>:/tmp/domain.crt
ssh my-vps-prod "sudo bash /opt/trello/apply-ssl.sh /tmp/domain.crt"
```

---

## 5. SSL/TLS Mode (Cloudflare)

- Mode: **Full (Strict)**
- Mã hóa end-to-end, yêu cầu certificate hợp lệ ở origin server

---

## 6. Nginx Configuration

File: `/opt/trello/Trello_Infra/nginx/nginx.conf`

- `server_name productcon.vn www.productcon.vn`
- Port 80 → redirect 301 sang HTTPS
- Port 443 → SSL termination với Sectigo cert
- Upstream `api_servers` → `trello-agent-api:8080`
- Upstream `web_servers` → `trello-agent-web:80`
- Route `/api/` → backend API
- Route `/` → frontend web container

### Reload nginx

```bash
ssh my-vps-prod "sudo docker exec trello-agent-nginx nginx -s reload"
```

---

## 7. Frontend Build

- `VITE_API_URL=https://productcon.vn/api/v1` baked vào image lúc build
- Image: `trello-agent-web:local`
- HTML có `Cache-Control: no-cache` để tránh Cloudflare cache stale assets

### Rebuild frontend

```bash
ssh my-vps-prod "cd /opt/trello/Trello_Frontend && sudo docker build --no-cache --build-arg VITE_API_URL=https://productcon.vn/api/v1 -t trello-agent-web:local ."
ssh my-vps-prod "sudo docker stop trello-agent-web && sudo docker rm trello-agent-web && sudo docker run -d --name trello-agent-web --restart unless-stopped --network trello_infra_trello-agent-network trello-agent-web:local"
```

---

## Traffic Flow

```
Browser
  └─ HTTPS ──► Cloudflare (edge cert: Let's Encrypt, auto-managed)
                  └─ HTTPS ──► Nginx on VPS (Sectigo cert, valid đến 2026-11-26)
                                  ├─ /api/* ──► trello-agent-api:8080 (Go backend)
                                  ├─ /storage/* ──► minio:9000
                                  └─ /* ──► trello-agent-web:80 (React frontend)
```

---

## Bugs Fixed

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| Mixed Content error | `VITE_API_URL` baked với `http://222.x.x.x` | Rebuild image với `https://productcon.vn/api/v1` |
| "Login failed" thay vì error thực | Axios interceptor bắt 401 từ login → thử refresh token → reject sai error | Bỏ qua refresh cho `/auth/` endpoints |
| Nginx 404 tất cả routes | Không có upstream/location cho frontend | Thêm `web_servers` upstream + `location /` |
