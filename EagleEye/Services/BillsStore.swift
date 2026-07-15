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
    /// Whether a `loadMore()` request is currently in flight.
    private(set) var isLoadingMore = false
    /// Whether scrolling to the bottom should attempt to fetch another page.
    private(set) var canLoadMore = true

    private let service: CongressService
    private let pageSize = 20

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
        }
        // Start each attempt clean; the branches below re-raise a message if the
        // refresh doesn't actually replace the feed.
        statusMessage = nil
        canLoadMore = true

        do {
            let fetched = try await service.recentBills(limit: pageSize)
            if fetched.isEmpty {
                // A successful-but-empty response must not silently overwrite a
                // good cache. If we have nothing else, fall back to samples;
                // otherwise keep the cache but say it wasn't refreshed.
                if bills.isEmpty {
                    bills = SampleData.bills.rankedByImportance()
                } else {
                    statusMessage = "Couldn't load newer bills just now — showing saved bills."
                }
            } else {
                let ranked = fetched.rankedByImportance()
                bills = ranked
                Self.saveCache(ranked)
            }
            loadState = .ready
        } catch CongressService.ServiceError.missingAPIKey {
            if bills.isEmpty {
                bills = SampleData.bills.rankedByImportance()
            }
            statusMessage = "Showing sample data — add a Congress.gov API key to load live bills."
            loadState = .ready
        } catch {
            // A failed refresh used to be swallowed whenever a cache was on
            // screen, leaving the feed silently frozen on stale bills. Surface
            // it even when we keep showing the cache so the staleness is visible.
            if bills.isEmpty {
                bills = SampleData.bills.rankedByImportance()
                statusMessage = error.localizedDescription
            } else {
                statusMessage = "Couldn't refresh — showing saved bills. (\(error.localizedDescription))"
            }
            loadState = .ready
        }
    }

    /// Fetches the next page of bills ranked just below what's already shown and
    /// appends them, for infinite-scroll as the user nears the bottom of the feed.
    func loadMore() async {
        guard !isLoadingMore, canLoadMore, loadState == .ready else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let fetched = try await service.recentBills(limit: pageSize, offset: bills.count)
            if fetched.isEmpty {
                canLoadMore = false
                return
            }
            let existingIDs = Set(bills.map(\.id))
            let newBills = fetched.filter { !existingIDs.contains($0.id) }
            bills.append(contentsOf: newBills)
            Self.saveCache(bills)
            if fetched.count < pageSize {
                canLoadMore = false
            }
        } catch {
            // No more pages worth trying this session (e.g. no API key, or the
            // ranked pool is exhausted) — fail quietly since the feed already
            // has bills on screen.
            canLoadMore = false
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
