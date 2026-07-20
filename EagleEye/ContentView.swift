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
    @State private var mapData = MapDataStore()
    @State private var bookmarksStore = BookmarksStore()
    @State private var enactedLawsNotifier = EnactedLawsNotifier()
    @State private var location = LocationManager()
    /// A bill referenced by the home screen widget's tap URL, forwarded to the
    /// home feed's navigation stack once the main tabs are showing.
    @State private var widgetDeepLinkedBill: LegislationRef?
    
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var hideOnboardingText = false
    @State private var dragOnboardingUp = false

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            content
                .onOpenURL(perform: handleWidgetURL)

            if !hasCompletedOnboarding {
                onboardingView
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // Returning to the foreground re-checks bookmarked bills and
                // new laws; the initial launch is already covered by `.task`.
                Task { await refreshBills() }
            case .background:
                // Ask iOS to wake us later so the same checks run while suspended.
                BillRefreshScheduler.scheduleAppRefresh()
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
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
                    // Stage 1 — the visible screen. Load the home feed of bills
                    // at normal priority (cached results first, then a refresh
                    // from the API) so the tab the user is looking at wins the
                    // main thread and the network.
                    await refreshBills()
                }
                .task(priority: .utility) {
                    // Stages 2 & 3 — warm the other tabs in the background at a
                    // lower priority so they fill in behind the home feed
                    // without competing for the main thread. Their heavy work
                    // (rep enrichment, boundary parsing, roster decoding) all
                    // runs off-main, so this never stutters the feed.
                    //
                    // Reps and map load concurrently: `refreshUsingCachedLocation`
                    // quietly refreshes the delegation from the saved coordinate
                    // (no-op with no cached location), and `prefetch` warms the
                    // map's boundaries and national rosters.
                    async let reps: Void = store.refreshUsingCachedLocation()
                    async let map: Void = mapData.prefetch()
                    _ = await (reps, map)
                }
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selection) {
            // Left tab: the user's congressional delegation.
            Tab("Your Reps", systemImage: "person.2", value: .representatives) {
                RepresentativesView(
                    representatives: store.representatives,
                    // Governor disabled until v1.1.
                    // governor: store.governor,
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
                    onRefresh: refreshBills,
                    onLoadMore: billsStore.loadMore,
                    deepLinkedBill: $widgetDeepLinkedBill
                )
            }

            // Right tab: a map of the representatives' offices.
            Tab("Map", systemImage: "map", value: .map) {
                DistrictMapView(representatives: store.representatives, userCoordinate: store.cachedCoordinate, mapData: mapData)
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
        .environment(bookmarksStore)
    }
    
    private var onboardingView: some View {
        GeometryReader { geo in
            VStack(spacing: -2) {
                
                // TOP SECTION (80% of screen)
                ZStack(alignment: .bottom) {
                    // Moved the gradient here so it doesn't bleed behind the white section
                    LinearGradient(
                        colors: [
                            Color(hue: 207 / 360.0, saturation: 1.0, brightness: 0.9),
                            Color(hue: 213 / 360.0, saturation: 1.0, brightness: 0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    VStack(spacing: 24) {
                        Spacer()
                        
                        Text("Welcome to Politica")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .fontDesign(.serif)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.4), radius: 4, x: 4, y: 4)
                        
                        // Feature List
                        VStack(alignment: .leading, spacing: 24) {
                            HStack(spacing: 16) {
                                Image(systemName: "person.2.fill")
                                    .font(.title2)
                                    .frame(width: 32)
                                Text("Meet your representatives")
                                    .font(.title3)
                                    .fontWeight(.medium)
                            }
                            
                            HStack(spacing: 16) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.title2)
                                    .frame(width: 32)
                                Text("See how they vote")
                                    .font(.title3)
                                    .fontWeight(.medium)
                            }
                            
                            HStack(spacing: 16) {
                                Image(systemName: "bookmark.fill") //alternative: "scroll.fill"
                                    .font(.title2)
                                    .frame(width: 32)
                                Text("Track individual bills")
                                    .font(.title3)
                                    .fontWeight(.medium)
                            }
                        }
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.4), radius: 4, x: 4, y: 4)
                        // This padding brings the list inward slightly so it's centered nicely under the title
                        .padding(.horizontal, 40)
                        
                        Spacer()
                        Spacer()
                        Spacer()
                        Spacer() //refactor this, 4 spacers seems unnecessary
                    }
                    .opacity(hideOnboardingText ? 0 : 1)
                    .offset(y: dragOnboardingUp ? (geo.size.height * 1.5) : 0)
                    
                    Image("CongressIconExtended")
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width)
                        .shadow(color: .black.opacity(0.4), radius: 4, x: 4, y: 4)
                        .scaleEffect(dragOnboardingUp ? 2.75 : 1.0, anchor: .bottom)
                }
                .frame(height: geo.size.height * 0.85)
                
                // BOTTOM SECTION (Auto-fills the remaining 20%)
                ZStack(alignment: .top) {
                    VStack(spacing: -2) {
                        Color.white
                            .frame(height: geo.size.height * 0.15)
                        
                        LinearGradient(
                            colors: [.white, .white.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: geo.size.height * 0.5)
                    }
                    
                    Button(action: executeOnboardingTransition) {
                        HStack(spacing: 8) {
                            Text("Get Started")
                            Image(systemName: "arrow.forward")
                        }
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 17 / 255.0, green: 101 / 255.0, blue: 172 / 255.0))
                    }
                    //.padding(.top, 5)
                    .opacity(hideOnboardingText ? 0 : 1)
                    .offset(y: dragOnboardingUp ? (geo.size.height * 1.5) : 0)
                }
                .clipped()
            }
            // Because the GeometryReader ignores safe areas, geo.size.height is the exact
            // total height of the phone display. Sliding up by this exact amount
            // perfectly clears the screen, revealing the app directly beneath it.
            .offset(y: dragOnboardingUp ? -(geo.size.height * 1.5) : 0)
        }
        .ignoresSafeArea()
    }
    
    private func executeOnboardingTransition() { //add timing curve
        withAnimation(.easeOut(duration: 0.6)) {
            hideOnboardingText = true
        }
        
        withAnimation(.easeInOut(duration: 0.9).delay(0.2)) {
            dragOnboardingUp = true
        }
        // Remove the layer once it is fully cleared.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            hasCompletedOnboarding = true
        }
    }

    /// Refreshes the home feed, then checks whether any bookmarked bill's
    /// status changed or any bill newly became law since the last refresh,
    /// notifying the user if so.
    private func refreshBills() async {
        await billsStore.load()
        // Also re-fetches bookmarked bills that have dropped out of the feed, so
        // their tracking stays current even when they're no longer recent.
        await bookmarksStore.refresh(feedBills: billsStore.bills)
        enactedLawsNotifier.checkForNewlyEnacted(in: billsStore.bills)
    }

    /// Handles the `eagleeye://bill?congress=…&type=…&number=…` URL the top
    /// bill widget attaches to itself, switching to the home feed and pushing
    /// straight to that bill's detail screen.
    private func handleWidgetURL(_ url: URL) {
        guard url.scheme == "eagleeye", url.host == "bill",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        guard let congressString = query["congress"], let congress = Int(congressString),
              let type = query["type"], let number = query["number"] else { return }
        selection = .home
        widgetDeepLinkedBill = LegislationRef(congress: congress, type: type, number: number, title: "")
    }

    /// Asks for the user's location, then loads their delegation. Stays on the
    /// location prompt (so the system permission dialog, when shown, has the
    /// prompt visible behind it) until the user answers it, then moves to the
    /// main tabs right away so the home feed can load while CoreLocation waits
    /// for a fix. Falls back to the location prompt if access is denied or no
    /// fix arrives.
    private func resolveLocation() async {
        do {
            try await location.requestAuthorizationIfNeeded()
            store.beginLocating()
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
