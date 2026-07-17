//
//  GovernorDetailView.swift
//  EagleEye
//
//  Profile screen shown when a governor is tapped in the Representatives
//  list. Governors carry none of `Representative`'s congressional data (no
//  committees or sponsored bills — see `Governor`), so in place of those
//  sections this shows the notable bills the governor has signed into law,
//  pulled from `StateLawDirectory`.
//

import SwiftUI

struct GovernorDetailView: View {
    let governor: Governor

    private var partyColor: Color {
        switch governor.party {
        case .democrat: .blue
        case .republican: .red
        case .independent: .purple
        }
    }

    private var laws: [StateLaw] { StateLawDirectory.laws(forState: governor.state) }
    private var pacFunders: [Funder] { GovernorFunderDirectory.pacFunders(forState: governor.state) }
    private var individualFunders: [Funder] { GovernorFunderDirectory.individualFunders(forState: governor.state) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 12) {
                    GovernorPortrait(governor: governor, size: 140)

                    VStack(spacing: 4) {
                        Text(governor.name)
                            .font(.title2.bold())
                        Text(governor.roleDescription)
                            .font(.headline)
                            .foregroundStyle(partyColor)
                    }
                }
                .frame(maxWidth: .infinity)

                lawsPassedSection
                pacFundersSection
                individualFundersSection
            }
            .padding()
        }
        .navigationTitle(governor.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The "Laws Passed" section: notable bills this governor has signed,
    /// most recent first. Shown above where contact information will go once
    /// governors carry it.
    private var lawsPassedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Laws Passed", systemImage: "checkmark.seal")
                .font(.headline)

            if laws.isEmpty {
                Text("No signed laws on record.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(laws) { law in
                        StateLawRow(law: law)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 14))
    }

    /// Top PAC contributors to this governor's campaign, mirroring
    /// `RepresentativeDetailView`'s equivalent section.
    private var pacFundersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Top PAC Funders", systemImage: "dollarsign.circle")
                .font(.headline)

            if pacFunders.isEmpty {
                Text("Funding data unavailable.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(pacFunders, id: \.self) { funder in
                        GovernorFunderRow(funder: funder)
                    }
                    Text("Direct contributions from each organization's political action committee (PAC).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 14))
    }

    /// Top individual contributors, grouped by employer or occupation.
    private var individualFundersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Top Individual Funders", systemImage: "person.2")
                .font(.headline)

            if individualFunders.isEmpty {
                Text("Individual contributor data unavailable.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(individualFunders, id: \.self) { funder in
                        GovernorFunderRow(funder: funder)
                    }
                    Text("Individual donations totaled by the employer or occupation each contributor reported.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 14))
    }
}

/// A single funder's name, category, and contribution total.
private struct GovernorFunderRow: View {
    let funder: Funder

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(funder.name)
                    .font(.subheadline)
                if !funder.category.isEmpty {
                    Text(funder.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(funder.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// A single signed bill: its title, a short plain-language summary, the date
/// it was signed, and — when known — a link to read more.
private struct StateLawRow: View {
    let law: StateLaw

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(law.title)
                .font(.subheadline.weight(.semibold))
            Text(law.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(law.dateSigned, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if let url = law.sourceURL {
                    Link("Read more", destination: url)
                        .font(.caption.bold())
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        GovernorDetailView(governor: GovernorDirectory.all[0])
    }
}
