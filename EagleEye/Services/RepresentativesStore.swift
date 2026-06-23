//
//  RepresentativesStore.swift
//  EagleEye
//
//  Loads and holds the user's congressional delegation for the UI.
//

import Foundation
import Observation

/// Owns the list of representatives shown in the app and loads it from the
/// Congress.gov API. Falls back to bundled sample data when no API key is
/// configured, so the app still has something to show out of the box.
@Observable
final class RepresentativesStore {
    private(set) var representatives: [Representative] = []
    private(set) var isLoading = false
    /// A user-facing note when live data could not be loaded (e.g. no API key).
    private(set) var statusMessage: String?

    private let service: CongressService

    init(service: CongressService = CongressService()) {
        self.service = service
    }

    /// Loads the current delegation for a state, identified by its two-letter
    /// postal code (e.g. "CA").
    func load(state stateCode: String) async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            let members = try await service.currentMembers(forState: stateCode)
            representatives = members.sorted(by: Self.delegationOrder)
        } catch CongressService.ServiceError.missingAPIKey {
            representatives = SampleData.representatives
            statusMessage = "Showing sample data — add a Congress.gov API key to load live representatives."
        } catch {
            statusMessage = error.localizedDescription
            if representatives.isEmpty {
                representatives = SampleData.representatives
            }
        }
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
