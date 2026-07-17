//
//  StatePopulationDirectory.swift
//  EagleEye
//
//  A small on-disk cache in front of `StatePopulationService`, so reopening a
//  state's detail sheet doesn't refetch its population from the Census API
//  every time — population estimates only update once a year. Mirrors
//  `DistrictPopulationDirectory`, keyed by state instead of state+district.
//

import Foundation
import Observation

@MainActor
@Observable
final class StatePopulationDirectory {
    private var cache: [String: Int]
    private let service: StatePopulationService

    init(service: StatePopulationService = StatePopulationService()) {
        self.service = service
        self.cache = Self.loadCache()
    }

    /// The cached population for a state, if it's already been fetched this
    /// app session or a previous one.
    func cachedPopulation(state: String) -> Int? {
        cache[state]
    }

    /// Fetches and caches a state's population, if not already on file.
    /// Leaves the cache untouched on failure (e.g. offline, or a territory
    /// with no ACS state-level data).
    func loadIfNeeded(state: String) async {
        guard cache[state] == nil else { return }
        guard let population = try? await service.population(state: state) else { return }
        cache[state] = population
        Self.saveCache(cache)
    }

    // MARK: - Cache

    private static let cacheKey = "cachedStatePopulations"

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
