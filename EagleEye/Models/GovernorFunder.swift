//
//  GovernorFunder.swift
//  EagleEye
//
//  A PAC or individual contributor to a governor's campaign, shown on their
//  profile's money section in place of `Representative`'s FEC-backed
//  funders — the FEC only covers federal candidates, so there's no live
//  equivalent for gubernatorial campaign finance (see
//  `GovernorFunderDirectory`).
//

import Foundation

/// A `Funder` tied to a specific governor, keyed by state.
struct GovernorFunder: Identifiable, Codable, Hashable {
    let id: UUID
    /// Two-letter postal code, matching `Governor.state`.
    let state: String
    let funder: Funder

    init(id: UUID = UUID(), state: String, funder: Funder) {
        self.id = id
        self.state = state
        self.funder = funder
    }
}
