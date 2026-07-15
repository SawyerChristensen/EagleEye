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
                statusMessage: store.statusMessage,
                onRequestLocation: resolveLocation,
                onSubmitZIP: store.loadDelegation(forZIP:)
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
                RepresentativesView(
                    representatives: store.representatives,
                    isLoading: store.loadState == .loading
                )
            }

            // Center tab: the home feed of bills in Congress.
            Tab("Recent", systemImage: "building.columns", value: .home) {
                HomeFeedView(
                    bills: billsStore.bills,
                    isLoading: billsStore.loadState == .loading,
                    statusMessage: billsStore.statusMessage,
                    isLoadingMore: billsStore.isLoadingMore,
                    onRefresh: billsStore.load,
                    onLoadMore: billsStore.loadMore
                )
            }

            // Right tab: a map of the representatives' offices.
            Tab("Map", systemImage: "map", value: .map) {
                DistrictMapView(representatives: SampleData.representatives)
            }
        }
        // Make the user's delegation available to bill detail screens so each
        // roll-call tally can surface their representatives' votes on top. The
        // House tally matches on Bioguide ID; the Senate roster has none, so it
        // matches on a state+surname key instead.
        .environment(\.userRepBioguideIDs, Set(store.representatives.compactMap(\.bioguideID)))
        .environment(\.userRepMatchKeys, Set(store.representatives.map {
            MemberVote.matchKey(
                state: $0.state,
                lastName: MemberVote.lastName(fromDisplayName: $0.name)
            )
        }))
    }

    /// Asks for the user's location, then loads their delegation. Moves to the
    /// main tabs right away so the home feed can load while CoreLocation waits
    /// for a fix, only falling back to the location prompt if access is denied
    /// or no fix arrives.
    private func resolveLocation() async {
        store.beginLocating()
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
