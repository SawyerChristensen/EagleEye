//
//  SenateService.swift
//  EagleEye
//
//  Loads senators' recent floor votes from Senate.gov's public roll-call XML.
//
//  Congress.gov's roll-call vote endpoints cover the House of Representatives
//  only, so senators would otherwise show no voting history. Senate.gov
//  publishes its own roll calls as XML: a per-session menu listing every vote
//  (with its question and the measure it concerned), and a per-vote file
//  carrying the full member roster. Both are public — no API key is required.
//

import Foundation

/// Loads a senator's recent significant floor votes from Senate.gov.
struct SenateService {
    var session: URLSession = .shared

    /// Resolves a measure's short, popular Congress.gov title (e.g. "Laken Riley
    /// Act") from its congress/type/number, so Senate rows read like the House
    /// feed rather than carrying Senate.gov's long official titles. Injected by
    /// `CongressService`, which owns the API key; the default (used in isolation)
    /// leaves the Senate.gov title in place.
    var resolveTitle: (_ congress: Int, _ type: String, _ number: String) async -> String? = { _, _, _ in nil }

    /// The Congress whose votes we read, kept in step with the rest of the app.
    private var currentCongress: Int { CongressService.currentCongress }

    /// Returns the senator's most recent *significant* floor votes, newest first
    /// — final passage of a bill or resolution, not the cloture motions, motions
    /// to proceed, and amendment votes that make up the bulk of roll calls.
    ///
    /// Non-senators and members whose state can't be mapped to a postal code
    /// (e.g. sample data) yield an empty list.
    func votingHistory(for representative: Representative, limit: Int = 8) async -> [VoteRecord] {
        guard representative.office == .senator,
              let stateCode = Self.stateCode(for: representative.state) else {
            return []
        }

        // The per-session menu already carries each vote's question and measure,
        // so the significant ones can be picked without fetching every detail —
        // only the votes we keep need their full roster pulled.
        let candidates = await significantVotes(limit: limit)
        guard !candidates.isEmpty else { return [] }

        // Resolve this senator's position on each kept vote concurrently,
        // restoring the newest-first ordering afterward.
        return await withTaskGroup(of: (Int, VoteRecord?).self) { group in
            for (index, vote) in candidates.enumerated() {
                group.addTask {
                    (index, await self.voteRecord(for: representative, stateCode: stateCode, on: vote))
                }
            }
            var collected: [(Int, VoteRecord)] = []
            for await (index, record) in group {
                if let record { collected.append((index, record)) }
            }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    // MARK: - Selecting significant votes

    /// Pulls both sessions' vote menus, keeps the significant measure votes, and
    /// returns the newest `limit`, newest first. Ordering is by (session, vote
    /// number) since both climb with time and the menu carries no full date.
    private func significantVotes(limit: Int) async -> [MenuVote] {
        async let secondSession = menu(session: 2)
        async let firstSession = menu(session: 1)
        let all = await secondSession + firstSession
        return all
            .filter(\.isSignificant)
            .sorted { ($0.session, $0.number) > ($1.session, $1.number) }
            .prefix(limit)
            .map { $0 }
    }

    /// Loads and parses one session's vote menu. Returns an empty list for a
    /// session that hasn't happened yet or on any failure.
    private func menu(session: Int) async -> [MenuVote] {
        let url = URL(string:
            "https://www.senate.gov/legislative/LIS/roll_call_lists/vote_menu_\(currentCongress)_\(session).xml"
        )!
        guard let data = await fetchXML(url) else { return [] }
        return SenateMenuParser.parse(data, session: session)
    }

    // MARK: - Resolving a single vote

    /// Fetches one roll call's full detail, finds how this senator voted, and
    /// builds a record labelled with the measure's name. Returns nil when the
    /// senator isn't on the roster or the lookup fails.
    private func voteRecord(
        for representative: Representative,
        stateCode: String,
        on vote: MenuVote
    ) async -> VoteRecord? {
        let padded = String(format: "%05d", vote.number)
        let url = URL(string:
            "https://www.senate.gov/legislative/LIS/roll_call_votes/vote\(currentCongress)\(vote.session)/vote_\(currentCongress)_\(vote.session)_\(padded).xml"
        )!
        guard let data = await fetchXML(url),
              let detail = SenateVoteParser.parse(data) else {
            return nil
        }

        // Two senators share each state; pick the one whose surname appears in
        // this member's name, which sidesteps first-name/nickname mismatches.
        guard let member = detail.members.first(where: {
            $0.state.caseInsensitiveCompare(stateCode) == .orderedSame
                && representative.name.localizedCaseInsensitiveContains($0.lastName)
        }) else {
            return nil
        }

        let measure = Self.measure(from: vote.issue)
        return VoteRecord(
            billTitle: await title(for: vote, detail: detail),
            position: Self.position(fromCast: member.voteCast),
            date: detail.date ?? Date(),
            question: vote.question,
            congress: currentCongress,
            type: measure?.type,
            number: measure?.number
        )
    }

    /// The measure's display title, matching the House feed's naming. Resolves
    /// the short Congress.gov title and formats it as "Title — S. 5", falling
    /// back to the Senate.gov title and finally the clerk's descriptive line
    /// when the measure can't be resolved.
    private func title(for vote: MenuVote, detail: SenateVoteDetail) async -> String {
        if let measure = Self.measure(from: vote.issue),
           let resolved = await resolveTitle(currentCongress, measure.type, measure.number) {
            return Bill.displayTitle(type: measure.type, number: measure.number, title: resolved)
        }
        return detail.measureTitle ?? vote.title
    }

    /// Splits a measure label like "H.J.Res. 140" into the Congress.gov type
    /// code and number it addresses ("hjres", "140"). Returns nil for labels
    /// that carry no number (e.g. a stray procedural entry).
    static func measure(from label: String) -> (type: String, number: String)? {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard let firstDigit = trimmed.firstIndex(where: \.isNumber) else { return nil }
        let type = trimmed[..<firstDigit].filter(\.isLetter).lowercased()
        let number = trimmed[firstDigit...].trimmingCharacters(in: .whitespaces)
        guard !type.isEmpty, !number.isEmpty else { return nil }
        return (type, number)
    }

    // MARK: - Bill roll-call tally

    /// Resolves a single Senate roll call to its full member roster for a bill's
    /// detail screen — the Senate counterpart to the House tally Congress.gov
    /// provides. Returns nil on any failure or when the roster comes back empty.
    func billTally(congress: Int, session: Int, rollCall: Int) async -> BillVoteTally? {
        let padded = String(format: "%05d", rollCall)
        let url = URL(string:
            "https://www.senate.gov/legislative/LIS/roll_call_votes/vote\(congress)\(session)/vote_\(congress)_\(session)_\(padded).xml"
        )!
        guard let data = await fetchXML(url),
              let detail = SenateVoteParser.parse(data) else {
            return nil
        }

        let members = detail.members.map { member -> MemberVote in
            let name = [member.firstName, member.lastName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return MemberVote(
                // Senate rosters carry no Bioguide ID, so key rows by state and
                // surname — enough to surface the user's own senators on top.
                id: MemberVote.matchKey(state: member.state, lastName: member.lastName),
                name: name.isEmpty ? member.lastName : name,
                party: Self.party(fromCode: member.party),
                state: member.state,
                position: Self.position(fromCast: member.voteCast)
            )
        }
        guard !members.isEmpty else { return nil }

        return BillVoteTally(
            chamber: .senate,
            question: detail.question,
            date: detail.date,
            result: detail.result,
            memberVotes: members
        )
    }

    // MARK: - Networking

    /// Fetches a Senate.gov XML document. A User-Agent is set because the site
    /// rejects requests without one. Returns nil on any non-2xx or failure.
    private func fetchXML(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("EagleEye/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            return nil
        }
        return data
    }

    // MARK: - Mapping helpers

    /// Maps the Senate clerk's recorded vote ("Yea", "Nay", "Present", "Not
    /// Voting") onto the app's simpler position model.
    static func position(fromCast cast: String) -> VotePosition {
        switch cast.lowercased() {
        case "yea", "aye", "yes": .yea
        case "nay", "no": .nay
        case "present": .present
        default: .notVoting
        }
    }

    /// Maps the Senate clerk's single-letter party code ("D"/"R"/"I") onto the
    /// app's party model.
    static func party(fromCode code: String) -> Party {
        switch code.uppercased() {
        case "D": .democrat
        case "R": .republican
        default: .independent
        }
    }

    /// Parses the timestamps the vote-detail files use, e.g.
    /// "December 18, 2025, 12:30 PM".
    static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return detailDateFormatter.date(from: string)
    }

    /// Resolves a state name (as Congress.gov returns it, e.g. "Wisconsin") to
    /// its two-letter postal code, which is what the roll-call roster uses. A
    /// value that is already a two-letter code is passed through.
    static func stateCode(for state: String) -> String? {
        let trimmed = state.trimmingCharacters(in: .whitespaces)
        if trimmed.count == 2 { return trimmed.uppercased() }
        return statesByName[trimmed.lowercased()]
    }

    private static let statesByName: [String: String] = [
        "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR",
        "california": "CA", "colorado": "CO", "connecticut": "CT", "delaware": "DE",
        "florida": "FL", "georgia": "GA", "hawaii": "HI", "idaho": "ID",
        "illinois": "IL", "indiana": "IN", "iowa": "IA", "kansas": "KS",
        "kentucky": "KY", "louisiana": "LA", "maine": "ME", "maryland": "MD",
        "massachusetts": "MA", "michigan": "MI", "minnesota": "MN", "mississippi": "MS",
        "missouri": "MO", "montana": "MT", "nebraska": "NE", "nevada": "NV",
        "new hampshire": "NH", "new jersey": "NJ", "new mexico": "NM", "new york": "NY",
        "north carolina": "NC", "north dakota": "ND", "ohio": "OH", "oklahoma": "OK",
        "oregon": "OR", "pennsylvania": "PA", "rhode island": "RI", "south carolina": "SC",
        "south dakota": "SD", "tennessee": "TN", "texas": "TX", "utah": "UT",
        "vermont": "VT", "virginia": "VA", "washington": "WA", "west virginia": "WV",
        "wisconsin": "WI", "wyoming": "WY",
        "american samoa": "AS", "district of columbia": "DC", "guam": "GU",
        "northern mariana islands": "MP", "puerto rico": "PR", "virgin islands": "VI",
    ]
}

/// Shared formatter for the "December 18, 2025, 12:30 PM" timestamps the vote
/// detail files carry.
private let detailDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/New_York")
    formatter.dateFormat = "MMMM d, yyyy, hh:mm a"
    return formatter
}()

// MARK: - Parsed shapes

/// One entry from a session's vote menu — enough to order the votes and decide
/// which are worth resolving to a full roster.
private struct MenuVote {
    let session: Int
    let number: Int
    /// The measure voted on, e.g. "H.R. 21", "S.J.Res. 20", or "PN373" for a
    /// nomination.
    let issue: String
    let question: String
    /// The clerk's descriptive title, used as a fallback when the detail file's
    /// measure name is unavailable.
    let title: String

    /// Whether this roll call decides the fate of a substantive measure — final
    /// passage of a bill, or agreeing to a joint/concurrent resolution or
    /// conference report — rather than a nomination (issue "PN…") or a
    /// procedural step (cloture, motion to proceed, an amendment, a motion to
    /// table). Bare simple resolutions ("On the Resolution") are excluded: they
    /// are dominated by internal, executive-calendar housekeeping rather than
    /// policy positions.
    var isSignificant: Bool {
        guard !issue.isEmpty, !issue.uppercased().hasPrefix("PN") else { return false }
        let question = question.lowercased()
        let passageMarkers = [
            "on passage",
            "on the joint resolution",
            "on the concurrent resolution",
            "on the conference report",
        ]
        return passageMarkers.contains { question.contains($0) }
    }
}

/// A single roll call's detail: when it was taken, the measure it concerned, and
/// how every senator was recorded.
private struct SenateVoteDetail {
    let date: Date?
    /// The short floor question, e.g. "On Passage of the Bill".
    let question: String?
    /// The clerk's outcome text, e.g. "Bill Passed" or "Amendment Rejected".
    let result: String?
    let document: Document?
    let members: [SenateMember]

    /// The measure's familiar name for display, e.g. "Laken Riley Act — S. 5",
    /// preferring the short title over the long official one.
    var measureTitle: String? {
        guard let document else { return nil }
        let name = (document.shortTitle?.isEmpty == false) ? document.shortTitle : document.title
        guard let name, !name.isEmpty else { return document.name }
        guard let code = document.name, !code.isEmpty else { return name }
        return "\(name) — \(code)"
    }

    struct Document {
        let name: String?
        let title: String?
        let shortTitle: String?
    }

    struct SenateMember {
        let firstName: String
        let lastName: String
        /// The clerk's single-letter party code, e.g. "D", "R", "I".
        let party: String
        let state: String
        let voteCast: String
    }
}

// MARK: - XML parsing

/// Parses a session's `vote_menu` XML into its list of votes. Only the fields
/// that are direct children of each `<vote>` are captured, so the nested
/// `<en_bloc>`/`<matter>` entries of batch nomination votes don't leak in.
private final class SenateMenuParser: NSObject, XMLParserDelegate {
    static func parse(_ data: Data, session: Int) -> [MenuVote] {
        let parser = SenateMenuParser(session: session)
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return parser.votes
    }

    private let session: Int
    private var votes: [MenuVote] = []
    private var stack: [String] = []
    private var text = ""

    private var number = ""
    private var issue = ""
    private var question = ""
    private var title = ""

    private init(session: Int) { self.session = session }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        stack.append(elementName)
        text = ""
        if elementName == "vote" {
            number = ""; issue = ""; question = ""; title = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.dropLast().last
        if parent == "vote" {
            switch elementName {
            case "vote_number": number = trimmed
            case "issue": issue = trimmed
            case "question": question = trimmed
            case "title": title = trimmed
            default: break
            }
        }
        if elementName == "vote", let number = Int(number) {
            votes.append(MenuVote(
                session: session, number: number,
                issue: issue, question: question, title: title
            ))
        }
        stack.removeLast()
        text = ""
    }
}

/// Parses a single roll call's detail XML into its date, measure, and roster.
private final class SenateVoteParser: NSObject, XMLParserDelegate {
    static func parse(_ data: Data) -> SenateVoteDetail? {
        let parser = SenateVoteParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() else { return nil }
        return SenateVoteDetail(
            date: SenateService.parseDate(parser.voteDate),
            question: parser.question.isEmpty ? nil : parser.question,
            result: parser.result.isEmpty ? nil : parser.result,
            document: parser.hasDocument
                ? .init(name: parser.docName, title: parser.docTitle, shortTitle: parser.docShortTitle)
                : nil,
            members: parser.members
        )
    }

    private var stack: [String] = []
    private var text = ""

    private var voteDate = ""
    private var question = ""
    private var result = ""
    private var hasDocument = false
    private var docName = ""
    private var docTitle = ""
    private var docShortTitle = ""

    private var members: [SenateVoteDetail.SenateMember] = []
    private var memberFirst = ""
    private var memberLast = ""
    private var memberParty = ""
    private var memberState = ""
    private var memberCast = ""

    private override init() {}

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        stack.append(elementName)
        text = ""
        if elementName == "member" {
            memberFirst = ""; memberLast = ""; memberParty = ""
            memberState = ""; memberCast = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.dropLast().last
        switch (parent, elementName) {
        case ("roll_call_vote", "vote_date"): voteDate = trimmed
        case ("roll_call_vote", "question"): question = trimmed
        case ("roll_call_vote", "vote_result"): result = trimmed
        case ("document", "document_name"): docName = trimmed; hasDocument = true
        case ("document", "document_title"): docTitle = trimmed; hasDocument = true
        case ("document", "document_short_title"): docShortTitle = trimmed
        case ("member", "first_name"): memberFirst = trimmed
        case ("member", "last_name"): memberLast = trimmed
        case ("member", "party"): memberParty = trimmed
        case ("member", "state"): memberState = trimmed
        case ("member", "vote_cast"): memberCast = trimmed
        case ("members", "member"):
            members.append(.init(
                firstName: memberFirst, lastName: memberLast, party: memberParty,
                state: memberState, voteCast: memberCast
            ))
        default: break
        }
        stack.removeLast()
        text = ""
    }
}
