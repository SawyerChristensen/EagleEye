//
//  Bill.swift
//  EagleEye
//
//  A piece of legislation moving through Congress.
//

import Foundation

/// The chamber a bill originates in.
enum Chamber: String, Codable {
    case house = "House"
    case senate = "Senate"

    var symbolName: String {
        switch self {
        case .house: "building.columns"
        case .senate: "building.columns.fill"
        }
    }
}

/// Where a bill currently sits in the legislative process.
enum BillStatus: String, Codable, CaseIterable {
    case introduced = "Introduced"
    case inCommittee = "In Committee"
    case passedHouse = "Passed House"
    case passedSenate = "Passed Senate"
    case toPresident = "To President"
    case enacted = "Enacted"

    var tint: String {
        switch self {
        case .introduced, .inCommittee: "secondary"
        case .passedHouse, .passedSenate, .toPresident: "blue"
        case .enacted: "green"
        }
    }

    /// A single label that folds in the chamber where it adds meaning, e.g.
    /// "Introduced to the House". Stages that already name a chamber
    /// ("Passed House") or don't involve one ("Enacted") read on their own.
    func displayLabel(chamber: Chamber) -> String {
        switch self {
        case .introduced: "Introduced to the \(chamber.rawValue)"
        case .inCommittee: "In \(chamber.rawValue) Committee"
        case .passedHouse, .passedSenate, .toPresident, .enacted: rawValue
        }
    }
}

/// A single bill shown in the home feed. `title` is the name of the bill and
/// `summary` is the human-readable description displayed underneath it.
struct Bill: Identifiable, Codable, Hashable {
    let id: UUID
    /// The official short name, e.g. "Clean Water Act — H.R. 1234".
    let title: String
    /// A plain-language summary used as the feed description.
    let summary: String
    /// For acronym-named bills (e.g. "KIDS Act"), the full title the acronym
    /// stands for (e.g. "Kids Internet and Digital Safety Act"), surfaced as a
    /// subtitle. `nil` when the bill isn't acronym-named.
    let acronymExpansion: String?
    let chamber: Chamber
    let status: BillStatus
    /// The date of the most recent action on the bill.
    let latestActionDate: Date
    /// Broad policy areas the bill touches, used for quick scanning.
    let topics: [String]

    // MARK: - Identifiers
    // Carried so the detail screen can fetch the bill's roll-call votes. `nil`
    // for sample data, which has no live counterpart to look up.

    /// The Congress the bill belongs to, e.g. 119.
    let congress: Int?
    /// The measure type code, e.g. "HR", "S", "HRES".
    let billType: String?
    /// The measure number as a string, e.g. "1842".
    let billNumber: String?

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        acronymExpansion: String? = nil,
        chamber: Chamber,
        status: BillStatus,
        latestActionDate: Date,
        topics: [String] = [],
        congress: Int? = nil,
        billType: String? = nil,
        billNumber: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.acronymExpansion = acronymExpansion
        self.chamber = chamber
        self.status = status
        self.latestActionDate = latestActionDate
        self.topics = topics
        self.congress = congress
        self.billType = billType
        self.billNumber = billNumber
    }
}

// MARK: - Roll-call votes

/// One member's recorded position on a roll-call vote, used to disclose the full
/// tally on a bill's detail screen.
struct MemberVote: Identifiable, Hashable {
    /// The member's Bioguide ID, also used to spot the user's own representatives.
    let id: String
    let name: String
    let party: Party
    /// Two-letter state postal code, e.g. "CA".
    let state: String
    let position: VotePosition
}

/// The roll-call breakdown for a bill: how every member voted, plus the question
/// asked and when. House only — Congress.gov exposes member-level rosters for the
/// House of Representatives.
struct BillVoteTally: Hashable {
    /// The floor question, e.g. "On Passage" or "On Motion to Concur…".
    let question: String?
    let date: Date?
    /// The outcome as reported by the clerk, e.g. "Passed" or "Failed".
    let result: String?
    let memberVotes: [MemberVote]

    func count(_ position: VotePosition) -> Int {
        memberVotes.filter { $0.position == position }.count
    }

    var yea: Int { count(.yea) }
    var nay: Int { count(.nay) }
    var present: Int { count(.present) }
    var notVoting: Int { count(.notVoting) }
    var total: Int { memberVotes.count }
}

// MARK: - Display formatting

extension Bill {
    /// The measure's short code, e.g. "H.R. 1842", shown only in the navigation
    /// bar on the detail screen. Derived from the type/number identifiers when
    /// available, otherwise parsed out of the title. `nil` when the bill carries
    /// no recognizable code.
    var displayCode: String? {
        if let prefix = Bill.typePrefix(billType),
           let billNumber, !billNumber.isEmpty {
            return "\(prefix) \(billNumber)"
        }
        return title
            .components(separatedBy: " — ")
            .compactMap { Bill.codeToken($0) }
            .first
    }

    /// The bill's name with its measure code stripped off, e.g. "Clean Energy
    /// Innovation Act". Used in the feed and as the detail screen's title so the
    /// exact code only surfaces in the navigation bar.
    var displayName: String {
        let name = title
            .components(separatedBy: " — ")
            .filter { Bill.codeToken($0) == nil }
            .joined(separator: " — ")
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? title : name
    }

    /// Returns the trimmed text when it looks like a measure code (e.g. "H.R.
    /// 1842" or "S. 305"), otherwise `nil`.
    private static func codeToken(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let pattern = #"^[A-Z][A-Za-z.]*\.\s*\d+$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil ? trimmed : nil
    }

    /// Maps a measure type code (e.g. "HR") to its formatted prefix (e.g. "H.R.").
    private static func typePrefix(_ type: String?) -> String? {
        switch type?.uppercased() {
        case "HR": "H.R."
        case "S": "S."
        case "HRES": "H.Res."
        case "SRES": "S.Res."
        case "HJRES": "H.J.Res."
        case "SJRES": "S.J.Res."
        case "HCONRES": "H.Con.Res."
        case "SCONRES": "S.Con.Res."
        default: nil
        }
    }
}

// MARK: - Ranking

extension Bill {
    /// How far the bill has advanced through the legislative process, from 0
    /// (just introduced) to 1 (enacted). Bills further along carry more weight.
    var progressWeight: Double {
        switch status {
        case .introduced: 0.1
        case .inCommittee: 0.25
        case .passedHouse, .passedSenate: 0.6
        case .toPresident: 0.85
        case .enacted: 1.0
        }
    }

    /// A ranking score that surfaces consequential, *active* legislation first:
    /// it rises with how far the bill has advanced and decays as its most recent
    /// action ages. A bill near the President's desk outranks one stuck in
    /// committee, but a long-dormant bill sinks beneath fresher activity.
    func importance(asOf now: Date = Date()) -> Double {
        let days = max(0, now.timeIntervalSince(latestActionDate) / 86_400)
        // Exponential decay with a roughly three-week time constant.
        let recency = exp(-days / 21)
        // Blend legislative progress with recency in roughly equal measure: a
        // bill near the President's desk outranks one stuck in committee, but a
        // long-dormant advanced bill sinks beneath fresher activity. This keeps
        // a healthy mix of stages in the feed rather than letting enacted laws
        // crowd out recent committee and introduced bills.
        return progressWeight + recency
    }
}

extension Array where Element == Bill {
    /// Orders bills by importance (legislative progress plus recency), most
    /// important first.
    func rankedByImportance(asOf now: Date = Date()) -> [Bill] {
        sorted { $0.importance(asOf: now) > $1.importance(asOf: now) }
    }
}
