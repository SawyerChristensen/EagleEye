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
//  Portrait URLs point at the official headshots published on the National
//  Governors Association's governors directory (nga.org/governors) — the
//  same source used for the "Photos" NGA maintains per sitting governor.
//
//  Backend-only for now: nothing in the map view consumes this yet. Updating
//  after an election: replace the affected state's entry below.
//

import Foundation

enum GovernorDirectory {
    static let all: [Governor] = [
        Governor(name: "Kay Ivey", party: .republican, state: "AL", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2018/01/Governor-Ivey-2019-Headshot-scaled.jpg")),
        Governor(name: "Mike Dunleavy", party: .republican, state: "AK", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/09/Gov_Dunleavy_Sep2023_square-scaled.jpg")),
        Governor(name: "Katie Hobbs", party: .democrat, state: "AZ", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2023/01/governor-katie-hobbs-scaled.jpeg")),
        Governor(name: "Sarah Huckabee Sanders", party: .republican, state: "AR", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2023/01/Governor-Headshot-sanders-e1756131825437.jpg")),
        Governor(name: "Gavin Newsom", party: .democrat, state: "CA", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/09/1200px-Gavin_Newsom_official_photo_square.jpg")),
        Governor(name: "Jared Polis", party: .democrat, state: "CO", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/01/Colorado-Jared-Polis-November-2019.jpg")),
        Governor(name: "Ned Lamont", party: .democrat, state: "CT", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/09/govlamont-scaled.jpg")),
        Governor(name: "Matt Meyer", party: .democrat, state: "DE", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2025/01/matt-meyer_800x600.jpg")),
        Governor(name: "Ron DeSantis", party: .republican, state: "FL", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/09/Ron_DeSantis_Official_Portrait_113th_Congress.jpg")),
        Governor(name: "Brian Kemp", party: .republican, state: "GA", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/09/GovBrianKemp_2024WEB.jpg")),
        Governor(name: "Josh Green", party: .democrat, state: "HI", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2022/12/Governor_Josh_Green.jpg")),
        Governor(name: "Brad Little", party: .republican, state: "ID", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/09/governor_little_square.jpg")),
        Governor(name: "JB Pritzker", party: .democrat, state: "IL", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/09/2026-JB-Headshot.jpg")),
        Governor(name: "Mike Braun", party: .republican, state: "IN", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2025/01/GMB-Official-Headshot-scaled.jpg")),
        Governor(name: "Kim Reynolds", party: .republican, state: "IA", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/09/Governor-Reynolds-2025-Headshot_square.jpg")),
        Governor(name: "Laura Kelly", party: .democrat, state: "KS", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/09/kelly_square.jpg")),
        Governor(name: "Andy Beshear", party: .democrat, state: "KY", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/12/Governor-Beshear_Official-Picture_square-scaled.jpg")),
        Governor(name: "Jeff Landry", party: .republican, state: "LA", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2024/01/Governor-Landry-Official-Portrait_square-scaled.jpg")),
        Governor(name: "Janet Mills", party: .democrat, state: "ME", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/09/3218_Gov-Janet-Mills-20230307_square-scaled.jpg")),
        Governor(name: "Wes Moore", party: .democrat, state: "MD", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2023/01/governor-wes-moore-official-portrait_square.jpg")),
        Governor(name: "Maura Healey", party: .democrat, state: "MA", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2023/01/Maura_Healey_square.jpg")),
        Governor(name: "Gretchen Whitmer", party: .democrat, state: "MI", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/09/GovWhitmerPortMaster_square-scaled.jpg")),
        Governor(name: "Tim Walz", party: .democrat, state: "MN", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/09/Governor-Walz-2024_square.jpg")),
        Governor(name: "Tate Reeves", party: .republican, state: "MS", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2020/01/headshot-governor-tate-reeves_R_square.jpg")),
        Governor(name: "Mike Kehoe", party: .republican, state: "MO", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2025/01/Governor-Mike-Kehoe_square-scaled.jpg")),
        Governor(name: "Greg Gianforte", party: .republican, state: "MT", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2020/11/Montana-Greg-Gianforte-January-2021.jpg")),
        Governor(name: "Jim Pillen", party: .republican, state: "NE", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2023/01/Governor_Pillen.png")),
        Governor(name: "Joe Lombardo", party: .republican, state: "NV", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2023/01/Governor-Joe-Lombardo_Official-Photo-scaled.jpg")),
        Governor(name: "Kelly Ayotte", party: .republican, state: "NH", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2025/01/ayotte_portrait-for-online.jpg")),
        Governor(name: "Mikie Sherrill", party: .democrat, state: "NJ", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2026/01/home-gov_official_square.jpg")),
        Governor(name: "Michelle Lujan Grisham", party: .democrat, state: "NM", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/02/New-Mexico-Michelle-Lujan-Grisham-January-2018.jpg")),
        Governor(name: "Kathy Hochul", party: .democrat, state: "NY", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2021/08/GovernorHochul.jpg")),
        Governor(name: "Josh Stein", party: .democrat, state: "NC", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2025/01/Josh-Stein_NC.jpg")),
        Governor(name: "Kelly Armstrong", party: .republican, state: "ND", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2024/12/GovernorArmstrong.jpg")),
        Governor(name: "Mike DeWine", party: .republican, state: "OH", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/01/Gov-Mike-DeWine.jpg")),
        Governor(name: "Kevin Stitt", party: .republican, state: "OK", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/06/Oklahoma-Kevin-Stitt-June-2019.jpg")),
        Governor(name: "Tina Kotek", party: .democrat, state: "OR", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2023/01/Governor-Tina-Kotek_Official.jpg")),
        Governor(name: "Josh Shapiro", party: .democrat, state: "PA", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2023/01/JDS_headshot.png")),
        Governor(name: "Dan McKee", party: .democrat, state: "RI", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2021/03/Gov-Dan-Mckee-400.png")),
        Governor(name: "Henry McMaster", party: .republican, state: "SC", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/09/McMaster-Gov.-2025a-full-size_square-scaled.jpg")),
        Governor(name: "Larry Rhoden", party: .republican, state: "SD", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2025/01/Governor-Rhoden-square-scaled.jpg")),
        Governor(name: "Bill Lee", party: .republican, state: "TN", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/09/GBL_2022_square.jpg")),
        Governor(name: "Greg Abbott", party: .republican, state: "TX", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2018/07/TX_Gov_Greg_Abbott.png")),
        Governor(name: "Spencer Cox", party: .republican, state: "UT", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2021/01/Governor_Cox_official_square-scaled.jpg")),
        Governor(name: "Phil Scott", party: .republican, state: "VT", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/02/Vermont-Phil-Scott-November-2018.jpg")),
        Governor(name: "Abigail Spanberger", party: .democrat, state: "VA", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2026/01/Abigail_Spanberger_2026.jpg")),
        Governor(name: "Bob Ferguson", party: .democrat, state: "WA", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2025/01/Bob_Ferguson.jpg")),
        Governor(name: "Patrick Morrisey", party: .republican, state: "WV", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2025/01/Patrick-Morrisey-scaled-1.jpg")),
        Governor(name: "Tony Evers", party: .democrat, state: "WI", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/09/Wisconsin-Tony-Evers-January-2019.jpg")),
        Governor(name: "Mark Gordon", party: .republican, state: "WY", portraitURL: URL(string: "https://www.nga.org/wp-content/uploads/2019/01/Wyoming-Mark-Gordon-November-2019.jpg")),
    ]

    /// The governor of the given state, matched by two-letter postal code.
    static func governor(forState state: String) -> Governor? {
        all.first { $0.state.caseInsensitiveCompare(state) == .orderedSame }
    }
}
