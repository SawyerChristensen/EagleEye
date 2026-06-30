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

    /// Returns a copy of `representative` with its sponsored/cosponsored bill
    /// lists and recent voting history filled in from the member's Congress.gov
    /// endpoints. The lookups run concurrently. Sample members (no Bioguide ID)
    /// and any failed lookup leave the corresponding section unchanged/empty.
    func enrichedProfile(for representative: Representative, limit: Int = 20) async -> Representative {
        guard let bioguideID = representative.bioguideID else { return representative }

        async let sponsored = legislation(
            SponsoredLegislationResponse.self,
            path: "member/\(bioguideID)/sponsored-legislation",
            limit: limit
        )
        async let cosponsored = legislation(
            CosponsoredLegislationResponse.self,
            path: "member/\(bioguideID)/cosponsored-legislation",
            limit: limit
        )
        async let votes = votingHistory(for: representative)

        return representative
            .withBills(sponsored: await sponsored, cosponsored: await cosponsored)
            .withVotes(await votes)
    }

    // MARK: - Voting history

    /// Returns the member's most recent *significant* House floor votes, newest
    /// first — final passage of a bill or resolution, not the procedural motions
    /// (previous question, motions to recommit, amendments) that make up the
    /// bulk of roll calls.
    ///
    /// The Congress.gov roll-call vote endpoints cover the House of
    /// Representatives only (from the 118th Congress onward), so senators and
    /// sample members (no Bioguide ID) yield an empty list.
    func votingHistory(for representative: Representative, limit: Int = 8) async -> [VoteRecord] {
        guard representative.office == .representative,
              let bioguideID = representative.bioguideID else {
            return []
        }

        // Scan a generous window of recent roll calls — most are procedural —
        // and keep only the significant ones, up to `limit`.
        let candidates = await recentHouseVotes(limit: Self.voteScanWindow)
        let significant = await significantVotes(among: candidates, limit: limit)
        guard !significant.isEmpty else { return [] }

        // Look up this member's position on each kept vote concurrently,
        // restoring the newest-first ordering afterward.
        return await withTaskGroup(of: (Int, VoteRecord?).self) { group in
            for (index, vote) in significant.enumerated() {
                group.addTask { (index, await self.voteRecord(for: bioguideID, on: vote)) }
            }
            var collected: [(Int, VoteRecord)] = []
            for await (index, record) in group {
                if let record { collected.append((index, record)) }
            }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// How many recent roll calls to inspect when looking for significant votes.
    /// Wide enough that the procedural majority still leaves plenty of passage
    /// votes to choose from.
    private static let voteScanWindow = 40

    /// Fetches the most recent House roll-call votes of the current Congress,
    /// newest first. Both sessions are pulled and merged because the list
    /// endpoint returns votes in an arbitrary order and isn't sortable, so the
    /// newest `limit` across both sessions are selected client-side.
    private func recentHouseVotes(limit: Int) async -> [HouseVoteDTO] {
        async let firstSession = houseVotes(session: 1)
        async let secondSession = houseVotes(session: 2)
        let votes = await firstSession + secondSession
        return votes
            .sorted { ($0.startDate ?? "") > ($1.startDate ?? "") }
            .prefix(limit)
            .map { $0 }
    }

    /// Loads one session's House roll-call vote list. Returns an empty list on
    /// any failure or for a session that hasn't taken place yet.
    private func houseVotes(session: Int) async -> [HouseVoteDTO] {
        let response = try? await getJSON(
            HouseVoteListResponse.self,
            path: "house-vote/\(Self.currentCongress)/\(session)",
            queryItems: [URLQueryItem(name: "limit", value: "250")]
        )
        return response?.houseRollCallVotes ?? []
    }

    /// Fetches each candidate's lightweight detail (which carries the vote's
    /// question) concurrently, keeps only the significant votes, and returns the
    /// newest `limit` of them. The detail endpoint is tiny next to the full
    /// member roster, so classifying here avoids pulling rosters we'd discard.
    private func significantVotes(among candidates: [HouseVoteDTO], limit: Int) async -> [HouseVoteDetail] {
        let details = await withTaskGroup(of: HouseVoteDetail?.self) { group in
            for vote in candidates {
                group.addTask { await self.voteDetail(for: vote) }
            }
            var collected: [HouseVoteDetail] = []
            for await detail in group {
                if let detail { collected.append(detail) }
            }
            return collected
        }

        return details
            .filter { Self.isSignificant(question: $0.voteQuestion) }
            // Require a numbered measure: a passage vote the API hasn't linked to
            // legislation has no bill name to show, so the row would fall back to
            // a bare procedural question — exactly the noise we're filtering out.
            .filter { $0.legislationType?.isEmpty == false && $0.legislationNumber?.isEmpty == false }
            .sorted { ($0.startDate ?? "") > ($1.startDate ?? "") }
            .prefix(limit)
            .map { $0 }
    }

    /// Loads a single roll call's detail (question, legislation, date), without
    /// the full member roster. Returns nil on any failure.
    private func voteDetail(for vote: HouseVoteDTO) async -> HouseVoteDetail? {
        guard let session = vote.sessionNumber, let number = vote.rollCallNumber else {
            return nil
        }
        let response = try? await getJSON(
            HouseVoteDetailResponse.self,
            path: "house-vote/\(Self.currentCongress)/\(session)/\(number)"
        )
        return response?.houseRollCallVote
    }

    /// Looks up how a member voted on a single roll call, returning nil when the
    /// member wasn't recorded on it or the lookup fails. The member roster and
    /// the bill's title are fetched concurrently so each row can show the bill's
    /// name rather than the procedural question.
    private func voteRecord(for bioguideID: String, on vote: HouseVoteDetail) async -> VoteRecord? {
        guard let session = vote.sessionNumber, let number = vote.rollCallNumber else {
            return nil
        }

        async let roster = memberRoster(session: session, rollCall: number)
        async let billName = billName(type: vote.legislationType, number: vote.legislationNumber)

        // Skip the vote unless we have both the member's position and a bill name
        // to show — a nameless row would just read as a procedural question.
        guard let member = (await roster)?.first(where: { $0.bioguideID == bioguideID }),
              let name = await billName else {
            return nil
        }

        return VoteRecord(
            billTitle: Bill.displayTitle(type: vote.legislationType, number: vote.legislationNumber, title: name),
            position: Self.position(fromCast: member.voteCast),
            date: Self.parseVoteDate(vote.startDate) ?? Date(),
            question: Self.question(for: vote)
        )
    }

    /// Fetches how every member was recorded on a roll call. Returns nil on
    /// failure.
    private func memberRoster(session: Int, rollCall: Int) async -> [MemberVoteDTO]? {
        let response = try? await getJSON(
            HouseVoteMembersResponse.self,
            path: "house-vote/\(Self.currentCongress)/\(session)/\(rollCall)/members"
        )
        return response?.houseRollCallVoteMemberVotes.results
    }

    /// Fetches the title of a numbered bill or resolution. Returns nil for votes
    /// not tied to a numbered measure, or on any failure.
    private func billName(type: String?, number: String?) async -> String? {
        guard let type, let number, !number.isEmpty else { return nil }
        let response = try? await getJSON(
            BillDetailResponse.self,
            path: "bill/\(Self.currentCongress)/\(type.lowercased())/\(number)"
        )
        guard let title = response?.bill.title, !title.isEmpty else { return nil }
        return title
    }

    /// Whether a roll call decides the fate of the underlying bill or resolution
    /// — final passage, agreeing to a resolution or conference report, or
    /// concurring in a Senate amendment — rather than a procedural step (the
    /// previous question, a motion to recommit, an amendment, a motion to table).
    private static func isSignificant(question: String?) -> Bool {
        guard let question = question?.lowercased() else { return false }
        let passageMarkers = [
            "on passage",
            "suspend the rules and pass",
            "suspend the rules and agree",
            "agreeing to the resolution",
            "agreeing to the conference report",
            // Concurring in a Senate amendment clears a bill for the President;
            // matched loosely since the API abbreviates "Amendment" as "Adt".
            "concur",
        ]
        return passageMarkers.contains { question.contains($0) }
    }

    /// The specific floor question put to a vote, e.g. "On Passage".
    private static func question(for vote: HouseVoteDetail) -> String {
        let question = vote.voteQuestion?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (question?.isEmpty == false) ? question! : "Roll call vote"
    }

    /// Maps the House clerk's recorded vote ("Yea"/"Aye", "Nay"/"No", "Present",
    /// "Not Voting") onto the app's simpler position model.
    private static func position(fromCast cast: String?) -> VotePosition {
        switch cast?.lowercased() {
        case "yea", "aye", "yes": .yea
        case "nay", "no": .nay
        case "present": .present
        default: .notVoting
        }
    }

    /// Maps the single-letter party code the vote roster uses ("D"/"R"/"I") onto
    /// the app's party model.
    private static func party(fromCode code: String?) -> Party {
        switch code?.uppercased() {
        case "D": .democrat
        case "R": .republican
        default: .independent
        }
    }

    /// Parses the ISO-8601 timestamps the vote endpoints return, e.g.
    /// "2026-02-24T14:18:00-05:00".
    private static func parseVoteDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return voteDateFormatter.date(from: string)
    }

    /// Loads a member's sponsored or cosponsored legislation as references that
    /// carry the identifiers needed to open each bill's detail screen. Returns an
    /// empty list on failure.
    private func legislation<T: LegislationListResponse>(
        _ type: T.Type,
        path: String,
        limit: Int
    ) async -> [LegislationRef] {
        guard let response = try? await getJSON(
            type,
            path: path,
            queryItems: [URLQueryItem(name: "limit", value: String(limit))]
        ) else {
            return []
        }
        return response.items.compactMap { item in
            guard let title = item.title, !title.isEmpty else { return nil }
            return LegislationRef(
                congress: item.congress,
                type: item.type,
                number: item.number,
                title: title
            )
        }
    }

    /// Loads the full detail for a referenced bill — its plain-language summary,
    /// policy area, status, and latest action — for the profile's bill detail
    /// screen. Returns nil for references without identifiers (e.g. sample data)
    /// or on any failure.
    func billDetail(for reference: LegislationRef) async -> Bill? {
        guard let congress = reference.congress,
              let type = reference.type, !type.isEmpty,
              let number = reference.number, !number.isEmpty else {
            return nil
        }

        let path = "bill/\(congress)/\(type.lowercased())/\(number)"
        guard let response = try? await getJSON(SingleBillResponse.self, path: path),
              let base = Bill(dto: response.bill) else {
            return nil
        }

        async let summary = latestSummaryText(path: path)
        async let policyArea = policyAreaName(path: path)

        return base.withDetails(
            summary: (await summary).map { Self.cleanedSummary($0, title: response.bill.title) },
            topics: (await policyArea).map { [$0] } ?? []
        )
    }

    // MARK: - Bill roll-call tally

    /// Fetches the roll-call breakdown for a bill's most recent House vote: how
    /// every member voted, plus the question and outcome. Returns nil for bills
    /// with no House roll call (e.g. still in committee, or a Senate vote, which
    /// Congress.gov doesn't expose member-by-member) or on any failure.
    func billVoteTally(congress: Int, type: String, number: String) async -> BillVoteTally? {
        // The bill's recorded votes live on its actions, each carrying a roll-call
        // number we can resolve to a full member roster.
        guard let actions = try? await getJSON(
            BillActionsResponse.self,
            path: "bill/\(congress)/\(type.lowercased())/\(number)/actions",
            queryItems: [URLQueryItem(name: "limit", value: "250")]
        ) else {
            return nil
        }

        let houseVotes = actions.actions
            .compactMap(\.recordedVotes)
            .flatMap { $0 }
            .filter { ($0.chamber ?? "").localizedCaseInsensitiveContains("house") }

        // Surface the most recent House roll call — typically final passage or the
        // bill's last floor disposition.
        guard let latest = houseVotes.max(by: { ($0.date ?? "") < ($1.date ?? "") }),
              let session = latest.sessionNumber,
              let roll = latest.rollNumber else {
            return nil
        }

        let voteCongress = latest.congress ?? congress
        guard let response = try? await getJSON(
            HouseVoteMembersResponse.self,
            path: "house-vote/\(voteCongress)/\(session)/\(roll)/members"
        ) else {
            return nil
        }

        let payload = response.houseRollCallVoteMemberVotes
        let members = payload.results.map { dto -> MemberVote in
            let name = [dto.firstName, dto.lastName]
                .compactMap { $0 }
                .joined(separator: " ")
            return MemberVote(
                id: dto.bioguideID,
                name: name.isEmpty ? dto.bioguideID : name,
                party: Self.party(fromCode: dto.voteParty),
                state: dto.voteState ?? "",
                position: Self.position(fromCast: dto.voteCast)
            )
        }
        guard !members.isEmpty else { return nil }

        return BillVoteTally(
            question: payload.voteQuestion,
            date: Self.parseVoteDate(payload.startDate),
            result: payload.result,
            memberVotes: members
        )
    }

    /// Fetches the bills most recently acted on in the current Congress, newest
    /// first. These power the home feed of legislation moving through Congress.
    func recentBills(limit: Int = 20) async throws -> [Bill] {
        print("🔍 CongressService: Starting fetch for recent bills...")

        guard !apiKey.isEmpty, apiKey != Self.apiKeyPlaceholder else {
            print("🚨 CongressService Error: API key is missing or still set to placeholder!")
            throw ServiceError.missingAPIKey
        }

        // The list endpoint can only sort by updateDate (when a record was last
        // touched), not by latest *action*. Many recently-updated records carry
        // old actions, so a shallow fetch fills with administratively-touched
        // bills and hides ones with genuinely recent floor activity. Pull a
        // deeper pool, rank it by importance, then enrich only the bills we'll
        // actually show — keeping detail-request volume bounded.
        let poolLimit = min(250, max(limit * 5, 100))

        var components = URLComponents(
            string: "https://api.congress.gov/v3/bill/\(Self.currentCongress)"
        )!
        components.queryItems = [
            URLQueryItem(name: "sort", value: "updateDate+desc"),
            URLQueryItem(name: "limit", value: String(poolLimit)),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "api_key", value: apiKey),
        ]

        guard let url = components.url else {
            print("🚨 CongressService Error: Failed to construct URL from components.")
            throw URLError(.badURL)
        }

        print("🌐 CongressService: Requesting URL: \(url.absoluteString.replacingOccurrences(of: apiKey, with: "REDACTED_KEY"))")

        let (data, response) = try await session.data(from: url)
        print("📥 CongressService: Received raw payload (\(data.count) bytes).")

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

        let payload = try JSONDecoder().decode(BillListResponse.self, from: data)

        // Build base bills (latest-action text only) from the whole pool and
        // rank them by importance — legislative progress plus recency of the
        // latest *action* — so the most consequential, recently-acted-on bills
        // win the limited slots regardless of when their record was last touched.
        let ranked = payload.bills
            .compactMap { dto in Bill(dto: dto).map { (dto, $0) } }
            .sorted { $0.1.importance() > $1.1.importance() }
            .prefix(limit)
            .map(\.0)

        // The list endpoint omits summaries and policy areas, so enrich only the
        // bills we'll show with their own detail requests. Run them concurrently
        // and restore the ranked ordering afterward.
        let bills = await withTaskGroup(of: (Int, Bill?).self) { group in
            for (index, dto) in ranked.enumerated() {
                group.addTask { (index, await self.enriched(dto)) }
            }
            var collected: [(Int, Bill)] = []
            for await (index, bill) in group {
                if let bill { collected.append((index, bill)) }
            }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }

        print("✅ CongressService Success: Selected and enriched \(bills.count) of \(payload.bills.count) bills by importance.")
        return bills
    }

    /// Enriches a list-level bill with its real plain-language summary and
    /// policy area, each of which lives behind a separate detail request. If
    /// either lookup fails the base bill (latest-action text, no topics) stands.
    private func enriched(_ dto: BillDTO) async -> Bill? {
        guard let base = Bill(dto: dto) else { return nil }
        guard let congress = dto.congress, let type = dto.type, let number = dto.number else {
            return base
        }

        let path = "bill/\(congress)/\(type.lowercased())/\(number)"
        async let summary = latestSummaryText(path: path)
        async let policyArea = policyAreaName(path: path)

        return base.withDetails(
            summary: (await summary).map { Self.cleanedSummary($0, title: dto.title) },
            topics: (await policyArea).map { [$0] } ?? []
        )
    }

    /// Tidies a CRS summary for display by stripping content the feed already
    /// shows elsewhere: a leading copy of the bill's title (which appears in
    /// the bill's title) and the boilerplate "This bill" opener.
    private static func cleanedSummary(_ summary: String, title: String?) -> String {
        var text = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop the bill's title where it's repeated inside the summary.
        if let title, !title.isEmpty {
            text = text.replacingOccurrences(of: title, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Drop the boilerplate "This bill" opener.
        if text.hasPrefix("This bill") {
            text = String(text.dropFirst("This bill".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Re-capitalize the new leading word so the summary reads cleanly.
            text = text.prefix(1).uppercased() + text.dropFirst()
        }

        return text
    }

    /// Fetches the most recent CRS summary for a bill and reduces its HTML to
    /// plain text. Returns nil when the bill has no summary yet.
    private func latestSummaryText(path: String) async -> String? {
        guard let response = try? await getJSON(SummariesResponse.self, path: "\(path)/summaries"),
              let html = response.summaries
                .filter({ $0.text?.isEmpty == false })
                .max(by: { ($0.updateDate ?? "") < ($1.updateDate ?? "") })?
                .text else {
            return nil
        }
        let text = Self.plainText(fromHTML: html)
        return text.isEmpty ? nil : text
    }

    /// Fetches a bill's broad policy area (e.g. "Health", "Taxation").
    private func policyAreaName(path: String) async -> String? {
        guard let response = try? await getJSON(BillDetailResponse.self, path: path),
              let name = response.bill.policyArea?.name, !name.isEmpty else {
            return nil
        }
        return name
    }

    /// Performs a GET against the Congress.gov API and decodes the response,
    /// appending the shared `format` and `api_key` query items.
    private func getJSON<T: Decodable>(
        _ type: T.Type,
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        var components = URLComponents(string: "https://api.congress.gov/v3/\(path)")!
        components.queryItems = queryItems + [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.badResponse(-1)
        }
        guard 200..<300 ~= http.statusCode else {
            throw ServiceError.badResponse(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Strips HTML tags and decodes common entities from a CRS summary, leaving
    /// readable plain text for the feed and detail screens.
    private static func plainText(fromHTML html: String) -> String {
        var text = html.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&nbsp;": " ",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

// MARK: - Member legislation wire format

/// Shared shape for the sponsored- and cosponsored-legislation endpoints, which
/// return the same list of bills under different top-level keys.
private protocol LegislationListResponse: Decodable {
    var items: [LegislationDTO] { get }
}

private struct SponsoredLegislationResponse: LegislationListResponse {
    let sponsoredLegislation: [LegislationDTO]
    var items: [LegislationDTO] { sponsoredLegislation }
}

private struct CosponsoredLegislationResponse: LegislationListResponse {
    let cosponsoredLegislation: [LegislationDTO]
    var items: [LegislationDTO] { cosponsoredLegislation }
}

private struct LegislationDTO: Decodable {
    let congress: Int?
    let type: String?
    let number: String?
    let title: String?
}

// MARK: - Bill wire format

private struct BillListResponse: Decodable {
    let bills: [BillDTO]
}

/// The bill detail endpoint's single-bill payload, shaped like a list entry.
private struct SingleBillResponse: Decodable {
    let bill: BillDTO
}

/// The bill actions endpoint, whose entries carry the roll-call votes taken on
/// the bill.
private struct BillActionsResponse: Decodable {
    let actions: [Action]

    struct Action: Decodable {
        let recordedVotes: [RecordedVote]?
    }

    struct RecordedVote: Decodable {
        let chamber: String?
        let congress: Int?
        let date: String?
        let rollNumber: Int?
        let sessionNumber: Int?
    }
}

struct BillDTO: Decodable {
    let congress: Int?
    let type: String?
    let number: String?
    let title: String?
    let originChamber: String?
    let latestAction: LatestAction?

    struct LatestAction: Decodable {
        let actionDate: String?
        let text: String?
    }
}

// MARK: - House roll-call vote wire format

private struct HouseVoteListResponse: Decodable {
    let houseRollCallVotes: [HouseVoteDTO]
}

/// One entry from the roll-call vote list endpoint. Only the fields needed to
/// order the votes and address each detail lookup are decoded.
private struct HouseVoteDTO: Decodable {
    let rollCallNumber: Int?
    let sessionNumber: Int?
    let startDate: String?
}

private struct HouseVoteDetailResponse: Decodable {
    let houseRollCallVote: HouseVoteDetail
}

/// A single roll call's detail: the question asked, the legislation it
/// concerned, and when it was taken — everything needed to label and classify
/// the vote, without the full member roster.
private struct HouseVoteDetail: Decodable {
    let rollCallNumber: Int?
    let sessionNumber: Int?
    let startDate: String?
    let voteQuestion: String?
    let legislationType: String?
    let legislationNumber: String?
}

private struct HouseVoteMembersResponse: Decodable {
    let houseRollCallVoteMemberVotes: HouseVoteMemberVotes
}

/// The member-level vote payload: how every House member was recorded, plus the
/// question and outcome that label the tally.
private struct HouseVoteMemberVotes: Decodable {
    let results: [MemberVoteDTO]
    let voteQuestion: String?
    let result: String?
    let startDate: String?
}

private struct MemberVoteDTO: Decodable {
    let bioguideID: String
    let firstName: String?
    let lastName: String?
    let voteParty: String?
    let voteState: String?
    let voteCast: String?
}

private struct SummariesResponse: Decodable {
    let summaries: [SummaryDTO]

    struct SummaryDTO: Decodable {
        let text: String?
        let updateDate: String?
    }
}

private struct BillDetailResponse: Decodable {
    let bill: BillDetail

    struct BillDetail: Decodable {
        let title: String?
        let policyArea: PolicyArea?

        struct PolicyArea: Decodable {
            let name: String?
        }
    }
}

// MARK: - Bill mapping

extension Bill {
    /// Builds a feed `Bill` from a Congress.gov list entry. The list endpoint
    /// doesn't include a plain-language summary or policy areas, so we surface
    /// the latest action text as the description and leave topics empty.
    init?(dto: BillDTO) {
        guard let rawTitle = dto.title, !rawTitle.isEmpty else { return nil }

        let chamber: Chamber = (dto.originChamber ?? "").localizedCaseInsensitiveContains("senate")
            ? .senate : .house
        let actionText = dto.latestAction?.text

        self.init(
            title: Self.displayTitle(type: dto.type, number: dto.number, title: rawTitle),
            summary: actionText ?? "No recent action recorded.",
            chamber: chamber,
            status: Self.status(fromAction: actionText, chamber: chamber),
            latestActionDate: Self.parseDate(dto.latestAction?.actionDate) ?? Date(),
            topics: [],
            congress: dto.congress,
            billType: dto.type,
            billNumber: dto.number
        )
    }

    /// Returns a copy of the bill with its summary and topics replaced by the
    /// enriched detail-endpoint values, keeping the latest-action text only when
    /// no real summary is available.
    func withDetails(summary newSummary: String?, topics: [String]) -> Bill {
        Bill(
            id: id,
            title: title,
            summary: (newSummary?.isEmpty == false) ? newSummary! : summary,
            chamber: chamber,
            status: status,
            latestActionDate: latestActionDate,
            topics: topics,
            congress: congress,
            billType: billType,
            billNumber: billNumber
        )
    }

    /// Formats a bill into its familiar short name, e.g. "Clean Water Act — H.R. 1234".
    static func displayTitle(type: String?, number: String?, title: String) -> String {
        guard let number, !number.isEmpty, let prefix = typePrefix(type) else {
            return title
        }
        return "\(title) — \(prefix) \(number)"
    }

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

    /// Infers where the bill sits in the process from its latest action text,
    /// which is the only progress signal the list endpoint provides. `chamber`
    /// is the bill's origin chamber, used to resolve post-passage procedural
    /// actions that don't name the chamber themselves.
    private static func status(fromAction text: String?, chamber: Chamber) -> BillStatus {
        let text = text?.lowercased() ?? ""
        if text.contains("became public law") || text.contains("became law")
            || text.contains("signed by president") {
            return .enacted
        }
        if text.contains("presented to president") || text.contains("to president")
            || text.contains("cleared for white house") {
            return .toPresident
        }
        if text.contains("passed senate") || text.contains("agreed to in senate") {
            return .passedSenate
        }
        if text.contains("passed house") || text.contains("agreed to in house") {
            return .passedHouse
        }
        // After a chamber passes a measure its *latest* action is often clean-up
        // boilerplate or a hand-off to the other chamber — neither of which
        // names the passing chamber — so a just-passed bill like H.R. 7757
        // ("Motion to reconsider laid on the table…") would otherwise sink to
        // "introduced". Treat these as passage, inferring the chamber.
        if text.contains("received in the senate") { return .passedHouse }
        if text.contains("received in the house") { return .passedSenate }
        if text.contains("motion to reconsider laid on the table")
            || text.contains("held at the desk")
            || text.contains("ordered to be engrossed")
            || text.contains("passed/agreed to") {
            return chamber == .house ? .passedHouse : .passedSenate
        }
        if text.contains("committee") || text.contains("referred to") {
            return .inCommittee
        }
        return .introduced
    }

    /// Parses a Congress.gov "yyyy-MM-dd" action date.
    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return billDateFormatter.date(from: string)
    }
}

/// Shared formatter for the ISO-8601 timestamps the roll-call vote endpoints
/// return (e.g. "2026-02-24T14:18:00-05:00").
private let voteDateFormatter = ISO8601DateFormatter()

/// Shared formatter for the "yyyy-MM-dd" dates Congress.gov returns.
private let billDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/New_York")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()
