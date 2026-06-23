//
//  CongressService.swift
//  EagleEye
//
//  A thin client for the Congress.gov API (https://api.congress.gov).
//  Used to load the current congressional delegation, including each
//  member's official portrait.
//
//  Get a free API key at https://api.congress.gov/sign-up/ and supply it
//  via the CONGRESS_GOV_API_KEY environment variable, a `CongressGovAPIKey`
//  entry in Info.plist, or by replacing `apiKeyPlaceholder` below.
//

import Foundation

/// Loads members of Congress from the Congress.gov API.
struct CongressService {
    /// The Congress currently in session (the 119th covers 2025–2026).
    static let currentCongress = 119

    /// Placeholder used when no real key has been configured.
    static let apiKeyPlaceholder = "YOUR_CONGRESS_GOV_API_KEY"

    var apiKey: String = CongressService.configuredAPIKey
    var session: URLSession = .shared

    enum ServiceError: LocalizedError {
        case missingAPIKey
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "No Congress.gov API key configured."
            case .badResponse(let code):
                "Congress.gov returned HTTP \(code)."
            }
        }
    }

    /// Fetches the current delegation for a state, identified by its
    /// two-letter postal code (e.g. "CA"). Returns the state's senators and
    /// all of its House members.
    func currentMembers(forState stateCode: String) async throws -> [Representative] {
        guard !apiKey.isEmpty, apiKey != Self.apiKeyPlaceholder else {
            throw ServiceError.missingAPIKey
        }

        var components = URLComponents(
            string: "https://api.congress.gov/v3/member/congress/\(Self.currentCongress)/\(stateCode)"
        )!
        components.queryItems = [
            URLQueryItem(name: "currentMember", value: "true"),
            URLQueryItem(name: "limit", value: "250"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "api_key", value: apiKey),
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.badResponse(-1)
        }
        guard 200..<300 ~= http.statusCode else {
            throw ServiceError.badResponse(http.statusCode)
        }

        let payload = try JSONDecoder().decode(MemberListResponse.self, from: data)
        return payload.members.compactMap(Representative.init(member:))
    }

    /// Resolves the API key from, in order: the `CONGRESS_GOV_API_KEY`
    /// environment variable, the bundled (gitignored) `Secrets.plist`, or the
    /// `CongressGovAPIKey` Info.plist entry. Falls back to the placeholder when
    /// none is set, which keeps the app on sample data.
    static var configuredAPIKey: String {
        if let env = ProcessInfo.processInfo.environment["CONGRESS_GOV_API_KEY"],
           !env.isEmpty {
            return env
        }
        if let secret = secretsValue(forKey: "CongressGovAPIKey") {
            return secret
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "CongressGovAPIKey") as? String,
           !plist.isEmpty {
            return plist
        }
        return apiKeyPlaceholder
    }

    /// Reads a string from the bundled `Secrets.plist`, if present. Returns nil
    /// when the file or key is missing or empty (e.g. on a fresh clone).
    private static func secretsValue(forKey key: String) -> String? {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = plist as? [String: Any],
            let value = dict[key] as? String,
            !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

// MARK: - Wire format

/// The top-level shape of a Congress.gov member-list response.
private struct MemberListResponse: Decodable {
    let members: [MemberDTO]
}

/// A single member as returned by the Congress.gov list endpoints.
struct MemberDTO: Decodable {
    let bioguideId: String
    /// The member's name in "Last, First Middle" order.
    let name: String
    let partyName: String?
    let state: String
    /// Present for House members; `nil` for senators.
    let district: Int?
    let depiction: Depiction?
    let terms: Terms?

    struct Depiction: Decodable {
        let imageUrl: String?
        let attribution: String?
    }

    /// The API nests the list of terms under an `item` array.
    struct Terms: Decodable {
        let item: [Term]
    }

    struct Term: Decodable {
        let chamber: String?
        let startYear: Int?
        let endYear: Int?
    }
}

// MARK: - Mapping

extension Representative {
    /// Builds a domain `Representative` from a Congress.gov member record.
    ///
    /// Note: the member endpoint does not provide office coordinates, so
    /// `officeLatitude`/`officeLongitude` default to 0 — the map needs a
    /// separate geocoding pass before it can plot live members.
    init?(member: MemberDTO) {
        let terms = member.terms?.item ?? []

        // The most recent term tells us the member's current chamber.
        let latestTerm = terms.max { ($0.startYear ?? 0) < ($1.startYear ?? 0) }
        let chamber = latestTerm?.chamber
            ?? (member.district == nil ? "Senate" : "House of Representatives")
        let office: Office = chamber.localizedCaseInsensitiveContains("senate")
            ? .senator : .representative

        let party: Party
        switch member.partyName {
        case "Democratic", "Democrat": party = .democrat
        case "Republican": party = .republican
        default: party = .independent
        }

        // Tenure starts at the earliest term we have on record.
        let tenureStart = terms.compactMap(\.startYear).min()
            .flatMap { Calendar.current.date(from: DateComponents(year: $0, month: 1, day: 1)) }
            ?? Date()

        self.init(
            name: Self.displayName(fromInvertedOrder: member.name),
            party: party,
            office: office,
            state: member.state,
            district: member.district,
            bioguideID: member.bioguideId,
            officeLatitude: 0,
            officeLongitude: 0,
            portraitURL: member.depiction?.imageUrl.flatMap(URL.init(string:)),
            tenureStart: tenureStart
        )
    }

    /// Converts the API's "Last, First Middle" into display order "First Middle Last".
    private static func displayName(fromInvertedOrder name: String) -> String {
        let parts = name
            .split(separator: ",", maxSplits: 1)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return name }
        return "\(parts[1]) \(parts[0])"
    }
}
