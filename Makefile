.PHONY: help dev up prod down health logs logs-api restart migrate migrate-down db-shell redis-cli build-api docker-push clean clean-all

help:
	@echo "Trello Infra - Available commands:"
	@echo ""
	@echo "  Environments:"
	@echo "    make dev          - Start dev stack (docker-compose.yml)"
	@echo "    make up           - Start dev stack in background"
	@echo "    make prod         - Start prod stack (docker-compose.prod.yml)"
	@echo "    make down         - Stop current stack"
	@echo "    make health       - Check API health endpoint"
	@echo ""
	@echo "  Logs:"
	@echo "    make logs         - View logs (all services)"
	@echo "    make logs-api     - View API logs only"
	@echo "    make restart      - Restart all services"
	@echo ""
	@echo "  Database:"
	@echo "    make migrate      - Run database migrations"
	@echo "    make migrate-down - Rollback last migration"
	@echo "    make db-shell     - Open PostgreSQL shell"
	@echo "    make redis-cli    - Open Redis CLI"
	@echo ""
	@echo "  Docker:"
	@echo "    make build-api    - Build API image from Backend repo"
	@echo "    make docker-push  - Push image to registry"
	@echo ""

# ==========================================
# Development
# ==========================================

dev:
	docker compose -f docker-compose.yml up

up:
	docker compose -f docker-compose.yml up -d

down:
	docker compose down

# ==========================================
# Production
# ==========================================

prod:
	docker compose -f docker-compose.prod.yml up -d

health:
	@curl -sf http://localhost:8080/health && echo " OK" || echo " FAIL"

logs:
	docker compose logs -f

logs-api:
	docker compose logs -f api

restart:
	docker compose restart

# ==========================================
# Database
# ==========================================

migrate:
	docker compose exec api /app/server migrate up

migrate-down:
	docker compose exec api /app/server migrate down

db-shell:
	docker compose exec postgres psql -U trello_agent -d trello_agent

redis-cli:
	docker compose exec redis redis-cli -a redis_secret

# ==========================================
# Docker
# ==========================================

VERSION ?= latest
REGISTRY ?= ghcr.io/your-org

build-api:
	cd ../Trello_Backend && docker build -t trello-agent-api:$(VERSION) .

docker-push:
	docker tag trello-agent-api:$(VERSION) $(REGISTRY)/trello-agent-api:$(VERSION)
	docker push $(REGISTRY)/trello-agent-api:$(VERSION)

# ==========================================
# Cleanup
# ==========================================

clean:
	docker compose down -v --remove-orphans

clean-all: clean
	docker system prune -af
	docker volume prune -f
