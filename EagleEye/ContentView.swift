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
    @State private var billsStore = BillsStore()
    @State private var location = LocationManager()

    var body: some View {
        switch store.loadState {
        case .locating, .denied:
            LocationPromptView(
                isDenied: store.loadState == .denied,
                onRequestLocation: resolveLocation,
                onUseSampleData: store.continueWithSampleData
            )
        case .loading, .ready:
            mainTabs
                .task {
                    // We launched straight into the app from a cached
                    // delegation; quietly refresh it using the saved coordinate
                    // so the data stays current without re-prompting.
                    await store.refreshUsingCachedLocation()
                }
                .task {
                    // Load the home feed of bills (uses cached results first,
                    // then refreshes from the API).
                    await billsStore.load()
                }
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selection) {
            // Left tab: the user's congressional delegation.
            Tab("Your Reps", systemImage: "person.2", value: .representatives) {
                RepresentativesView(representatives: store.representatives)
            }

            // Center tab: the home feed of bills in Congress.
            Tab("Recent", systemImage: "building.columns", value: .home) {
                HomeFeedView(
                    bills: billsStore.bills,
                    isLoading: billsStore.loadState == .loading,
                    onRefresh: billsStore.load
                )
            }

            // Right tab: a map of the representatives' offices.
            Tab("Map", systemImage: "map", value: .map) {
                DistrictMapView(representatives: SampleData.representatives)
            }
        }
    }

    /// Asks for the user's location, then loads their delegation. Falls back to
    /// the denied state (with sample data) if access isn't granted.
    private func resolveLocation() async {
        do {
            let coordinate = try await location.requestLocation()
            await store.loadDelegation(at: coordinate)
        } catch {
            store.locationAccessDenied()
        }
    }
}

#Preview {
    ContentView()
}
