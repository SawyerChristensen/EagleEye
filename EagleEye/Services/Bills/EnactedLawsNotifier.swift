//
//  EnactedLawsNotifier.swift
//  EagleEye
//
//  Fires a local notification the moment any bill in the home feed newly
//  reaches "Enacted" status, so users learn about new laws without having to
//  bookmark every bill up front. Complements BookmarksStore, which only
//  covers bills the user chose to follow.
//

import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class EnactedLawsNotifier {
    /// The status last recorded for each bill this notifier has seen, keyed by
    /// `Bill.stableKey`, so a later refresh can tell whether it just became
    /// enacted. A bill's first sighting only records its status and never
    /// fires a notification, so laws already enacted before the app noticed
    /// them (e.g. right after install, or paged in via "load more") don't
    /// flood the user with backlog.
    private var lastKnownStatuses: [String: BillStatus]

    init() {
        lastKnownStatuses = Self.loadStatuses()
    }

    /// Compares freshly fetched bills against their last known status and
    /// notifies about any that transitioned to "Enacted" since the previous
    /// refresh.
    func checkForNewlyEnacted(in bills: [Bill]) {
        var newlyEnacted: [Bill] = []
        for bill in bills {
            guard let key = bill.stableKey else { continue }
            if let previous = lastKnownStatuses[key], previous != .enacted, bill.status == .enacted {
                newlyEnacted.append(bill)
            }
            lastKnownStatuses[key] = bill.status
        }
        Self.saveStatuses(lastKnownStatuses)

        guard !newlyEnacted.isEmpty else { return }
        requestNotificationAuthorizationIfNeeded()
        newlyEnacted.forEach(notify(about:))
    }

    private func requestNotificationAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func notify(about bill: Bill) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "New Law", comment: "Local notification title when a bill in the feed is signed into law.")
        content.body = bill.displayName
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Persistence

    private static let statusesKey = "enactedNotifierBillStatuses"

    private static func loadStatuses() -> [String: BillStatus] {
        guard let raw = UserDefaults.standard.dictionary(forKey: statusesKey) as? [String: String] else { return [:] }
        return raw.compactMapValues(BillStatus.init(rawValue:))
    }

    private static func saveStatuses(_ statuses: [String: BillStatus]) {
        UserDefaults.standard.set(statuses.mapValues(\.rawValue), forKey: statusesKey)
    }
}
