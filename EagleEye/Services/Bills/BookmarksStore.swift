//
//  BookmarksStore.swift
//  EagleEye
//
//  Tracks bills the user has bookmarked, and fires a local notification when a
//  bookmarked bill's status changes between refreshes (e.g. it clears a
//  chamber, is defeated, or is enacted).
//

import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class BookmarksStore {
    private(set) var bookmarkedKeys: Set<String> = []

    /// The status snapshot recorded the last time each bookmarked bill was seen,
    /// keyed by `Bill.stableKey`, so a later refresh can tell whether it changed.
    private var lastKnownSnapshots: [String: String] = [:]

    /// Used to re-fetch bookmarked bills that have dropped out of the recent feed.
    private let service: CongressService

    init(service: CongressService = CongressService()) {
        self.service = service
        bookmarkedKeys = Self.loadBookmarks()
        lastKnownSnapshots = Self.loadSnapshots()
    }

    func isBookmarked(_ bill: Bill) -> Bool {
        guard let key = bill.stableKey else { return false }
        return bookmarkedKeys.contains(key)
    }

    /// Toggles the bookmark for a bill, requesting notification permission the
    /// first time the user bookmarks anything.
    func toggleBookmark(for bill: Bill) {
        guard let key = bill.stableKey else { return }
        if bookmarkedKeys.contains(key) {
            bookmarkedKeys.remove(key)
            lastKnownSnapshots.removeValue(forKey: key)
        } else {
            bookmarkedKeys.insert(key)
            // Record the bill's current standing so the next refresh only
            // notifies about changes that happen *after* bookmarking it.
            lastKnownSnapshots[key] = Self.snapshot(for: bill)
            requestNotificationAuthorizationIfNeeded()
        }
        Self.saveBookmarks(bookmarkedKeys)
        Self.saveSnapshots(lastKnownSnapshots)
    }

    /// Brings every bookmarked bill up to date and notifies about any that
    /// changed. Bills still present in the recent feed are read straight from
    /// `feedBills`; bookmarks that have since dropped out of the feed are fetched
    /// individually by identifier, so tracking never goes stale just because a
    /// bill scrolled off the top of Congress's recent-activity list. Safe to run
    /// from a background refresh — the store is entirely UserDefaults-backed.
    func refresh(feedBills: [Bill]) async {
        guard !bookmarkedKeys.isEmpty else { return }

        let feedByKey = Dictionary(
            feedBills.compactMap { bill in bill.stableKey.map { ($0, bill) } },
            uniquingKeysWith: { first, _ in first }
        )

        var bills: [Bill] = []
        for key in bookmarkedKeys {
            if let inFeed = feedByKey[key] {
                bills.append(inFeed)
            } else if let reference = Self.reference(fromKey: key),
                      let fetched = await service.billDetail(for: reference) {
                bills.append(fetched)
            }
        }
        checkForUpdates(in: bills)
    }

    /// Compares freshly fetched bills against the last known status of each
    /// bookmarked bill and fires a local notification for anything that changed.
    /// Once a bookmarked bill reaches a dead end — defeated on the floor, or
    /// signed into law — its bookmark is dropped after the user is notified of
    /// the outcome, since there's no further progress left to track.
    func checkForUpdates(in bills: [Bill]) {
        guard !bookmarkedKeys.isEmpty else { return }
        var terminalKeys: [String] = []
        for bill in bills {
            guard let key = bill.stableKey, bookmarkedKeys.contains(key) else { continue }
            let current = Self.snapshot(for: bill)
            if let previous = lastKnownSnapshots[key], previous != current {
                notify(about: bill)
                if bill.failed || bill.status == .enacted {
                    terminalKeys.append(key)
                }
            }
            lastKnownSnapshots[key] = current
        }
        for key in terminalKeys {
            bookmarkedKeys.remove(key)
            lastKnownSnapshots.removeValue(forKey: key)
        }
        Self.saveSnapshots(lastKnownSnapshots)
        if !terminalKeys.isEmpty {
            Self.saveBookmarks(bookmarkedKeys)
        }
    }

    /// A comparable fingerprint of a bill's standing: its stage plus whichever
    /// chamber defeated it, if any.
    private static func snapshot(for bill: Bill) -> String {
        "\(bill.status.rawValue)|\(bill.failedChamber?.rawValue ?? "")"
    }

    private func requestNotificationAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func notify(about bill: Bill) {
        let content = UNMutableNotificationContent()
        content.title = bill.displayName
        content.body = bill.failedChamber.map {
            String(localized: "Failed in \($0.rawValue)", comment: "Local notification body for a bookmarked bill defeated on the floor of a chamber.")
        } ?? bill.status.displayLabel(chamber: bill.chamber)
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Rebuilds a `LegislationRef` from a persisted bookmark key (e.g.
    /// "119-HR-1842") so a bookmarked bill can be re-fetched by identifier.
    /// Keys always come from `Bill.stableKey`, which joins the numeric congress,
    /// the alphabetic measure type, and the numeric measure number with hyphens.
    private static func reference(fromKey key: String) -> LegislationRef? {
        let parts = key.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let congress = Int(parts[0]) else { return nil }
        return LegislationRef(
            congress: congress,
            type: String(parts[1]),
            number: String(parts[2]),
            title: ""
        )
    }

    // MARK: - Persistence

    private static let bookmarksKey = "bookmarkedBillKeys"
    private static let snapshotsKey = "bookmarkedBillSnapshots"

    private static func loadBookmarks() -> Set<String> {
        guard let array = UserDefaults.standard.array(forKey: bookmarksKey) as? [String] else { return [] }
        return Set(array)
    }

    private static func saveBookmarks(_ keys: Set<String>) {
        UserDefaults.standard.set(Array(keys), forKey: bookmarksKey)
    }

    private static func loadSnapshots() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: snapshotsKey) as? [String: String] ?? [:]
    }

    private static func saveSnapshots(_ snapshots: [String: String]) {
        UserDefaults.standard.set(snapshots, forKey: snapshotsKey)
    }
}
