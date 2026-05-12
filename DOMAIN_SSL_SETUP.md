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

| Type  | Name                      | Content                                      | Proxy     |
|-------|---------------------------|----------------------------------------------|-----------|
| A     | `dev`                     | `103.82.193.252` (VPS Dev)                   | Proxied   |
| A     | `productcon.vn`           | `222.255.180.94` (VPS Prod)                  | Proxied   |
| A     | `www`                     | `222.255.180.94` (VPS Prod)                  | Proxied   |
| CNAME | `_d12e3ab251056e6a16b79d5985356913` | `245aa7f42c9201600b3c40915d1470ea.6720d91ed3926aafbece323705cffe34.nTVopd3O.sectigo.com` | DNS only |

---

## 3. VPS Servers (Cloudfly)

| Name               | IP              | Purpose    | Specs          |
|--------------------|-----------------|------------|----------------|
| trello_server_prod | 222.255.180.94  | Production | Standard-1-2-20 |
| trello_server_dev  | 103.82.193.252  | Dev        | Standard-1-2-20 |

Hạn: đến 23:59 ngày 05-06-2026

---

## 4. SSL Certificate (Cloudfly)

- Gói: **Positive SSL** (Sectigo)
- Domain: `productcon.vn`
- Tổng phí: 216,000đ
- Trạng thái: ACTIVE
- Phương thức verify: **CNAME certification method**
- CNAME record đã thêm vào Cloudflare để Sectigo xác nhận ownership

---

## 5. SSL/TLS Mode (Cloudflare)

- Mode: **Full (Strict)**
- Mã hóa end-to-end, yêu cầu certificate hợp lệ ở origin server

---

## Traffic Flow

```
Browser
  └─ HTTPS ──► Cloudflare (proxy, edge cert)
                  └─ HTTPS ──► VPS Origin (SSL cert từ Cloudfly/Sectigo)
```
