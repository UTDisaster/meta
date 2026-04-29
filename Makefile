.PHONY: help env-check up down reset logs bootstrap seed-db ps

COMPOSE := docker compose -f docker-compose.yml
DATASET_DEFAULT := ../florence-hurricane-complete/data-example
PARSED_JSON := /app/data-example/parsed_data.json

help:
	@echo "Targets:"
	@echo "  make up         - start postgis, backend, frontend"
	@echo "  make bootstrap  - start stack and load parsed_data.json into DB"
	@echo "  make seed-db    - load parsed_data.json into DB (backend must be up)"
	@echo "  make logs       - tail logs for all services"
	@echo "  make ps         - show service status"
	@echo "  make down       - stop stack"
	@echo "  make reset      - destroy DB volume and restart clean"

env-check:
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "Created meta/.env from template. Fill GEMINI_API_KEY."; \
	fi
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
