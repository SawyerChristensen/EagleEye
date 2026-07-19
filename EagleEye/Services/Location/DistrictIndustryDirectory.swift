//
//  DistrictIndustryDirectory.swift
//  EagleEye
//
//  A small on-disk cache in front of `DistrictIndustryService`, so reopening
//  a district's detail sheet doesn't refetch its top industries from the
//  Census API every time — the underlying estimates only update once a year.
//

import Foundation
import Observation

@MainActor
@Observable
final class DistrictIndustryDirectory {
    private var cache: [String: [IndustryShare]]
    private let service: DistrictIndustryService

    init(service: DistrictIndustryService = DistrictIndustryService()) {
        self.service = service
        self.cache = Self.loadCache()
    }

    /// The cached top industries for a district, if it's already been
    /// fetched this app session or a previous one.
    func cachedTopIndustries(state: String, district: Int) -> [IndustryShare]? {
        cache[key(state: state, district: district)]
    }

    /// Fetches and caches a district's top industries, if not already on
    /// file. Leaves the cache untouched on failure (e.g. offline, or a
    /// territory with no ACS congressional-district data).
    func loadIfNeeded(state: String, district: Int) async {
        let key = key(state: state, district: district)
        guard cache[key] == nil else { return }
        guard let industries = try? await service.topIndustries(state: state, district: district) else { return }
        cache[key] = industries
        Self.saveCache(cache)
    }

    private func key(state: String, district: Int) -> String {
        "\(state)-\(district)"
    }

    // MARK: - Cache

    // Bumped to `…V2` when the cached shape changed from `[String]` labels to
    // `[IndustryShare]`; the old key's data is simply ignored and refetched.
    private static let cacheKey = "cachedDistrictIndustriesV2"

    private static func saveCache(_ cache: [String: [IndustryShare]]) {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private static func loadCache() -> [String: [IndustryShare]] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode([String: [IndustryShare]].self, from: data)
        else { return [:] }
        return cache
    }
}
