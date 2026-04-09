#!/usr/bin/env python3
"""
Validate the parsed Hurricane Florence dataset against what the
UTDisaster frontend and backend actually consume.

Usage:
    python validate_florence.py [path/to/data-example]

Exit codes:
    0  all checks passed
    1  one or more assertions failed
"""
from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

ALLOWED_CLASSIFICATIONS = {"none", "minor", "severe", "destroyed", "unknown"}
FLORENCE_LAT_RANGE = (33.0, 35.5)
FLORENCE_LNG_RANGE = (-80.0, -77.5)


def fail(msg: str) -> None:
    print(f"  FAIL: {msg}")


def section(title: str) -> None:
    print(f"\n=== {title} ===")


def main(argv: list[str]) -> int:
    data_dir = Path(argv[1] if len(argv) > 1 else "data-example").resolve()
    parsed_path = data_dir / "parsed_data.json"
    images_root = data_dir / "images"

    print(f"Validating: {data_dir}")
    print(f"  parsed_data.json: {parsed_path}")
    print(f"  images root:      {images_root}")

    if not parsed_path.is_file():
        fail(f"parsed_data.json missing at {parsed_path}")
        return 1

    parsed = json.loads(parsed_path.read_text(encoding="utf-8"))
    failures = 0

    section("1. Top-level structure")
    if "hurricane-florence" not in parsed:
        fail("'hurricane-florence' key missing from parsed_data.json")
        return 1
    print("  OK: hurricane-florence key present")

    florence = parsed["hurricane-florence"]
    for required in ("disasterId", "type", "images"):
        if required not in florence:
            fail(f"'{required}' missing from florence payload")
            failures += 1
    if not failures:
        print(f"  OK: disasterId={florence['disasterId']}, type={florence['type']}")

    images = florence.get("images", [])
    pair_count = len(images)
    print(f"  pair count: {pair_count}")

    section("2. Image files exist on disk (referenced from parsed_data.json)")
    missing_images: list[str] = []
    for image in images:
        for phase in ("pre", "post"):
            relpath = image.get("path", {}).get(phase, "")
            if not relpath:
                missing_images.append(f"{image.get('uid', '?')}.{phase}: empty path")
                continue
            full = data_dir / relpath
            if not full.is_file():
                missing_images.append(f"{image.get('uid', '?')}.{phase}: {full}")

    if missing_images:
        fail(f"{len(missing_images)} referenced images missing on disk")
        for m in missing_images[:10]:
            print(f"    - {m}")
        if len(missing_images) > 10:
            print(f"    ... and {len(missing_images) - 10} more")
        failures += 1
    else:
        print(f"  OK: all {pair_count * 2} image files exist")

    section("3. Image dimensions consistent (all 1024x1024 RGB)")
    bad_dims: list[str] = []
    for image in images[:50]:
        for phase in ("pre", "post"):
            size = image.get("size", {}).get(phase, {})
            w, h = size.get("width"), size.get("height")
            if w != 1024 or h != 1024:
                bad_dims.append(f"{image.get('uid')}.{phase}: {w}x{h}")
    if bad_dims:
        fail(f"non-1024x1024 images: {len(bad_dims)} (showing 5)")
        for b in bad_dims[:5]:
            print(f"    - {b}")
        failures += 1
    else:
        print(f"  OK: first 50 pairs all report 1024x1024")

    section("4. Classification values within allowed set")
    classifications = Counter()
    bad_class = []
    for image in images:
        for loc in image.get("locations", []):
            c = loc.get("classification", "unknown")
            classifications[c] += 1
            if c not in ALLOWED_CLASSIFICATIONS:
                bad_class.append(f"{image.get('uid')}/{loc.get('uid', '?')}: {c}")
    if bad_class:
        fail(f"out-of-set classifications: {len(bad_class)}")
        for b in bad_class[:5]:
            print(f"    - {b}")
        failures += 1
    else:
        print(f"  OK: all classifications in {sorted(ALLOWED_CLASSIFICATIONS)}")
    print(f"  distribution:")
    for cls, n in classifications.most_common():
        print(f"    {cls:>12}: {n}")

    section("5. Locations have valid points for WKT polygon construction")
    locs_total = 0
    locs_polygon_ok = 0
    for image in images:
        for loc in image.get("locations", []):
            locs_total += 1
            post_pts = loc.get("points", {}).get("post", [])
            valid = [
                p for p in post_pts
                if isinstance(p.get("long"), (int, float))
                and isinstance(p.get("lat"), (int, float))
            ]
            if len(valid) >= 3:
                locs_polygon_ok += 1
    print(f"  total locations: {locs_total}")
    print(f"  with >=3 valid points (load_step builds WKT): {locs_polygon_ok}")
    if locs_polygon_ok == 0:
        fail("zero locations have valid polygon points")
        failures += 1
    else:
        ratio = locs_polygon_ok / locs_total * 100
        print(f"  OK: {ratio:.1f}% of locations will produce valid polygons")

    section("6. Affine control points (for image bounds)")
    pairs_with_affine = 0
    for image in images:
        good_points = 0
        for loc in image.get("locations", []):
            for p in loc.get("points", {}).get("post", []):
                if all(
                    isinstance(p.get(k), (int, float))
                    for k in ("x", "y", "lat", "long")
                ):
                    good_points += 1
                    if good_points >= 3:
                        break
            if good_points >= 3:
                break
        if good_points >= 3:
            pairs_with_affine += 1
    print(f"  pairs with >=3 affine control points: {pairs_with_affine}/{pair_count}")
    if pairs_with_affine < pair_count:
        fail(f"{pair_count - pairs_with_affine} pairs missing affine controls (load_step bounds will be NULL)")
        failures += 1
    else:
        print(f"  OK: all pairs can compute pre/post bounds")

    section("7. Geographic bounding box (must overlap NC coast)")
    all_lats = []
    all_lngs = []
    for image in images:
        for loc in image.get("locations", []):
            for p in loc.get("points", {}).get("post", []):
                if isinstance(p.get("lat"), (int, float)):
                    all_lats.append(p["lat"])
                if isinstance(p.get("long"), (int, float)):
                    all_lngs.append(p["long"])
    if not all_lats:
        fail("no valid coordinates in any location")
        failures += 1
    else:
        min_lat, max_lat = min(all_lats), max(all_lats)
        min_lng, max_lng = min(all_lngs), max(all_lngs)
        print(f"  lat range: [{min_lat:.4f}, {max_lat:.4f}]  expected ~ {FLORENCE_LAT_RANGE}")
        print(f"  lng range: [{min_lng:.4f}, {max_lng:.4f}]  expected ~ {FLORENCE_LNG_RANGE}")
        if not (FLORENCE_LAT_RANGE[0] <= min_lat <= FLORENCE_LAT_RANGE[1]
                and FLORENCE_LAT_RANGE[0] <= max_lat <= FLORENCE_LAT_RANGE[1]):
            fail("latitude range outside expected NC coast")
            failures += 1
        if not (FLORENCE_LNG_RANGE[0] <= min_lng <= FLORENCE_LNG_RANGE[1]
                and FLORENCE_LNG_RANGE[0] <= max_lng <= FLORENCE_LNG_RANGE[1]):
            fail("longitude range outside expected NC coast")
            failures += 1
        if not failures:
            print(f"  OK: coordinates land on NC coast")

    section("8. Targets directory coverage (informational, not blocking)")
    targets_dir = data_dir.parent / "florence_complete" / "targets"
    if not targets_dir.is_dir():
        targets_dir = data_dir / "targets"
    if targets_dir.is_dir():
        target_files = list(targets_dir.glob("hurricane-florence_*"))
        print(f"  targets/ contains {len(target_files)} florence files")
        expected = pair_count * 2
        if len(target_files) >= expected:
            print(f"  OK: >= {expected} expected (1 per pre/post)")
        else:
            print(f"  INFO: < {expected} expected (some pairs missing target masks)")
    else:
        print(f"  INFO: no targets/ directory found at {targets_dir} (not blocking)")

    section("Result")
    if failures:
        print(f"  {failures} CHECK(S) FAILED")
        return 1
    print("  ALL CHECKS PASSED")
    print(f"  pairs:        {pair_count}")
    print(f"  locations:    {locs_total}")
    print(f"  polygons:     {locs_polygon_ok}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
