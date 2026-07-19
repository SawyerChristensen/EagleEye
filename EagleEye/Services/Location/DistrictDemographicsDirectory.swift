//
//  DistrictDemographicsDirectory.swift
//  EagleEye
//
//  A small on-disk cache in front of `DistrictDemographicsService`, so
//  reopening a district's detail sheet doesn't refetch its demographics from
//  the Census API every time — the underlying estimates only update once a
//  year. Mirrors `DistrictIndustryDirectory`, keyed by state and district.
//

import Foundation
import Observation

@MainActor
@Observable
final class DistrictDemographicsDirectory {
    private var cache: [String: DistrictDemographics]
    private let service: DistrictDemographicsService

    init(service: DistrictDemographicsService = DistrictDemographicsService()) {
        self.service = service
        self.cache = Self.loadCache()
    }

    /// The cached demographics for a district, if already fetched this app
    /// session or a previous one.
    func cachedDemographics(state: String, district: Int) -> DistrictDemographics? {
        cache[key(state: state, district: district)]
    }

    /// Fetches and caches a district's demographics, if not already on file.
    /// Leaves the cache untouched on failure (e.g. offline, or a territory
    /// with no ACS congressional-district data).
    func loadIfNeeded(state: String, district: Int) async {
        let key = key(state: state, district: district)
        guard cache[key] == nil else { return }
        guard let demographics = try? await service.demographics(state: state, district: district) else { return }
        cache[key] = demographics
        Self.saveCache(cache)
    }

    private func key(state: String, district: Int) -> String {
        "\(state)-\(district)"
    }

    // MARK: - Cache

    private static let cacheKey = "cachedDistrictDemographics"

    private static func saveCache(_ cache: [String: DistrictDemographics]) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private static func loadCache() -> [String: DistrictDemographics] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode([String: DistrictDemographics].self, from: data)
        else { return [:] }
        return cache
    }
}
