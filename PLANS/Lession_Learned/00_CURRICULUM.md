# Learning Curriculum: Go Backend Development

> A structured learning path based on the TaskFlow (Trello Clone) project built with Go.

---

## Overview

This curriculum teaches you backend development through **real code examples** from your TaskFlow project. Each lesson builds upon the previous one, taking you from fundamentals to production-ready skills.

**Your Stack:**
- Language: Go 1.25
- Framework: Gin (HTTP router)
- Database: PostgreSQL 16 (with pgx driver)
- Cache: Redis 7
- Storage: MinIO (S3-compatible)
- Auth: JWT tokens
- Containerization: Docker

---

## Learning Path

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         LEARNING JOURNEY                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  PHASE 1: FOUNDATIONS (Lessons 1-3)                                         │
│  ────────────────────────────────────                                       │
│  ┌──────────────┐   ┌──────────────────┐   ┌─────────────────────┐         │
│  │ 01. Go       │──▶│ 02. Project      │──▶│ 03. Clean           │         │
│  │    Basics    │   │    Structure     │   │    Architecture     │         │
│  └──────────────┘   └──────────────────┘   └─────────────────────┘         │
│                                                                             │
│  PHASE 2: CORE PATTERNS (Lessons 4-7)                                       │
│  ─────────────────────────────────────                                      │
│  ┌──────────────┐   ┌──────────────────┐   ┌─────────────────────┐         │
│  │ 04. Domain   │──▶│ 05. Repository   │──▶│ 06. Service         │         │
│  │    Models    │   │    Pattern       │   │    Layer            │         │
│  └──────────────┘   └──────────────────┘   └─────────────────────┘         │
│                            │                                                │
│                            ▼                                                │
│                     ┌──────────────────┐                                    │
│                     │ 07. Handlers     │                                    │
│                     │    & REST API    │                                    │
│                     └──────────────────┘                                    │
│                                                                             │
│  PHASE 3: ADVANCED TOPICS (Lessons 8-11)                                    │
│  ───────────────────────────────────────                                    │
│  ┌──────────────┐   ┌──────────────────┐   ┌─────────────────────┐         │
│  │ 08. Middle-  │──▶│ 09. PostgreSQL   │──▶│ 10. JWT Auth        │         │
│  │    ware      │   │    & Migrations  │   │    & Security       │         │
│  └──────────────┘   └──────────────────┘   └─────────────────────┘         │
│                                                                             │
│  PHASE 4: DEPLOYMENT (Lesson 11)                                            │
│  ────────────────────────────────                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 11. Docker & Deployment                                              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Lesson Index

### Phase 1: Foundations

| # | Lesson | Description | Time |
|:-:|--------|-------------|:----:|
| 01 | [Go Basics](01_GO_BASICS.md) | Variables, functions, structs, interfaces, error handling | 2-3h |
| 02 | [Project Structure](02_PROJECT_STRUCTURE.md) | How to organize a Go project (cmd, internal, pkg) | 1h |
| 03 | [Clean Architecture](03_CLEAN_ARCHITECTURE.md) | Layered architecture: Handler → Service → Repository | 1-2h |

### Phase 2: Core Patterns

| # | Lesson | Description | Time |
|:-:|--------|-------------|:----:|
| 04 | [Domain Models](04_DOMAIN_MODELS.md) | Defining entities (User, Board, Card) with Go structs | 1h |
| 05 | [Repository Pattern](05_REPOSITORY_PATTERN.md) | Data access layer with PostgreSQL | 2-3h |
| 06 | [Service Layer](06_SERVICE_LAYER.md) | Business logic, validation, orchestration | 2-3h |
| 07 | [Handlers & REST API](07_HANDLERS_API.md) | HTTP handlers, request/response, routing | 2-3h |

### Phase 3: Advanced Topics

| # | Lesson | Description | Time |
|:-:|--------|-------------|:----:|
| 08 | [Middleware](08_MIDDLEWARE.md) | Auth, rate limiting, error handling middleware | 1-2h |
| 09 | [PostgreSQL & Migrations](09_DATABASE_POSTGRESQL.md) | Database design, SQL, migrations with Goose | 2-3h |
| 10 | [JWT Authentication](10_JWT_AUTHENTICATION.md) | Access tokens, refresh tokens, token rotation | 2-3h |

### Phase 4: Deployment

| # | Lesson | Description | Time |
|:-:|--------|-------------|:----:|
| 11 | [Docker & Deployment](11_DOCKER_DEPLOYMENT.md) | Containerization, docker-compose, production setup | 2h |

### Supplementary

| # | Lesson | Description |
|:-:|--------|-------------|
| - | [Redis & PostgreSQL](REDIS_PG.md) | How Redis and PostgreSQL work together (already exists) |

---

## How to Use This Curriculum

### For Each Lesson:

1. **Read the concept explanation** — Understand the WHY before the HOW
2. **Study the code examples** — All examples are from YOUR project
3. **Find the actual file** — The file path is provided for each example
4. **Explore the external resources** — Deepen your understanding
5. **Try modifying the code** — Best way to learn is by doing

### Recommended Study Order:

```
Week 1: Lessons 01-03 (Foundations)
Week 2: Lessons 04-05 (Models & Repository)
Week 3: Lessons 06-07 (Service & Handlers)
Week 4: Lessons 08-10 (Middleware, DB, Auth)
Week 5: Lesson 11 (Docker & Deployment)
```

---

## Key Files to Study

These are the most important files in your project:

| File | What You'll Learn |
|------|-------------------|
| `cmd/server/main.go` | Application entry point, dependency injection |
| `internal/domain/user.go` | Domain model definition |
| `internal/repository/user_repository.go` | Database operations |
| `internal/service/auth_service.go` | Business logic |
| `internal/handler/auth_handler.go` | HTTP request handling |
| `internal/middleware/auth.go` | JWT authentication |
| `docker-compose.yml` | Service orchestration |

---

## External Learning Resources

### Go Language

| Resource | URL | Type |
|----------|-----|:----:|
| Go Tour | https://go.dev/tour | Interactive |
| Go by Example | https://gobyexample.com | Examples |
| Effective Go | https://go.dev/doc/effective_go | Official Doc |

### Web Development

| Resource | URL | Type |
|----------|-----|:----:|
| Gin Documentation | https://gin-gonic.com/docs | Official Doc |
| REST API Design | https://restfulapi.net | Guide |

### Database

| Resource | URL | Type |
|----------|-----|:----:|
| PostgreSQL Tutorial | https://www.postgresqltutorial.com | Tutorial |
| pgx Documentation | https://github.com/jackc/pgx | GitHub |

### Architecture

| Resource | URL | Type |
|----------|-----|:----:|
| Clean Architecture | https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html | Article |
| Go Project Layout | https://github.com/golang-standards/project-layout | GitHub |

---

## Progress Tracker

Use this to track your learning progress:

- [ ] Lesson 01: Go Basics
- [ ] Lesson 02: Project Structure
- [ ] Lesson 03: Clean Architecture
- [ ] Lesson 04: Domain Models
- [ ] Lesson 05: Repository Pattern
- [ ] Lesson 06: Service Layer
- [ ] Lesson 07: Handlers & REST API
- [ ] Lesson 08: Middleware
- [ ] Lesson 09: PostgreSQL & Migrations
- [ ] Lesson 10: JWT Authentication
- [ ] Lesson 11: Docker & Deployment

---

## Tips for Learning

1. **Don't rush** — Understanding > Speed
2. **Type the code** — Don't just read, practice typing
3. **Break things** — Modify code, see what breaks, learn why
4. **Use the debugger** — Step through code to understand flow
5. **Ask questions** — Use Claude to explain anything unclear
6. **Build something** — After each phase, try adding a small feature

---

## Next Step

Start with **[Lesson 01: Go Basics](01_GO_BASICS.md)** to begin your journey!
