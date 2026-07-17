//
//  StateCityDirectory.swift
//  EagleEye
//
//  A small on-disk cache in front of `DistrictCityService`, so reopening a
//  state's detail sheet doesn't refetch its top cities from the Census
//  servers every time. `DistrictCityService.places(state:)` already fetches
//  every place in the state, so unlike `DistrictCityDirectory` there's no
//  district boundary to filter to — just the state's most populous places.
//

import Foundation
import Observation

@MainActor
@Observable
final class StateCityDirectory {
    private var cache: [String: [String]]
    private let service: DistrictCityService

    init(service: DistrictCityService = DistrictCityService()) {
        self.service = service
        self.cache = Self.loadCache()
    }

    /// The cached top cities for a state, if it's already been fetched this
    /// app session or a previous one.
    func cachedTopCities(state: String) -> [String]? {
        cache[state]
    }

    /// Fetches and caches a state's most populous cities/towns, if not
    /// already on file. Leaves the cache untouched on failure (e.g. offline,
    /// or a territory with no place data on file).
    func loadIfNeeded(state: String, limit: Int = 4) async {
        guard cache[state] == nil else { return }
        guard let places = try? await service.places(state: state) else { return }

        let topCities = places
            .sorted { $0.population > $1.population }
            .prefix(limit)
            .map { "\($0.name) — \(Self.populationFormatter.string(from: NSNumber(value: $0.population)) ?? "\($0.population)")" }

        cache[state] = topCities
        Self.saveCache(cache)
    }

    private static let populationFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    // MARK: - Cache

    private static let cacheKey = "cachedStateCities"

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
