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
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await onRefresh?()
                    }
                }
            }
            .navigationTitle("Congress")
            .navigationDestination(for: Bill.self) { bill in
                BillDetailView(bill: bill)
            }
        }
    }
}

/// A single row in the home feed: bill name as the title, summary as the description.
private struct BillRow: View {
    let bill: Bill

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusBadge(status: bill.status)
                Spacer()
                Text(bill.latestActionDate, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(bill.title)
                .font(.headline)

            Text(bill.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if !bill.topics.isEmpty {
                HStack(spacing: 6) {
                    ForEach(bill.topics, id: \.self) { topic in
                        Text(topic)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: .capsule)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A colored pill describing where the bill is in the process.
struct StatusBadge: View {
    let status: BillStatus

    private var color: Color {
        switch status.tint {
        case "blue": .blue
        case "green": .green
        default: .secondary
        }
    }

    var body: some View {
        Text(status.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: .capsule)
    }
}

#Preview {
    HomeFeedView(bills: SampleData.bills)
}
