# Domain & SSL Setup 
**Date:** 2026-05-12

---

## 1. Domain Registration (tenten.vn)

- Domain:  ask owner 
- Cập nhật Nameserver sang Cloudflare:(set to Cloudflare-branded nameservers) 

---

## 2. DNS Records (Cloudflare)

| Type  | Name                                       | Content                                                                                          | Proxy    |
|-------|--------------------------------------------|--------------------------------------------------------------------------------------------------|----------|
| A     | `dev`                                      | VPS Dev IP (ask owner)                                                                           | Proxied  |
| A     | ask owner                            | VPS Prod IP (ask owner)                                                                          | Proxied  |
| A     | `www`                                      | VPS Prod IP (ask owner)                                                                          | Proxied  |
| CNAME | CNAME certification (ask owner)        | Value (ask owner)        | DNS only |

---

## 3. VPS Servers (Cloudfly)

| Name               | IP          | Purpose    | Specs           |
|--------------------|-------------|------------|-----------------|
| trello_server_prod | ask owner   | Production | Standard-1-2-20 |
| trello_server_dev  | ask owner   | Dev        | Standard-1-2-20 |

Hạn: ask owner

---

## 4. SSL Certificate (Cloudfly)

- Gói: **Positive SSL** (Sectigo)
- Domain: ask owner
- Phương thức verify: **CNAME certification method**

### Files certificate (gitignored - không commit)

| File | Vị trí trên VPS |
|------|-----------------|
| `fullchain.pem` (cert + CA chain) | `<SERVER_PATH>/nginx/ssl/fullchain.pem` |
| `privkey.pem` (private key) | `<SERVER_PATH>/nginx/ssl/privkey.pem` |

### Renew SSL

```bash
# Khi có cert mới từ Cloudfly, upload và chạy:
scp certificate.crt <DEPLOY_USER>@<VPS_PROD_IP>:/tmp/domain.crt
ssh my-vps-prod "sudo bash <PATH_TO_APPLY_SSL_SCRIPT> /tmp/domain.crt"
```

---

## 5. SSL/TLS Mode (Cloudflare)

- Mode: **Full (Strict)**
- Mã hóa end-to-end, yêu cầu certificate hợp lệ ở origin server

---

## 6. Nginx Configuration

File: `<SERVER_PATH>/nginx/nginx.conf`

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
                  └─ HTTPS ──► Nginx on VPS (Sectigo cert, valid until ask owner)
                                  ├─ /api/* ──► trello-agent-api:8080 (Go backend)
                                  ├─ /storage/* ──► minio:9000
                                  └─ /* ──► trello-agent-web:80 (React frontend)
```

---

