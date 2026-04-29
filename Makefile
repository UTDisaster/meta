.PHONY: help init-env env-dev env-prod env-check up down reset logs bootstrap seed-db ps

COMPOSE := docker compose -f docker-compose.yml
DATASET_DEFAULT := ../florence-hurricane-complete/data-example
PARSED_JSON := /app/data-example/parsed_data.json

help:
	@echo "Targets:"
	@echo "  make init-env   - create .env and .env.prod from examples (if missing)"
	@echo "  make env-dev    - copy .env.example -> .env"
	@echo "  make env-prod   - copy .env.prod.example -> .env.prod and .env"
	@echo "  make up         - start postgis, backend, frontend"
	@echo "  make bootstrap  - start stack and load parsed_data.json into DB"
	@echo "  make seed-db    - load parsed_data.json into DB (backend must be up)"
	@echo "  make logs       - tail logs for all services"
	@echo "  make ps         - show service status"
	@echo "  make down       - stop stack"
	@echo "  make reset      - destroy DB volume and restart clean"

init-env:
	@if [ ! -f .env ]; then cp .env.example .env; echo "Created .env from .env.example"; fi
	@if [ ! -f .env.prod ]; then cp .env.prod.example .env.prod; echo "Created .env.prod from .env.prod.example"; fi

env-check:
	@$(MAKE) init-env
	@if [ ! -d "$${HOST_DATA_EXAMPLE_DIR:-$(DATASET_DEFAULT)}" ]; then \
		echo "Dataset directory missing: $${HOST_DATA_EXAMPLE_DIR:-$(DATASET_DEFAULT)}"; \
		echo "Expected parsed_data.json at: $${HOST_DATA_EXAMPLE_DIR:-$(DATASET_DEFAULT)}/parsed_data.json"; \
		exit 1; \
	fi
	@if [ ! -d "$${HOST_DATA_EXAMPLE_DIR:-$(DATASET_DEFAULT)}/images/hurricane-florence" ]; then \
		echo "Images directory missing: $${HOST_DATA_EXAMPLE_DIR:-$(DATASET_DEFAULT)}/images/hurricane-florence"; \
		exit 1; \
	fi

up: env-check
	$(COMPOSE) up -d --build postgis backend frontend
	$(COMPOSE) ps

seed-db:
	$(COMPOSE) exec -T backend test -f $(PARSED_JSON)
	$(COMPOSE) exec -T backend python util/preprocess-data.py --start-at load --stop-after load --input $(PARSED_JSON)
	@echo "Dataset loaded into PostGIS."

bootstrap: up
	$(MAKE) seed-db

logs:
	$(COMPOSE) logs -f --tail=200

ps:
	$(COMPOSE) ps

down:
	$(COMPOSE) down

reset:
	$(COMPOSE) down -v --remove-orphans
	$(COMPOSE) up -d --build postgis backend frontend
	$(MAKE) seed-db
