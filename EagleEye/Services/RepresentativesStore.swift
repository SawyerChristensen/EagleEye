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

    init(
        service: CongressService = CongressService(),
        geocoder: CensusGeocoder = CensusGeocoder()
    ) {
        self.service = service
        self.geocoder = geocoder
    }

    /// Resolves `coordinate` into a state and district, then loads the user's
    /// senators and their one House member.
    func loadDelegation(at coordinate: CLLocationCoordinate2D) async {
        loadState = .loading
        statusMessage = nil

        await Task {
            do {
                let stateCode = try await stateCode(for: coordinate)
                // A missing district just means we can't single out the House
                // member; the senators are still correct.
                let district = try? await geocoder.congressionalDistrict(at: coordinate)
                
                let members = try await service.currentMembers(forState: stateCode)
                representatives = Self.delegation(from: members, district: district)
                loadState = .ready
            } catch CongressService.ServiceError.missingAPIKey {
                representatives = SampleData.representatives
                statusMessage = "Showing sample data — add a Congress.gov API key to load live representatives."
                loadState = .ready
            } catch {
                statusMessage = error.localizedDescription
                if representatives.isEmpty {
                    representatives = SampleData.representatives
                }
                loadState = .ready
            }
        }.value
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
}
