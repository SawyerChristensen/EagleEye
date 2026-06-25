//
//  RepresentativeDetailView.swift
//  EagleEye
//
//  Profile screen shown when a representative is tapped in the grid.
//  Several sections use placeholder data until the relevant APIs
//  (e.g. Congress.gov for votes/bills, OpenSecrets for funding) are wired up.
//

import SwiftUI

struct RepresentativeDetailView: View {
    let representative: Representative

    private var partyColor: Color {
        switch representative.party {
        case .democrat: .blue
        case .republican: .red
        case .independent: .purple
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                committeesSection
                sponsorshipSection
                votingHistorySection
                fundingSection
            }
            .padding()
        }
        .navigationTitle(representative.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            RepresentativePortrait(representative: representative, size: 140)

            VStack(spacing: 4) {
                Text(representative.name)
                    .font(.title2.bold())
                Text(representative.roleDescription)
                    .font(.headline)
                    .foregroundStyle(partyColor)
                Label(representative.tenureDescription, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sections

    private var committeesSection: some View {
        ProfileSection(title: "Committees", systemImage: "person.3") {
            if representative.committees.isEmpty {
                EmptyNote("No committee assignments on record.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(representative.committees, id: \.self) { committee in
                        Text("• \(committee)")
                            .font(.body)
                    }
                }
            }
        }
    }

    private var sponsorshipSection: some View {
        ProfileSection(title: "Bills", systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 14) {
                BillGroup(title: "Sponsored", bills: representative.sponsoredBills)
                BillGroup(title: "Cosponsored", bills: representative.cosponsoredBills)
            }
        }
    }

    private var votingHistorySection: some View {
        ProfileSection(title: "Voting History", systemImage: "checklist") {
            if representative.keyVotes.isEmpty {
                EmptyNote("No recent votes on record.")
            } else {
                VStack(spacing: 12) {
                    ForEach(representative.keyVotes, id: \.self) { vote in
                        VoteRow(vote: vote)
                    }
                }
            }
        }
    }

    private var fundingSection: some View {
        ProfileSection(title: "Top Funders", systemImage: "dollarsign.circle") {
            if representative.funders.isEmpty {
                EmptyNote("Funding data unavailable.")
            } else {
                VStack(spacing: 12) {
                    ForEach(representative.funders, id: \.self) { funder in
                        FunderRow(funder: funder)
                    }
                }
            }
        }
    }
}

// MARK: - Reusable pieces

/// A titled card-style block used for each profile section.
private struct ProfileSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 14))
    }
}

private struct EmptyNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

/// A titled list of bills that collapses to a few rows when long, fading the
/// overflow under a gradient with a chevron to expand or collapse it.
private struct BillGroup: View {
    let title: String
    let bills: [String]

    @State private var isExpanded = false

    /// Height of the collapsed list — enough to show a few bills before fading.
    private let collapsedHeight: CGFloat = 132
    /// Only worth collapsing once there are more bills than fit comfortably.
    private var isCollapsible: Bool { bills.count > 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) (\(bills.count))")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            if bills.isEmpty {
                EmptyNote("None.")
            } else if isCollapsible {
                collapsibleList
            } else {
                billRows
            }
        }
    }

    private var billRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(bills, id: \.self) { bill in
                Label(bill, systemImage: "checkmark.seal")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var collapsibleList: some View {
        VStack(spacing: 0) {
            if isExpanded {
                billRows
                expandButton
                    .padding(.top, 10)
            } else {
                ZStack(alignment: .bottom) {
                    billRows
                        .frame(maxHeight: collapsedHeight, alignment: .top)
                        .clipped()
                        .mask(fadeMask)

                    expandButton
                }
            }
        }
    }

    /// Fades the bottom of the collapsed list out so the cut-off bill trails
    /// off rather than ending abruptly.
    private var fadeMask: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.6),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var expandButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() }
        } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(8)
                .background(.thinMaterial, in: .circle)
                .overlay(Circle().strokeBorder(.quaternary, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Show fewer \(title.lowercased()) bills" : "Show all \(title.lowercased()) bills")
    }
}

private struct VoteRow: View {
    let vote: VoteRecord

    private var color: Color {
        switch vote.position {
        case .yea: .green
        case .nay: .red
        case .notVoting: .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vote.billTitle)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(vote.date, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(vote.position.rawValue)
                .font(.caption.bold())
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color.opacity(0.15), in: .capsule)
        }
    }
}

private struct FunderRow: View {
    let funder: Funder

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(funder.name)
                    .font(.subheadline)
                Text(funder.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(funder.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        RepresentativeDetailView(representative: SampleData.representatives[0])
    }
}
