#!/bin/bash
# Simulates mobile app flow to fetch golf course data
# Usage: ./fetch_course.sh "course name"

set -e

COURSE_NAME="${1:-Pelican Hill}"
CACHE_DIR="$HOME/.cache/osm-golf"
INDEX_URL="https://raw.githubusercontent.com/nicechester/osm-golf-courses/main/indexes/index.json"
RELEASE_URL="https://github.com/nicechester/osm-golf-courses/releases/latest/download"

mkdir -p "$CACHE_DIR"

echo "=== Searching for: $COURSE_NAME ==="

# Step 1: Fetch index (would be cached in real app)
INDEX_FILE="$CACHE_DIR/index.json"
if [[ ! -f "$INDEX_FILE" ]]; then
  echo "Downloading index..."
  curl -sL "$INDEX_URL" -o "$INDEX_FILE"
fi

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

# Step 3: Download region file (would be cached in real app)
REGION_FILE="$CACHE_DIR/$FILE"
if [[ ! -f "$REGION_FILE" ]]; then
  echo "Downloading region file..."
  curl -L "$RELEASE_URL/$FILE" -o "$REGION_FILE"
fi

# Step 4: Extract course features
echo ""
echo "=== Course Features ==="
gunzip -c "$REGION_FILE" | jq --arg id "$OSM_ID" '[.features[] | select(
  .id == $id or 
  (.properties.leisure == "golf_course" and .properties.name and (.properties.name | test("'"$COURSE_NAME"'"; "i")))
)]' > /tmp/course_boundary.json

# Get bounding box from course boundary
BOUNDS=$(jq -r '.[0] | 
  if .geometry.type == "Polygon" then
    { minLat: ([.geometry.coordinates[0][] | .[1]] | min),
      maxLat: ([.geometry.coordinates[0][] | .[1]] | max),
      minLon: ([.geometry.coordinates[0][] | .[0]] | min),
      maxLon: ([.geometry.coordinates[0][] | .[0]] | max) }
  else
    { minLat: ([.geometry.coordinates[][] | .[] | .[1]] | min),
      maxLat: ([.geometry.coordinates[][] | .[] | .[1]] | max),
      minLon: ([.geometry.coordinates[][] | .[] | .[0]] | min),
      maxLon: ([.geometry.coordinates[][] | .[] | .[0]] | max) }
  end | "\(.minLat)|\(.maxLat)|\(.minLon)|\(.maxLon)"' /tmp/course_boundary.json)

IFS='|' read -r MIN_LAT MAX_LAT MIN_LON MAX_LON <<< "$BOUNDS"

# Add buffer
MIN_LAT=$(echo "$MIN_LAT - 0.002" | bc)
MAX_LAT=$(echo "$MAX_LAT + 0.002" | bc)
MIN_LON=$(echo "$MIN_LON - 0.002" | bc)
MAX_LON=$(echo "$MAX_LON + 0.002" | bc)

echo "Bounding box: $MIN_LAT,$MIN_LON to $MAX_LAT,$MAX_LON"

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
echo ""
echo "Output saved to: /tmp/course_features.json"
