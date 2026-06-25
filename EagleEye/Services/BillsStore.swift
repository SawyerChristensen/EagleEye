//
//  BillsStore.swift
//  EagleEye
//
//  Loads and holds the home feed of bills moving through Congress.
//

import Foundation
import Observation

/// Owns the list of bills shown in the home feed. It loads the most recently
/// active legislation from the Congress.gov API, falling back to bundled sample
/// data when no API key is configured so the feed still has something to show.
///
/// The last successful fetch is cached on disk, so the feed appears instantly on
/// the next launch and then refreshes quietly in the background.
@MainActor
@Observable
final class BillsStore {
    /// Where the store is in its load flow.
    enum LoadState: Equatable {
        /// Fetching bills with nothing yet to show.
        case loading
        /// Bills (or sample data) are ready to show.
        case ready
    }

    private(set) var bills: [Bill] = []
    private(set) var loadState: LoadState = .loading
    /// A user-facing note when live data could not be loaded (e.g. no API key).
    private(set) var statusMessage: String?

    private let service: CongressService

    init(service: CongressService = CongressService()) {
        self.service = service

        // Show the last fetch immediately while a fresh one loads in the background.
        if let cached = Self.loadCache(), !cached.isEmpty {
            bills = cached
            loadState = .ready
        }
    }

    /// Loads the latest bills from the API. Keeps any cached bills visible while
    /// the request runs, and falls back to sample data only when there's nothing
    /// else to show.
    func load() async {
        if bills.isEmpty {
            loadState = .loading
            statusMessage = nil
        }

        do {
            let fetched = try await service.recentBills()
            if !fetched.isEmpty {
                bills = fetched
                Self.saveCache(fetched)
            }
            loadState = .ready
        } catch CongressService.ServiceError.missingAPIKey {
            if bills.isEmpty {
                bills = SampleData.bills
                statusMessage = "Showing sample data — add a Congress.gov API key to load live bills."
            }
            loadState = .ready
        } catch {
            if bills.isEmpty {
                bills = SampleData.bills
                statusMessage = error.localizedDescription
            }
            loadState = .ready
        }
    }

    // MARK: - Cache

    private static let cacheKey = "cachedBills"

    private static func saveCache(_ bills: [Bill]) {
        if let data = try? JSONEncoder().encode(bills) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private static func loadCache() -> [Bill]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode([Bill].self, from: data)
    }
}
