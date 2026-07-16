//
//  RepresentativesView.swift
//  EagleEye
//
//  The left "Your Representatives" tab: the user's congressional delegation.
//

import SwiftUI

struct RepresentativesView: View {
    let representatives: [Representative]
    /// The user's state governor, shown at the bottom of the delegation list.
    var governor: Governor?
    /// True while the delegation is being resolved and there's nothing to show
    /// yet, so the grid shows a spinner instead of a blank screen.
    var isLoading: Bool = false

    private var senators: [Representative] {
        representatives.filter { $0.office == .senator }
    }

    private var houseMembers: [Representative] {
        representatives.filter { $0.office == .representative }
    }

    /// The delegation in display order: the most senior senator first, then
    /// the junior senator, then the House representative.
    private var orderedRepresentatives: [Representative] {
        senators.sorted { $0.tenureStart < $1.tenureStart } + houseMembers
    }

    var body: some View {
        NavigationStack {
            Group {
                if representatives.isEmpty && isLoading {
                    ProgressView("Finding your representatives…")
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(orderedRepresentatives.indices, id: \.self) { index in
                                NavigationLink(value: orderedRepresentatives[index]) {
                                    RepresentativeRow(representative: orderedRepresentatives[index])
                                }
                                .buttonStyle(.plain)

                                if index < orderedRepresentatives.count - 1 || governor != nil {
                                    Divider()
                                }
                            }

                            if let governor {
                                NavigationLink(value: governor) {
                                    GovernorRow(governor: governor)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("Your Representatives")
            .navigationDestination(for: Representative.self) { rep in
                RepresentativeDetailView(representative: rep)
            }
            .navigationDestination(for: Governor.self) { governor in
                GovernorDetailView(governor: governor)
            }
            .navigationDestination(for: LegislationRef.self) { bill in
                MemberBillDetailView(reference: bill)
            }
        }
    }

    // MARK: - Previous two-per-row grid layout
    //
    // Kept here in case we want to bring the grid back. Superseded by the
    // seniority-ordered list above.
    //
    // private var rows: [[Representative]] {
    //     chunked(senators, by: 2) + chunked(houseMembers, by: 2)
    // }
    //
    // private var gridBody: some View {
    //     ScrollView {
    //         VStack(spacing: 24) {
    //             ForEach(rows.indices, id: \.self) { index in
    //                 HStack(spacing: 0) {
    //                     ForEach(rows[index]) { rep in
    //                         NavigationLink(value: rep) {
    //                             RepresentativeGridCell(representative: rep)
    //                         }
    //                         .buttonStyle(.plain)
    //                         .frame(maxWidth: .infinity)
    //                     }
    //                 }
    //             }
    //         }
    //         .padding(.horizontal, 8)
    //         .padding(.vertical, 12)
    //     }
    // }
    //
    // /// Splits a list into sub-arrays of at most `size` elements.
    // private func chunked(_ reps: [Representative], by size: Int) -> [[Representative]] {
    //     stride(from: 0, to: reps.count, by: size).map {
    //         Array(reps[$0..<min($0 + size, reps.count)])
    //     }
    // }
}

/// A single tappable representative in the list: a portrait with a party-color
/// glow beside the member's name and role. Also reused by the district map's
/// sheet to show the representative for a tapped district.
struct RepresentativeRow: View {
    let representative: Representative

    var body: some View {
        HStack(spacing: 16) {
            RepresentativePortrait(representative: representative, size: 72, style: .shadow)

            VStack(alignment: .leading, spacing: 3) {
                Text(representative.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(representative.roleDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// A single tappable governor, styled the same as `RepresentativeRow` so the
/// governor reads as part of the same list.
struct GovernorRow: View {
    let governor: Governor

    var body: some View {
        HStack(spacing: 16) {
            GovernorPortrait(governor: governor, size: 72, style: .shadow)

            VStack(alignment: .leading, spacing: 3) {
                Text(governor.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(governor.roleDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Previous two-per-row grid cell
//
// Kept alongside the grid layout above in case we bring it back.
//
// private struct RepresentativeGridCell: View {
//     let representative: Representative
//
//     var body: some View {
//         VStack(spacing: 10) {
//             RepresentativePortrait(representative: representative, size: 120)
//
//             VStack(spacing: 3) {
//                 Text("\(representative.name) \(Image(systemName: "chevron.right"))")
//                     .font(.headline)
//                     .foregroundStyle(.primary)
//                     .multilineTextAlignment(.center)
//                 Text(representative.roleDescription)
//                     .font(.subheadline)
//                     .foregroundStyle(.secondary)
//                     .multilineTextAlignment(.center)
//             }
//         }
//     }
// }

/// How a portrait's party affiliation is indicated.
enum PortraitAccentStyle {
    /// A colored ring stroked around the portrait.
    case outline
    /// A soft colored glow behind the portrait, with no ring.
    case shadow
}

/// The member's official portrait, falling back to colored initials when no
/// image is available. Shared by the list and the profile screen.
struct RepresentativePortrait: View {
    let representative: Representative
    let size: CGFloat
    var style: PortraitAccentStyle = .outline

    private var partyColor: Color {
        switch representative.party {
        case .democrat: .blue
        case .republican: .red
        case .independent: .purple
        }
    }

    private var initials: String {
        representative.name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
    }

    var body: some View {
        Group {
            if let url = representative.portraitURL {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if style == .outline {
                Circle().strokeBorder(partyColor.opacity(0.6), lineWidth: 3)
            }
        }
        .shadow(
            color: style == .shadow ? partyColor.opacity(0.7) : .clear,
            radius: style == .shadow ? size * 0.12 : 0
        )
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(partyColor.gradient)
            Text(initials)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// A governor's initials avatar with a party-color glow. There's no portrait
/// source for governors (unlike `Representative`'s Congress.gov photos), so
/// this is always the colored-initials placeholder.
struct GovernorPortrait: View {
    let governor: Governor
    let size: CGFloat
    var style: PortraitAccentStyle = .outline

    private var partyColor: Color {
        switch governor.party {
        case .democrat: .blue
        case .republican: .red
        case .independent: .purple
        }
    }

    private var initials: String {
        governor.name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
    }

    var body: some View {
        ZStack {
            Rectangle().fill(partyColor.gradient)
            Text(initials)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if style == .outline {
                Circle().strokeBorder(partyColor.opacity(0.6), lineWidth: 3)
            }
        }
        .shadow(
            color: style == .shadow ? partyColor.opacity(0.7) : .clear,
            radius: style == .shadow ? size * 0.12 : 0
        )
    }
}

#Preview {
    RepresentativesView(representatives: SampleData.representatives)
}
