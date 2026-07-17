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
//  list rather than a live fetch, sourced from OpenSecrets, Transparency USA,
//  and state campaign-finance reporting for each governor's most recent race.
//
//  States without entries below simply show no funders on record; that's
//  expected for a starter list and isn't a bug. Extending it: add a
//  `GovernorFunder` entry under the relevant state's postal code with a real,
//  sourced contribution figure.
//

import Foundation

enum GovernorFunderDirectory {
    /// Top PAC contributors, keyed by the governor's two-letter postal code.
    static let pacFunders: [GovernorFunder] = [
        GovernorFunder(state: "FL", funder: Funder(name: "Republican Governors Association", amount: 20_950_000, category: "Party Committee")),
        GovernorFunder(state: "MI", funder: Funder(name: "SEIU Committee on Political Education", amount: 51_500, category: "Labor Unions")),
        GovernorFunder(state: "MI", funder: Funder(name: "Iron Workers Local 25 PAC", amount: 25_000, category: "Labor Unions")),
        GovernorFunder(state: "MI", funder: Funder(name: "General Motors PAC", amount: 10_000, category: "Automotive")),
        GovernorFunder(state: "TX", funder: Funder(name: "Texans for Lawsuit Reform PAC", amount: 100_000, category: "Legal Reform")),
        GovernorFunder(state: "GA", funder: Funder(name: "Republican Governors Association", amount: 9_000_000, category: "Party Committee")),
        GovernorFunder(state: "CO", funder: Funder(name: "Democratic Governors Association", amount: 1_500_000, category: "Party Committee")),
        GovernorFunder(state: "CA", funder: Funder(name: "Agua Caliente Band of Cahuilla Indians", amount: 64_800, category: "Tribal Gaming")),
        GovernorFunder(state: "CA", funder: Funder(name: "California Nurses Association PAC", amount: 64_800, category: "Labor Unions")),
        GovernorFunder(state: "NY", funder: Funder(name: "Hotel Trades Council PAC", amount: 139_400, category: "Labor Unions")),
        GovernorFunder(state: "NY", funder: Funder(name: "LAWPAC (New York State Trial Lawyers Association)", amount: 68_700, category: "Legal")),
        GovernorFunder(state: "OH", funder: Funder(name: "Ohio Republican State Central & Executive Committee State Candidate Fund", amount: 1_959_075, category: "Party Committee")),
        GovernorFunder(state: "OH", funder: Funder(name: "Ohio Republican PAC", amount: 520_784, category: "Party Committee")),
    ]

    /// Top individual contributors (totaled by employer or occupation),
    /// keyed by the governor's two-letter postal code.
    static let individualFunders: [GovernorFunder] = [
        GovernorFunder(state: "IL", funder: Funder(name: "J.B. Pritzker (self-funded)", amount: 90_000_000, category: "Self-Funded")),
        GovernorFunder(state: "FL", funder: Funder(name: "Robert Bigelow", amount: 10_000_000, category: "Aerospace")),
        GovernorFunder(state: "MI", funder: Funder(name: "Melinda French Gates", amount: 7_150, category: "Philanthropy")),
        GovernorFunder(state: "MI", funder: Funder(name: "Steve Ballmer", amount: 7_000, category: "Business")),
        GovernorFunder(state: "MI", funder: Funder(name: "Rhea Perlman", amount: 5_000, category: "Entertainment")),
        GovernorFunder(state: "TX", funder: Funder(name: "S. Javaid Anwar", amount: 2_222_086, category: "Oil & Gas")),
        GovernorFunder(state: "TX", funder: Funder(name: "Kelcy Warren", amount: 1_000_000, category: "Energy")),
        GovernorFunder(state: "GA", funder: Funder(name: "Timothy Mellon", amount: 5_000_000, category: "Transportation")),
        GovernorFunder(state: "CO", funder: Funder(name: "Jared Polis (self-funded)", amount: 12_600_000, category: "Self-Funded")),
        GovernorFunder(state: "CA", funder: Funder(name: "Akiko Yamazaki", amount: 64_800, category: "Philanthropy")),
        GovernorFunder(state: "CA", funder: Funder(name: "Angelo K. Tsakopoulos", amount: 64_800, category: "Real Estate")),
        GovernorFunder(state: "NY", funder: Funder(name: "Rudin Family", amount: 226_000, category: "Real Estate")),
        GovernorFunder(state: "NY", funder: Funder(name: "Jeff and Lisa Blau (Related Companies)", amount: 139_400, category: "Real Estate")),
        GovernorFunder(state: "OH", funder: Funder(name: "Eric Wagenbrenner", amount: 35_650, category: "Real Estate")),
        GovernorFunder(state: "OH", funder: Funder(name: "George A. Skestos", amount: 30_608, category: "Real Estate")),
    ]

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
