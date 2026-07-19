//
//  DistrictIndustryService.swift
//  EagleEye
//
//  Looks up a congressional district's top employing industries from the
//  Census Bureau's free ACS 5-year "Industry by Occupation" subject table
//  (S2403, no API key required), mirroring `DistrictPopulationService`'s use
//  of the same agency's free endpoints.
//

import Foundation

struct IndustryShare: Codable, Hashable {
    /// The industry's category name (e.g. "Manufacturing").
    let name: String
    /// The industry's share of the district's employed civilian population,
    /// as a fraction 0...1.
    let share: Double
}

struct DistrictIndustryService {
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

    /// The employed civilian population's top industries in a congressional
    /// district, most- to least-employing, each with its share of the
    /// district's total employment — or `nil` if the state has no FIPS code
    /// on file (the territories, whose delegates' districts aren't part of the
    /// ACS congressional-district geography) or the API has no matching row.
    /// `limit` caps how many industries are returned; the share is computed
    /// against the full set of leaf industries, not just the returned top few.
    func topIndustries(state: String, district: Int, limit: Int = 3) async throws -> [IndustryShare]? {
        guard let fips = CensusStateFIPS.byPostalCode[state] else { return nil }
        // The Census Data API rejects keyless requests, so without a key there
        // is nothing to fetch — leave the section empty rather than fail.
        guard CensusAPIKey.isConfigured else { return nil }
        let districtParam = String(format: "%02d", district)

        var components = URLComponents(string: "https://api.census.gov/data/\(vintage)/acs/acs5/subject")!
        components.queryItems = [
            URLQueryItem(name: "get", value: "NAME,\(Self.variables.map(\.code).joined(separator: ","))"),
            URLQueryItem(name: "for", value: "congressional district:\(districtParam)"),
            URLQueryItem(name: "in", value: "state:\(fips)"),
            URLQueryItem(name: "key", value: CensusAPIKey.configured),
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.badResponse(-1)
        }
        guard 200..<300 ~= http.statusCode else {
            throw ServiceError.badResponse(http.statusCode)
        }

        // The API returns a JSON array of rows, the first being the header;
        // the second holds NAME followed by one value per requested variable,
        // in the same order they were requested.
        let rows = try JSONDecoder().decode([[String]].self, from: data)
        guard rows.count > 1 else { return nil }
        let values = rows[1].dropFirst()

        let employedByIndustry = zip(Self.variables, values).compactMap { variable, value -> (String, Int)? in
            guard let employed = Int(value), employed > 0 else { return nil }
            return (variable.label, employed)
        }
        guard !employedByIndustry.isEmpty else { return nil }

        let totalEmployed = employedByIndustry.reduce(0) { $0 + $1.1 }
        guard totalEmployed > 0 else { return nil }

        return employedByIndustry
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { IndustryShare(name: $0.0, share: Double($0.1) / Double(totalEmployed)) }
    }

    /// The leaf-level industry categories of Census table S2403 ("Industry
    /// by Occupation for the Civilian Employed Population 16 Years and
    /// Over") — excludes the table's parent/subtotal rows (e.g. C01_009,
    /// the "Transportation and warehousing, and utilities" combined row
    /// covering C01_010 and C01_011) so industries aren't double-counted.
    private static let variables: [(code: String, label: String)] = [
        ("S2403_C01_003E", "Agriculture, forestry, fishing and hunting"),
        ("S2403_C01_004E", "Mining, quarrying, and oil and gas extraction"),
        ("S2403_C01_005E", "Construction"),
        ("S2403_C01_006E", "Manufacturing"),
        ("S2403_C01_007E", "Wholesale trade"),
        ("S2403_C01_008E", "Retail trade"),
        ("S2403_C01_010E", "Transportation and warehousing"),
        ("S2403_C01_011E", "Utilities"),
        ("S2403_C01_012E", "Information"),
        ("S2403_C01_014E", "Finance and insurance"),
        ("S2403_C01_015E", "Real estate and rental and leasing"),
        ("S2403_C01_017E", "Professional, scientific, and technical services"),
        ("S2403_C01_018E", "Management of companies and enterprises"),
        ("S2403_C01_019E", "Administrative and support and waste management services"),
        ("S2403_C01_021E", "Educational services"),
        ("S2403_C01_022E", "Health care and social assistance"),
        ("S2403_C01_024E", "Arts, entertainment, and recreation"),
        ("S2403_C01_025E", "Accommodation and food services"),
        ("S2403_C01_026E", "Other services, except public administration"),
        ("S2403_C01_027E", "Public administration"),
    ]
}
