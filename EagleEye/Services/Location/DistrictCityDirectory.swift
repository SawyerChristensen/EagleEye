//
//  DistrictCityDirectory.swift
//  EagleEye
//
//  A small on-disk cache in front of `DistrictCityService`, so reopening a
//  district's detail sheet doesn't refetch and re-filter its top cities from
//  the Census servers every time. A state's full place list is also kept
//  in-memory for the rest of the app session, since every district within a
//  state shares the same underlying places.
//

import Foundation
import Observation

@MainActor
@Observable
final class DistrictCityDirectory {
    private var cache: [String: [String]]
    private var placesByState: [String: [DistrictCityService.Place]] = [:]
    private let service: DistrictCityService

    init(service: DistrictCityService = DistrictCityService()) {
        self.service = service
        self.cache = Self.loadCache()
    }

    /// The cached top cities for a district, if it's already been fetched
    /// this app session or a previous one.
    func cachedTopCities(state: String, district: Int) -> [String]? {
        cache[key(state: state, district: district)]
    }

    /// Fetches and caches a district's most populous cities/towns, if not
    /// already on file. Leaves the cache untouched on failure (e.g. offline,
    /// or a territory with no place data on file).
    func loadIfNeeded(boundary: MapBoundary, limit: Int = 4) async {
        let state = boundary.state
        let district = boundary.district ?? 0
        let key = key(state: state, district: district)
        guard cache[key] == nil else { return }

        let places: [DistrictCityService.Place]
        if let cached = placesByState[state] {
            places = cached
        } else {
            guard let fetched = try? await service.places(state: state) else { return }
            placesByState[state] = fetched
            places = fetched
        }

        let topCities = places
            .filter { boundary.contains($0.coordinate) }
            .sorted { $0.population > $1.population }
            .prefix(limit)
            .map { "\($0.name) — \(Self.populationFormatter.string(from: NSNumber(value: $0.population)) ?? "\($0.population)")" }

        cache[key] = topCities
        Self.saveCache(cache)
    }

    private func key(state: String, district: Int) -> String {
        "\(state)-\(district)"
    }

    private static let populationFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    // MARK: - Cache

    private static let cacheKey = "cachedDistrictCities"

    private static func saveCache(_ cache: [String: [String]]) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private static func loadCache() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return cache
    }
}
