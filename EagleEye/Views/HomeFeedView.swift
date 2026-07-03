//
//  HomeFeedView.swift
//  EagleEye
//
//  The center "Home" tab: a feed of bills moving through Congress.
//

import SwiftUI

struct HomeFeedView: View {
    let bills: [Bill]
    var isLoading: Bool = false /// True while bills are being fetched and there's nothing to show yet.
    var statusMessage: String? = nil /// A note shown above the feed when the latest refresh couldn't replace the data.
    var onRefresh: (() async -> Void)? = nil /// Pull-to-refresh handler; omitted in previews and when not applicable.

    var body: some View {
        NavigationStack {
            Group {
                if bills.isEmpty && isLoading {
                    ProgressView("Loading bills…")
                } else {
                    List {
                        ForEach(bills) { bill in
                            NavigationLink(value: bill) {
                                BillRow(bill: bill)
                            }
                            // Pin the row separator to the leading edge so it
                            // spans the full width; otherwise SwiftUI insets it
                            // to align with the row's content and it only covers
                            // the right portion of the screen.
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await onRefresh?()
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if let statusMessage {
                    FeedStatusBanner(text: statusMessage)
                }
            }
            .navigationTitle("Recent Bills")
            .navigationDestination(for: Bill.self) { bill in
                BillDetailView(bill: bill)
            }
        }
    }
}

/// A thin banner shown above the feed when the most recent refresh failed or
/// returned nothing, so the user knows the bills below may be out of date.
private struct FeedStatusBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
                .font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// A single row in the home feed: bill name as the title, summary as the description.
private struct BillRow: View {
    let bill: Bill

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusBadge(status: bill.status, chamber: bill.chamber)
                    .layoutPriority(1)

                if bill.topics.isEmpty {
                    Spacer(minLength: 8)
                } else {
                    TopicPillStrip(topics: bill.topics)
                }

                // Kept at full size and laid out first so a wide topic strip
                // fades out before it ever reaches the date.
                Text(bill.latestActionDate, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
            }

            Text(bill.displayName)
                .font(.headline)

            Text(bill.summary.replacingOccurrences(of: "\n", with: " "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }
}

/// A horizontal row of topic pills that takes the slack between the status
/// badge and the date. When the pills are wider than the available space they
/// overflow to the trailing edge and fade out, rather than pushing into (or
/// hiding) the date.
private struct TopicPillStrip: View {
    let topics: [String]

    var body: some View {
        // A hidden, single-character element drives the height (matching the
        // pills' font + vertical padding, so it scales with Dynamic Type) and
        // gives the strip a tiny minimum width. The real pills live in an
        // overlay so their width never forces the row wider or squashes the
        // status badge — anything past the trailing edge is clipped and faded.
        // The font/padding here must match the pills below, otherwise the mask
        // is shorter than the pills and clips them vertically. It's a Label (not
        // plain text) so the icon's height is accounted for.
        Label(" ", systemImage: "tag")
            .font(.caption)
            .padding(.vertical, 5)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                HStack(spacing: 6) {
                    ForEach(topics, id: \.self) { topic in
                        HStack(spacing: 4) {
                            Image(systemName: PolicyArea.symbolName(for: topic))
                            Text(topic)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.secondary.opacity(0.1), in: .capsule)
                        .fixedSize()
                    }
                }
            }
            .mask(
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 20)
                }
            )
        }
}

/// A colored pill describing where the bill is in the process, with the
/// chamber folded into a single label (e.g. "Introduced to the House").
struct StatusBadge: View {
    let status: BillStatus
    let chamber: Chamber

    @Environment(\.colorScheme) private var colorScheme

    /// A brighter blue in dark mode, where the stock system blue reads too dark
    /// against the near-black feed background.
    private var blue: Color {
        colorScheme == .dark ? Color(red: 0.40, green: 0.66, blue: 1.0) : .blue
    }

    private var foregroundColor: Color {
        switch status.tint {
        case "blue": blue
        case "green": .green
        default: .secondary
        }
    }

    private var backgroundColor: Color {
        switch status.tint {
        case "blue": blue.opacity(colorScheme == .dark ? 0.18 : 0.1)
        case "green": .green.opacity(0.1)
        // Distinct gray for the fallback; systemGray5 reads too bright in dark
        // mode, so drop to the darker systemGray6 there.
        default: colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray5)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: chamber.symbolName)
            Text(status.displayLabel(chamber: chamber))
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(backgroundColor, in: .capsule)
    }
}

#Preview {
    HomeFeedView(bills: SampleData.bills)
}
