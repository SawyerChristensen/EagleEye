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
    @Environment(\.userRepBioguideIDs) private var userRepIDs

    private let service = CongressService()
    @State private var tally: BillVoteTally?
    @State private var voteLoad: VoteLoadState = .loading

    private enum VoteLoadState {
        case loading
        case loaded
        case unavailable
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

                    StatusBadge(status: bill.status, chamber: bill.chamber)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Divider()

                if !bill.topics.isEmpty {
                    HStack(spacing: 6) {
                        Text("Topic:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(bill.topics, id: \.self) { topic in
                            Text(topic)
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

                Text("Last action on \(bill.latestActionDate, format: .dateTime.month().day().year())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                Divider()
                    .padding(.top, 4)

                votesSection
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
        Text("Roll Call Vote")
            .font(.headline)

        switch voteLoad {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading vote…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .loaded:
            if let tally {
                VoteTallyView(tally: tally, userRepIDs: userRepIDs)
            }
        case .unavailable:
            Text("No House roll-call vote has been recorded for this bill yet. (Senate roll calls aren't available from this data source.)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func loadVotes() async {
        guard let congress = bill.congress,
              let type = bill.billType,
              let number = bill.billNumber else {
            voteLoad = .unavailable
            return
        }

        voteLoad = .loading
        if let result = await service.billVoteTally(congress: congress, type: type, number: number) {
            tally = result
            voteLoad = .loaded
        } else {
            voteLoad = .unavailable
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

extension EnvironmentValues {
    /// Bioguide IDs of the user's own representatives, used to surface their
    /// votes at the top of a bill's roll-call breakdown.
    var userRepBioguideIDs: Set<String> {
        get { self[UserRepBioguideIDsKey.self] }
        set { self[UserRepBioguideIDsKey.self] = newValue }
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
