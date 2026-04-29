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

Pull the full dataset from GitHub release (or download the archive manually) and extract it:

```sh
gh release download florence-complete-v1 --repo UTDisaster/meta --pattern '*.tar.gz'
tar -xzf florence-hurricane-complete.tar.gz
```

This will likely take a few minutes.

## Quick Start

To just start everything automatically altogether:
```sh
cd meta
make bootstrap
```

This command will:
- start PostGIS + backend + frontend containers
- validate dataset path (`../florence-hurricane-complete/data-example` by default)
- load `parsed_data.json` into PostGIS
- mount full `data-example` into backend and serve images from `/assets/images/hurricane-florence/<filename>.png`

If your dataset is in a different location, set:
```sh
HOST_DATA_EXAMPLE_DIR=/absolute/path/to/florence-hurricane-complete/data-example make bootstrap
```

You can ignore the reset of the steps in this section for most cases. They are for starting and running the individual services.

## Manual Steps

### Database and Backend

cd to the backend directory.

Copy `.env.example` to `.env` and add your api keys for testing. 

```sh
cp .env.example .env
cp .env.prod.example .env.prod
```

Do the same with `.env.prod` (second line) if you want to test against production environment (not always necessary). When testing with prod you can just change the `APP_ENV` variable to `prod` from dev and it will load that file instead.

Start the database (clean):

```sh
docker compose down -v --remove-orphans
docker compose up -d db
until docker compose exec -T db pg_isready -U utd -d utd_data >/dev/null 2>&1; do
  echo "waiting for db..."
  sleep 2
done
echo "db ready"
```

Install the dependencies needed for preprocessing/vlm:

```bash
uv venv
source .venv/bin/activate
uv pip install -r requirements.txt
```

Then load dataset into the DB:

```sh
DATABASE_URL=postgresql+psycopg://utd:utdpass@127.0.0.1:5433/utd_data \
.venv/bin/python util/preprocess-data.py \
  --start-at load \
  --stop-after load \
  --input ../florence-hurricane-complete/data-example/parsed_data.json
```

Load additional chat schema:

```sh
docker exec -i "$(docker compose ps -q db)" psql -U utd -d utd_data < ../meta/init-chat-schema.sql
```

Quick verification:

```sh
docker exec -i "$(docker compose ps -q db)" psql -U utd -d utd_data -c \
"select to_regclass('public.disasters'), to_regclass('public.image_pairs'), to_regclass('public.locations'), to_regclass('chat.vlm_assessments');"

docker exec -i "$(docker compose ps -q db)" psql -U utd -d utd_data -c \
"select (select count(*) from disasters) as disasters, (select count(*) from image_pairs) as image_pairs, (select count(*) from locations) as locations;"
```

If you see `(1 row)` printed twice, everything is good.

Start the backend api:

```sh
docker compose up -d --build --force-recreate api
docker compose logs -f api
```

Remember to shut it down after you are done testing or making changes:

```sh
docker compose down
```

### Frontend

cd to the frontend directory.

Install the dependencies:

```sh
npm i
```

Run the client:

```sh
npm run dev
```

## Batch VLM Predictions

soon
