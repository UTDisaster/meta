# UTDisaster Meta

Cross-cutting documentation, data pipeline, and reference data for the UTDisaster project.

See [START.md](START.md) for a detailed guide on getting started and running the project.

## Repositories

| Repo | Stack | Purpose |
|------|-------|---------|
| [frontend](https://github.com/UTDisaster/frontend) | React + Vite + Leaflet + TypeScript | Interactive disaster dashboard |
| [backend](https://github.com/UTDisaster/backend) | FastAPI + SQLAlchemy + PostGIS | API + data pipeline |
| [meta](https://github.com/UTDisaster/meta) | This repo | Data, docs, scripts |

## Hurricane Florence Dataset

The complete xBD Hurricane Florence dataset (546 image pairs, 11,548 building locations) is available as a release asset.

### Quick start

```bash
# Download the dataset (~1.43 GiB)
gh release download florence-complete-v1 --repo UTDisaster/meta --pattern '*.tar.gz'

# Extract
tar -xzf florence-hurricane-complete.tar.gz

# Point the backend at the parsed data
cd /path/to/backend
export PARSED_DATA_DIR=/path/to/florence-hurricane-complete/data-example

# Load into PostGIS (requires running database)
.venv/Scripts/python.exe util/preprocess-data.py --start-at load --stop-after load

# Start the API
uvicorn app.main:app --reload
```

### What's inside

```
florence-hurricane-complete/
  data-example/                      (what PARSED_DATA_DIR points to)
    parsed_data.json                 46 MB - building polygons + damage classes
    images/hurricane-florence/       1092 PNGs (546 pre/post pairs, 1.5 GB)
  targets/                           1092 damage mask PNGs (7 MB)
  labels/                            1092 raw xBD label JSONs (24 MB)
  geotransforms/
    xview_geotransforms.json         8 MB - per-image origin/projection metadata
```

### Dataset coverage

- **546 image pairs** across 3 xBD subsets: hold (119), test (108), tier1 (319)
- **11,548 building locations** with damage classifications: none (8466), severe (1949), unknown (820), minor (232), destroyed (81)
- All images are 1024x1024 RGB PNG
- Geographic extent: North Carolina coast (lat 33.58-34.89, lng -79.06 to -77.84)
- Disaster type: flooding (Hurricane Florence, September 2018)
- Tier3 was checked and contains no Hurricane Florence data

See [DATA.md](DATA.md) for the full pipeline runbook and [MANIFEST.json](MANIFEST.json) for machine-readable metadata.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Data License

Original imagery: xBD / xview2 dataset. See https://xview2.org for terms.
