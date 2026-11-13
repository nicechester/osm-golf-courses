# OSM Golf Courses

Golf course data extracted from OpenStreetMap, organized by state/province.

## Structure

- `index.json` - All courses with name, city, state, location, chunk reference
- Releases contain gzipped GeoJSON chunks per state/province

## Usage

```javascript
// 1. Fetch index
const index = await fetch('https://raw.githubusercontent.com/nicechester/osm-golf-courses/main/index.json').then(r => r.json());

// 2. Search locally
const nearby = index.filter(c => distance(c.lat, c.lon, userLat, userLon) < 50000);

// 3. Download chunk when needed
const chunk = await fetch(`https://github.com/nicechester/osm-golf-courses/releases/latest/download/${course.chunk}.geojson.gz`);
```

## Regions

- US: 50 states + DC + Puerto Rico
- Canada: 13 provinces/territories  
- Mexico

## Source

[Geofabrik](https://download.geofabrik.de/) extracts, updated weekly via GitHub Actions.
