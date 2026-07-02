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

/// The 32 policy areas the Library of Congress assigns to legislation. A bill
/// carries at most one, which we surface as its single topic alongside a
/// best-matching SF Symbol for quick scanning.
enum PolicyArea: String, CaseIterable {
    case agricultureAndFood = "Agriculture and Food"
    case animals = "Animals"
    case armedForces = "Armed Forces and National Security"
    case artsCultureReligion = "Arts, Culture, Religion"
    case civilRights = "Civil Rights and Liberties, Minority Issues"
    case commerce = "Commerce"
    case congress = "Congress"
    case crime = "Crime and Law Enforcement"
    case economics = "Economics and Public Finance"
    case education = "Education"
    case emergencyManagement = "Emergency Management"
    case energy = "Energy"
    case environment = "Environmental Protection"
    case families = "Families"
    case finance = "Finance and Financial Sector"
    case foreignTrade = "Foreign Trade and International Finance"
    case government = "Government Operations and Politics"
    case health = "Health"
    case housing = "Housing and Community Development"
    case immigration = "Immigration"
    case internationalAffairs = "International Affairs"
    case labor = "Labor and Employment"
    case law = "Law"
    case nativeAmericans = "Native Americans"
    case publicLands = "Public Lands and Natural Resources"
    case science = "Science, Technology, Communications"
    case socialSciences = "Social Sciences and History"
    case socialWelfare = "Social Welfare"
    case sports = "Sports and Recreation"
    case taxation = "Taxation"
    case transportation = "Transportation and Public Works"
    case waterResources = "Water Resources Development"

    /// The SF Symbol shown alongside the topic label.
    var symbolName: String {
        switch self {
        case .agricultureAndFood: "fork.knife"
        case .animals: "pawprint"
        case .armedForces: "shield"
        case .artsCultureReligion: "paintpalette"
        case .civilRights: "hand.raised"
        case .commerce: "cart"
        case .congress: "building.columns"
        case .crime: "lock.shield"
        case .economics: "chart.line.uptrend.xyaxis"
        case .education: "graduationcap"
        case .emergencyManagement: "exclamationmark.triangle"
        case .energy: "bolt"
        case .environment: "leaf"
        case .families: "figure.2.and.child.holdinghands"
        case .finance: "banknote"
        case .foreignTrade: "shippingbox"
        case .government: "building.2"
        case .health: "cross.case"
        case .housing: "house"
        case .immigration: "airplane.arrival"
        case .internationalAffairs: "globe"
        case .labor: "briefcase"
        case .law: "book.closed"
        case .nativeAmericans: "person.3"
        case .publicLands: "mountain.2"
        case .science: "antenna.radiowaves.left.and.right"
        case .socialSciences: "book"
        case .socialWelfare: "hands.sparkles"
        case .sports: "sportscourt"
        case .taxation: "percent"
        case .transportation: "bus"
        case .waterResources: "drop"
        }
    }

    /// Resolves a raw policy-area string (e.g. from the Congress API) to a known
    /// area, tolerating case differences.
    static func named(_ raw: String) -> PolicyArea? {
        PolicyArea(rawValue: raw)
            ?? allCases.first { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }
    }

    /// The SF Symbol for a raw topic string, falling back to a generic tag icon
    /// for anything outside the 32 canonical areas.
    static func symbolName(for topic: String) -> String {
        named(topic)?.symbolName ?? "tag"
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
    /// Identifies the member and spots the user's own representatives. For House
    /// votes this is the Bioguide ID; the Senate roster is keyed by LIS ID rather
    /// than Bioguide, so Senate rows use `matchKey` instead.
    let id: String
    let name: String
    let party: Party
    /// Two-letter state postal code, e.g. "CA".
    let state: String
    let position: VotePosition
}

extension MemberVote {
    /// A chamber-agnostic identity key like "CA|PADILLA", used to match a member
    /// when no Bioguide ID is on hand (the Senate roll-call roster carries LIS
    /// IDs, not Bioguide). State is normalized to its two-letter postal code.
    static func matchKey(state: String, lastName: String) -> String {
        let code = SenateService.stateCode(for: state) ?? state.uppercased()
        return "\(code)|\(lastName.uppercased())"
    }

    /// Derives a surname from a "First Last" display name for use with
    /// `matchKey`, so the user's senators can be matched against the roster.
    static func lastName(fromDisplayName name: String) -> String {
        name.split(separator: " ").last.map(String.init) ?? name
    }
}

/// The roll-call breakdown for one chamber's vote on a bill: how every member
/// voted, plus the question asked and when. House rosters come from Congress.gov;
/// Senate rosters from Senate.gov's roll-call XML.
struct BillVoteTally: Hashable {
    /// Which chamber's vote this tally is, so the detail screen can label it.
    let chamber: Chamber
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

/// How a bill cleared a chamber when no roll call was taken, parsed from the
/// action text so the detail screen can name the method rather than show a
/// vague "no vote recorded".
enum PassageMethod {
    case voiceVote
    case unanimousConsent
}

/// The result of looking up a bill's roll-call votes.
enum BillVoteOutcome {
    /// One or more recorded roll calls with full member rosters — a bill that
    /// cleared both chambers carries a House and a Senate tally, ordered
    /// most-recent first.
    case recorded([BillVoteTally])
    /// The bill cleared the floor without a roll call. `method` names how when
    /// the action text says so, otherwise `nil`.
    case unrecorded(method: PassageMethod?)
    /// No vote was found — the bill is still pre-floor, or the lookup failed.
    case unavailable
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
        let cleaned = Bill.stripStatutoryClauses(name)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? title : cleaned
    }

    /// Strips the "pursuant to …" statutory-citation clause that clutters the
    /// titles of directing and authorizing resolutions, e.g. turning
    /// "Directing the President pursuant to section 5(c) of the War Powers
    /// Resolution to remove …" into "Directing the President to remove …".
    ///
    /// The clause runs from "pursuant to" up to the proper-noun that names the
    /// statute — "Act", "Resolution", "Code", etc. Matching is non-greedy so it
    /// stops at the first such name, and the names must be capitalized so a
    /// lowercase verb like "act" won't cut the clause short. Any comma that set
    /// the clause off ("President, pursuant to …,") is consumed with it so the
    /// surrounding words read naturally rather than leaving a dangling comma.
    static func stripStatutoryClauses(_ text: String) -> String {
        let clausePattern =
            #",?\s*[Pp]ursuant to\b.+?\b(?:Act|Resolution|Code|Constitution|Statutes at Large|U\.S\.C\.)\b"#
        let stripped = text.replacingOccurrences(
            of: clausePattern,
            with: " ",
            options: .regularExpression
        )
        // Collapse the runs of whitespace left where clauses were removed.
        let collapsed = stripped.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        // Tidy up spaces stranded before punctuation, e.g. "President , to".
        return collapsed.replacingOccurrences(
            of: #"\s+([,.;:])"#,
            with: "$1",
            options: .regularExpression
        )
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
