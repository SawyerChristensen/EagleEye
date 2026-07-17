//
//  DistrictCityService.swift
//  EagleEye
//
//  Looks up a state's incorporated places and census-designated places
//  (cities/towns) along with their latest population estimate, so a
//  district's top cities can be found by locally filtering to whichever
//  places fall inside its boundary.
//
//  Unlike `DistrictPopulationService`/`DistrictIndustryService`, this avoids
//  the Census ACS Data API (`api.census.gov`) entirely — as of this writing
//  it redirects every request, including theirs, to a "missing API key"
//  page. Place geometry comes from TIGERweb (`tigerweb.geo.census.gov`) and
//  population from the Population Estimates Program's per-state bulk file
//  (`www2.census.gov`), both free, keyless, unauthenticated endpoints.
//

import Foundation
import CoreLocation

struct DistrictCityService {
    struct Place {
        let name: String
        let population: Int
        let coordinate: CLLocationCoordinate2D
    }

    enum ServiceError: LocalizedError {
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .badResponse(let code):
                "The Census server returned HTTP \(code)."
            }
        }
    }

    var session: URLSession = .shared

    /// Every incorporated place and census-designated place in a state, with
    /// its latest population estimate and centroid coordinate — or `nil` if
    /// the state has no FIPS code on file (the territories).
    func places(state: String) async throws -> [Place]? {
        guard let fips = CensusStateFIPS.byPostalCode[state] else { return nil }

        async let geometry = placeGeometry(fips: fips)
        async let population = placePopulation(fips: fips)
        let (geometryByPlace, populationByPlace) = try await (geometry, population)

        return geometryByPlace.compactMap { placeID, entry -> Place? in
            guard let population = populationByPlace[placeID], population > 0 else { return nil }
            return Place(name: entry.name, population: population, coordinate: entry.coordinate)
        }
    }

    // MARK: - TIGERweb geometry

    private struct GeometryEntry {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    private struct TIGERwebResponse: Decodable {
        struct Feature: Decodable {
            struct Attributes: Decodable {
                let NAME: String
                let PLACE: String
                let CENTLAT: String
                let CENTLON: String
            }
            let attributes: Attributes
        }
        let features: [Feature]
    }

    /// Names and centroid coordinates of every place in a state, keyed by
    /// 5-digit place FIPS code. Queries both the "Incorporated Places" and
    /// "Census Designated Places" layers, since a state's largest cities can
    /// be either.
    private func placeGeometry(fips: String) async throws -> [String: GeometryEntry] {
        var entries: [String: GeometryEntry] = [:]
        for layer in [4, 5] {
            var components = URLComponents(
                string: "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/Places_CouSub_ConCity_SubMCD/MapServer/\(layer)/query"
            )!
            components.queryItems = [
                URLQueryItem(name: "where", value: "STATE='\(fips)'"),
                URLQueryItem(name: "outFields", value: "NAME,PLACE,CENTLAT,CENTLON"),
                URLQueryItem(name: "returnGeometry", value: "false"),
                URLQueryItem(name: "f", value: "json"),
            ]

            let (data, response) = try await session.data(from: components.url!)
            guard let http = response as? HTTPURLResponse else {
                throw ServiceError.badResponse(-1)
            }
            guard 200..<300 ~= http.statusCode else {
                throw ServiceError.badResponse(http.statusCode)
            }

            let result = try JSONDecoder().decode(TIGERwebResponse.self, from: data)
            for feature in result.features {
                let attributes = feature.attributes
                guard let lat = Double(attributes.CENTLAT), let lon = Double(attributes.CENTLON) else { continue }
                entries[attributes.PLACE] = GeometryEntry(
                    name: Self.displayName(from: attributes.NAME),
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
            }
        }
        return entries
    }

    /// TIGERweb/PopEst names carry a legal/statistical suffix (e.g.
    /// "Springfield city", "Loyalton CDP") — strip it for plain display.
    private static func displayName(from rawName: String) -> String {
        var name = rawName
        for suffix in [" city", " town", " village", " municipality", " borough", " CDP"] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
            break
        }
        return name
    }

    // MARK: - Population Estimates Program

    /// The Population Estimates Program vintage bundled with the app — the
    /// most recent annual city/town estimates published as of this writing.
    private static let popEstYear = 2023
    private static let popEstRange = "2020-2023"

    /// Latest population estimate per place, keyed by 5-digit place FIPS
    /// code, parsed from the Population Estimates Program's per-state bulk
    /// CSV (one flat file per state, no API key required).
    private func placePopulation(fips: String) async throws -> [String: Int] {
        guard let stateNumber = Int(fips) else { return [:] }
        let url = URL(
            string: "https://www2.census.gov/programs-surveys/popest/datasets/\(Self.popEstRange)/cities/totals/sub-est\(Self.popEstYear)_\(stateNumber).csv"
        )!

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.badResponse(-1)
        }
        guard 200..<300 ~= http.statusCode else {
            throw ServiceError.badResponse(http.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8) else { return [:] }

        var populationByPlace: [String: Int] = [:]
        // Columns: SUMLEV,STATE,COUNTY,PLACE,COUSUB,CONCIT,PRIMGEO_FLAG,
        // FUNCSTAT,NAME,STNAME,ESTIMATESBASE2020,POPESTIMATE2020,
        // POPESTIMATE2021,POPESTIMATE2022,POPESTIMATE2023
        for line in text.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            // SUMLEV 162 is a place's total population, independent of
            // county lines — the row we want, rather than the per-county
            // slices of a place that straddles a county boundary.
            guard fields.count >= 15, fields[0] == "162" else { continue }
            guard let population = Int(fields[14]) else { continue }
            populationByPlace[String(fields[3])] = population
        }
        return populationByPlace
    }
}
