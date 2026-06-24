//
//  CongressService.swift
//  EagleEye
//
//  A thin client for the Congress.gov API (https://api.congress.gov).
//  Used to load informatin about the current congressional delegation
//
//  ---------------------------------------------------------------------------
//  Setting up your own Congress.gov API key
//  ---------------------------------------------------------------------------
//  The Congress.gov API is free, but each developer needs their own key.
//  To get one and wire it into the app:
//
//    1. Request a key at https://api.congress.gov/sign-up/. It is free and
//       arrives by email, usually within a minute.
//    2. In the EagleEye/EagleEye folder, copy `Secrets.example.plist` to a
//       new file named `Secrets.plist` (same folder). `Secrets.plist` is
//       gitignored, so your key never gets committed or pushed to GitHub.
//    3. Open `Secrets.plist` and replace the `YOUR_CONGRESS_GOV_API_KEY`
//       placeholder with the key from your email, then build and run.
//
//  Prefer not to use a file? You can instead set the `CONGRESS_GOV_API_KEY`
//  environment variable in your scheme, or add a `CongressGovAPIKey` entry to
//  Info.plist. See `configuredAPIKey` below for the full resolution order.
//
//  Until a real key is configured the app falls back to bundled sample data,
//  so it still runs and shows placeholder representatives out of the box.
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
        print("🔍 CongressService: Starting fetch for state \(stateCode)...")
        
        guard !apiKey.isEmpty, apiKey != Self.apiKeyPlaceholder else {
            print("🚨 CongressService Error: API key is missing or still set to placeholder!")
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

        guard let url = components.url else {
            print("🚨 CongressService Error: Failed to construct URL from components.")
            throw URLError(.badURL)
        }
        
        print("🌐 CongressService: Requesting URL: \(url.absoluteString.replacingOccurrences(of: apiKey, with: "REDACTED_KEY"))")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
            print("📥 CongressService: Received raw payload (\(data.count) bytes).")
        } catch {
            print("🚨 CongressService Network Error: \(error.localizedDescription)")
            throw error
        }
        
        guard let http = response as? HTTPURLResponse else {
            print("🚨 CongressService Error: Response was not a valid HTTPURLResponse.")
            throw ServiceError.badResponse(-1)
        }
        
        print("📊 CongressService: HTTP Status Code: \(http.statusCode)")
        
        guard 200..<300 ~= http.statusCode else {
            print("🚨 CongressService Error: Bad HTTP Status Code \(http.statusCode).")
            if let rawString = String(data: data, encoding: .utf8) {
                print("📄 Server error body response: \(rawString)")
            }
            throw ServiceError.badResponse(http.statusCode)
        }

        // Catching specific decoding errors pinpointed to exact lines/keys
        do {
            let payload = try JSONDecoder().decode(MemberListResponse.self, from: data)
            let mappedRepresentatives = payload.members.compactMap(Representative.init(member:))
            print("✅ CongressService Success: Successfully decoded and mapped \(mappedRepresentatives.count) representatives.")
            return mappedRepresentatives
        } catch let decodingError as DecodingError {
            print("🚨 CongressService JSON Decoding Failure!")
            switch decodingError {
            case .typeMismatch(let type, let context):
                print("❌ Type Mismatch: Expected \(type) at coding path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                print("💡 Context: \(context.debugDescription)")
            case .valueNotFound(let type, let context):
                print("❌ Value Not Found: Expected \(type) at coding path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                print("💡 Context: \(context.debugDescription)")
            case .keyNotFound(let key, let context):
                print("❌ Key Not Found: Missing key '\(key.stringValue)' at coding path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                print("💡 Context: \(context.debugDescription)")
            case .dataCorrupted(let context):
                print("❌ Data Corrupted at coding path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                print("💡 Context: \(context.debugDescription)")
            @unknown default:
                print("❌ Unknown decoding error: \(decodingError)")
            }
            
            // Helpful step to see the exact structural anomaly causing the crash
            if let rawJSONString = String(data: data, encoding: .utf8) {
                print("📝 Raw JSON Payload context begins below:")
                print(String(rawJSONString.prefix(2000))) // Print up to first 2000 characters so console isn't flooded
            }
            throw decodingError
        } catch {
            print("🚨 CongressService Unexpected error during decoding phase: \(error)")
            throw error
        }
    }

    /// Resolves the API key from, in order: the `CONGRESS_GOV_API_KEY`
    /// environment variable, the bundled (gitignored) `Secrets.plist`, or the
    /// `CongressGovAPIKey` Info.plist entry. Falls back to the placeholder when
    /// none is set, which keeps the app on sample data.
    static var configuredAPIKey: String {
        if let env = ProcessInfo.processInfo.environment["CONGRESS_GOV_API_KEY"],
           !env.isEmpty {
            print("🔑 CongressService Key Resolution: Using key from Environment Variable.")
            return env
        }
        if let secret = secretsValue(forKey: "CongressGovAPIKey") {
            print("🔑 CongressService Key Resolution: Using key from Secrets.plist.")
            return secret
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "CongressGovAPIKey") as? String,
           !plist.isEmpty {
            print("🔑 CongressService Key Resolution: Using key from Info.plist.")
            return plist
        }
        print("⚠️ CongressService Key Resolution WARNING: No key detected. Defaulting to placeholder.")
        return apiKeyPlaceholder
    }

    /// Reads a string from the bundled `Secrets.plist`, if present. Returns nil
    /// when the file or key is missing or empty (e.g. on a fresh clone).
    private static func secretsValue(forKey key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
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

private struct MemberListResponse: Decodable {
    let members: [MemberDTO]
}

struct MemberDTO: Decodable {
    let bioguideId: String
    let name: String
    let partyName: String?
    let state: String
    let district: Int?
    let depiction: Depiction?
    let terms: Terms?

    struct Depiction: Decodable {
        let imageUrl: String?
        let attribution: String?
    }

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
    init?(member: MemberDTO) {
        let terms = member.terms?.item ?? []

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

    private static func displayName(fromInvertedOrder name: String) -> String {
        let parts = name
            .split(separator: ",", maxSplits: 1)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return name }
        return "\(parts[1]) \(parts[0])"
    }
}
