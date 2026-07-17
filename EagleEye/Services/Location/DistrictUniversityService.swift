//
//  DistrictUniversityService.swift
//  EagleEye
//
//  Looks up a state's degree-granting four-year-and-above colleges and
//  universities along with their latest fall enrollment, so a district's top
//  universities can be found by locally filtering to whichever campuses fall
//  inside its boundary. Data comes from the Urban Institute's Education Data
//  Portal (`educationdata.urban.org`), a free, keyless API that republishes
//  the Department of Education's IPEDS institution directory and enrollment
//  surveys — including each institution's coordinates, so no separate
//  geometry lookup is needed the way `DistrictCityService` needs TIGERweb.
//

import Foundation
import CoreLocation

struct DistrictUniversityService {
    struct University {
        let name: String
        let enrollment: Int
        let coordinate: CLLocationCoordinate2D
    }

    enum ServiceError: LocalizedError {
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .badResponse(let code):
                "The Urban Institute server returned HTTP \(code)."
            }
        }
    }

    var session: URLSession = .shared

    /// The most recent IPEDS vintage with fall enrollment published on the
    /// Education Data Portal as of this writing.
    private static let year = 2021

    /// Every active, degree-granting four-year-and-above institution in a
    /// state, with its latest fall enrollment and coordinate — or `nil` if
    /// the state has no FIPS code on file (the territories).
    func universities(state: String) async throws -> [University]? {
        guard let fips = CensusStateFIPS.byPostalCode[state] else { return nil }

        async let directory = fetchDirectory(fips: fips)
        async let enrollment = fetchEnrollment(fips: fips)
        let (institutions, enrollmentByID) = try await (directory, enrollment)

        return institutions.compactMap { institution -> University? in
            guard let enrollment = enrollmentByID[institution.unitID], enrollment > 0 else { return nil }
            return University(name: institution.name, enrollment: enrollment, coordinate: institution.coordinate)
        }
    }

    // MARK: - IPEDS directory

    private struct Institution {
        let unitID: Int
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    private struct DirectoryResponse: Decodable {
        struct Result: Decodable {
            let unitid: Int
            let inst_name: String
            let latitude: Double?
            let longitude: Double?
            let currently_active_ipeds: Int
            let degree_granting: Int
            let institution_level: Int
        }
        let results: [Result]
    }

    /// Names and coordinates of every currently-active, degree-granting
    /// four-year-and-above institution in a state, keyed by IPEDS unit ID.
    /// `institution_level == 4` is IPEDS' code for "at least four years" —
    /// it excludes community colleges and sub-baccalaureate trade schools,
    /// which would otherwise crowd out actual universities by headcount.
    private func fetchDirectory(fips: String) async throws -> [Institution] {
        var components = URLComponents(
            string: "https://educationdata.urban.org/api/v1/college-university/ipeds/directory/\(Self.year)/"
        )!
        components.queryItems = [
            URLQueryItem(name: "fips", value: fips),
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.badResponse(-1)
        }
        guard 200..<300 ~= http.statusCode else {
            throw ServiceError.badResponse(http.statusCode)
        }

        let result = try JSONDecoder().decode(DirectoryResponse.self, from: data)
        return result.results.compactMap { row -> Institution? in
            guard row.currently_active_ipeds == 1, row.degree_granting == 1, row.institution_level == 4 else { return nil }
            guard let latitude = row.latitude, let longitude = row.longitude else { return nil }
            return Institution(
                unitID: row.unitid,
                name: row.inst_name,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            )
        }
    }

    // MARK: - IPEDS fall enrollment

    private struct EnrollmentResponse: Decodable {
        struct Result: Decodable {
            let unitid: Int
            let level_of_study: Int
            let est_fte: Int?
        }
        let results: [Result]
    }

    /// Total fall full-time-equivalent enrollment per institution, keyed by
    /// IPEDS unit ID, summed across undergraduate (`level_of_study == 1`) and
    /// graduate (`== 2`) — `race=99&sex=99` selects the all-races, all-sexes
    /// total row rather than one row per demographic breakdown.
    private func fetchEnrollment(fips: String) async throws -> [Int: Int] {
        var components = URLComponents(
            string: "https://educationdata.urban.org/api/v1/college-university/ipeds/fall-enrollment/\(Self.year)/"
        )!
        components.queryItems = [
            URLQueryItem(name: "fips", value: fips),
            URLQueryItem(name: "race", value: "99"),
            URLQueryItem(name: "sex", value: "99"),
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.badResponse(-1)
        }
        guard 200..<300 ~= http.statusCode else {
            throw ServiceError.badResponse(http.statusCode)
        }

        let result = try JSONDecoder().decode(EnrollmentResponse.self, from: data)
        var enrollmentByID: [Int: Int] = [:]
        for row in result.results where row.level_of_study == 1 || row.level_of_study == 2 {
            enrollmentByID[row.unitid, default: 0] += row.est_fte ?? 0
        }
        return enrollmentByID
    }
}
