//
//  MapDataStore.swift
//  EagleEye
//
//  Owns the district map's heavyweight data — the state/district boundary
//  geometry and the nationwide House/Senate rosters — so it can be prefetched
//  and cached before the user ever opens the Map tab, and shared with
//  `DistrictMapView` rather than reloaded each time the tab appears.
//

import Foundation
import Observation

/// Holds the map's boundary geometry and national rosters, hoisted out of
/// `DistrictMapView` so `ContentView` can warm them in the background while the
/// user reads the home feed. Once prefetched, opening the Map tab is instant.
@MainActor
@Observable
final class MapDataStore {
    private(set) var stateBoundaries: [MapBoundary] = []
    private(set) var districtBoundaries: [MapBoundary] = []

    /// Every current House member nationwide (party colors for each district).
    let nationalHouseDirectory = NationalHouseDirectory()
    /// Every current senator nationwide (for the state-level detail sheet).
    let nationalSenateDirectory = NationalSenateDirectory()

    /// Loads boundaries and rosters if they aren't already in memory. Safe to
    /// call repeatedly: the boundary load is guarded by `isEmpty`, and each
    /// directory's `loadIfNeeded()` no-ops once populated. The heavy boundary
    /// parsing runs on a detached `.utility` task so it never touches the main
    /// thread; the rosters decode their cache off-main too.
    func prefetch() async {
        await loadBoundariesIfNeeded()
        // Rosters fetch concurrently; each shows its cached copy first, then
        // refreshes from the API.
        async let house: Void = nationalHouseDirectory.loadIfNeeded()
        async let senate: Void = nationalSenateDirectory.loadIfNeeded()
        _ = await (house, senate)
    }

    private func loadBoundariesIfNeeded() async {
        guard districtBoundaries.isEmpty, stateBoundaries.isEmpty else { return }
        // Parse + simplify (or decode the persisted thinned geometry) off the
        // main thread at background-fill priority.
        async let districts = Task.detached(priority: .utility) {
            BoundaryLoader.loadDistrictsCached()
        }.value
        async let states = Task.detached(priority: .utility) {
            BoundaryLoader.loadStatesCached()
        }.value
        districtBoundaries = await districts
        stateBoundaries = await states
    }
}
