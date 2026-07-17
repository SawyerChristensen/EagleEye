//
//  DistrictPopulationService.swift
//  EagleEye
//
//  Looks up a congressional district's total population from the Census
//  Bureau's free ACS 5-year estimates API (no API key required), mirroring
//  `CensusGeocoder`'s use of the same agency's free endpoints.
//

import Foundation

struct DistrictPopulationService {
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

    /// The ACS 5-year vintage to query — 2022 matches the bundled 118th
    /// Congress district boundaries (`cb_2022_us_cd118_5m`), since district
    /// lines shift between Congresses in states that redistrict.
    private let vintage = 2022

    /// Total population of a congressional district (Census table
    /// B01003_001E), or `nil` if the state has no FIPS code on file (the
    /// territories, whose delegates' districts aren't part of the ACS
    /// congressional-district geography) or the API has no matching row.
    func population(state: String, district: Int) async throws -> Int? {
        guard let fips = Self.stateFIPS[state] else { return nil }
        let districtParam = String(format: "%02d", district)

        var components = URLComponents(string: "https://api.census.gov/data/\(vintage)/acs/acs5")!
        components.queryItems = [
            URLQueryItem(name: "get", value: "NAME,B01003_001E"),
            URLQueryItem(name: "for", value: "congressional district:\(districtParam)"),
            URLQueryItem(name: "in", value: "state:\(fips)"),
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.badResponse(-1)
        }
        guard 200..<300 ~= http.statusCode else {
            throw ServiceError.badResponse(http.statusCode)
        }

        // The API returns a JSON array of rows, the first being the header
        // (["NAME", "B01003_001E", "state", "congressional district"]).
        let rows = try JSONDecoder().decode([[String]].self, from: data)
        guard rows.count > 1, let population = Int(rows[1][1]) else { return nil }
        return population
    }

    /// Two-digit Census FIPS codes keyed by postal code, for the API's
    /// `in=state:` parameter. Covers the 50 states plus DC — the ACS
    /// congressional-district geography has no rows for the territories.
    private static let stateFIPS: [String: String] = [
        "AL": "01", "AK": "02", "AZ": "04", "AR": "05", "CA": "06",
        "CO": "08", "CT": "09", "DE": "10", "DC": "11", "FL": "12",
        "GA": "13", "HI": "15", "ID": "16", "IL": "17", "IN": "18",
        "IA": "19", "KS": "20", "KY": "21", "LA": "22", "ME": "23",
        "MD": "24", "MA": "25", "MI": "26", "MN": "27", "MS": "28",
        "MO": "29", "MT": "30", "NE": "31", "NV": "32", "NH": "33",
        "NJ": "34", "NM": "35", "NY": "36", "NC": "37", "ND": "38",
        "OH": "39", "OK": "40", "OR": "41", "PA": "42", "RI": "44",
        "SC": "45", "SD": "46", "TN": "47", "TX": "48", "UT": "49",
        "VT": "50", "VA": "51", "WA": "53", "WV": "54", "WI": "55",
        "WY": "56",
    ]
}
