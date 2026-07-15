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
enum BoundaryLoader {
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
                    ring.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                }
            )
        }
    }
}
