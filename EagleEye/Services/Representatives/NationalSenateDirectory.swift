//
//  NationalSenateDirectory.swift
//  EagleEye
//
//  Loads every current U.S. Senator nationwide, independent of the user's own
//  delegation, so the district map's state-level sheet can show a tapped
//  state's two senators — not just the user's own. Mirrors
//  `NationalHouseDirectory`.
//

import Foundation
import Observation

@MainActor
@Observable
final class NationalSenateDirectory {
    private(set) var members: [Representative] = []

    private let service: CongressService

    init(service: CongressService = CongressService()) {
        self.service = service
    }

    /// Fetches every current senator nationwide, once per app session — the
    /// roster doesn't change often enough to warrant refetching every time
    /// the map appears. Leaves any cached roster in place on failure (e.g. no
    /// API key configured).
    func loadIfNeeded() async {
        guard members.isEmpty else { return }
        // Surface the persisted roster first (decoded off the main thread),
        // then refresh from the API.
        if let cached = await Self.loadCacheOffMain() { members = cached }
        guard let fetched = try? await service.allCurrentSenateMembers(), !fetched.isEmpty else { return }
        members = fetched
        Self.saveCache(fetched)
    }

    /// The (up to) two senators representing a state, identified by its
    /// two-letter postal code (e.g. "CA"), ordered most senior first.
    func senators(forState state: String) -> [Representative] {
        members
            .filter { $0.state == state }
            .sorted { $0.tenureStart < $1.tenureStart }
    }

    // MARK: - Cache

    nonisolated private static let cacheKey = "cachedNationalSenateMembers"

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

    /// Decodes the cached roster on a background task so the JSON parse never
    /// blocks the main thread during launch prefetch.
    private static func loadCacheOffMain() async -> [Representative]? {
        await Task.detached(priority: .utility) { loadCache() }.value
    }
}
