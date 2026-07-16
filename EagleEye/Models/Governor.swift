//
//  Governor.swift
//  EagleEye
//
//  A state's chief executive, tracked separately from `Representative` since
//  governors carry none of that model's congressional fields (chamber,
//  district, committees, sponsored bills, and so on).
//

import Foundation

/// A U.S. state governor.
struct Governor: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let party: Party
    /// Two-letter postal code, matching `MapBoundary.state`.
    let state: String

    init(id: UUID = UUID(), name: String, party: Party, state: String) {
        self.id = id
        self.name = name
        self.party = party
        self.state = state
    }

    /// The state's full name, e.g. "California" for "CA".
    var stateName: String { MapBoundary.stateName(for: state) }

    /// The state's capital city, e.g. "Sacramento" for "CA".
    var capitalCity: String { MapBoundary.capitalCity(for: state) }

    /// e.g. "Governor of California".
    var roleDescription: String { "Governor of \(stateName)" }
}
