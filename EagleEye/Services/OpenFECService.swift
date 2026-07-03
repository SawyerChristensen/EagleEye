//
//  OpenFECService.swift
//  EagleEye
//
//  Loads a member's top campaign funders from the Federal Election Commission's
//  OpenFEC API (https://api.open.fec.gov). "Top funders" here means the
//  organizations that gave the most *directly* to the member's principal
//  campaign committee through their affiliated political action committees
//  (PACs) — the only way a company, union, or trade group can contribute, since
//  federal law bars direct corporate/union treasury donations to candidates.
//
//  ---------------------------------------------------------------------------
//  Setting up your own OpenFEC API key
//  ---------------------------------------------------------------------------
//  OpenFEC is free and shares the api.data.gov key infrastructure.
//
//    1. Request a key at https://api.data.gov/signup/. It arrives by email.
//    2. Add an `OpenFECAPIKey` entry to your (gitignored) `Secrets.plist`
//       alongside the Congress.gov key, or set the `OPENFEC_API_KEY`
//       environment variable in your scheme.
//
//  Without a key the Top Funders section simply stays empty — the rest of the
//  profile is unaffected, and the large FEC crosswalk is never downloaded.
//

import Foundation

/// Fetches a member's top campaign funders from OpenFEC. Mapping a member to
/// their FEC candidate record relies on the `id.fec` crosswalk published in the
/// open-source `unitedstates/congress-legislators` dataset, since Congress.gov
/// carries no FEC identifiers.
struct OpenFECService {
    /// Placeholder used when no real key has been configured.
    static let apiKeyPlaceholder = "YOUR_OPENFEC_API_KEY"

    var apiKey: String = OpenFECService.configuredAPIKey
    var session: URLSession = .shared

    /// The full `legislators-current` dataset, whose entries carry each member's
    /// Bioguide ID and FEC candidate IDs. Fetched once for the whole delegation.
    static let crosswalkURL = URL(
        string: "https://unitedstates.github.io/congress-legislators/legislators-current.json"
    )!

    private static let baseURL = "https://api.open.fec.gov/v1"

    /// Whether a usable key is configured. When false the caller should skip the
    /// funder lookups entirely, avoiding the large crosswalk download.
    var isConfigured: Bool {
        !apiKey.isEmpty && apiKey != Self.apiKeyPlaceholder
    }

    /// Loads the Bioguide → FEC-candidate-ID crosswalk from the legislators
    /// dataset. Returns an empty map on any failure, which simply leaves every
    /// member's funders empty.
    func candidateIDsByBioguide() async -> [String: [String]] {
        guard let (data, response) = try? await session.data(from: Self.crosswalkURL),
              let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              let entries = try? JSONDecoder().decode([LegislatorEntry].self, from: data) else {
            return [:]
        }

        var result: [String: [String]] = [:]
        for entry in entries {
            guard let bioguide = entry.id.bioguide,
                  let fec = entry.id.fec, !fec.isEmpty else { continue }
            result[bioguide] = fec
        }
        return result
    }

    /// Loads the organizations that gave the most *directly* to the member's
    /// principal campaign committee — their affiliated political action
    /// committees (PACs). Returns an empty list when no key is configured, no FEC
    /// candidate matches the member's chamber, on any failure, or when the member
    /// takes no PAC money (which is itself meaningful).
    func topFunders(
        candidateIDs: [String],
        office: Office,
        limit: Int = 6
    ) async -> [Funder] {
        guard isConfigured,
              let candidateID = Self.candidateID(matching: office, from: candidateIDs) else {
            return []
        }

        // A candidate → principal committee → its incoming PAC contributions: the
        // committee is what actually receives (and reports) the money.
        guard let committee = await principalCommittee(forCandidate: candidateID) else {
            return []
        }

        return await topPACContributions(
            committeeID: committee.id,
            period: committee.latestCycle,
            limit: limit
        )
    }

    /// Loads the member's top *individual* contributors, grouped the way voters
    /// think of them: by the employer whose staff gave the most (labeled
    /// "Employees", since federal law bars the company itself from donating), and
    /// — for the self-employed and independents who list no employer — by
    /// occupation (e.g. "Attorneys"). Returns an empty list under the same
    /// conditions as `topFunders`.
    func topIndividualFunders(
        candidateIDs: [String],
        office: Office,
        limit: Int = 6
    ) async -> [Funder] {
        guard isConfigured,
              let candidateID = Self.candidateID(matching: office, from: candidateIDs),
              let committee = await principalCommittee(forCandidate: candidateID) else {
            return []
        }

        return await topIndividualContributions(
            committeeID: committee.id,
            period: committee.latestCycle,
            limit: limit
        )
    }

    // MARK: - Candidate → committee

    /// Picks the FEC candidate ID for the member's current chamber. FEC IDs are
    /// prefixed by office ("S" Senate, "H" House), and a member who has served in
    /// both chambers carries an ID for each; matching the prefix keeps a former
    /// House member's Senate funders from showing their old campaign's.
    private static func candidateID(matching office: Office, from ids: [String]) -> String? {
        let prefix = office == .senator ? "S" : "H"
        return ids.first { $0.hasPrefix(prefix) } ?? ids.first
    }

    /// Resolves a candidate's principal campaign committee and the most recent
    /// election cycle it has data for.
    private func principalCommittee(forCandidate candidateID: String) async -> (id: String, latestCycle: Int)? {
        guard let response = try? await getJSON(
            CommitteesResponse.self,
            path: "candidate/\(candidateID)/committees",
            queryItems: [URLQueryItem(name: "per_page", value: "20")]
        ) else {
            return nil
        }

        // Designation "P" is the candidate's principal campaign committee — the
        // main fundraising vehicle, as opposed to joint or leadership PACs.
        let principals = response.results.filter { $0.designation == "P" }
        let committees = principals.isEmpty ? response.results : principals
        guard let committee = committees.max(by: {
            ($0.cycles?.max() ?? 0) < ($1.cycles?.max() ?? 0)
        }) else {
            return nil
        }
        return (committee.committeeID, committee.cycles?.max() ?? Self.fallbackCycle)
    }

    /// Current default election cycle, used when a committee lists none.
    private static let fallbackCycle = 2026

    /// Loads the organizations' PACs that gave most directly to the committee.
    ///
    /// Federal law bars companies and unions from donating to candidates out of
    /// their own treasuries, so the closest thing to a "direct organizational
    /// donation" is a contribution from the organization's affiliated PAC
    /// (e.g. "Boeing Company PAC"). Pulling Schedule A with `is_individual=false`
    /// yields every non-individual contribution; keeping only `entity_type ==
    /// "PAC"` drops party-committee support, joint-fundraising transfers, and the
    /// member's own leadership fund (all `COM`/`ORG`). Rows are aggregated by
    /// contributor since a PAC typically gives once per election.
    private func topPACContributions(committeeID: String, period: Int, limit: Int) async -> [Funder] {
        guard let response = try? await getJSON(
            ScheduleAResponse.self,
            path: "schedules/schedule_a",
            queryItems: [
                URLQueryItem(name: "committee_id", value: committeeID),
                URLQueryItem(name: "two_year_transaction_period", value: String(period)),
                URLQueryItem(name: "is_individual", value: "false"),
                URLQueryItem(name: "sort", value: "-contribution_receipt_amount"),
                URLQueryItem(name: "per_page", value: "100"),
            ]
        ) else {
            return []
        }

        var merged: [String: (display: String, total: Double)] = [:]
        for row in response.results {
            guard row.entityType == "PAC",
                  let name = row.contributorName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, let amount = row.amount, amount > 0 else {
                continue
            }
            let key = row.contributorId ?? name.uppercased()
            let existing = merged[key]
            merged[key] = (
                display: existing?.display ?? Self.titleCased(name),
                total: (existing?.total ?? 0) + amount
            )
        }

        return merged.values
            .sorted { $0.total > $1.total }
            .prefix(limit)
            // The section footnote explains these are PACs, so the per-row
            // category is left blank rather than repeating "PAC" on every line.
            .map { Funder(name: $0.display, amount: Int($0.total.rounded()), category: "") }
    }

    /// Employer/occupation values that carry no useful grouping — the donor is
    /// their own boss, out of the workforce, or simply declined to say. Compared
    /// against the uppercased, trimmed field.
    private static let uninformativeAffiliations: Set<String> = [
        "", "SELF", "SELF-EMPLOYED", "SELF EMPLOYED", "SELFEMPLOYED", "NONE",
        "N/A", "NA", "NOT EMPLOYED", "NOT-EMPLOYED", "UNEMPLOYED", "RETIRED",
        "HOMEMAKER", "INFORMATION REQUESTED", "INFORMATION REQUESTED PER BEST EFFORTS",
        "REQUESTED", "REFUSED", "UNKNOWN",
    ]

    /// Loads the member's top individual contributors, aggregated by the employer
    /// or occupation they listed.
    ///
    /// Individuals must be itemized by name, so the meaningful unit is the group
    /// they belong to — the standard way campaign-finance trackers surface "top
    /// contributors". Each row's employer is preferred (its staff, hence the
    /// "Employees" label); when that's missing or generic, the occupation stands
    /// in and is pluralized for display (e.g. "Attorney" → "Attorneys"). Rows
    /// with neither are dropped.
    private func topIndividualContributions(committeeID: String, period: Int, limit: Int) async -> [Funder] {
        guard let response = try? await getJSON(
            ScheduleAResponse.self,
            path: "schedules/schedule_a",
            queryItems: [
                URLQueryItem(name: "committee_id", value: committeeID),
                URLQueryItem(name: "two_year_transaction_period", value: String(period)),
                URLQueryItem(name: "is_individual", value: "true"),
                URLQueryItem(name: "sort", value: "-contribution_receipt_amount"),
                URLQueryItem(name: "per_page", value: "100"),
            ]
        ) else {
            return []
        }

        var merged: [String: (display: String, isEmployer: Bool, total: Double)] = [:]
        for row in response.results {
            guard let amount = row.amount, amount > 0 else { continue }

            let employer = row.contributorEmployer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let occupation = row.contributorOccupation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let group: (key: String, display: String, isEmployer: Bool)
            if !Self.uninformativeAffiliations.contains(employer.uppercased()) {
                group = ("EMP:\(employer.uppercased())", Self.titleCased(employer), true)
            } else if !Self.uninformativeAffiliations.contains(occupation.uppercased()) {
                group = ("OCC:\(occupation.uppercased())", Self.pluralized(Self.titleCased(occupation)), false)
            } else {
                continue
            }

            let existing = merged[group.key]
            merged[group.key] = (
                display: existing?.display ?? group.display,
                isEmployer: group.isEmployer,
                total: (existing?.total ?? 0) + amount
            )
        }

        return merged.values
            .sorted { $0.total > $1.total }
            .prefix(limit)
            // Employer groups are the company's staff; occupation groups already
            // read as a plural noun, so they need no subtitle.
            .map { Funder(
                name: $0.display,
                amount: Int($0.total.rounded()),
                category: $0.isEmployer ? "Employees of" : ""
            ) }
    }

    /// Pluralizes a single occupation noun for display using basic English
    /// rules — enough for the short, common titles the FEC records (e.g.
    /// "Attorney" → "Attorneys", "Physician" → "Physicians", "Business" →
    /// "Businesses"). Multi-word titles are pluralized on their final word.
    private static func pluralized(_ noun: String) -> String {
        guard let lastSpace = noun.lastIndex(of: " ") else {
            return pluralizeWord(noun)
        }
        let head = noun[..<noun.index(after: lastSpace)]
        let tail = String(noun[noun.index(after: lastSpace)...])
        return head + pluralizeWord(tail)
    }

    private static func pluralizeWord(_ word: String) -> String {
        guard let last = word.last else { return word }
        let lower = word.lowercased()
        if lower.hasSuffix("s") || lower.hasSuffix("x") || lower.hasSuffix("z")
            || lower.hasSuffix("ch") || lower.hasSuffix("sh") {
            return word + "es"
        }
        // Consonant + "y" becomes "ies" ("Attorney" keeps its vowel-"y" and just
        // gains an "s").
        if last == "y", let penult = word.dropLast().last, !"aeiou".contains(penult.lowercased()) {
            return word.dropLast() + "ies"
        }
        return word + "s"
    }

    /// Renders an all-caps FEC employer name (e.g. "GOOGLE INC") as title case
    /// for display, leaving short acronyms like "AT&T" untouched.
    private static func titleCased(_ name: String) -> String {
        name.split(separator: " ").map { word -> String in
            let string = String(word)
            // Keep short all-caps tokens (likely acronyms) as-is.
            if string.count <= 3, string.allSatisfy({ $0.isUppercase || !$0.isLetter }) {
                return string
            }
            return string.prefix(1).uppercased() + string.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    // MARK: - Networking

    /// Performs a GET against OpenFEC and decodes the response, appending the
    /// shared `api_key` query item.
    private func getJSON<T: Decodable>(
        _ type: T.Type,
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        var components = URLComponents(string: "\(Self.baseURL)/\(path)")!
        components.queryItems = queryItems + [URLQueryItem(name: "api_key", value: apiKey)]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Key resolution

    /// Resolves the key from, in order: the `OPENFEC_API_KEY` environment
    /// variable, the bundled `Secrets.plist` (`OpenFECAPIKey`), or the
    /// `OpenFECAPIKey` Info.plist entry. Falls back to the placeholder, which
    /// keeps the Top Funders section empty.
    static var configuredAPIKey: String {
        if let env = ProcessInfo.processInfo.environment["OPENFEC_API_KEY"], !env.isEmpty {
            return env
        }
        if let secret = secretsValue(forKey: "OpenFECAPIKey") {
            return secret
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "OpenFECAPIKey") as? String,
           !plist.isEmpty {
            return plist
        }
        return apiKeyPlaceholder
    }

    /// Reads a string from the bundled `Secrets.plist`, if present.
    private static func secretsValue(forKey key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any],
              let value = dict[key] as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

// MARK: - Wire format

/// One entry from the `legislators-current` dataset — only the identifiers are
/// decoded.
private struct LegislatorEntry: Decodable {
    let id: ID

    struct ID: Decodable {
        let bioguide: String?
        let fec: [String]?
    }
}

/// The candidate-committees payload, listing the committees tied to a candidate.
private struct CommitteesResponse: Decodable {
    let results: [Committee]

    struct Committee: Decodable {
        let committeeID: String
        let designation: String?
        let cycles: [Int]?

        enum CodingKeys: String, CodingKey {
            case committeeID = "committee_id"
            case designation
            case cycles
        }
    }
}

/// A page of itemized Schedule A receipts — used, with `is_individual=false`, to
/// find the committee's incoming PAC contributions.
private struct ScheduleAResponse: Decodable {
    let results: [Row]

    struct Row: Decodable {
        let contributorName: String?
        let contributorId: String?
        /// The contributor's FEC entity type, e.g. "PAC", "COM", "ORG", "IND".
        let entityType: String?
        /// For individual contributors, the employer and occupation they listed,
        /// used to group donations into "top contributors".
        let contributorEmployer: String?
        let contributorOccupation: String?
        let amount: Double?

        enum CodingKeys: String, CodingKey {
            case contributorName = "contributor_name"
            case contributorId = "contributor_id"
            case entityType = "entity_type"
            case contributorEmployer = "contributor_employer"
            case contributorOccupation = "contributor_occupation"
            case amount = "contribution_receipt_amount"
        }
    }
}
