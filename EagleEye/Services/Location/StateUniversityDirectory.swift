//
//  StateUniversityDirectory.swift
//  EagleEye
//
//  A small on-disk cache in front of `DistrictUniversityService`, so
//  reopening a state's detail sheet doesn't refetch its top universities from
//  the Education Data Portal every time. `DistrictUniversityService.universities(state:)`
//  already fetches every institution in the state, so unlike
//  `DistrictUniversityDirectory` there's no district boundary to filter to —
//  just the state's highest-enrollment institutions.
//

import Foundation
import Observation

@MainActor
@Observable
final class StateUniversityDirectory {
    private var cache: [String: [String]]
    private let service: DistrictUniversityService

    init(service: DistrictUniversityService = DistrictUniversityService()) {
        self.service = service
        self.cache = Self.loadCache()
    }

    /// The cached top universities for a state, if it's already been fetched
    /// this app session or a previous one.
    func cachedTopUniversities(state: String) -> [String]? {
        cache[state]
    }

    /// Fetches and caches a state's highest-enrollment universities, if not
    /// already on file. Leaves the cache untouched on failure (e.g. offline,
    /// or a territory with no institution data on file).
    func loadIfNeeded(state: String, limit: Int = 4) async {
        guard cache[state] == nil else { return }
        guard let universities = try? await service.universities(state: state) else { return }

        let topUniversities = universities
            .sorted { $0.enrollment > $1.enrollment }
            .prefix(limit)
            .map { "\($0.name) — \(Self.enrollmentFormatter.string(from: NSNumber(value: $0.enrollment)) ?? "\($0.enrollment)") students" }

        cache[state] = topUniversities
        Self.saveCache(cache)
    }

    private static let enrollmentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    // MARK: - Cache

    private static let cacheKey = "cachedStateUniversities"

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
