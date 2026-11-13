# OSM Golf Courses

Pre-extracted golf course data from OpenStreetMap for mobile app integration.

## Data Structure

Golf course GeoJSON files are stored in [GitHub Releases](https://github.com/nicechester/osm-golf-courses/releases), organized by region:

```
north-america_us_california.geojson.gz    # All California courses
north-america_us_texas.geojson.gz         # All Texas courses
north-america_ca_ontario.geojson.gz       # All Ontario courses
north-america_mx_mexico.geojson.gz        # All Mexico courses
```

## API Endpoints

| Resource | URL |
|----------|-----|
| Release (latest) | `https://github.com/nicechester/osm-golf-courses/releases/latest` |
| Region file | `https://github.com/nicechester/osm-golf-courses/releases/latest/download/{region}.geojson.gz` |
| Master index | `https://raw.githubusercontent.com/nicechester/osm-golf-courses/main/indexes/index.json` |

## GeoJSON Content

Each region file contains all golf features for that area:

| Feature Type | OSM Tag | Description |
|--------------|---------|-------------|
| Course boundary | `leisure=golf_course` | Overall course polygon |
| Holes | `golf=hole` | Individual hole polygons |
| Fairways | `golf=fairway` | Fairway areas |
| Greens | `golf=green` | Putting greens |
| Bunkers | `golf=bunker` | Sand traps |
| Rough | `golf=rough` | Rough areas |

## Mobile App Integration

### Index Format

The master index (`indexes/index.json`) contains all courses:

```json
[
  {
    "name": "Pebble Beach Golf Links",
    "city": "Pebble Beach",
    "osmId": "w123456",
    "file": "north-america_us_california.geojson.gz",
    "lat": 36.5725,
    "lon": -121.9486
  }
]
```

### iOS (Swift)

```swift
import Foundation
import Compression

class GolfCourseService {
    static let shared = GolfCourseService()
    private let cache = NSCache<NSString, NSData>()
    private let baseURL = "https://github.com/nicechester/osm-golf-courses/releases/latest/download/"
    
    func loadRegion(_ filename: String) async throws -> Data {
        // Check cache
        if let cached = cache.object(forKey: filename as NSString) {
            return cached as Data
        }
        
        // Download
        let url = URL(string: baseURL + filename)!
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Decompress gzip
        let decompressed = try decompress(data)
        
        // Cache for 1 day
        cache.setObject(decompressed as NSData, forKey: filename as NSString)
        
        return decompressed
    }
    
    private func decompress(_ data: Data) throws -> Data {
        // Skip gzip header (10 bytes) and decompress
        let decompressed = try (data.dropFirst(10) as NSData)
            .decompressed(using: .zlib)
        return decompressed as Data
    }
}
```

### Android (Kotlin)

```kotlin
import java.net.URL
import java.util.zip.GZIPInputStream

class GolfCourseRepository {
    private val cache = mutableMapOf<String, String>()
    private val baseUrl = "https://github.com/nicechester/osm-golf-courses/releases/latest/download/"
    
    suspend fun loadRegion(filename: String): String {
        cache[filename]?.let { return it }
        
        val geojson = withContext(Dispatchers.IO) {
            URL(baseUrl + filename).openStream().use { input ->
                GZIPInputStream(input).bufferedReader().readText()
            }
        }
        
        cache[filename] = geojson
        return geojson
    }
}
```

### Caching Strategy

- Cache region files with 1 day TTL
- Use `file` field from index to determine which region to download
- Find nearest course using lat/lon from index, then load its region file

## Coverage

| Region | States/Provinces |
|--------|------------------|
| US | 50 states + DC + Puerto Rico |
| Canada | 13 provinces/territories |
| Mexico | Entire country |

## Update Schedule

Data is refreshed weekly (Sunday 00:00 UTC) from [Geofabrik](https://download.geofabrik.de/) OSM mirrors.

## License

Data © OpenStreetMap contributors, licensed under [ODbL](https://opendatacommons.org/licenses/odbl/).
