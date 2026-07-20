//
//  DistrictBoundary.swift
//  EagleEye
//
//  State and congressional-district border geometry, bundled from Census
//  Bureau cartographic boundary files (cb_2022_us_cd118_5m / cb_2022_us_state_20m).
//

import Foundation
import CoreLocation
import MapKit

/// A single state or congressional-district boundary, ready to draw on a map.
/// A boundary can have multiple `rings` (e.g. a district with offshore islands).
struct MapBoundary: Identifiable {
    let id: String
    let state: String
    let district: Int?
    /// Full-detail geometry (simplified to ~110m at load) — used for
    /// hit-testing, the detail-sheet thumbnail, and drawing when zoomed in
    /// close enough that the extra vertices are actually visible.
    let rings: [[CLLocationCoordinate2D]]
    /// A far coarser copy of `rings` (simplified to ~2km) drawn in place of
    /// the full geometry once the map is zoomed out — at that scale the
    /// dropped vertices are sub-pixel, but they're the bulk of the polygon
    /// data MapKit has to buffer, so swapping to this cuts the Metal resource
    /// count dramatically when many boundaries are on screen at once.
    let coarseRings: [[CLLocationCoordinate2D]]
    /// One full-detail `MKPolygon` per ring, ready to hand straight to MapKit as
    /// a map overlay. Built here — during boundary loading, which runs off the
    /// main thread — so the map's overlay rebuild only has to wrap these in an
    /// `MKMultiPolygon` and add them, rather than copying every district's
    /// vertices into MapKit on the main thread (the old ~2.5s map-tab stall).
    let fillPolygons: [MKPolygon]
    /// This boundary's bounding box in Mercator map-point space, precomputed
    /// so the map can cheaply cull boundaries that don't intersect the
    /// visible viewport instead of handing every one to MapKit every frame.
    let boundingBox: MKMapRect

    /// The coarse geometry is simplified this aggressively (in degrees, ≈2km).
    /// Only ever drawn when zoomed far enough out that this is imperceptible.
    private static let coarseTolerance = 0.02

    init(id: String, state: String, district: Int?, rings: [[CLLocationCoordinate2D]]) {
        self.id = id
        self.state = state
        self.district = district
        self.rings = rings
        self.coarseRings = rings.map { BoundaryLoader.simplify($0, tolerance: Self.coarseTolerance) }
        // Build the overlay polygons once, here, and keep both them and the
        // bounding box derived from them (MapKit computes `boundingMapRect` in
        // optimized C). Rings with fewer than three points can't form a polygon.
        let polygons = rings.compactMap { ring -> MKPolygon? in
            guard ring.count > 2 else { return nil }
            return MKPolygon(coordinates: ring, count: ring.count)
        }
        self.fillPolygons = polygons
        var rect = MKMapRect.null
        for polygon in polygons {
            rect = rect.union(polygon.boundingMapRect)
        }
        self.boundingBox = rect
    }

    /// A point near the geometric middle of this boundary, used to pin a
    /// representative on the map. Uses the largest ring by area — rather than
    /// averaging every ring — so a district with small offshore islands or
    /// exclaves still centers on its mainland body.
    var centroid: CLLocationCoordinate2D {
        guard let largestRing = rings.max(by: { abs(Self.signedArea($0)) < abs(Self.signedArea($1)) }) else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        return Self.centroid(of: largestRing)
    }

    /// A human-readable label for this boundary, e.g. "California's 12th
    /// District" or "Wyoming's At-Large District".
    var displayName: String {
        let stateName = Self.stateName(for: state)
        guard let district, district != 0 else {
            return "\(stateName)'s At-Large District"
        }
        return "\(stateName)'s \(Self.ordinal(district)) District"
    }

    /// The full state/territory name for a two-letter postal code, e.g.
    /// "CA" → "California". Falls back to the code itself if unrecognized.
    static func stateName(for code: String) -> String {
        stateNames[code] ?? code
    }

    /// Full state/territory names keyed by postal code, for display purposes.
    private static let stateNames: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
        "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
        "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia", "HI": "Hawaii",
        "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
        "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine",
        "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
        "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska",
        "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
        "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
        "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "PR": "Puerto Rico",
        "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee",
        "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia",
        "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
        "AS": "American Samoa", "GU": "Guam", "MP": "Northern Mariana Islands",
        "VI": "U.S. Virgin Islands",
    ]

    /// The state capital for a two-letter postal code, e.g. "CA" → "Sacramento".
    /// Falls back to the full state name if unrecognized (e.g. a territory).
    static func capitalCity(for code: String) -> String {
        capitalCities[code] ?? stateName(for: code)
    }

    /// State capitals keyed by postal code, for the "Your Representatives"
    /// list's "In [capital city]" subheader over the governor.
    private static let capitalCities: [String: String] = [
        "AL": "Montgomery", "AK": "Juneau", "AZ": "Phoenix", "AR": "Little Rock",
        "CA": "Sacramento", "CO": "Denver", "CT": "Hartford", "DE": "Dover",
        "FL": "Tallahassee", "GA": "Atlanta", "HI": "Honolulu", "ID": "Boise",
        "IL": "Springfield", "IN": "Indianapolis", "IA": "Des Moines", "KS": "Topeka",
        "KY": "Frankfort", "LA": "Baton Rouge", "ME": "Augusta", "MD": "Annapolis",
        "MA": "Boston", "MI": "Lansing", "MN": "Saint Paul", "MS": "Jackson",
        "MO": "Jefferson City", "MT": "Helena", "NE": "Lincoln", "NV": "Carson City",
        "NH": "Concord", "NJ": "Trenton", "NM": "Santa Fe", "NY": "Albany",
        "NC": "Raleigh", "ND": "Bismarck", "OH": "Columbus", "OK": "Oklahoma City",
        "OR": "Salem", "PA": "Harrisburg", "RI": "Providence", "SC": "Columbia",
        "SD": "Pierre", "TN": "Nashville", "TX": "Austin", "UT": "Salt Lake City",
        "VT": "Montpelier", "VA": "Richmond", "WA": "Olympia", "WV": "Charleston",
        "WI": "Madison", "WY": "Cheyenne",
    ]

    private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()

    private static func ordinal(_ number: Int) -> String {
        ordinalFormatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    /// Whether `point` falls inside this ring, via ray casting. Treats the
    /// ring as planar in lat/lon degrees, which is accurate enough for
    /// hit-testing a map tap against a district boundary.
    static func ringContains(_ point: CLLocationCoordinate2D, _ ring: [CLLocationCoordinate2D]) -> Bool {
        guard ring.count > 2 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let pi = ring[i]
            let pj = ring[j]
            if (pi.latitude > point.latitude) != (pj.latitude > point.latitude) {
                let slope = (pj.longitude - pi.longitude) / (pj.latitude - pi.latitude)
                let intersectLongitude = pi.longitude + slope * (point.latitude - pi.latitude)
                if point.longitude < intersectLongitude {
                    inside.toggle()
                }
            }
            j = i
        }
        return inside
    }

    /// Whether `point` falls inside any of this boundary's rings.
    func contains(_ point: CLLocationCoordinate2D) -> Bool {
        rings.contains { Self.ringContains(point, $0) }
    }

    /// Signed area of a ring via the shoelace formula (positive/negative
    /// indicates winding order; magnitude is what matters for ring size).
    private static func signedArea(_ ring: [CLLocationCoordinate2D]) -> Double {
        guard ring.count > 2 else { return 0 }
        var sum = 0.0
        for i in 0..<ring.count {
            let p0 = ring[i]
            let p1 = ring[(i + 1) % ring.count]
            sum += p0.longitude * p1.latitude - p1.longitude * p0.latitude
        }
        return sum / 2
    }

    /// Area-weighted centroid of a polygon ring, which lands inside the shape
    /// far more reliably than a plain average of its vertices.
    private static func centroid(of ring: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        let area = signedArea(ring)
        guard ring.count > 2, abs(area) > .ulpOfOne else {
            let lat = ring.map(\.latitude).reduce(0, +) / Double(max(ring.count, 1))
            let lon = ring.map(\.longitude).reduce(0, +) / Double(max(ring.count, 1))
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        var cx = 0.0
        var cy = 0.0
        for i in 0..<ring.count {
            let p0 = ring[i]
            let p1 = ring[(i + 1) % ring.count]
            let cross = p0.longitude * p1.latitude - p1.longitude * p0.latitude
            cx += (p0.longitude + p1.longitude) * cross
            cy += (p0.latitude + p1.latitude) * cross
        }
        cx /= (6 * area)
        cy /= (6 * area)
        return CLLocationCoordinate2D(latitude: cy, longitude: cx)
    }
}

private struct BoundaryFeatureDTO: Codable {
    let id: String
    let state: String
    let district: Int?
    let rings: [[[Double]]]
}

private struct BoundaryCollectionDTO: Codable {
    let features: [BoundaryFeatureDTO]
}

/// Loads bundled boundary geometry. Parsing ~180k coordinate pairs takes a
/// noticeable moment, so callers should run this off the main thread.
///
/// Rendering that many vertices as MapKit overlays nationwide at once is
/// what drove the map's memory footprint over the OS limit (EXC_RESOURCE
/// high-watermark crash), so every ring is simplified with the
/// Douglas-Peucker algorithm on load. A tolerance of ~110m is imperceptible
/// at the zoom levels this map is used at, but cuts the vertex count
/// dramatically since the bundled Census cartographic files are far denser
/// than the app needs.
enum BoundaryLoader {
    private static let simplificationTolerance = 0.001 // degrees, ≈110m

    static func loadStates() -> [MapBoundary] {
        load(resource: "StateBoundaries")
    }

    static func loadDistricts() -> [MapBoundary] {
        load(resource: "CongressionalDistricts")
    }

    // MARK: - Disk-cached loading

    /// Bumped when the on-load simplification changes, so a stale cache from an
    /// older build is ignored rather than decoded into the wrong geometry.
    private static let cacheVersion = 1

    /// Same as `loadStates()`, but decodes the persisted thinned geometry when
    /// available so later launches skip the expensive bundle parse + simplify.
    static func loadStatesCached() -> [MapBoundary] {
        loadCached(resource: "StateBoundaries")
    }

    /// Same as `loadDistricts()`, backed by the on-disk simplified cache.
    static func loadDistrictsCached() -> [MapBoundary] {
        loadCached(resource: "CongressionalDistricts")
    }

    /// Returns the simplified boundaries from the Caches directory when a
    /// version-matched file exists; otherwise runs the full bundle parse +
    /// Douglas-Peucker pass once and persists the thinned result for next time.
    /// Runs entirely off the main thread (callers dispatch it to a background
    /// task); the cache is derived from immutable bundled files, so it only
    /// needs invalidating across app versions via `cacheVersion`.
    private static func loadCached(resource: String) -> [MapBoundary] {
        if let url = cacheURL(for: resource),
           let data = try? Data(contentsOf: url),
           let collection = try? JSONDecoder().decode(BoundaryCollectionDTO.self, from: data) {
            return collection.features.map(makeBoundary)
        }
        let boundaries = load(resource: resource)
        persist(boundaries, for: resource)
        return boundaries
    }

    private static func makeBoundary(from feature: BoundaryFeatureDTO) -> MapBoundary {
        MapBoundary(
            id: feature.id,
            state: feature.state,
            district: feature.district,
            rings: feature.rings.map { ring in
                ring.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
            }
        )
    }

    private static func cacheURL(for resource: String) -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return dir.appendingPathComponent("\(resource)-simplified-v\(cacheVersion).json")
    }

    /// Writes the already-simplified rings back out in the same `[lng, lat]`
    /// shape the bundle uses, so `loadCached` can round-trip them cheaply.
    private static func persist(_ boundaries: [MapBoundary], for resource: String) {
        guard !boundaries.isEmpty, let url = cacheURL(for: resource) else { return }
        let collection = BoundaryCollectionDTO(features: boundaries.map { boundary in
            BoundaryFeatureDTO(
                id: boundary.id,
                state: boundary.state,
                district: boundary.district,
                rings: boundary.rings.map { ring in ring.map { [$0.longitude, $0.latitude] } }
            )
        })
        if let data = try? JSONEncoder().encode(collection) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func load(resource: String) -> [MapBoundary] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let collection = try? JSONDecoder().decode(BoundaryCollectionDTO.self, from: data) else {
            return []
        }
        return collection.features.map { feature in
            MapBoundary(
                id: feature.id,
                state: feature.state,
                district: feature.district,
                rings: feature.rings.map { ring in
                    simplify(
                        ring.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) },
                        tolerance: simplificationTolerance
                    )
                }
            )
        }
    }

    /// Reduces a ring's vertex count with the Douglas-Peucker algorithm,
    /// dropping points that fall within `tolerance` (in degrees) of the
    /// line between their neighbors while preserving the ring's shape.
    /// Exposed (not `private`) so callers needing an even coarser pass — e.g.
    /// the map's world-mask cutouts, which are just a wash and never stroked
    /// or hit-tested — can re-simplify already-loaded rings on top of the
    /// standard tolerance applied at load time.
    static func simplify(_ points: [CLLocationCoordinate2D], tolerance: Double) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        
        // Square the tolerance once up front
        let toleranceSquared = tolerance * tolerance
        
        simplifySegment(points, 0, points.count - 1, toleranceSquared, &keep)
        return points.indices.compactMap { keep[$0] ? points[$0] : nil }
    }

    private static func simplifySegment(
        _ points: [CLLocationCoordinate2D],
        _ start: Int,
        _ end: Int,
        _ toleranceSquared: Double, // Now passing the squared tolerance
        _ keep: inout [Bool]
    ) {
        guard end > start + 1 else { return }
        var maxDistanceSquared = 0.0
        var farthestIndex = start
        
        for i in (start + 1)..<end {
            let distanceSquared = perpendicularDistanceSquared(points[i], points[start], points[end])
            if distanceSquared > maxDistanceSquared {
                maxDistanceSquared = distanceSquared
                farthestIndex = i
            }
        }
        
        // Compare squared distance against squared tolerance
        if maxDistanceSquared > toleranceSquared {
            keep[farthestIndex] = true
            simplifySegment(points, start, farthestIndex, toleranceSquared, &keep)
            simplifySegment(points, farthestIndex, end, toleranceSquared, &keep)
        }
    }

    /// Squared distance from `point` to the line through `lineStart`/`lineEnd`.
    /// Returning the squared value avoids expensive square root calculations during heavy recursion.
    private static func perpendicularDistanceSquared(
        _ point: CLLocationCoordinate2D,
        _ lineStart: CLLocationCoordinate2D,
        _ lineEnd: CLLocationCoordinate2D
    ) -> Double {
        let dx = lineEnd.longitude - lineStart.longitude
        let dy = lineEnd.latitude - lineStart.latitude
        let lengthSquared = dx * dx + dy * dy
        
        guard lengthSquared > .ulpOfOne else {
            let ddx = point.longitude - lineStart.longitude
            let ddy = point.latitude - lineStart.latitude
            return ddx * ddx + ddy * ddy
        }
        
        let cross = dx * (lineStart.latitude - point.latitude) - dy * (lineStart.longitude - point.longitude)
        
        // Return the squared result: (cross / sqrt(lengthSquared))^2 -> cross^2 / lengthSquared
        return (cross * cross) / lengthSquared
    }
}
