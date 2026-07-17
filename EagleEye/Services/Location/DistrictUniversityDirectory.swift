//
//  DistrictUniversityDirectory.swift
//  EagleEye
//
//  A small on-disk cache in front of `DistrictUniversityService`, so
//  reopening a district's detail sheet doesn't refetch and re-filter its top
//  universities from the Education Data Portal every time. A state's full
//  institution list is also kept in-memory for the rest of the app session,
//  since every district within a state shares the same underlying campuses.
//

import Foundation
import Observation

@MainActor
@Observable
final class DistrictUniversityDirectory {
    private var cache: [String: [String]]
    private var universitiesByState: [String: [DistrictUniversityService.University]] = [:]
    private let service: DistrictUniversityService

    init(service: DistrictUniversityService = DistrictUniversityService()) {
        self.service = service
        self.cache = Self.loadCache()
    }

    /// The cached top universities for a district, if it's already been
    /// fetched this app session or a previous one.
    func cachedTopUniversities(state: String, district: Int) -> [String]? {
        cache[key(state: state, district: district)]
    }

    /// Fetches and caches a district's most populous universities, if not
    /// already on file. Leaves the cache untouched on failure (e.g. offline,
    /// or a territory with no institution data on file).
    func loadIfNeeded(boundary: MapBoundary, limit: Int = 4) async {
        let state = boundary.state
        let district = boundary.district ?? 0
        let key = key(state: state, district: district)
        guard cache[key] == nil else { return }

        let universities: [DistrictUniversityService.University]
        if let cached = universitiesByState[state] {
            universities = cached
        } else {
            guard let fetched = try? await service.universities(state: state) else { return }
            universitiesByState[state] = fetched
            universities = fetched
        }

        let topUniversities = universities
            .filter { boundary.contains($0.coordinate) }
            .sorted { $0.enrollment > $1.enrollment }
            .prefix(limit)
            .map { "\($0.name) — \(Self.enrollmentFormatter.string(from: NSNumber(value: $0.enrollment)) ?? "\($0.enrollment)") students" }

        cache[key] = topUniversities
        Self.saveCache(cache)
    }

    private func key(state: String, district: Int) -> String {
        "\(state)-\(district)"
    }

    private static let enrollmentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    // MARK: - Cache

    private static let cacheKey = "cachedDistrictUniversities"

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
