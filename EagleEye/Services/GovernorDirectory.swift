//
//  GovernorDirectory.swift
//  EagleEye
//
//  Every current U.S. state governor, retrieved the same way
//  `NationalHouseDirectory` retrieves every House member — but there's no
//  free federal API for state executives, since Congress.gov and OpenFEC both
//  stop at the legislative and campaign-finance data they're built for. So,
//  like `MarketPerformanceService`'s year-end snapshot, this is a
//  hand-curated list rather than a live fetch — one that changes only after
//  an election or a resignation/succession, not a data feed worth polling.
//
//  Backend-only for now: nothing in the map view consumes this yet. Updating
//  after an election: replace the affected state's entry below.
//

import Foundation

enum GovernorDirectory {
    static let all: [Governor] = [
        Governor(name: "Kay Ivey", party: .republican, state: "AL"),
        Governor(name: "Mike Dunleavy", party: .republican, state: "AK"),
        Governor(name: "Katie Hobbs", party: .democrat, state: "AZ"),
        Governor(name: "Sarah Huckabee Sanders", party: .republican, state: "AR"),
        Governor(name: "Gavin Newsom", party: .democrat, state: "CA"),
        Governor(name: "Jared Polis", party: .democrat, state: "CO"),
        Governor(name: "Ned Lamont", party: .democrat, state: "CT"),
        Governor(name: "Matt Meyer", party: .democrat, state: "DE"),
        Governor(name: "Ron DeSantis", party: .republican, state: "FL"),
        Governor(name: "Brian Kemp", party: .republican, state: "GA"),
        Governor(name: "Josh Green", party: .democrat, state: "HI"),
        Governor(name: "Brad Little", party: .republican, state: "ID"),
        Governor(name: "JB Pritzker", party: .democrat, state: "IL"),
        Governor(name: "Mike Braun", party: .republican, state: "IN"),
        Governor(name: "Kim Reynolds", party: .republican, state: "IA"),
        Governor(name: "Laura Kelly", party: .democrat, state: "KS"),
        Governor(name: "Andy Beshear", party: .democrat, state: "KY"),
        Governor(name: "Jeff Landry", party: .republican, state: "LA"),
        Governor(name: "Janet Mills", party: .democrat, state: "ME"),
        Governor(name: "Wes Moore", party: .democrat, state: "MD"),
        Governor(name: "Maura Healey", party: .democrat, state: "MA"),
        Governor(name: "Gretchen Whitmer", party: .democrat, state: "MI"),
        Governor(name: "Tim Walz", party: .democrat, state: "MN"),
        Governor(name: "Tate Reeves", party: .republican, state: "MS"),
        Governor(name: "Mike Kehoe", party: .republican, state: "MO"),
        Governor(name: "Greg Gianforte", party: .republican, state: "MT"),
        Governor(name: "Jim Pillen", party: .republican, state: "NE"),
        Governor(name: "Joe Lombardo", party: .republican, state: "NV"),
        Governor(name: "Kelly Ayotte", party: .republican, state: "NH"),
        Governor(name: "Mikie Sherrill", party: .democrat, state: "NJ"),
        Governor(name: "Michelle Lujan Grisham", party: .democrat, state: "NM"),
        Governor(name: "Kathy Hochul", party: .democrat, state: "NY"),
        Governor(name: "Josh Stein", party: .democrat, state: "NC"),
        Governor(name: "Kelly Armstrong", party: .republican, state: "ND"),
        Governor(name: "Mike DeWine", party: .republican, state: "OH"),
        Governor(name: "Kevin Stitt", party: .republican, state: "OK"),
        Governor(name: "Tina Kotek", party: .democrat, state: "OR"),
        Governor(name: "Josh Shapiro", party: .democrat, state: "PA"),
        Governor(name: "Dan McKee", party: .democrat, state: "RI"),
        Governor(name: "Henry McMaster", party: .republican, state: "SC"),
        Governor(name: "Larry Rhoden", party: .republican, state: "SD"),
        Governor(name: "Bill Lee", party: .republican, state: "TN"),
        Governor(name: "Greg Abbott", party: .republican, state: "TX"),
        Governor(name: "Spencer Cox", party: .republican, state: "UT"),
        Governor(name: "Phil Scott", party: .republican, state: "VT"),
        Governor(name: "Abigail Spanberger", party: .democrat, state: "VA"),
        Governor(name: "Bob Ferguson", party: .democrat, state: "WA"),
        Governor(name: "Patrick Morrisey", party: .republican, state: "WV"),
        Governor(name: "Tony Evers", party: .democrat, state: "WI"),
        Governor(name: "Mark Gordon", party: .republican, state: "WY"),
    ]

    /// The governor of the given state, matched by two-letter postal code.
    static func governor(forState state: String) -> Governor? {
        all.first { $0.state.caseInsensitiveCompare(state) == .orderedSame }
    }
}
