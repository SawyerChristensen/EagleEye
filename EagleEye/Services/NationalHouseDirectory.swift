//
//  NationalHouseDirectory.swift
//  EagleEye
//
//  Loads every current U.S. House member nationwide, independent of the
//  user's own delegation, so the district map can fill in every congressional
//  district with its representative's party color and show that district's
//  own representative when tapped — not just the user's home district.
//

import Foundation
import Observation

@MainActor
@Observable
final class NationalHouseDirectory {
    private(set) var members: [Representative] = []

    private let service: CongressService

    init(service: CongressService = CongressService()) {
        self.service = service
        if let cached = Self.loadCache() {
            members = cached
        }
    }

    /// Fetches every current House member nationwide, once per app session —
    /// the roster doesn't change often enough to warrant refetching every
    /// time the map appears. Leaves any cached roster in place on failure
    /// (e.g. no API key configured).
    func loadIfNeeded() async {
        guard members.isEmpty else { return }
        guard let fetched = try? await service.allCurrentHouseMembers(), !fetched.isEmpty else { return }
        members = fetched
        Self.saveCache(fetched)
    }

    // MARK: - Cache

    private static let cacheKey = "cachedNationalHouseMembers"

    /// Persists the roster on disk so it's available immediately (and offline)
    /// on the next launch, without waiting on a fresh fetch.
    private static func saveCache(_ members: [Representative]) {
        if let data = try? JSONEncoder().encode(members) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private static func loadCache() -> [Representative]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode([Representative].self, from: data)
    }
}
