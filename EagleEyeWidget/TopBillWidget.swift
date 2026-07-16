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
        try? await CongressService(apiKey: resolvedAPIKey()).recentBills(limit: 1).first
    }

    /// `Bundle.main` inside the widget extension resolves to the `.appex`'s own
    /// bundle, not the app's, so `CongressService.configuredAPIKey`'s bundled
    /// `Secrets.plist` lookup always comes up empty here — leaving every fetch
    /// to fail with `missingAPIKey` and the widget stuck on "No bill available".
    /// Widget extensions are embedded inside the container app's bundle at
    /// build time, though, so the key the app was configured with can still be
    /// read by walking back up to it.
    private static func resolvedAPIKey() -> String {
        let configured = CongressService.configuredAPIKey
        if configured != CongressService.apiKeyPlaceholder { return configured }
        return containerAppAPIKey() ?? configured
    }

    private static func containerAppAPIKey() -> String? {
        let appBundleURL = Bundle.main.bundleURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // <App>.app
        guard let data = try? Data(contentsOf: appBundleURL.appendingPathComponent("Secrets.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let key = plist["CongressGovAPIKey"] as? String,
              !key.isEmpty, key != CongressService.apiKeyPlaceholder else {
            return nil
        }
        return key
    }
}

struct TopBillWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TopBillProvider.Entry

    var body: some View {
        if let bill = entry.bill {
            VStack(alignment: .leading, spacing: 6) {
                Text(bill.status.displayLabel(chamber: bill.chamber).uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                Text(bill.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(family == .systemSmall ? 3 : 4)
                    .fixedSize(horizontal: false, vertical: true)
                Text(bill.summary)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(family == .systemSmall ? 4 : 7)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let code = bill.displayCode {
                    Text(code)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(bill.status.widgetBackground, for: .widget)
        } else {
            Text("No bill available")
                .font(.caption)
                .foregroundStyle(.secondary)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

/// Solid background color per legislative stage: grey while it's still in
/// committee, blue once it's cleared a chamber, green once it's law. The
/// background is the only colored element — text stays white/grey — and the
/// system substitutes its own background in tinted/clear Home Screen modes,
/// so this only ever renders in standard full-color mode.
private extension BillStatus {
    var widgetBackground: Color {
        switch tint {
        case "blue": .blue
        case "green": .green
        default: .gray
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
