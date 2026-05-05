.PHONY: help dev up down logs logs-api restart migrate migrate-down db-shell redis-cli docker-build docker-push docker-prod clean clean-all

help:
	@echo "Trello Infra - Available commands:"
	@echo ""
	@echo "  Development:"
	@echo "    make dev          - Start development environment"
	@echo "    make up           - Start all services in background"
	@echo "    make down         - Stop all services"
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
	@echo "    make docker-build IMAGE=<tag> - Build API image from Backend repo"
	@echo "    make docker-push              - Push to registry"
	@echo "    make docker-prod              - Start production stack"
	@echo ""
	@echo "  NOTE: Build API image first:"
	@echo "    cd ../Trello_Backend && docker build -t trello-agent-api:local ."
	@echo ""

# ==========================================
# Development
# ==========================================

dev:
	docker compose up

up:
	docker compose up -d

down:
	docker compose down

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

docker-build:
	@echo "Build image from Trello_Backend repo:"
	@echo "  cd ../Trello_Backend && docker build -t trello-agent-api:$(VERSION) ."

docker-push:
	docker tag trello-agent-api:$(VERSION) $(REGISTRY)/trello-agent-api:$(VERSION)
	docker push $(REGISTRY)/trello-agent-api:$(VERSION)

docker-prod:
	docker compose -f docker-compose.prod.yml up -d

# ==========================================
# Cleanup
# ==========================================

clean:
	docker compose down -v --remove-orphans

clean-all: clean
	docker system prune -af
	docker volume prune -f
