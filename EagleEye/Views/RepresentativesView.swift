//
//  RepresentativesView.swift
//  EagleEye
//
//  The left "Your Representatives" tab: the user's congressional delegation.
//

import SwiftUI

struct RepresentativesView: View {
    let representatives: [Representative]

    private var senators: [Representative] {
        representatives.filter { $0.office == .senator }
    }

    private var houseMembers: [Representative] {
        representatives.filter { $0.office == .representative }
    }

    /// Senators first (top rows), then representatives, each grouped two per row.
    private var rows: [[Representative]] {
        chunked(senators, by: 2) + chunked(houseMembers, by: 2)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(spacing: 0) {
                            ForEach(rows[index]) { rep in
                                NavigationLink(value: rep) {
                                    RepresentativeCell(representative: rep)
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
            .navigationTitle("Your Reps")
            .navigationDestination(for: Representative.self) { rep in
                RepresentativeDetailView(representative: rep)
            }
            .navigationDestination(for: LegislationRef.self) { bill in
                MemberBillDetailView(reference: bill)
            }
        }
    }

    /// Splits a list into sub-arrays of at most `size` elements.
    private func chunked(_ reps: [Representative], by size: Int) -> [[Representative]] {
        stride(from: 0, to: reps.count, by: size).map {
            Array(reps[$0..<min($0 + size, reps.count)])
        }
    }
}

/// A single tappable representative in the grid: a large portrait above the
/// member's name and role.
private struct RepresentativeCell: View {
    let representative: Representative

    var body: some View {
        VStack(spacing: 10) {
            RepresentativePortrait(representative: representative, size: 120)

            VStack(spacing: 3) {
                Text("\(representative.name) \(Image(systemName: "chevron.right"))")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text(representative.roleDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// The member's official portrait, falling back to colored initials when no
/// image is available. Shared by the grid and the profile screen.
struct RepresentativePortrait: View {
    let representative: Representative
    let size: CGFloat

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
        .overlay(Circle().strokeBorder(partyColor.opacity(0.6), lineWidth: 3))
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

#Preview {
    RepresentativesView(representatives: SampleData.representatives)
}
