#!/bin/bash
set -euo pipefail

# Extract golf courses from Geofabrik OSM mirrors
# Downloads PBF, extracts golf features, outputs gzipped GeoJSON
# No GitHub access required - workflow handles uploads
#
# Usage: ./extract.sh [output_dir]
# Output: {output_dir}/{region}.geojson.gz files

OUTPUT_DIR="${1:-output}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"
mkdir -p "$OUTPUT_DIR"

mapfile -t regions < regions.txt
total=${#regions[@]}
current=0
success=0
failed=0
skipped=0

for region in "${regions[@]}"; do
  current=$((current + 1))
  echo ""
  echo "=========================================="
  echo "[$current/$total] Processing: $region"
  echo "=========================================="
  
  # Determine paths
  if [[ "$region" == "mexico" ]]; then
    url="https://download.geofabrik.de/north-america/mexico-latest.osm.pbf"
    output_name="north-america_mx_mexico"
  elif [[ "$region" == us/* ]]; then
    state_slug="${region#us/}"
    url="https://download.geofabrik.de/north-america/us/${state_slug}-latest.osm.pbf"
    output_name="north-america_us_${state_slug}"
  elif [[ "$region" == canada/* ]]; then
    prov_slug="${region#canada/}"
    url="https://download.geofabrik.de/north-america/canada/${prov_slug}-latest.osm.pbf"
    output_name="north-america_ca_${prov_slug}"
  fi
  
  # Skip if already done
  if [[ -f "$OUTPUT_DIR/${output_name}.geojson.gz" ]]; then
    echo "Already exists, skipping"
    skipped=$((skipped + 1))
    continue
  fi
  
  # Download
  echo "Downloading $url..."
  rm -f region.osm.pbf
  for i in 1 2 3; do
    curl -L --retry 3 --retry-delay 5 -o region.osm.pbf "$url" && break
    echo "Retry $i..."
    sleep $((i * 5))
  done
  
  if [[ ! -f region.osm.pbf ]] || [[ ! -s region.osm.pbf ]]; then
    echo "FAILED to download"
    failed=$((failed + 1))
    continue
  fi
  
  echo "Downloaded: $(ls -lh region.osm.pbf | awk '{print $5}')"
  
  # Extract golf features
  osmium tags-filter region.osm.pbf \
    nwr/leisure=golf_course nwr/golf=hole nwr/golf=fairway nwr/golf=green nwr/golf=bunker nwr/golf=rough \
    -o golf.osm.pbf --overwrite
  
  osmium export golf.osm.pbf -o all.geojson --add-unique-id=type_id --overwrite
  
  # Count courses
  course_count=$(jq '[.features[] | select(.properties.leisure == "golf_course" and .properties.name != null)] | length' all.geojson)
  echo "Found $course_count courses"
  
  if [[ "$course_count" -gt 0 ]]; then
    gzip -9 -c all.geojson > "$OUTPUT_DIR/${output_name}.geojson.gz"
    echo "Created ${output_name}.geojson.gz ($(ls -lh "$OUTPUT_DIR/${output_name}.geojson.gz" | awk '{print $5}'))"
    success=$((success + 1))
  else
    skipped=$((skipped + 1))
  fi
  
  rm -f region.osm.pbf golf.osm.pbf all.geojson
done

echo ""
echo "=========================================="
echo "SUMMARY: $success success, $failed failed, $skipped skipped (total: $total)"
echo "OUTPUT: $OUTPUT_DIR/"
echo "=========================================="

exit $failed
