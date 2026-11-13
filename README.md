# OSM Golf Courses

Golf course data extracted from OpenStreetMap for mobile app integration. Per-course GeoJSON files with detailed geometry (holes, fairways, greens, bunkers).

## Data Structure

### Release Assets (Course Files)

Each golf course is a separate gzipped GeoJSON file in GitHub Releases:

```
https://github.com/nicechester/osm-golf-courses/releases/latest/download/{filename}
```

**Filename format:** `{continent}_{country}_{state}_{course-name}-{osm-id}.geojson.gz`

Example: `north-america_us_hawaii_ala-wai-golf-course-a83995508.geojson.gz`

**File size:** ~50-300KB per course (gzipped)

### Index Files (in repo)

Hierarchical JSON indexes for searching/browsing:

```
indexes/
├── index.json                              # All courses (~15,000+)
├── north-america/
│   ├── index.json                          # All North America
│   ├── us/
│   │   ├── index.json                      # All US courses
│   │   ├── california/index.json           # California courses
│   │   ├── hawaii/index.json               # Hawaii courses
│   │   └── ...
│   ├── ca/
│   │   ├── index.json                      # All Canada courses
│   │   ├── ontario/index.json
│   │   └── ...
│   └── mx/
│       └── mexico/index.json
```

**Index entry format:**
```json
{
  "name": "Ala Wai Golf Course",
  "city": "Honolulu",
  "osmId": "a83995508",
  "file": "north-america_us_hawaii_ala-wai-golf-course-a83995508.geojson.gz",
  "lat": 21.279420,
  "lon": -157.819321
}
```

### GeoJSON Content

Each course file is a FeatureCollection containing:

| Feature Type | OSM Tag | Description |
|--------------|---------|-------------|
| Course boundary | `leisure=golf_course` | Overall course polygon |
| Holes | `golf=hole` | Hole centerlines (LineString) |
| Fairways | `golf=fairway` | Fairway polygons |
| Greens | `golf=green` | Green polygons |
| Bunkers | `golf=bunker` | Sand trap polygons |
| Rough | `golf=rough` | Rough area polygons |
| Tee boxes | `golf=tee` | Tee box polygons |

**OSM ID format:** `w123456` (way), `r123456` (relation), `a123456` (area)

## Mobile App Integration

### iOS (Swift)

```swift
// 1. Fetch state index
let indexURL = URL(string: "https://raw.githubusercontent.com/nicechester/osm-golf-courses/main/indexes/north-america/us/hawaii/index.json")!
let courses: [Course] = try await URLSession.shared.decode(from: indexURL)

// 2. Find nearby courses
let nearby = courses.filter { course in
    let distance = CLLocation(latitude: course.lat, longitude: course.lon)
        .distance(from: userLocation)
    return distance < 50_000 // 50km
}

// 3. Download course detail when selected
let courseURL = URL(string: "https://github.com/nicechester/osm-golf-courses/releases/latest/download/\(course.file)")!
let (data, _) = try await URLSession.shared.data(from: courseURL)
let decompressed = try (data as NSData).decompressed(using: .gzip)
let geoJSON = try JSONDecoder().decode(FeatureCollection.self, from: decompressed)
```

### Android (Kotlin)

```kotlin
// 1. Fetch state index
val indexUrl = "https://raw.githubusercontent.com/nicechester/osm-golf-courses/main/indexes/north-america/us/hawaii/index.json"
val courses: List<Course> = retrofit.create(GolfApi::class.java).getIndex(indexUrl)

// 2. Find nearby courses
val nearby = courses.filter { course ->
    val results = FloatArray(1)
    Location.distanceBetween(userLat, userLon, course.lat, course.lon, results)
    results[0] < 50_000 // 50km
}

// 3. Download course detail when selected
val courseUrl = "https://github.com/nicechester/osm-golf-courses/releases/latest/download/${course.file}"
val response = okHttpClient.newCall(Request.Builder().url(courseUrl).build()).execute()
val geoJson = GZIPInputStream(response.body?.byteStream()).bufferedReader().readText()
```

## Caching Strategy

Recommended approach for mobile apps:

1. **Index caching:** Cache state/country indexes locally, refresh weekly
2. **Course caching:** Cache downloaded course files indefinitely (use OSM ID as cache key)
3. **Lazy loading:** Only download course detail when user selects it
4. **Prefetch:** Optionally prefetch nearby courses in background

## Coverage

| Region | States/Provinces |
|--------|------------------|
| US | 50 states + DC + Puerto Rico |
| Canada | 13 provinces/territories |
| Mexico | Nationwide |

## Update Schedule

- **Frequency:** Weekly (Sunday 00:00 UTC)
- **Source:** [Geofabrik](https://download.geofabrik.de/) OSM extracts
- **Workflow:** GitHub Actions ([extract-golf.yml](.github/workflows/extract-golf.yml))

## API Endpoints

| Resource | URL |
|----------|-----|
| Root index | `https://raw.githubusercontent.com/nicechester/osm-golf-courses/main/indexes/index.json` |
| State index | `https://raw.githubusercontent.com/nicechester/osm-golf-courses/main/indexes/north-america/us/{state}/index.json` |
| Course file | `https://github.com/nicechester/osm-golf-courses/releases/latest/download/{filename}` |

## License

Data © OpenStreetMap contributors, licensed under [ODbL](https://opendatacommons.org/licenses/odbl/).
