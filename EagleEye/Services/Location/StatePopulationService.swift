//
//  StatePopulationService.swift
//  EagleEye
//
//  Looks up a state's total population from the Census Bureau's free ACS
//  5-year estimates API (no API key required), mirroring
//  `DistrictPopulationService`'s use of the same agency's free endpoints but
//  querying at the state level instead of per congressional district.
//

import Foundation

struct StatePopulationService {
    enum ServiceError: LocalizedError {
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .badResponse(let code):
                "The Census API returned HTTP \(code)."
            }
        }
    }

    var session: URLSession = .shared

    /// The ACS 5-year vintage to query.
    private let vintage = 2022

    /// Total population of a state (Census table B01003_001E), or `nil` if
    /// the state has no FIPS code on file (the territories) or the API has
    /// no matching row.
    func population(state: String) async throws -> Int? {
        guard let fips = CensusStateFIPS.byPostalCode[state] else { return nil }
        // The Census Data API rejects keyless requests, so without a key there
        // is nothing to fetch — leave the section empty rather than fail.
        guard CensusAPIKey.isConfigured else { return nil }

        var components = URLComponents(string: "https://api.census.gov/data/\(vintage)/acs/acs5")!
        components.queryItems = [
            URLQueryItem(name: "get", value: "NAME,B01003_001E"),
            URLQueryItem(name: "for", value: "state:\(fips)"),
            URLQueryItem(name: "key", value: CensusAPIKey.configured),
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.badResponse(-1)
        }
        guard 200..<300 ~= http.statusCode else {
            throw ServiceError.badResponse(http.statusCode)
        }

        // The API returns a JSON array of rows, the first being the header
        // (["NAME", "B01003_001E", "state"]).
        let rows = try JSONDecoder().decode([[String]].self, from: data)
        guard rows.count > 1, let population = Int(rows[1][1]) else { return nil }
        return population
    }
}
