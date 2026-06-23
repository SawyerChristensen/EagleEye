//
//  ContentView.swift
//  EagleEye
//
//

import SwiftUI

/// The top-level tabs of the app.
enum AppTab: Hashable {
    case representatives
    case home
    case map
}

struct ContentView: View {
    @State private var selection: AppTab = .home
    @State private var store = RepresentativesStore()

    var body: some View {
        TabView(selection: $selection) {
            // Left tab: the user's congressional delegation.
            Tab("Your Reps", systemImage: "person.2", value: .representatives) {
                RepresentativesView(representatives: store.representatives)
            }

            // Center tab: the home feed of bills in Congress.
            Tab("Home", systemImage: "house", value: .home) {
                HomeFeedView(bills: SampleData.bills)
            }

            // Right tab: a map of the representatives' offices.
            Tab("Map", systemImage: "map", value: .map) {
                DistrictMapView(representatives: SampleData.representatives)
            }
        }
        .task {
            // TODO: derive the state from the user's location or settings.
            await store.load(state: "CA")
        }
    }
}

#Preview {
    ContentView()
}
