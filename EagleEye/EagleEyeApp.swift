//
//  EagleEyeApp.swift
//  EagleEye
//
//  Created by Sawyer Christensen on 6/23/26.
//

import SwiftUI

@main
struct EagleEyeApp: App {
    init() {
        #if DEBUG
        // Force the onboarding to show up every time we build the app
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        
        if ProcessInfo.processInfo.arguments.contains("-ResetAppState"),
           let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Refresh the feed in the background so bookmarked-bill and new-law
        // notifications fire even while the app is suspended. iOS registers the
        // handler for this identifier automatically; ContentView submits the
        // requests as the app backgrounds.
        .backgroundTask(.appRefresh(BillRefreshScheduler.taskIdentifier)) {
            await BillRefreshScheduler.handleAppRefresh()
        }
    }
}
