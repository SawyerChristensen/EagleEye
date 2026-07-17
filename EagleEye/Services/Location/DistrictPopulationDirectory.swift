//
//  DistrictPopulationDirectory.swift
//  EagleEye
//
//  A small on-disk cache in front of `DistrictPopulationService`, so
//  reopening a district's detail sheet doesn't refetch its population from
//  the Census API every time — population estimates only update once a year.
//

import Foundation
import Observation

@MainActor
@Observable
final class DistrictPopulationDirectory {
    private var cache: [String: Int]
    private let service: DistrictPopulationService

    init(service: DistrictPopulationService = DistrictPopulationService()) {
        self.service = service
        self.cache = Self.loadCache()
    }

    /// The cached population for a district, if it's already been fetched
    /// this app session or a previous one.
    func cachedPopulation(state: String, district: Int) -> Int? {
        cache[key(state: state, district: district)]
    }

    /// Fetches and caches a district's population, if not already on file.
    /// Leaves the cache untouched on failure (e.g. offline, or a territory
    /// with no ACS congressional-district data).
    func loadIfNeeded(state: String, district: Int) async {
        let key = key(state: state, district: district)
        guard cache[key] == nil else { return }
        guard let population = try? await service.population(state: state, district: district) else { return }
        cache[key] = population
        Self.saveCache(cache)
    }

    private func key(state: String, district: Int) -> String {
        "\(state)-\(district)"
    }

    // MARK: - Cache

    private static let cacheKey = "cachedDistrictPopulations"

    private static func saveCache(_ cache: [String: Int]) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private static func loadCache() -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return cache
    }
}
