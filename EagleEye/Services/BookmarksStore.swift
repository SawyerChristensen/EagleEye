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

    init() {
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

    /// Compares freshly fetched bills against the last known status of each
    /// bookmarked bill and fires a local notification for anything that changed.
    func checkForUpdates(in bills: [Bill]) {
        guard !bookmarkedKeys.isEmpty else { return }
        for bill in bills {
            guard let key = bill.stableKey, bookmarkedKeys.contains(key) else { continue }
            let current = Self.snapshot(for: bill)
            if let previous = lastKnownSnapshots[key], previous != current {
                notify(about: bill)
            }
            lastKnownSnapshots[key] = current
        }
        Self.saveSnapshots(lastKnownSnapshots)
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
