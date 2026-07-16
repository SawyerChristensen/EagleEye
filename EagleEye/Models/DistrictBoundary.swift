//
//  DistrictBoundary.swift
//  EagleEye
//
//  State and congressional-district border geometry, bundled from Census
//  Bureau cartographic boundary files (cb_2022_us_cd118_5m / cb_2022_us_state_20m).
//

import Foundation
import CoreLocation

/// A single state or congressional-district boundary, ready to draw on a map.
/// A boundary can have multiple `rings` (e.g. a district with offshore islands).
struct MapBoundary: Identifiable {
    let id: String
    let state: String
    let district: Int?
    let rings: [[CLLocationCoordinate2D]]

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

private struct BoundaryFeatureDTO: Decodable {
    let id: String
    let state: String
    let district: Int?
    let rings: [[[Double]]]
}

private struct BoundaryCollectionDTO: Decodable {
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
    private static func simplify(_ points: [CLLocationCoordinate2D], tolerance: Double) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        simplifySegment(points, 0, points.count - 1, tolerance, &keep)
        return points.indices.compactMap { keep[$0] ? points[$0] : nil }
    }

    private static func simplifySegment(
        _ points: [CLLocationCoordinate2D],
        _ start: Int,
        _ end: Int,
        _ tolerance: Double,
        _ keep: inout [Bool]
    ) {
        guard end > start + 1 else { return }
        var maxDistance = 0.0
        var farthestIndex = start
        for i in (start + 1)..<end {
            let distance = perpendicularDistance(points[i], points[start], points[end])
            if distance > maxDistance {
                maxDistance = distance
                farthestIndex = i
            }
        }
        if maxDistance > tolerance {
            keep[farthestIndex] = true
            simplifySegment(points, start, farthestIndex, tolerance, &keep)
            simplifySegment(points, farthestIndex, end, tolerance, &keep)
        }
    }

    /// Distance from `point` to the line through `lineStart`/`lineEnd`, in
    /// the same (degree) units as the coordinates.
    private static func perpendicularDistance(
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
            return (ddx * ddx + ddy * ddy).squareRoot()
        }
        let cross = dx * (lineStart.latitude - point.latitude) - dy * (lineStart.longitude - point.longitude)
        return abs(cross) / lengthSquared.squareRoot()
    }
}
