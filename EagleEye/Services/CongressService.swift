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

    /// Loads senators' voting history from Senate.gov, which publishes the
    /// Senate roll calls that Congress.gov's House-only endpoints omit.
    var senateService = SenateService()

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
        async let votes = recentVotes(for: representative)

        return representative
            .withBills(sponsored: await sponsored, cosponsored: await cosponsored)
            .withVotes(await votes)
    }

    /// Loads a member's recent significant votes from the right source: the
    /// House roll calls on Congress.gov for representatives, Senate.gov for
    /// senators (whose votes Congress.gov doesn't cover).
    private func recentVotes(for representative: Representative) async -> [VoteRecord] {
        switch representative.office {
        case .senator:
            // Resolve Senate measures' titles through the same Congress.gov
            // lookup the House feed uses, so both chambers' rows read alike.
            var senate = senateService
            senate.resolveTitle = { _, type, number in
                await self.billName(type: type, number: number)
            }
            return await senate.votingHistory(for: representative)
        case .representative:
            return await votingHistory(for: representative)
        }
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
            question: Self.question(for: vote),
            congress: Self.currentCongress,
            type: vote.legislationType,
            number: vote.legislationNumber
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

        let rawSummary = await summary
        return base.withDetails(
            summary: rawSummary.map { Self.cleanedSummary($0, title: response.bill.title) },
            acronymExpansion: rawSummary.flatMap {
                Self.acronymExpansion(fromSummary: $0, shortTitle: base.displayName)
            },
            topics: (await policyArea).map { [$0] } ?? []
        )
    }

    // MARK: - Bill roll-call tally

    /// Looks up a bill's roll-call votes in both chambers. Resolves the most
    /// recent House roll call (via Congress.gov) and the most recent Senate roll
    /// call (via Senate.gov, which Congress.gov's House-only endpoints omit) to
    /// full member rosters. A bill that cleared both chambers yields both
    /// tallies, most-recent first. When no roster is found it reports how the
    /// bill passed — voice vote, unanimous consent — when the action text says
    /// so, otherwise that no vote was found.
    func billVote(congress: Int, type: String, number: String) async -> BillVoteOutcome {
        // The bill's recorded votes live on its actions, each carrying the
        // chamber and a roll-call number we can resolve to a full member roster.
        guard let actions = try? await getJSON(
            BillActionsResponse.self,
            path: "bill/\(congress)/\(type.lowercased())/\(number)/actions",
            queryItems: [URLQueryItem(name: "limit", value: "250")]
        ) else {
            return .unavailable
        }

        let recorded = actions.actions.compactMap(\.recordedVotes).flatMap { $0 }
        async let house = latestHouseTally(among: recorded, fallbackCongress: congress)
        async let senate = latestSenateTally(among: recorded, fallbackCongress: congress)

        let tallies = [await house, await senate]
            .compactMap { $0 }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

        if !tallies.isEmpty {
            return .recorded(tallies)
        }

        // No roll call to show — say how the bill passed, if the record says.
        return .unrecorded(method: Self.passageMethod(fromActions: actions.actions))
    }

    /// Resolves the bill's most recent House roll call to a full roster, or nil
    /// when it has no House recorded vote.
    private func latestHouseTally(
        among recorded: [BillActionsResponse.RecordedVote],
        fallbackCongress: Int
    ) async -> BillVoteTally? {
        let houseVotes = recorded.filter {
            ($0.chamber ?? "").localizedCaseInsensitiveContains("house")
        }
        guard let latest = houseVotes.max(by: { ($0.date ?? "") < ($1.date ?? "") }),
              let session = latest.sessionNumber, let roll = latest.rollNumber else {
            return nil
        }
        return await memberTally(
            congress: latest.congress ?? fallbackCongress, session: session, roll: roll
        )
    }

    /// Resolves the bill's most recent Senate roll call to a full roster via
    /// Senate.gov, or nil when it has no Senate recorded vote.
    private func latestSenateTally(
        among recorded: [BillActionsResponse.RecordedVote],
        fallbackCongress: Int
    ) async -> BillVoteTally? {
        let senateVotes = recorded.filter {
            ($0.chamber ?? "").localizedCaseInsensitiveContains("senate")
        }
        guard let latest = senateVotes.max(by: { ($0.date ?? "") < ($1.date ?? "") }),
              let session = latest.sessionNumber, let roll = latest.rollNumber else {
            return nil
        }
        return await senateService.billTally(
            congress: latest.congress ?? fallbackCongress, session: session, rollCall: roll
        )
    }

    /// Resolves a House roll call to its full member roster and summary. Returns
    /// nil on any failure or when the roster comes back empty.
    private func memberTally(congress: Int, session: Int, roll: Int) async -> BillVoteTally? {
        guard let response = try? await getJSON(
            HouseVoteMembersResponse.self,
            path: "house-vote/\(congress)/\(session)/\(roll)/members"
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
            chamber: .house,
            question: payload.voteQuestion,
            date: Self.parseVoteDate(payload.startDate),
            result: payload.result,
            memberVotes: members
        )
    }

    /// Reads how a bill cleared the floor from its action text, for bills that
    /// passed without a roll call. The clerk phrases these as "…Agreed to by
    /// voice vote" or "…by Unanimous Consent" / "without objection". Only
    /// actions that record the measure itself passing are considered, so a
    /// procedural voice vote on an amendment along the way isn't mistaken for
    /// the bill's own passage.
    private static func passageMethod(
        fromActions actions: [BillActionsResponse.Action]
    ) -> PassageMethod? {
        for action in actions {
            let text = (action.text ?? "").lowercased()
            guard text.contains("pass") || text.contains("agreed to") else { continue }
            if text.contains("unanimous consent") || text.contains("without objection") {
                return .unanimousConsent
            }
            if text.contains("voice vote") {
                return .voiceVote
            }
        }
        return nil
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
        // touched), not by latest *action*. Worse, Congress.gov periodically runs
        // bulk administrative updates that re-stamp hundreds of stale records with
        // a fresh updateDate, flooding the top of the sorted list with bills whose
        // real actions are weeks old. A shallow fetch fills entirely with that
        // flood and buries genuinely recent floor activity past the ceiling, so we
        // pull the full 250-record page Congress.gov allows, rank it by importance,
        // then enrich only the bills we'll show — keeping detail volume bounded.
        let poolLimit = min(250, max(limit * 5, 250))

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

        let rawSummary = await summary
        return base.withDetails(
            summary: rawSummary.map { Self.cleanedSummary($0, title: dto.title) },
            acronymExpansion: rawSummary.flatMap {
                Self.acronymExpansion(fromSummary: $0, shortTitle: base.displayName)
            },
            topics: (await policyArea).map { [$0] } ?? []
        )
    }

    /// Tidies a CRS summary for display by stripping content the feed already
    /// shows elsewhere: a leading title block (CRS opens each summary with the
    /// bill's title — sometimes "<long title> or the <short title>" — on its
    /// own line) and the boilerplate "This bill" opener.
    private static func cleanedSummary(_ summary: String, title: String?) -> String {
        var paragraphs = summary
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Drop the leading title line. Removing the whole paragraph is cleaner
        // than excising just the title string, which would leave behind the
        // "or the …" scaffolding and a dangling comma.
        if paragraphs.count > 1, isTitleLine(paragraphs[0], title: title) {
            paragraphs.removeFirst()
        }

        var text = paragraphs.joined(separator: "\n\n")

        // Fallback for summaries that inline the title in the opening sentence
        // rather than on a separate line.
        if let title, !title.isEmpty, text.hasPrefix(title) {
            text = String(text.dropFirst(title.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,–—-\n"))
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

    /// Extracts the full title an acronym-named bill stands for, drawn from the
    /// title line that opens its CRS summary. CRS writes these as
    /// "<full title> or the <short title>" (e.g. "Secure Auction For Energy
    /// Reserves Act of 2023 or the SAFER Act of 2023"); when the short title is
    /// an acronym, the full title is worth surfacing as a subtitle. Returns nil
    /// when the bill isn't acronym-named or no expansion is present.
    static func acronymExpansion(fromSummary summary: String, shortTitle: String) -> String? {
        // Only bills whose name carries an acronym get an expansion.
        guard titleContainsAcronym(shortTitle) else { return nil }

        // The expansion lives in the summary's opening title line.
        guard let titleLine = summary
            .components(separatedBy: "\n\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !titleLine.isEmpty else { return nil }

        // CRS joins the full and short titles with "or the"; split on the last
        // occurrence in case the full title itself contains the phrase.
        guard let separator = titleLine.range(
            of: " or the ", options: [.backwards, .caseInsensitive]
        ) else { return nil }

        let expansion = String(titleLine[..<separator.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Guard against degenerate lines that just echo the short title.
        guard !expansion.isEmpty,
              expansion.localizedCaseInsensitiveCompare(shortTitle) != .orderedSame else {
            return nil
        }
        return expansion
    }

    /// Whether a title carries an acronym — a run of two or more uppercase
    /// letters (e.g. "SAFER", "KIDS") that a full title would expand. Generic
    /// suffix words like "Act" are mixed-case and don't qualify.
    private static func titleContainsAcronym(_ title: String) -> Bool {
        let words = title.split { !$0.isLetter && !$0.isNumber }
        return words.contains { word in
            let letters = word.filter { $0.isLetter }
            return letters.count >= 2 && letters.allSatisfy { $0.isUppercase }
        }
    }

    /// Whether a paragraph is a CRS title line — the bill's title sitting on
    /// its own, rather than substantive summary text. Used to strip the
    /// redundant title block that opens most summaries.
    private static func isTitleLine(_ paragraph: String, title: String?) -> Bool {
        // Title lines are short; real summary paragraphs run much longer.
        guard paragraph.count <= 200 else { return false }

        // The strongest signal: the line contains the bill's known title.
        if let title, !title.isEmpty,
           paragraph.localizedCaseInsensitiveContains(title) {
            return true
        }

        // No title to match against: treat a short opening line that names an
        // Act/Resolution, doesn't start a sentence, and isn't punctuated like
        // prose as a title block.
        let namesMeasure = paragraph.range(
            of: "\\b(Act|Resolution)\\b", options: .regularExpression
        ) != nil
        let startsSentence = paragraph.hasPrefix("This ") || paragraph.hasPrefix("To ")
        return namesMeasure && !startsSentence && !paragraph.hasSuffix(".")
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
    /// readable plain text for the feed and detail screens. Block-level
    /// boundaries (`<p>`, `<br>`, list items) are preserved as paragraph breaks
    /// so sentences in separate paragraphs don't run together.
    private static func plainText(fromHTML html: String) -> String {
        var text = html

        // Turn block-level tags into paragraph breaks before stripping the
        // rest. CRS summaries wrap each paragraph in <p> and sometimes
        // enumerate provisions with <ul>/<li>; without this, adjacent
        // sentences across a "</p><p>" boundary collapse into one another.
        let breakTags = "p|br|li|ul|ol|div|tr|h[1-6]|blockquote"
        text = text.replacingOccurrences(
            of: "</?(?:\(breakTags))[^>]*>",
            with: "\n\n",
            options: [.regularExpression, .caseInsensitive]
        )

        // Strip every remaining (inline) tag.
        text = text.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )

        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&nbsp;": " ",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        // Collapse horizontal whitespace, tidy the space around the line
        // breaks we inserted, then squeeze runs of blank lines down to a
        // single paragraph break.
        let normalized = text
            .replacingOccurrences(of: "[^\\S\\n]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{2,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return rejoiningSplitSentences(normalized)
    }

    /// Folds back paragraph breaks that the block-tag conversion introduced
    /// mid-sentence. CRS summaries often enumerate a provision as a lead-in
    /// clause followed by `<li>`/`<p>` items — "…the task force must" /
    /// "coordinate with…" / "develop…" — which turns the lead-in into a
    /// paragraph with no terminal punctuation followed by lowercase-leading
    /// fragments. A break like that isn't a real paragraph, so merge each
    /// lowercase-leading paragraph into the previous one whenever that one
    /// doesn't already end a sentence.
    private static func rejoiningSplitSentences(_ text: String) -> String {
        var merged: [String] = []
        for paragraph in text.components(separatedBy: "\n\n") {
            if let previous = merged.last,
               let firstChar = paragraph.first, firstChar.isLowercase,
               let lastChar = previous.last, !".!?".contains(lastChar) {
                merged[merged.count - 1] = "\(previous) \(paragraph)"
            } else {
                merged.append(paragraph)
            }
        }
        return merged.joined(separator: "\n\n")
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
        let text: String?
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
    func withDetails(
        summary newSummary: String?,
        acronymExpansion newExpansion: String? = nil,
        topics: [String]
    ) -> Bill {
        Bill(
            id: id,
            title: title,
            summary: (newSummary?.isEmpty == false) ? newSummary! : summary,
            acronymExpansion: newExpansion ?? acronymExpansion,
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
    /// The title is run through the same statutory-clause cleanup the feed uses,
    /// so the feed, both chambers' voting histories, and the profile bill lists
    /// all render measure names identically.
    static func displayTitle(type: String?, number: String?, title: String) -> String {
        let cleaned = stripStatutoryClauses(title).trimmingCharacters(in: .whitespaces)
        let name = cleaned.isEmpty ? title : cleaned
        guard let number, !number.isEmpty, let prefix = typePrefix(type) else {
            return name
        }
        return "\(name) — \(prefix) \(number)"
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
