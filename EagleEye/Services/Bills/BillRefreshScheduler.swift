//
//  BillRefreshScheduler.swift
//  EagleEye
//
//  Drives background refresh of the bill feed so bookmarked bills and newly
//  enacted laws are noticed — and their notifications fired — even while the
//  app is suspended, rather than only when the user next opens it.
//

import Foundation
import BackgroundTasks

enum BillRefreshScheduler {
    /// The background-task identifier. Must match the entry in Info.plist's
    /// `BGTaskSchedulerPermittedIdentifiers` array and the identifier passed to
    /// the `.backgroundTask(.appRefresh(_:))` scene modifier.
    static let taskIdentifier = "Sawyer.EagleEye.billRefresh"

    /// How soon the system may run the next refresh. The scheduler treats this
    /// as a floor, not a promise — iOS chooses the actual time based on usage
    /// patterns and power, typically no more than a few times a day.
    private static let refreshInterval: TimeInterval = 4 * 60 * 60 // ~4 hours

    /// Asks the system to schedule the next background refresh. Called when the
    /// app moves to the background and again at the end of each background run,
    /// so there's always a pending request. Submitting fails on Simulator and
    /// when the user has disabled Background App Refresh — both are harmless.
    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The work performed when the system grants a background refresh: reload the
    /// feed, then run the same change-detection the foreground refresh does.
    /// Fresh stores are created here because the app isn't necessarily running;
    /// all state lives in UserDefaults, so a throwaway instance sees exactly what
    /// the live one would. Reschedules first so a crash mid-run still leaves a
    /// pending request behind.
    @MainActor
    static func handleAppRefresh() async {
        scheduleAppRefresh()

        let billsStore = BillsStore()
        let bookmarksStore = BookmarksStore()
        let enactedLawsNotifier = EnactedLawsNotifier()

        await billsStore.load()
        await bookmarksStore.refresh(feedBills: billsStore.bills)
        enactedLawsNotifier.checkForNewlyEnacted(in: billsStore.bills)
    }
}
