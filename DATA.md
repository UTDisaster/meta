# Data Pipeline

How the Hurricane Florence dataset was prepared for the UTDisaster backend.

## Source archives (from xview2.org)

| Archive | Size | SHA1 | Contents |
|---------|------|------|----------|
| xview2_geotiff.tgz (6 parts aa-af) | 51 GB | `6eae3baddf86796c15638682a6432e3e6223cb39` | GeoTIFF images + labels for hold/test/tier1 (no targets, no tier3) |
| train_images_labels_targets.tar | 7.8 GB | `b37a4ef4ee9c909e2b19d046e49d42ee3965714b` | Challenge tier1: images + labels + targets (PNG native) |
| test_images_labels_targets.tar | 2.6 GB | `86ed3dba2f8d16ceceb75d451005054fefa9616f` | Challenge test: images + labels + targets (PNG native) |
| hold_images_labels_targets.tar | 2.6 GB | `fe7f162f0895bfaff134cab3abc23872f38d17da` | Challenge hold: images + labels + targets (PNG native) |
| tier3.tar | 17.3 GB | `5bf6aaf8a71980b633fb4661776a99a200891de5` | Additional disasters (no florence data) |
| xview_geotransforms.json.tgz | 500 KB | `0b3bda08084ac102d8b540261ebbba0094203a2f` | Per-image geospatial metadata |

## Key findings during processing

1. **The geotiff archive ships int16 TIF files** but labels reference `.png` filenames. Conversion via tifffile + Pillow (clip 0-255, save uint8 PNG) was needed for geotiff route. Challenge archives ship native PNG -- no conversion needed.

2. **Tier3 contains zero florence data.** Its disasters: joplin-tornado, lower-puna-volcano, moore-tornado, nepal-flooding, etc. All florence data lives in hold + test + tier1.

3. **The geotiff archive has no targets.** Damage mask PNGs only exist in the Challenge variants.

4. **26 of 546 pairs (4.8%) lack enough control points** for affine bound computation. These pairs get NULL pre_bounds/post_bounds in PostGIS. The frontend handles this gracefully (skips overlay for those tiles).

## Reproduction steps

```bash
# 1. Download challenge sets + geotransforms from xview2.org

# 2. Extract florence-only files
for archive in train_images_labels_targets.tar test_images_labels_targets.tar hold_images_labels_targets.tar; do
  tar --force-local -xzf "$archive" \
    --wildcards --wildcards-match-slash --strip-components=1 \
    -C florence_complete/ \
    '*/hurricane-florence_*'
done

tar --force-local -xzf xview_geotransforms.json.tgz -C geotransforms/

# 3. Parse (requires Python venv with backend deps)
cd backend
python util/preprocess-data.py ../florence_complete \
  --output data-example \
  --start-at parse --stop-after parse \
  --disaster-id hurricane-florence

# 4. Validate
python ../meta/scripts/validate_florence.py data-example

# 5. Load into PostGIS (requires running database)
export DATABASE_URL='postgresql+psycopg://utd:utdpass@localhost:5432/utd_data'
python util/preprocess-data.py --start-at load --stop-after load
```

## Verification

Release tarball SHA256: `73e08cd2c5a43d50965c2dd990820b60a814366a72f2ccacf178d7223682ad97`
