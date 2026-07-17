//
//  GovernorFunderDirectory.swift
//  EagleEye
//
//  Top PAC and individual funders for the "money" section of a governor's
//  profile, mirroring `RepresentativeDetailView`'s funders sections. Unlike
//  representatives and senators, governors run in state races the FEC
//  doesn't track, and there's no free, uniform live data source across all
//  50 states' campaign-finance disclosures the way OpenFEC covers federal
//  candidates — so, as with `StateLawDirectory`, this is a hand-curated seed
//  list rather than a live fetch.
//
//  States without entries below simply show no funders on record; that's
//  expected for a starter list and isn't a bug. Extending it: add a
//  `GovernorFunder` entry under the relevant state's postal code with a real,
//  sourced contribution figure.
//

import Foundation

enum GovernorFunderDirectory {
    /// Top PAC contributors, keyed by the governor's two-letter postal code.
    static let pacFunders: [GovernorFunder] = []

    /// Top individual contributors (totaled by employer or occupation),
    /// keyed by the governor's two-letter postal code.
    static let individualFunders: [GovernorFunder] = []

    /// The PAC funders on record for the given state.
    static func pacFunders(forState state: String) -> [Funder] {
        pacFunders
            .filter { $0.state.caseInsensitiveCompare(state) == .orderedSame }
            .map(\.funder)
    }

    /// The individual funders on record for the given state.
    static func individualFunders(forState state: String) -> [Funder] {
        individualFunders
            .filter { $0.state.caseInsensitiveCompare(state) == .orderedSame }
            .map(\.funder)
    }
}
