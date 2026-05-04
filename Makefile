.PHONY: \
	help init init-env env-dev env-prod env-check \
	up down logs ps \
	migrate-db preprocess vlm-predictions enrich-addresses all-preprocessing \
	export-db import-db verify-db-load prod-migrate-import \
	bootstrap bootstrap-full reset

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
	@echo "  make verify-db-load    - verify required DB tables/data exist after import/load"
	@echo "  make prod-migrate-import - run migrate-db + import-db against DATABASE_URL in .env.prod"
	@echo "  make up                - start postgis + backend + frontend"
	@echo "  make down              - stop stack"
	@echo "  make logs              - tail logs"
	@echo "  make bootstrap         - first-time bootstrap using import-db snapshot"
	@echo "  make bootstrap-full    - full from-scratch preprocessing (includes VLM + enrich)"
	@echo "  make reset             - reset running setup (fresh DB + full preprocessing)"

init-env:
	@if [ ! -f .env ]; then cp .env.example .env; echo "Created .env from .env.example"; fi
	@if [ ! -f .env.prod ]; then cp .env.prod.example .env.prod; echo "Created .env.prod from .env.prod.example"; fi

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

preprocess:
	$(COMPOSE) exec -T backend test -f $(PARSED_JSON)
	$(COMPOSE) exec -T backend sh -lc "PYTHONPATH=/app python util/preprocess-data.py --start-at load --stop-after load --input $(PARSED_JSON)"
	@echo "Preprocess load complete."

migrate-db: preprocess
	$(COMPOSE) exec -T backend python -m util.migrate
	@echo "Migrations applied."

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

verify-db-load:
	$(COMPOSE) exec -T postgis psql -U utd -d utd_data -v ON_ERROR_STOP=1 -c \
	"SELECT to_regclass('public.disasters') AS disasters, to_regclass('public.image_pairs') AS image_pairs, to_regclass('public.locations') AS locations;"
	$(COMPOSE) exec -T postgis psql -U utd -d utd_data -v ON_ERROR_STOP=1 -c \
	"SELECT (SELECT count(*) FROM disasters) AS disasters, (SELECT count(*) FROM image_pairs) AS image_pairs, (SELECT count(*) FROM locations) AS locations;"
	@counts=$$($(COMPOSE) exec -T postgis psql -U utd -d utd_data -t -A -F, -c "SELECT (SELECT count(*) FROM image_pairs), (SELECT count(*) FROM locations);"); \
	ip_count=$$(echo $$counts | cut -d, -f1 | tr -d '[:space:]'); \
	loc_count=$$(echo $$counts | cut -d, -f2 | tr -d '[:space:]'); \
	if [ "$$ip_count" = "0" ] || [ "$$loc_count" = "0" ]; then \
		echo "DB verification failed: image_pairs=$$ip_count locations=$$loc_count after import/load"; \
		exit 1; \
	fi
	@echo "DB verification passed."

prod-migrate-import:
	@if [ ! -f ".env.prod" ]; then \
		echo "Missing .env.prod. Run 'make init-env' and fill .env.prod first."; \
		exit 1; \
	fi
	@if [ ! -f "$(SNAPSHOT_HOST)" ]; then \
		echo "Snapshot not found: $(SNAPSHOT_HOST). Run 'make export-db' first."; \
		exit 1; \
	fi
	@prod_db_url=$$(awk -F= '/^DATABASE_URL=/{sub(/^DATABASE_URL=/,""); print; exit}' .env.prod); \
	if [ -z "$$prod_db_url" ]; then \
		echo "DATABASE_URL is missing in .env.prod"; \
		exit 1; \
	fi; \
	if ! $(COMPOSE) ps backend --status running >/dev/null 2>&1; then \
		echo "Backend container is not running. Start it first with 'make up'."; \
		exit 1; \
	fi; \
	docker cp $(SNAPSHOT_HOST) utd-backend:$(SNAPSHOT_CONTAINER); \
	$(COMPOSE) exec -T -e DATABASE_URL="$$prod_db_url" backend python -m util.migrate; \
	$(COMPOSE) exec -T -e DATABASE_URL="$$prod_db_url" backend sh -lc "PYTHONPATH=/app python /app/util/import_db_snapshot.py --input $(SNAPSHOT_CONTAINER)"; \
	echo "Prod migrate+import complete using DATABASE_URL from .env.prod"

bootstrap:
	@if [ ! -f "$(SNAPSHOT_HOST)" ]; then \
		echo "Bootstrap requires snapshot $(SNAPSHOT_HOST) but it was not found."; \
		echo "Run 'make export-db' from a source environment first, then retry."; \
		exit 1; \
	fi
	$(MAKE) up
	$(MAKE) migrate-db
	$(MAKE) import-db
	$(MAKE) verify-db-load
	@echo "Bootstrap (import mode) complete."

bootstrap-full: up all-preprocessing
	@echo "Bootstrap (full preprocessing) complete."

reset:
	$(COMPOSE) down -v --remove-orphans
	$(MAKE) up
	$(MAKE) all-preprocessing
	@echo "Reset complete."
