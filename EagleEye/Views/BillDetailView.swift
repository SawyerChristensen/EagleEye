//
//  BillDetailView.swift
//  EagleEye
//
//  Detail screen shown when a bill is tapped in the home feed.
//

import SwiftUI

struct BillDetailView: View {
    let bill: Bill

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StatusBadge(status: bill.status)

                Text(bill.title)
                    .font(.title2.bold())

                Label(bill.chamber.rawValue, systemImage: bill.chamber.symbolName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Summary")
                    .font(.headline)
                Text(bill.summary)
                    .font(.body)

                if !bill.topics.isEmpty {
                    Text("Topics")
                        .font(.headline)
                        .padding(.top, 4)
                    HStack(spacing: 6) {
                        ForEach(bill.topics, id: \.self) { topic in
                            Text(topic)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.quaternary, in: .capsule)
                        }
                    }
                }

                Text("Last action on \(bill.latestActionDate, format: .dateTime.month().day().year())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Bill")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        BillDetailView(bill: SampleData.bills[0])
    }
}
