//
//  CensusGeocoder.swift
//  EagleEye
//
//  Maps a coordinate to its U.S. congressional district using the free
//  Census Bureau geocoder (https://geocoding.geo.census.gov). No API key
//  is required.
//

import Foundation
import CoreLocation

/// Looks up the congressional district that contains a coordinate. The Census
/// geocoder returns every geography a point falls in; we pull out the
/// congressional-district layer (its name varies by Congress, e.g. "119th
/// Congressional Districts").
struct CensusGeocoder {
    enum GeocoderError: LocalizedError {
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .badResponse(let code):
                "The Census geocoder returned HTTP \(code)."
            }
        }
    }

    var session: URLSession = .shared

    /// Returns the district number for `coordinate`, or `nil` if the point
    /// isn't inside a known congressional district. At-large districts come
    /// back as `0`.
    func congressionalDistrict(at coordinate: CLLocationCoordinate2D) async throws -> Int? {
        var components = URLComponents(
            string: "https://geocoding.geo.census.gov/geocoder/geographies/coordinates"
        )!
        components.queryItems = [
            URLQueryItem(name: "x", value: String(coordinate.longitude)),
            URLQueryItem(name: "y", value: String(coordinate.latitude)),
            URLQueryItem(name: "benchmark", value: "Public_AR_Current"),
            URLQueryItem(name: "vintage", value: "Current_Current"),
            URLQueryItem(name: "format", value: "json"),
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse else {
            throw GeocoderError.badResponse(-1)
        }
        guard 200..<300 ~= http.statusCode else {
            throw GeocoderError.badResponse(http.statusCode)
        }

        let payload = try JSONDecoder().decode(GeographiesResponse.self, from: data)
        return payload.districtNumber
    }
}

// MARK: - Wire format

/// The relevant slice of a Census "geographies/coordinates" response.
private struct GeographiesResponse: Decodable {
    let result: ResultBody

    struct ResultBody: Decodable {
        /// Each key is a geography layer name; the value is the matching areas.
        let geographies: [String: [Geography]]
    }

    struct Geography: Decodable {
        let basename: String?
        let name: String?

        enum CodingKeys: String, CodingKey {
            case basename = "BASENAME"
            case name = "NAME"
        }
    }

    /// Pulls the district number out of the congressional-district layer.
    var districtNumber: Int? {
        guard let layer = result.geographies.first(where: {
            $0.key.localizedCaseInsensitiveContains("Congressional District")
        }), let area = layer.value.first else {
            return nil
        }

        // The basename is the bare district number ("12", or "00" at-large).
        if let basename = area.basename, let number = Int(basename) {
            return number
        }
        // Fall back to parsing the trailing number out of the full name.
        if let trailing = area.name?.split(separator: " ").last, let number = Int(trailing) {
            return number
        }
        return nil
    }
}
