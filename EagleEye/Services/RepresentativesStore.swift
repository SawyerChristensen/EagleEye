//
//  RepresentativesStore.swift
//  EagleEye
//
//  Loads and holds the user's congressional delegation for the UI.
//

import Foundation
import CoreLocation
import Observation

/// Owns the list of representatives shown in the app. It resolves the user's
/// location into a state (for senators) and a congressional district (for their
/// House member), then loads that delegation from the Congress.gov API. Falls
/// back to bundled sample data when no API key is configured, so the app still
/// has something to show out of the box.
///
/// The resolved coordinate and delegation are cached on disk, so after the very
/// first launch the app shows the user's representatives immediately and never
/// has to ask for their location again — meaning "Allow Once" is enough.
@MainActor
@Observable
final class RepresentativesStore {
    /// Where the store is in the launch flow, used to drive the location prompt.
    enum LoadState: Equatable {
        /// Waiting on the user to grant access and a location fix to arrive.
        case locating
        /// Have a coordinate; fetching the delegation.
        case loading
        /// Delegation (or sample data) is ready to show.
        case ready
        /// The user declined location access.
        case denied
    }

    private(set) var representatives: [Representative] = []
    private(set) var loadState: LoadState = .locating
    /// A user-facing note when live data could not be loaded (e.g. no API key).
    private(set) var statusMessage: String?

    private let service: CongressService
    private let geocoder: CensusGeocoder
    private let committeeService: CommitteeService

    /// The last coordinate we successfully resolved a delegation for. Persisted
    /// so future launches can refresh without prompting for location again.
    private var cachedCoordinate: CLLocationCoordinate2D?

    init(
        service: CongressService = CongressService(),
        geocoder: CensusGeocoder = CensusGeocoder(),
        committeeService: CommitteeService = CommitteeService()
    ) {
        self.service = service
        self.geocoder = geocoder
        self.committeeService = committeeService

        // If we resolved the delegation on a previous launch, show it right away
        // and skip the location prompt entirely.
        if let cache = Self.loadCache(), !cache.representatives.isEmpty {
            representatives = cache.representatives
            cachedCoordinate = cache.coordinate
            loadState = .ready
        }
    }

    /// Whether a coordinate was cached from a previous launch, letting the app
    /// refresh the delegation without asking for location again.
    var hasCachedLocation: Bool { cachedCoordinate != nil }

    /// Resolves `coordinate` into a state and district, then loads the user's
    /// senators and their one House member.
    ///
    /// When `silent` is true the visible state is left untouched while the fetch
    /// runs (and the cached delegation is kept on failure), so a background
    /// refresh never flashes a spinner or wipes out good data.
    func loadDelegation(at coordinate: CLLocationCoordinate2D, silent: Bool = false) async {
        if !silent {
            loadState = .loading
            statusMessage = nil
        }

        await Task {
            do {
                let stateCode = try await stateCode(for: coordinate)
                // A missing district just means we can't single out the House
                // member; the senators are still correct.
                let district = try? await geocoder.congressionalDistrict(at: coordinate)

                let members = try await service.currentMembers(forState: stateCode)
                let delegation = Self.delegation(from: members, district: district)
                representatives = await Self.enrichedProfiles(
                    for: delegation,
                    using: service,
                    committeeService: committeeService
                )
                cachedCoordinate = coordinate
                Self.saveCache(coordinate: coordinate, representatives: representatives)
                loadState = .ready
            } catch CongressService.ServiceError.missingAPIKey {
                // No key configured: keep any cached delegation on a silent
                // refresh, otherwise show sample data.
                if !silent {
                    representatives = SampleData.representatives
                    statusMessage = "Showing sample data — add a Congress.gov API key to load live representatives."
                    loadState = .ready
                }
            } catch {
                // A background refresh that fails should leave the cached
                // delegation exactly as it was.
                if !silent {
                    statusMessage = error.localizedDescription
                    if representatives.isEmpty {
                        representatives = SampleData.representatives
                    }
                    loadState = .ready
                }
            }
        }.value
    }

    /// Refreshes the delegation using the coordinate saved on a previous launch,
    /// without re-prompting for location. No-op when nothing has been cached yet.
    func refreshUsingCachedLocation() async {
        guard let coordinate = cachedCoordinate else { return }
        await loadDelegation(at: coordinate, silent: true)
    }

    /// Records that location access was denied and shows sample data so the app
    /// remains usable.
    func locationAccessDenied() {
        representatives = SampleData.representatives
        statusMessage = "Showing sample data — share your location to see your own representatives."
        loadState = .denied
    }

    /// Dismisses the location prompt and continues with whatever sample data is
    /// loaded (used when the user declines but wants to keep browsing).
    func continueWithSampleData() {
        if representatives.isEmpty {
            representatives = SampleData.representatives
        }
        loadState = .ready
    }

    // MARK: - Delegation

    /// Narrows a state's full membership down to the three representatives the
    /// app shows: both senators and the single House member for the user's
    /// district. When the district is unknown, falls back to the
    /// lowest-numbered district so there's still a House member to show.
    private static func delegation(from members: [Representative], district: Int?) -> [Representative] {
        let senators = members.filter { $0.office == .senator }
        let houseMembers = members.filter { $0.office == .representative }

        let houseMember: Representative?
        if let district,
           let match = houseMembers.first(where: { ($0.district ?? 0) == district }) {
            houseMember = match
        } else {
            // Unknown district (or no exact match): show the first by district.
            houseMember = houseMembers.min { ($0.district ?? 0) < ($1.district ?? 0) }
        }

        return (senators + (houseMember.map { [$0] } ?? [])).sorted(by: delegationOrder)
    }

    /// Fills in each member's profile: sponsored/cosponsored bills from
    /// Congress.gov (fetched per member, concurrently) and committee assignments
    /// from the shared committee dataset (fetched once for the whole delegation).
    /// Both run concurrently and member order is preserved.
    private static func enrichedProfiles(
        for delegation: [Representative],
        using service: CongressService,
        committeeService: CommitteeService
    ) async -> [Representative] {
        // Kick off the single committee-dataset fetch alongside the per-member
        // bill lookups so they overlap.
        async let assignments = committeeService.committeeAssignments()

        let billEnriched = await withTaskGroup(of: (Int, Representative).self) { group in
            for (index, rep) in delegation.enumerated() {
                group.addTask { (index, await service.enrichedProfile(for: rep)) }
            }
            var enriched = delegation
            for await (index, rep) in group {
                enriched[index] = rep
            }
            return enriched
        }

        let committeesByID = await assignments
        return billEnriched.map { rep in
            guard let id = rep.bioguideID,
                  let committees = committeesByID[id], !committees.isEmpty else {
                return rep
            }
            return rep.withCommittees(committees)
        }
    }

    /// Reverse-geocodes a coordinate to its two-letter state postal code.
    private func stateCode(for coordinate: CLLocationCoordinate2D) async throws -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        guard let stateCode = placemarks.first?.administrativeArea, !stateCode.isEmpty else {
            throw CLError(.geocodeFoundNoResult)
        }
        print("Detected state:", stateCode)
        return stateCode
    }

    /// Senators first, then House members ordered by district — matching the
    /// grid's "senators on top" layout.
    private static func delegationOrder(_ lhs: Representative, _ rhs: Representative) -> Bool {
        if lhs.office != rhs.office {
            return lhs.office == .senator
        }
        return (lhs.district ?? 0) < (rhs.district ?? 0)
    }

    // MARK: - Cache

    /// The on-disk snapshot of a resolved delegation: the coordinate it was
    /// resolved for plus the representatives themselves.
    private struct DelegationCache: Codable {
        let latitude: Double
        let longitude: Double
        let representatives: [Representative]

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    private static let cacheKey = "cachedDelegation"

    /// Persists a freshly resolved delegation so the next launch can skip the
    /// location prompt.
    private static func saveCache(coordinate: CLLocationCoordinate2D, representatives: [Representative]) {
        let cache = DelegationCache(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            representatives: representatives
        )
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    /// Loads the delegation saved on a previous launch, if any.
    private static func loadCache() -> DelegationCache? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(DelegationCache.self, from: data)
    }
}
