//
//  StateIndustryDirectory.swift
//  EagleEye
//
//  A small on-disk cache in front of `StateIndustryService`, so reopening a
//  state's detail sheet doesn't refetch its top industries from the Census
//  API every time. Mirrors `DistrictIndustryDirectory`, keyed by state
//  instead of state+district.
//

import Foundation
import Observation

@MainActor
@Observable
final class StateIndustryDirectory {
    private var cache: [String: [String]]
    private let service: StateIndustryService

    init(service: StateIndustryService = StateIndustryService()) {
        self.service = service
        self.cache = Self.loadCache()
    }

    /// The cached top industries for a state, if it's already been fetched
    /// this app session or a previous one.
    func cachedTopIndustries(state: String) -> [String]? {
        cache[state]
    }

    /// Fetches and caches a state's top industries, if not already on file.
    /// Leaves the cache untouched on failure (e.g. offline, or a territory
    /// with no ACS state-level data).
    func loadIfNeeded(state: String) async {
        guard cache[state] == nil else { return }
        guard let industries = try? await service.topIndustries(state: state) else { return }
        cache[state] = industries
        Self.saveCache(cache)
    }

    // MARK: - Cache

    private static let cacheKey = "cachedStateIndustries"

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
