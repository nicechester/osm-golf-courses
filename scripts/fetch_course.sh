#!/bin/bash
# Simulates mobile app flow to fetch golf course data
# Usage: ./fetch_course.sh "course name" [local_data_dir]

set -e

COURSE_NAME="${1:-Pelican Hill}"
LOCAL_DATA_DIR="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="$HOME/.cache/osm-golf"
RELEASE_URL="https://github.com/nicechester/osm-golf-courses/releases/latest/download"

mkdir -p "$CACHE_DIR"

echo "=== Searching for: $COURSE_NAME ==="

# Step 1: Use local index
INDEX_FILE="$REPO_ROOT/indexes/index.json"

# Step 2: Find course in index
echo "Looking up course..."
MATCH=$(jq -r --arg name "$COURSE_NAME" '.[] | select(.name | test($name; "i")) | "\(.name)|\(.file)|\(.osmId)|\(.lat)|\(.lon)"' "$INDEX_FILE" | head -1)

if [[ -z "$MATCH" ]]; then
  echo "Course not found: $COURSE_NAME"
  exit 1
fi

IFS='|' read -r NAME FILE OSM_ID LAT LON <<< "$MATCH"
echo "Found: $NAME"
echo "  File: $FILE"
echo "  OSM ID: $OSM_ID"
echo "  Location: $LAT, $LON"

# Step 3: Get region file (local or download)
if [[ -n "$LOCAL_DATA_DIR" && -f "$LOCAL_DATA_DIR/$FILE" ]]; then
  REGION_FILE="$LOCAL_DATA_DIR/$FILE"
  echo "Using local: $REGION_FILE"
else
  REGION_FILE="$CACHE_DIR/$FILE"
  if [[ ! -f "$REGION_FILE" ]]; then
    echo "Downloading region file..."
    curl -L "$RELEASE_URL/$FILE" -o "$REGION_FILE"
  fi
fi

# Step 4: Extract course outline and find all nearby golf_course outlines
echo ""
echo "=== Course Features ==="

# Get the requested outline
gunzip -c "$REGION_FILE" | jq --arg id "$OSM_ID" '[.features[] | select(.id == $id)]' > /tmp/course_boundary.json

# Get bounding box from course boundary (prefer Polygon/MultiPolygon over LineString)
BOUNDS=$(jq -r '
  (map(select(.geometry.type == "Polygon" or .geometry.type == "MultiPolygon")) | if length > 0 then .[0] else .[0] end) |
  def all_coords:
    if .geometry.type == "Point" then [.geometry.coordinates]
    elif .geometry.type == "LineString" then .geometry.coordinates
    elif .geometry.type == "Polygon" then [.geometry.coordinates[][] ]
    elif .geometry.type == "MultiPolygon" then [.geometry.coordinates[][][] ]
    else [] end;
  (all_coords | map(.[1])) as $lats | (all_coords | map(.[0])) as $lons |
  "\($lats | min)|\($lats | max)|\($lons | min)|\($lons | max)"' /tmp/course_boundary.json)

IFS='|' read -r MIN_LAT MAX_LAT MIN_LON MAX_LON <<< "$BOUNDS"

# Add buffer (0.006° ~ 660m, same as iOS)
MARGIN=0.006
MIN_LAT=$(echo "$MIN_LAT - $MARGIN" | bc)
MAX_LAT=$(echo "$MAX_LAT + $MARGIN" | bc)
MIN_LON=$(echo "$MIN_LON - $MARGIN" | bc)
MAX_LON=$(echo "$MAX_LON + $MARGIN" | bc)

echo "Bounding box: $MIN_LAT,$MIN_LON to $MAX_LAT,$MAX_LON (margin: $MARGIN°)"

# Find ALL golf_course outlines within the bounding box
gunzip -c "$REGION_FILE" | jq --argjson minLat "$MIN_LAT" --argjson maxLat "$MAX_LAT" --argjson minLon "$MIN_LON" --argjson maxLon "$MAX_LON" '
  def get_coords:
    if .geometry.type == "Polygon" then [.geometry.coordinates[][] ]
    elif .geometry.type == "MultiPolygon" then [.geometry.coordinates[][][] ]
    else [] end;
  def in_bounds:
    (get_coords | map(.[1] >= $minLat and .[1] <= $maxLat and .[0] >= $minLon and .[0] <= $maxLon) | any) // false;
  [.features[] | select(.properties.leisure == "golf_course" and in_bounds)]
' > /tmp/all_outlines.json

OUTLINE_COUNT=$(jq 'length' /tmp/all_outlines.json)
echo "Golf course outlines in bounding box: $OUTLINE_COUNT"
if [[ "$OUTLINE_COUNT" -gt 1 ]]; then
  echo "  ⚠️  Multiple outlines detected - holes need filtering!"
  jq -r '.[] | "  - \(.id): \(.properties.name // "unnamed")"' /tmp/all_outlines.json
fi

# Extract all features within bounds
gunzip -c "$REGION_FILE" | jq --argjson minLat "$MIN_LAT" --argjson maxLat "$MAX_LAT" --argjson minLon "$MIN_LON" --argjson maxLon "$MAX_LON" '
  def get_coords:
    if .geometry.type == "Point" then [.geometry.coordinates]
    elif .geometry.type == "LineString" then .geometry.coordinates
    elif .geometry.type == "Polygon" then .geometry.coordinates | flatten(1)
    elif .geometry.type == "MultiPolygon" then .geometry.coordinates | flatten(2)
    else [] end;
  def in_bounds:
    (get_coords | map(.[1] >= $minLat and .[1] <= $maxLat and .[0] >= $minLon and .[0] <= $maxLon) | any) // false;
  { type: "FeatureCollection", features: [.features[] | select(in_bounds)] }
' > /tmp/course_features.json

# Summary
echo ""
echo "=== Summary ==="
jq -r '.features | group_by(.properties.leisure // .properties.golf // "other") | .[] | "\(.[0].properties.leisure // .[0].properties.golf // "other"): \(length)"' /tmp/course_features.json

TOTAL=$(jq '.features | length' /tmp/course_features.json)
echo "Total features: $TOTAL"

# Hole analysis (simulates iOS extractor logic)
echo ""
echo "=== Hole Analysis ==="
HOLES=$(jq '[.features[] | select(.properties.golf == "hole")]' /tmp/course_features.json)
HOLE_COUNT=$(echo "$HOLES" | jq 'length')
echo "Total hole lines in bounding box: $HOLE_COUNT"

# If multiple outlines, filter holes to only those belonging to requested outline
if [[ "$OUTLINE_COUNT" -gt 1 ]]; then
  echo ""
  echo "=== Hole-to-Outline Association (proposed fix) ==="
  
  # Get centroid of requested outline
  REQ_CENTROID=$(jq -r --arg id "$OSM_ID" '.[] | select(.id == $id) |
    def all_coords:
      if .geometry.type == "Polygon" then [.geometry.coordinates[][] ]
      elif .geometry.type == "MultiPolygon" then [.geometry.coordinates[][][] ]
      else [] end;
    (all_coords | map(.[1]) | add / length) as $lat |
    (all_coords | map(.[0]) | add / length) as $lon |
    "\($lat)|\($lon)"' /tmp/all_outlines.json)
  IFS='|' read -r REQ_LAT REQ_LON <<< "$REQ_CENTROID"
  echo "Requested outline centroid: $REQ_LAT, $REQ_LON"
  
  # For each hole, find nearest outline by centroid distance
  # Associate hole with the outline whose centroid is closest to hole start point
  FILTERED_HOLES=$(echo "$HOLES" | jq --argjson outlines "$(cat /tmp/all_outlines.json)" --arg reqId "$OSM_ID" '
    def outline_centroid:
      if .geometry.type == "Polygon" then
        (.geometry.coordinates[0] | map(.[1]) | add / length) as $lat |
        (.geometry.coordinates[0] | map(.[0]) | add / length) as $lon |
        {lat: $lat, lon: $lon}
      elif .geometry.type == "MultiPolygon" then
        ([.geometry.coordinates[][][] | .[1]] | add / length) as $lat |
        ([.geometry.coordinates[][][] | .[0]] | add / length) as $lon |
        {lat: $lat, lon: $lon}
      else {lat: 0, lon: 0} end;
    def dist($p1; $p2): (($p1.lat - $p2.lat) | . * .) + (($p1.lon - $p2.lon) | . * .) | sqrt;
    ($outlines | map({id: .id, centroid: outline_centroid})) as $centroids |
    [.[] | . as $hole |
      ($hole.geometry.coordinates[0] | {lat: .[1], lon: .[0]}) as $start |
      ($centroids | map({id: .id, d: dist(.centroid; $start)}) | min_by(.d)) as $nearest |
      select($nearest.id == $reqId)
    ]')
  
  FILTERED_COUNT=$(echo "$FILTERED_HOLES" | jq 'length')
  echo "Holes belonging to $OSM_ID: $FILTERED_COUNT (filtered from $HOLE_COUNT)"
  
  # Use filtered holes for analysis
  HOLES="$FILTERED_HOLES"
  HOLE_COUNT="$FILTERED_COUNT"
fi

# Check golf:course:name tags
TAGGED=$(echo "$HOLES" | jq '[.[] | select(.properties["golf:course:name"] != null)] | length')
echo "With golf:course:name tag: $TAGGED"

# Show refs
echo ""
echo "Hole refs:"
echo "$HOLES" | jq -r '.[].properties.ref' | sort -V | uniq -c

# Layout detection
echo ""
echo "=== Layout Detection ==="

# Method 1: golf:course:name tag
if [[ "$TAGGED" -gt 0 && "$TAGGED" -eq "$HOLE_COUNT" ]]; then
  echo "Method: golf:course:name tags"
  echo "$HOLES" | jq -r 'group_by(.properties["golf:course:name"]) | .[] | "  \(.[0].properties["golf:course:name"]): \(length) holes"'
else
  # Method 2: ref-embedded course name (e.g. "Creek 1", "Oaks 5", "Stone House 1")
  # Extract prefix before the trailing number
  PREFIXES=$(echo "$HOLES" | jq -r '.[].properties.ref // ""' | sed -E 's/ *[0-9]+$//' | sort | uniq)
  PREFIX_COUNT=$(echo "$PREFIXES" | grep -v '^$' | wc -l | tr -d ' ')
  
  if [[ "$PREFIX_COUNT" -gt 1 ]]; then
    echo "Method: ref-embedded course name (e.g. 'Creek 1')"
    while IFS= read -r prefix; do
      if [[ -n "$prefix" ]]; then
        count=$(echo "$HOLES" | jq --arg p "$prefix " '[.[] | select(.properties.ref | startswith($p))] | length')
        echo "  $prefix: $count holes"
      fi
    done <<< "$PREFIXES"
  else
    # Method 3: duplicate refs -> way-ID gap splitting
    MAX_DUP=$(echo "$HOLES" | jq '[.[].properties.ref] | group_by(.) | map(length) | max')
    if [[ "$MAX_DUP" -gt 1 ]]; then
      echo "Method: way-ID gap splitting (duplicate refs detected)"
      echo "  Layout count: $MAX_DUP (based on max duplicate refs)"
      echo "  Holes per layout: ~$((HOLE_COUNT / MAX_DUP))"
    else
      echo "Method: single course (no duplicates, no prefixes)"
      echo "  Holes: $HOLE_COUNT"
    fi
  fi
fi

# Numeric refs only (current iOS behavior)
NUMERIC_REFS=$(echo "$HOLES" | jq '[.[] | select(.properties.ref != null and (.properties.ref | test("^[0-9]+$")))] | length')
echo ""
echo "Current iOS (numeric refs only): $NUMERIC_REFS holes"

echo ""
echo "Output saved to: /tmp/course_features.json"
