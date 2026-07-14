//
//  BillDetailView.swift
//  EagleEye
//
//  Detail screen shown when a bill is tapped in the home feed. Below the bill's
//  summary it discloses the full roll-call tally — who voted and which way —
//  with the user's own representatives surfaced on top.
//

import SwiftUI

struct BillDetailView: View {
    let bill: Bill

    /// The user's representatives, so their votes float to the top of the tally.
    /// House rows are matched by Bioguide ID; the Senate roster has none, so
    /// senators are matched by a state+surname key instead.
    @Environment(\.userRepBioguideIDs) private var userRepIDs
    @Environment(\.userRepMatchKeys) private var userRepMatchKeys

    private let service = CongressService()
    @State private var voteLoad: VoteLoadState = .loading

    private enum VoteLoadState {
        case loading
        case recorded([BillVoteTally])
        case unrecorded(PassageMethod?)
    }

    /// The date of the bill's most recent action. The feed's `latestActionDate`
    /// can lag behind a roll-call vote that Congress.gov records separately, so
    /// once a recorded vote is loaded we surface whichever date is newer rather
    /// than showing a "last action" that predates the vote just above it.
    private var lastActionDate: Date {
        if case .recorded(let tallies) = voteLoad,
           let newestVote = tallies.compactMap(\.date).max() {
            return max(bill.latestActionDate, newestVote)
        }
        return bill.latestActionDate
    }

    /// The summary split into its paragraphs, so each renders as its own block
    /// rather than one undifferentiated wall of text.
    private var summaryParagraphs: [String] {
        bill.summary
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text(bill.displayName)
                            .font(.title.bold())
                            //.fontDesign(.serif)
                            .multilineTextAlignment(.center)

                        if let expansion = bill.acronymExpansion {
                            Text(expansion)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }

                    BillProgressStrip(status: bill.status, chamber: bill.chamber, failedChamber: bill.failedChamber)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Divider()

                if !bill.topics.isEmpty {
                    HStack(spacing: 6) {
                        Text("Topic:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(bill.topics, id: \.self) { topic in
                            Label(topic, systemImage: PolicyArea.symbolName(for: topic))
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(.systemGray5), in: .capsule)
                        }
                    }
                }

                Text("Summary")
                    .font(.headline)
                    .underline()
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(summaryParagraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text("\t\(paragraph)")
                            .font(.body)
                    }
                }

                Divider()
                    .padding(.top, 4)

                votesSection

                Divider()
                    .padding(.top, 8)

                Text("Last action on \(lastActionDate, format: .dateTime.month().day().year())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom)
            //.padding(.top, 4)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                BillTitleLabel(code: bill.displayCode)
            }
        }
        .task { await loadVotes() }
    }

    // MARK: - Votes

    @ViewBuilder
    private var votesSection: some View {
        Text(voteSectionTitle)
            .font(.headline)

        switch voteLoad {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading vote…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .recorded(let tallies):
            VStack(alignment: .leading, spacing: 24) {
                ForEach(Array(tallies.enumerated()), id: \.offset) { _, tally in
                    VStack(alignment: .leading, spacing: 10) {
                        // Label the chamber so a bill with both a House and a
                        // Senate vote reads clearly; harmless with just one.
                        Text("\(tally.chamber.rawValue) Vote")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        VoteTallyView(tally: tally, userRepIDs: userIDs(for: tally.chamber))
                    }
                }
            }
        case .unrecorded(let method):
            Text(unavailableMessage(method: method))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// "Roll Call Votes" when both chambers voted, singular otherwise.
    private var voteSectionTitle: String {
        if case .recorded(let tallies) = voteLoad, tallies.count > 1 {
            return "Roll Call Votes"
        }
        return "Roll Call Vote"
    }

    /// The identity set used to surface the user's own members in a chamber's
    /// tally: Bioguide IDs for the House, state+surname keys for the Senate.
    private func userIDs(for chamber: Chamber) -> Set<String> {
        chamber == .senate ? userRepMatchKeys : userRepIDs
    }

    /// Explains *why* there's no tally. When the record names how the bill
    /// passed, say so plainly; otherwise the message differs by how far the
    /// bill has come — one that has cleared a chamber passed without a recorded
    /// vote, whereas one still in committee hasn't reached a floor vote.
    private func unavailableMessage(method: PassageMethod?) -> String {
        switch method {
        case .voiceVote:
            return "Passed by voice vote — no roll-call vote was recorded."
        case .unanimousConsent:
            return "Passed by unanimous consent — no roll-call vote was recorded."
        case nil:
            switch bill.status {
            case .introduced, .inCommittee:
                return "This bill hasn't reached a recorded floor vote yet."
            case .passedHouse, .passedSenate, .toPresident, .enacted:
                return "Passed without a recorded roll-call vote."
            }
        }
    }

    private func loadVotes() async {
        guard let congress = bill.congress,
              let type = bill.billType,
              let number = bill.billNumber else {
            voteLoad = .unrecorded(nil)
            return
        }

        voteLoad = .loading
        switch await service.billVote(congress: congress, type: type, number: number) {
        case .recorded(let tallies):
            voteLoad = .recorded(tallies)
        case .unrecorded(let method):
            voteLoad = .unrecorded(method)
        case .unavailable:
            voteLoad = .unrecorded(nil)
        }
    }
}

// MARK: - Navigation title

/// The inline navigation-bar title for a bill: the word "Bill" with the
/// measure's code (e.g. "H.R. 1842") alongside it, so the exact code is only
/// revealed once the user opens the detail screen.
private struct BillTitleLabel: View {
    let code: String?

    var body: some View {
        HStack(spacing: 6) {
            Text("Bill")
                .font(.headline)
            if let code {
                Text(code)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Progress strip

private extension HorizontalAlignment {
    /// Centers the progress strip on the *current* stage badge rather than the
    /// strip's geometric middle, so the badge stays screen-centered while the
    /// past and next stages fan out to either side.
    enum ProgressCurrent: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[HorizontalAlignment.center] }
    }
    static let progressCurrent = HorizontalAlignment(ProgressCurrent.self)
}

/// A horizontal filmstrip of the bill's journey: the stage it just cleared
/// (dimmed, to the left), the stage it sits at now (the colored StatusBadge),
/// and the stage it advances to next (greyed, since it hasn't happened yet).
/// The flanking stages fade out where they exceed the view's bounds, keeping
/// the current stage centered and prominent — the same edge fade the home
/// feed's topic strip uses.
private struct BillProgressStrip: View {
    let status: BillStatus
    let chamber: Chamber
    /// The chamber that defeated the bill, when it failed. A failed bill is a
    /// dead end: the strip shows the stage it cleared, then the red "Failed"
    /// badge, with no future stage since it advances no further.
    var failedChamber: Chamber? = nil

    var body: some View {
        // A hidden pill-height reference fills the available (already-padded)
        // width and fixes the row height, while the real pills sit in an overlay
        // so their combined width can exceed the row without ever forcing the
        // detail view wider than the screen (which would strip its padding).
        // Anything past the edges is clipped and faded — the same technique the
        // home feed's topic strip uses.
        Text(" ")
            .font(.caption.weight(.semibold))
            .padding(.vertical, 4)
            .hidden()
            .frame(maxWidth: .infinity)
            .overlay(alignment: Alignment(horizontal: .progressCurrent, vertical: .center)) {
                // A real HStack guarantees an 8pt gap between stages (so they can
                // never overlap), while the custom `.progressCurrent` alignment
                // pins the *current* badge's center — not the strip's geometric
                // middle — to the row's center, so the badge stays screen-centered
                // however wide the flanking labels are. `.fixedSize()` keeps the
                // pills at full width, letting them overflow and fade at the edges.
                HStack(spacing: 8) {
                    if failedChamber != nil {
                        // Dead end: the stage it cleared, then the failure. No
                        // next stage — the bill advances no further.
                        StepPill(label: status.displayLabel(chamber: chamber), kind: .past)
                        StatusBadge(status: status, chamber: chamber, failedChamber: failedChamber)
                            .alignmentGuide(.progressCurrent) { $0[HorizontalAlignment.center] }
                    } else {
                        if let previous = status.previousStage(chamber: chamber) {
                            StepPill(label: previous.displayLabel(chamber: chamber), kind: .past)
                        }
                        StatusBadge(status: status, chamber: chamber)
                            .alignmentGuide(.progressCurrent) { $0[HorizontalAlignment.center] }
                        if let next = status.nextStage(chamber: chamber) {
                            StepPill(label: next.displayLabel(chamber: chamber), kind: .future)
                        }
                    }
                }
                .fixedSize()
            }
            .mask(edgeFade)
    }

    private var edgeFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: 28)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 28)
        }
    }
}

/// A flanking stage in the progress strip. A past stage reads in muted
/// secondary ink to show it's behind the bill; a future stage is greyed and
/// lighter still to signal it hasn't happened yet.
private struct StepPill: View {
    enum Kind { case past, future }
    let label: String
    let kind: Kind

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(kind == .past ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                kind == .past ? Color(.systemGray5) : Color(.systemGray6),
                in: .capsule
            )
    }
}

private extension BillStatus {
    /// The ordered stages a bill passes through, from introduction to
    /// enactment, arranged for the chamber it originated in — a Senate bill
    /// clears the Senate before the House, and a House bill the reverse.
    static func pipeline(originatingIn chamber: Chamber) -> [BillStatus] {
        switch chamber {
        case .house:
            [.introduced, .inCommittee, .passedHouse, .passedSenate, .toPresident, .enacted]
        case .senate:
            [.introduced, .inCommittee, .passedSenate, .passedHouse, .toPresident, .enacted]
        }
    }

    /// The stage immediately behind this one on the bill's path, or `nil` when
    /// this is the first stage.
    func previousStage(chamber: Chamber) -> BillStatus? {
        let stages = Self.pipeline(originatingIn: chamber)
        guard let index = stages.firstIndex(of: self), index > 0 else { return nil }
        return stages[index - 1]
    }

    /// The stage the bill advances to next, or `nil` once it has been enacted.
    func nextStage(chamber: Chamber) -> BillStatus? {
        let stages = Self.pipeline(originatingIn: chamber)
        guard let index = stages.firstIndex(of: self), index + 1 < stages.count else { return nil }
        return stages[index + 1]
    }
}

// MARK: - Tally

/// The full roll-call breakdown: a summary bar and legend, the user's own
/// representatives' votes on top, and the complete member-by-member list behind
/// a disclosure.
private struct VoteTallyView: View {
    let tally: BillVoteTally
    let userRepIDs: Set<String>

    @State private var showAll = false

    /// The user's representatives who were recorded on this vote.
    private var userReps: [MemberVote] {
        tally.memberVotes
            .filter { userRepIDs.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    /// Everyone, grouped by how they voted (Yea, Nay, Present, Not Voting) and
    /// alphabetical within each group.
    private var sortedAll: [MemberVote] {
        tally.memberVotes.sorted {
            let lhs = positionOrder($0.position), rhs = positionOrder($1.position)
            return lhs == rhs ? $0.name < $1.name : lhs < rhs
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            TallyBar(tally: tally)
            legend

            if !userReps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Representatives")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    ForEach(userReps) { vote in
                        MemberVoteRow(vote: vote, highlighted: true)
                    }
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAll.toggle() }
            } label: {
                Label(
                    showAll ? "Hide full roll call" : "Show all \(tally.total) votes",
                    systemImage: showAll ? "chevron.up" : "chevron.down"
                )
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            if showAll {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(sortedAll) { vote in
                        MemberVoteRow(vote: vote, highlighted: userRepIDs.contains(vote.id))
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let question = tally.question, !question.isEmpty {
                Text(question)
                    .font(.subheadline.weight(.semibold))
            }
            HStack(spacing: 8) {
                if let result = tally.result, !result.isEmpty {
                    resultBadge(result)
                }
                if let date = tally.date {
                    Text(date, format: .dateTime.month().day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem("Yea", tally.yea, .green)
            legendItem("Nay", tally.nay, .red)
            if tally.present > 0 { legendItem("Present", tally.present, .orange) }
            if tally.notVoting > 0 { legendItem("N/V", tally.notVoting, .gray) }
        }
        .font(.caption)
    }

    private func legendItem(_ label: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(count) \(label)").foregroundStyle(.secondary)
        }
    }

    private func resultBadge(_ result: String) -> some View {
        let passed = result.localizedCaseInsensitiveContains("pass")
            || result.localizedCaseInsensitiveContains("agreed")
        let color: Color = passed ? .green : .red
        return Text(result)
            .font(.caption.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: .capsule)
    }
}

/// A horizontal stacked bar showing the proportion of Yea / Nay / Present /
/// Not-Voting positions.
private struct TallyBar: View {
    let tally: BillVoteTally

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                segment(.green, tally.yea, in: geo.size.width)
                segment(.red, tally.nay, in: geo.size.width)
                segment(.orange, tally.present, in: geo.size.width)
                segment(.gray, tally.notVoting, in: geo.size.width)
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func segment(_ color: Color, _ count: Int, in totalWidth: CGFloat) -> some View {
        if count > 0 {
            color.frame(width: totalWidth * CGFloat(count) / CGFloat(max(tally.total, 1)))
        }
    }
}

/// A single member's row in the roll call: a party dot, name, state, and their
/// vote. Highlighted when the member is one of the user's own representatives.
private struct MemberVoteRow: View {
    let vote: MemberVote
    var highlighted = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(partyColor(vote.party))
                .frame(width: 8, height: 8)

            Text(vote.name)
                .font(.subheadline)
                .lineLimit(1)
            Text("(\(vote.party.abbreviation)-\(vote.state))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(positionShort(vote.position))
                .font(.caption.bold())
                .foregroundStyle(positionColor(vote.position))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(positionColor(vote.position).opacity(0.15), in: .capsule)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, highlighted ? 8 : 0)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.yellow.opacity(0.12))
            }
        }
    }
}

// MARK: - Shared helpers

private func partyColor(_ party: Party) -> Color {
    switch party {
    case .democrat: .blue
    case .republican: .red
    case .independent: .purple
    }
}

private func positionColor(_ position: VotePosition) -> Color {
    switch position {
    case .yea: .green
    case .nay: .red
    case .present: .orange
    case .notVoting: .gray
    }
}

private func positionShort(_ position: VotePosition) -> String {
    switch position {
    case .yea: "Yea"
    case .nay: "Nay"
    case .present: "Present"
    case .notVoting: "N/V"
    }
}

private func positionOrder(_ position: VotePosition) -> Int {
    switch position {
    case .yea: 0
    case .nay: 1
    case .present: 2
    case .notVoting: 3
    }
}

// MARK: - Environment

private struct UserRepBioguideIDsKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

private struct UserRepMatchKeysKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

extension EnvironmentValues {
    /// Bioguide IDs of the user's own representatives, used to surface their
    /// votes at the top of a bill's House roll-call breakdown.
    var userRepBioguideIDs: Set<String> {
        get { self[UserRepBioguideIDsKey.self] }
        set { self[UserRepBioguideIDsKey.self] = newValue }
    }

    /// State+surname keys (see `MemberVote.matchKey`) for the user's own
    /// members, used to surface their votes in a Senate tally, whose roster
    /// carries no Bioguide ID to match on.
    var userRepMatchKeys: Set<String> {
        get { self[UserRepMatchKeysKey.self] }
        set { self[UserRepMatchKeysKey.self] = newValue }
    }
}

// MARK: - Member bill detail loader

/// Loads a referenced bill's full detail on demand, then shows it with
/// `BillDetailView`. Used when a bill is tapped from a representative's profile,
/// where only the bill's identifiers (not its summary) are on hand.
struct MemberBillDetailView: View {
    let reference: LegislationRef

    private let service = CongressService()
    @State private var bill: Bill?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let bill {
                BillDetailView(bill: bill)
            } else if isLoading {
                ProgressView("Loading bill…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Bill Unavailable",
                    systemImage: "doc.questionmark",
                    description: Text("This bill's details couldn't be loaded.")
                )
            }
        }
        .navigationTitle("Bill")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            bill = await service.billDetail(for: reference)
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        BillDetailView(bill: SampleData.bills[0])
    }
}
