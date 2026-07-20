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
    }
}
