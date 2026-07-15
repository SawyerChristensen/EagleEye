//
//  TopBillWidget.swift
//  EagleEyeWidget
//
//  A home screen widget mirroring the home feed's top-ranked bill: the same
//  Congress.gov fetch and importance ranking `BillsStore` uses, just without
//  the on-disk cache a full app instance keeps warm.
//

import WidgetKit
import SwiftUI

struct TopBillEntry: TimelineEntry {
    let date: Date
    let bill: Bill?
}

struct TopBillProvider: TimelineProvider {
    fileprivate static let placeholderBill = Bill(
        title: "Clean Water Act — H.R. 1234",
        summary: "Strengthens protections for rivers, lakes, and drinking water sources.",
        chamber: .house,
        status: .passedHouse,
        latestActionDate: .now
    )

    func placeholder(in context: Context) -> TopBillEntry {
        TopBillEntry(date: .now, bill: Self.placeholderBill)
    }

    func getSnapshot(in context: Context, completion: @escaping (TopBillEntry) -> Void) {
        if context.isPreview {
            completion(TopBillEntry(date: .now, bill: Self.placeholderBill))
            return
        }
        Task {
            completion(TopBillEntry(date: .now, bill: await Self.fetchTopBill()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TopBillEntry>) -> Void) {
        Task {
            let entry = TopBillEntry(date: .now, bill: await Self.fetchTopBill())
            let nextRefresh = Date.now.addingTimeInterval(60 * 60)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private static func fetchTopBill() async -> Bill? {
        try? await CongressService().recentBills(limit: 1).first
    }
}

struct TopBillWidgetEntryView: View {
    var entry: TopBillProvider.Entry

    var body: some View {
        if let bill = entry.bill {
            VStack(alignment: .leading, spacing: 4) {
                Text(bill.status.displayLabel(chamber: bill.chamber).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(bill.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                Spacer(minLength: 0)
                if let code = bill.displayCode {
                    Text(code)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            Text("No bill available")
                .font(.caption)
                .foregroundStyle(.secondary)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct TopBillWidget: Widget {
    let kind = "TopBillWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TopBillProvider()) { entry in
            TopBillWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Top Bill")
        .description("Shows the most important active bill from your feed.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    TopBillWidget()
} timeline: {
    TopBillEntry(date: .now, bill: TopBillProvider.placeholderBill)
}
