#!/usr/bin/env bash
#
# Reproducible Hurricane Florence extraction pipeline.
#
# Takes the 6-part xview2_geotiff archive AND the 5 supplementary
# archives (tier3, challenge train/test/holdout, geotransforms),
# extracts only hurricane-florence files, and produces a unified
# florence_complete/ directory ready for backend/util/preprocess-data.py.
#
# Prerequisites:
#   - All source archives in $SRC_DIR (default: ./_downloads)
#   - tar, sha1sum, python3 with Pillow + tifffile + numpy
#
# Usage:
#   ./extract_florence.sh [SRC_DIR] [OUT_DIR]
#
set -euo pipefail

SRC_DIR="${1:-./_downloads}"
OUT_DIR="${2:-./florence_complete}"

mkdir -p "$OUT_DIR"/{images,labels,targets}

echo "==> Source: $SRC_DIR"
echo "==> Output: $OUT_DIR"

# 1. Recombine geotiff parts if needed
if [ ! -f "$SRC_DIR/xview2_geotiff.tgz" ]; then
    echo "==> Recombining xview2_geotiff parts..."
    cat "$SRC_DIR"/xview2_geotiff.tgz.part-a{a,b,c,d,e,f} > "$SRC_DIR/xview2_geotiff.tgz"
fi

STAGING="$(mktemp -d)"
trap "rm -rf '$STAGING'" EXIT

# 2. Extract florence-only from geotiff archive (images + labels, no targets)
echo "==> Extracting florence from xview2_geotiff.tgz..."
mkdir -p "$STAGING/geotiff"
tar -xzf "$SRC_DIR/xview2_geotiff.tgz" \
    --wildcards --wildcards-match-slash \
    -C "$STAGING/geotiff" \
    '*/hurricane-florence_*' || true

# Move images and labels into the unified output
find "$STAGING/geotiff" -type f -name 'hurricane-florence_*' \
    -path '*/images/*' -exec mv {} "$OUT_DIR/images/" \;
find "$STAGING/geotiff" -type f -name 'hurricane-florence_*' \
    -path '*/labels/*' -exec mv {} "$OUT_DIR/labels/" \;

# 3. Extract florence from tier3 archive (images + labels + targets)
if [ -f "$SRC_DIR/tier3_train_images_labels_targets.tar.gz" ] || ls "$SRC_DIR"/tier3* 2>/dev/null; then
    TIER3=$(ls "$SRC_DIR"/tier3* 2>/dev/null | head -1)
    if [ -n "${TIER3:-}" ]; then
        echo "==> Extracting florence from $TIER3..."
        mkdir -p "$STAGING/tier3"
        tar -xzf "$TIER3" \
            --wildcards --wildcards-match-slash \
            -C "$STAGING/tier3" \
            '*hurricane-florence_*' || true
        find "$STAGING/tier3" -type f -name 'hurricane-florence_*' \
            -path '*/images/*' -exec mv {} "$OUT_DIR/images/" \;
        find "$STAGING/tier3" -type f -name 'hurricane-florence_*' \
            -path '*/labels/*' -exec mv {} "$OUT_DIR/labels/" \;
        find "$STAGING/tier3" -type f -name 'hurricane-florence_*' \
            -path '*/targets/*' -exec mv {} "$OUT_DIR/targets/" \;
    fi
fi

# 4. Extract targets-only from challenge train/test/hold archives
for archive in train_images_labels_targets.tar.gz \
               test_images_labels_targets.tar.gz \
               hold_images_labels_targets.tar.gz; do
    full="$SRC_DIR/$archive"
    [ -f "$full" ] || continue
    echo "==> Extracting florence targets from $archive..."
    mkdir -p "$STAGING/$archive"
    tar -xzf "$full" \
        --wildcards --wildcards-match-slash \
        -C "$STAGING/$archive" \
        '*targets/hurricane-florence_*' || true
    find "$STAGING/$archive" -type f -name 'hurricane-florence_*' \
        -path '*/targets/*' -exec mv {} "$OUT_DIR/targets/" \;
done

# 5. Convert any TIFs to PNGs (the geotiff archive ships int16 TIFs even
#    though label JSONs reference .png filenames)
TIF_COUNT=$(find "$OUT_DIR/images" -name '*.tif' | wc -l)
if [ "$TIF_COUNT" -gt 0 ]; then
    echo "==> Converting $TIF_COUNT TIFs to PNGs..."
    python3 "$(dirname "$0")/convert_tif_to_png.py" --src-dir "$OUT_DIR/images"
fi

# 6. Report
echo
echo "==> Summary"
echo "  images:  $(find "$OUT_DIR/images" -type f | wc -l)"
echo "  labels:  $(find "$OUT_DIR/labels" -type f | wc -l)"
echo "  targets: $(find "$OUT_DIR/targets" -type f | wc -l)"
echo "  total:   $(du -sh "$OUT_DIR" | cut -f1)"

echo
echo "==> Done. Next step:"
echo "  cd <backend>"
echo "  python util/preprocess-data.py $OUT_DIR --output data-example \\"
echo "         --start-at parse --stop-after parse \\"
echo "         --disaster-id hurricane-florence"
