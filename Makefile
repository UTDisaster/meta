.PHONY: \
	help init init-env env-dev env-prod env-check \
	up down logs ps \
	migrate-db preprocess vlm-predictions enrich-addresses all-preprocessing \
	export-db import-db \
	bootstrap reset

COMPOSE := docker compose -f docker-compose.yml
DATASET_DEFAULT := ../florence-hurricane-complete/data-example
PARSED_JSON := /app/data-example/parsed_data.json
SNAPSHOT_HOST := ./artifacts/db_snapshot.json
SNAPSHOT_CONTAINER := /tmp/db_snapshot.json

help:
	@echo "Targets:"
	@echo "  make help              - display this menu"
	@echo "  make init              - basic initialization checks"
	@echo "  make init-env          - create .env and .env.prod from examples (if missing)"
	@echo "  make preprocess        - load parsed_data.json into DB (base preprocessing)"
	@echo "  make vlm-predictions   - run VLM predictions into chat.vlm_assessments"
	@echo "  make enrich-addresses  - enrich addresses in locations table"
	@echo "  make all-preprocessing - run preprocess + vlm-predictions + enrich-addresses"
	@echo "  make export-db         - export DB snapshot JSON to $(SNAPSHOT_HOST)"
	@echo "  make import-db         - import snapshot JSON from $(SNAPSHOT_HOST) safely"
	@echo "  make up                - start postgis + backend + frontend"
	@echo "  make down              - stop stack"
	@echo "  make logs              - tail logs"
	@echo "  make bootstrap         - first-time machine setup flow"
	@echo "  make reset             - reset running setup (fresh DB + full preprocessing)"

init-env:
	@if [ ! -f .env ]; then cp .env.example .env; echo "Created .env from .env.example"; fi
	@if [ ! -f .env.prod ]; then cp .env.prod.example .env.prod; echo "Created .env.prod from .env.prod.example"; fi

env-dev:
	cp .env.example .env
	@echo "Active env set to dev via .env.example"

env-prod:
	cp .env.prod.example .env.prod
	cp .env.prod .env
	@echo "Active env set to prod via .env.prod"

env-check:
	@$(MAKE) init-env
	@if [ ! -d "$${HOST_DATA_EXAMPLE_DIR:-$(DATASET_DEFAULT)}" ]; then \
		echo "Dataset directory missing: $${HOST_DATA_EXAMPLE_DIR:-$(DATASET_DEFAULT)}"; \
		echo "Expected parsed_data.json at: $${HOST_DATA_EXAMPLE_DIR:-$(DATASET_DEFAULT)}/parsed_data.json"; \
		exit 1; \
	fi
	@if [ ! -f "$${HOST_DATA_EXAMPLE_DIR:-$(DATASET_DEFAULT)}/parsed_data.json" ]; then \
		echo "Missing parsed_data.json at: $${HOST_DATA_EXAMPLE_DIR:-$(DATASET_DEFAULT)}/parsed_data.json"; \
		exit 1; \
	fi
	@if [ ! -d "$${HOST_DATA_EXAMPLE_DIR:-$(DATASET_DEFAULT)}/images/hurricane-florence" ]; then \
		echo "Images directory missing: $${HOST_DATA_EXAMPLE_DIR:-$(DATASET_DEFAULT)}/images/hurricane-florence"; \
		exit 1; \
	fi
	@mkdir -p artifacts

init: env-check
	@echo "Initialization checks complete."

up: init
	$(COMPOSE) up -d --build postgis backend frontend
	$(COMPOSE) ps

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=200

ps:
	$(COMPOSE) ps

migrate-db:
	$(COMPOSE) exec -T backend python -m util.migrate
	@echo "Migrations applied."

preprocess: migrate-db
	$(COMPOSE) exec -T backend test -f $(PARSED_JSON)
	$(COMPOSE) exec -T backend sh -lc "PYTHONPATH=/app python util/preprocess-data.py --start-at load --stop-after load --input $(PARSED_JSON)"
	@echo "Preprocess load complete."

vlm-predictions:
	$(COMPOSE) exec -T backend sh -lc "PYTHONPATH=/app python util/preprocess-data.py --start-at vlm --stop-after vlm"
	@echo "VLM predictions complete."

enrich-addresses:
	@echo "Enriching addresses in batches..."
	@while true; do \
		remaining=$$($(COMPOSE) exec -T postgis psql -U utd -d utd_data -t -A -c "SELECT COUNT(*) FROM locations WHERE address_fetched_at IS NULL;"); \
		remaining=$$(echo $$remaining | tr -d '[:space:]'); \
		if [ -z "$$remaining" ] || [ "$$remaining" = "0" ]; then \
			echo "Address enrichment complete."; \
			break; \
		fi; \
		echo "Remaining rows with null address_fetched_at: $$remaining"; \
		$(COMPOSE) exec -T backend sh -lc "PYTHONPATH=/app python -m util.enrich_addresses --limit 1000"; \
	done

all-preprocessing: preprocess vlm-predictions enrich-addresses
	@echo "All preprocessing steps complete."

export-db:
	$(COMPOSE) exec -T backend sh -lc "PYTHONPATH=/app python /app/util/export_db_snapshot.py --output $(SNAPSHOT_CONTAINER) --pretty"
	docker cp utd-backend:$(SNAPSHOT_CONTAINER) $(SNAPSHOT_HOST)
	@echo "Snapshot exported to $(SNAPSHOT_HOST)"

import-db:
	@if [ ! -f "$(SNAPSHOT_HOST)" ]; then \
		echo "Snapshot not found: $(SNAPSHOT_HOST). Run 'make export-db' first."; \
		exit 1; \
	fi
	docker cp $(SNAPSHOT_HOST) utd-backend:$(SNAPSHOT_CONTAINER)
	$(COMPOSE) exec -T backend sh -lc "PYTHONPATH=/app python /app/util/import_db_snapshot.py --input $(SNAPSHOT_CONTAINER)"
	@echo "Seed complete from $(SNAPSHOT_HOST)"

bootstrap: up all-preprocessing
	@echo "Bootstrap complete."

reset:
	$(COMPOSE) down -v --remove-orphans
	$(MAKE) up
	$(MAKE) all-preprocessing
	@echo "Reset complete."
