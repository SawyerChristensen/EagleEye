//
//  DistrictDemographicsService.swift
//  EagleEye
//
//  Looks up a congressional district's headline demographics — median
//  household income, median age, educational attainment, poverty rate, and
//  unemployment rate — from the Census Bureau's free ACS 5-year detailed
//  tables (no API key required), mirroring `DistrictPopulationService`'s use
//  of the same agency's free endpoints. Every figure comes from a single
//  request so the whole section fills in at once.
//

import Foundation

struct DistrictDemographics: Codable, Hashable {
    /// Median household income in the past 12 months, in whole dollars.
    let medianHouseholdIncome: Int?
    /// Median age of the district's residents, in years.
    let medianAge: Double?
    /// Share of residents 25 and over holding a bachelor's degree or higher,
    /// as a fraction 0...1.
    let bachelorsOrHigherShare: Double?
    /// Share of residents below the poverty level, as a fraction 0...1.
    let povertyShare: Double?
    /// Unemployment rate — unemployed as a share of the civilian labor
    /// force, as a fraction 0...1.
    let unemploymentShare: Double?
}

struct DistrictDemographicsService {
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

    /// Headline demographics for a congressional district, or `nil` if the
    /// state has no FIPS code on file (the territories, whose delegates'
    /// districts aren't part of the ACS congressional-district geography) or
    /// the API has no matching row.
    func demographics(state: String, district: Int) async throws -> DistrictDemographics? {
        guard let fips = CensusStateFIPS.byPostalCode[state] else { return nil }
        // The Census Data API rejects keyless requests, so without a key there
        // is nothing to fetch — leave the section empty rather than fail.
        guard CensusAPIKey.isConfigured else { return nil }
        let districtParam = String(format: "%02d", district)

        var components = URLComponents(string: "https://api.census.gov/data/\(vintage)/acs/acs5")!
        components.queryItems = [
            URLQueryItem(name: "get", value: "NAME,\(Self.variables.joined(separator: ","))"),
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

        // Map each requested variable code to its returned value, skipping the
        // leading NAME column, so lookups don't depend on column order.
        let values = Dictionary(uniqueKeysWithValues: zip(Self.variables, rows[1].dropFirst()))
        func number(_ code: String) -> Double? {
            // The Census API uses large negative sentinels (e.g. -666666666)
            // for medians it can't compute; treat any negative as missing.
            guard let value = values[code], let number = Double(value), number >= 0 else { return nil }
            return number
        }

        let educatedTotal = [Self.bachelors, Self.masters, Self.professional, Self.doctorate]
            .compactMap { number($0) }
            .reduce(0, +)
        let over25 = number(Self.educationUniverse)
        let povertyUniverse = number(Self.povertyUniverse)
        let laborForce = number(Self.laborForce)

        return DistrictDemographics(
            medianHouseholdIncome: number(Self.medianIncome).map { Int($0) },
            medianAge: number(Self.medianAge),
            bachelorsOrHigherShare: share(educatedTotal, of: over25),
            povertyShare: share(number(Self.belowPoverty), of: povertyUniverse),
            unemploymentShare: share(number(Self.unemployed), of: laborForce)
        )
    }

    /// A part-of-whole fraction, or `nil` when either side is missing or the
    /// denominator is zero.
    private func share(_ part: Double?, of whole: Double?) -> Double? {
        guard let part, let whole, whole > 0 else { return nil }
        return part / whole
    }

    // MARK: - ACS detailed-table variable codes

    private static let medianIncome = "B19013_001E"       // Median household income
    private static let medianAge = "B01002_001E"          // Median age

    private static let educationUniverse = "B15003_001E"  // Population 25 years and over
    private static let bachelors = "B15003_022E"
    private static let masters = "B15003_023E"
    private static let professional = "B15003_024E"
    private static let doctorate = "B15003_025E"

    private static let povertyUniverse = "B17001_001E"    // Pop. with poverty status determined
    private static let belowPoverty = "B17001_002E"       // Income below poverty level

    private static let laborForce = "B23025_003E"         // Civilian labor force
    private static let unemployed = "B23025_005E"         // Unemployed

    private static let variables: [String] = [
        medianIncome, medianAge,
        educationUniverse, bachelors, masters, professional, doctorate,
        povertyUniverse, belowPoverty,
        laborForce, unemployed,
    ]
}
