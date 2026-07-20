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
    }

    /// All current House members representing a given state, sorted by
    /// district number.
    func representatives(forState state: String) -> [Representative] {
        members
            .filter { $0.state == state }
            .sorted { ($0.district ?? 0) < ($1.district ?? 0) }
    }

    /// Fetches every current House member nationwide, once per app session —
    /// the roster doesn't change often enough to warrant refetching every
    /// time the map appears. Leaves any cached roster in place on failure
    /// (e.g. no API key configured).
    func loadIfNeeded() async {
        guard members.isEmpty else { return }
        // Surface the persisted roster first (decoded off the main thread) so
        // the map has party colors immediately, then refresh from the API.
        if let cached = await Self.loadCacheOffMain() { members = cached }
        guard let fetched = try? await service.allCurrentHouseMembers(), !fetched.isEmpty else { return }
        members = fetched
        Self.saveCache(fetched)
    }

    // MARK: - Cache

    nonisolated private static let cacheKey = "cachedNationalHouseMembers"

    /// Persists the roster on disk so it's available immediately (and offline)
    /// on the next launch, without waiting on a fresh fetch.
    private static func saveCache(_ members: [Representative]) {
        if let data = try? JSONEncoder().encode(members) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    nonisolated private static func loadCache() -> [Representative]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode([Representative].self, from: data)
    }

    /// Decodes the cached roster on a background task so the ~435-member JSON
    /// parse never blocks the main thread during launch prefetch.
    private static func loadCacheOffMain() async -> [Representative]? {
        await Task.detached(priority: .utility) { loadCache() }.value
    }
}
