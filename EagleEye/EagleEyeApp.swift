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
        // Pass "-ResetAppState" as a launch argument (Scheme → Run → Arguments)
        // to wipe the cached delegation and bills on launch, so the app starts
        // fresh at the location prompt. Location *permission* is an OS setting
        // that can't be reset here — use Simulator "Reset Location & Privacy"
        // (or delete the app) alongside this for a fully clean launch.
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
