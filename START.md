# General Project Information

## Initial Steps

Clone the three repositories into some common folder:

```sh
mkdir utd-cs-project
cd utd-cs-project

git clone git@github.com:UTDisaster/frontend.git
git clone git@github.com:UTDisaster/backend.git
git clone git@github.com:UTDisaster/meta.git
```

Pull the full dataset from GitHub release (or download manually) and extract it:

```sh
gh release download florence-complete-v1 --repo UTDisaster/meta --pattern '*.tar.gz'
tar -xzf florence-hurricane-complete.tar.gz
```

This may take a few minutes.

## Project Workflow (meta/Makefile)

All project orchestration is now centralized in `meta/Makefile`.

From `meta/`:

```sh
cd meta
make help
```

Current primary targets:

- `make init` - basic initialization checks
- `make init-env` - create `.env` and `.env.prod` from examples if missing
- `make up` / `make down` - start/stop PostGIS + backend + frontend
- `make logs` - tail logs
- `make migrate-db` - apply backend SQL migrations
- `make preprocess` - load `parsed_data.json` into DB
- `make vlm-predictions` - run VLM predictions and store assessments
- `make enrich-addresses` - fill address fields (map-first, Census fallback)
- `make all-preprocessing` - run preprocess + VLM + enrich
- `make export-db` - export DB snapshot JSON to `meta/artifacts/db_snapshot.json`
- `make import-db` - import `meta/artifacts/db_snapshot.json` safely
- `make bootstrap` - startup path using import snapshot
- `make bootstrap-full` - full from-scratch data processing path
- `make prod-migrate-import` - run migrate+import against `DATABASE_URL` in `.env.prod`
- `make reset` - destroy local volumes, start fresh, then run full preprocessing

## Standard Local Flows

### 1) First-time setup using snapshot import (recommended)

```sh
cd meta
make init-env
# fill .env values (and .env.prod if needed)
make up
make bootstrap
```

`bootstrap` runs:
- `up`
- `migrate-db`
- `import-db`

In order for boostrap to work, you will have to have the `artifacts/db_snapshot.json` file in meta root.

### 2) Full from-scratch pipeline

Alternatively to re-fetch the VLM classifications and run address enrichment from API. Unless the data in the db snapshot are outdated, you shouldn't need to do this step.

```sh
cd meta
make up
make bootstrap-full
```

`bootstrap-full` runs:
- `up`
- `all-preprocessing` (`preprocess`, `vlm-predictions`, `enrich-addresses`)

### 3) Subsequent runs

```sh
cd meta
make up
```

## Data Snapshot Workflow

### Export DB snapshot

```sh
cd meta
make export-db
```

Writes:
- `meta/artifacts/db_snapshot.json`

### Import DB snapshot safely

```sh
cd meta
make import-db
```

`import-db` is transactional inside the import script. If import fails, DB changes are rolled back.

## Production/Remote DB Migrate + Import

To apply migrations and import snapshot against remote/prod DB:

1. Ensure `meta/.env.prod` exists and has valid `DATABASE_URL`.
2. Ensure backend container is running (`make up`).
3. Ensure snapshot exists (`make export-db` first, if needed).

Then run:

```sh
cd meta
make prod-migrate-import
```

This target uses `DATABASE_URL` from `.env.prod` directly and does not overwrite `.env`.

## Environment Notes

- Default dataset location expected by Makefile:
  - `../florence-hurricane-complete/data-example`
- Override dataset path for commands with:

```sh
HOST_DATA_EXAMPLE_DIR=/absolute/path/to/florence-hurricane-complete/data-example make <target>
```

- Address enrichment behavior:
  - If `address_map.json` exists in data folder, enrichment uses it first.
  - Misses fall back to Census geocoder unless map-only mode is used in direct script invocation.
