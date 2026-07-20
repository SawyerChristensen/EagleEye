// NOTE: Governor feature disabled until v1.1. The entire file is commented
// out below; re-enable by removing this note and the surrounding /* ... */.
/*
//
//  StateLawDirectory.swift
//  EagleEye
//
//  Notable bills each governor has signed into law, shown on their profile's
//  "Laws Passed" section. As with `GovernorDirectory`, there's no free API
//  that tracks state legislation the way Congress.gov does for federal bills
//  (LegiScan and Open States both require a paid or registered API key for
//  the volume this app would need), so this is a hand-curated seed list
//  rather than a live fetch — a handful of the most notable signed bills per
//  governor, not an exhaustive record.
//
//  States without an entry below simply show no laws on record; that's
//  expected for a starter list and isn't a bug. Extending it: add a `StateLaw`
//  entry under the relevant state's postal code with a real bill and date.
//

import Foundation

enum StateLawDirectory {
    /// Notable signed bills, keyed by the governor's two-letter postal code.
    /// Ordered newest first within each state.
    static let all: [StateLaw] = [
        StateLaw(
            title: "Protect Illinois Communities Act",
            summary: "Banned the sale and manufacture of assault weapons and high-capacity magazines in Illinois.",
            dateSigned: Self.date(2023, 1, 10),
            state: "IL"
        ),
        StateLaw(
            title: "Right-to-Work Repeal",
            summary: "Repealed Michigan's right-to-work law, once again allowing union contracts to require all represented workers to pay dues.",
            dateSigned: Self.date(2023, 3, 24),
            state: "MI"
        ),
        StateLaw(
            title: "Parental Rights in Education",
            summary: "Restricted classroom instruction on sexual orientation and gender identity in Florida's early grades.",
            dateSigned: Self.date(2022, 3, 28),
            state: "FL"
        ),
        StateLaw(
            title: "Texas Heartbeat Act",
            summary: "Banned abortion in Texas after roughly six weeks of pregnancy, enforced through private civil lawsuits rather than the state.",
            dateSigned: Self.date(2021, 5, 19),
            state: "TX"
        ),
        StateLaw(
            title: "Election Integrity Act",
            summary: "Overhauled Georgia's election procedures, including new voter ID requirements for absentee ballots and shorter runoff periods.",
            dateSigned: Self.date(2021, 3, 25),
            state: "GA"
        ),
        StateLaw(
            title: "Fentanyl Accountability and Prevention Act",
            summary: "Increased criminal penalties for distributing fentanyl-laced drugs and expanded access to test strips and naloxone in Colorado.",
            dateSigned: Self.date(2023, 4, 19),
            state: "CO"
        ),
        StateLaw(
            title: "Fast Food Minimum Wage",
            summary: "Raised the minimum wage for California fast-food workers to $20 an hour and created a council to set future increases.",
            dateSigned: Self.date(2023, 9, 28),
            state: "CA"
        ),
        StateLaw(
            title: "FY2024 Budget Gas Stove Provision",
            summary: "Phased in a ban on fossil-fuel equipment, including gas stoves, in most new New York construction starting in 2026.",
            dateSigned: Self.date(2023, 5, 3),
            state: "NY"
        ),
        StateLaw(
            title: "Stand Your Ground",
            summary: "Removed Ohioans' duty to retreat before using force in self-defense outside the home.",
            dateSigned: Self.date(2021, 1, 4),
            state: "OH"
        ),
    ]

    /// The signed laws on record for the given state, matched by two-letter
    /// postal code and sorted most recent first.
    static func laws(forState state: String) -> [StateLaw] {
        all
            .filter { $0.state.caseInsensitiveCompare(state) == .orderedSame }
            .sorted { $0.dateSigned > $1.dateSigned }
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
}
*/
