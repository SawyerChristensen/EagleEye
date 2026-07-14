//
//  MarketPerformanceService.swift
//  EagleEye
//
//  Supplies the profile's "Beats the Market" indicator: an estimate of how a
//  member's disclosed stock portfolio performed over the year against the S&P
//  500.
//
//  There is no free, keyless API that publishes this finished per-member number
//  (only paid services like Quiver do), so rather than compute it in-app from
//  raw transactions this uses a small, hand-curated snapshot of the figures that
//  Unusual Whales publishes in its year-end congressional-trading report. That
//  matches the metric's real cadence — it only changes once a year — and keeps
//  the app free of a paid dependency or a fragile scraping job.
//
//  Updating for a new year: read the latest report and extend `records` with the
//  members it lists, then bump `year`, `benchmarkPercent`, and `sourceURL`. Only
//  members present here get a figure; everyone else's section falls back to a
//  link to the report.
//
//  Methodology (Unusual Whales): returns are estimated from the value of stocks
//  held at the start vs. the end of the year, based on STOCK Act disclosures
//  whose amounts are reported as ranges — so the figures are approximate and
//  described that way in the UI.
//

import Foundation

/// Matches a representative against the bundled year-end trading-performance
/// snapshot and builds their `MarketPerformance`, if listed.
struct MarketPerformanceService {
    /// The report year these figures cover.
    private static let year = 2025
    /// The S&P 500's total return for that year, the bar for "beating the market".
    private static let benchmarkPercent = 16.6
    /// The published report the figures come from.
    private static let sourceURL = URL(string: "https://unusualwhales.com/congress-trading-report-2025")

    /// Returns the member's annual performance estimate, or `nil` when they
    /// aren't among the members the report lists.
    func performance(for representative: Representative) -> MarketPerformance? {
        guard let record = Self.records.first(where: { $0.matches(representative) }) else {
            return nil
        }
        return MarketPerformance(
            year: Self.year,
            returnPercent: record.returnPercent,
            benchmarkPercent: Self.benchmarkPercent,
            sourceURL: Self.sourceURL
        )
    }

    /// If the member is publicly known not to trade individual stocks — because
    /// they hold a blind trust or only diversified funds — returns a short note
    /// saying so, used to show a positive "doesn't trade" state rather than
    /// implying missing data. Returns `nil` for everyone else.
    ///
    /// This list is hand-curated and asserts a fact about a named person, so it
    /// stays deliberately small and only holds members it can back up. Notably it
    /// does NOT include members who champion a trading ban but still trade
    /// themselves.
    func abstention(for representative: Representative) -> String? {
        Self.abstainers.first { $0.matches(representative) }?.note
    }

    /// One member's estimated portfolio return from the year-end report. Kept as
    /// last name + state + chamber so entries stay readable and match the same
    /// way the disclosure index does, without needing Bioguide IDs.
    private struct Record {
        let last: String
        let state: String
        let office: Office
        let returnPercent: Double

        /// Whether this figure belongs to the given representative — same chamber
        /// and state, with a last name that appears in the member's display name
        /// (mirroring how `FilingRecord` matches disclosure rows).
        func matches(_ representative: Representative) -> Bool {
            office == representative.office
                && state == representative.state
                && representative.name.localizedCaseInsensitiveContains(last)
        }
    }

    /// The 2025 top performers named in the Unusual Whales year-end report. The
    /// full ranking of every disclosed portfolio isn't published openly, so this
    /// carries the members whose figures the report states; expand it as more
    /// are published.
    private static let records: [Record] = [
        Record(last: "Davidson", state: "OH", office: .representative, returnPercent: 78.8),
        Record(last: "Norcross", state: "NJ", office: .representative, returnPercent: 70.8),
        Record(last: "Sewell", state: "AL", office: .representative, returnPercent: 67.9),
        Record(last: "Steil", state: "WI", office: .representative, returnPercent: 62.5),
        Record(last: "Padilla", state: "CA", office: .senator, returnPercent: 61.7),
        Record(last: "LaLota", state: "NY", office: .representative, returnPercent: 61.6),
        Record(last: "Scott", state: "FL", office: .senator, returnPercent: 54.8),
        Record(last: "Guest", state: "MS", office: .representative, returnPercent: 52.5),
        Record(last: "McClintock", state: "CA", office: .representative, returnPercent: 50.0),
        Record(last: "Evans", state: "PA", office: .representative, returnPercent: 41.9),
        // Ranked 28th in the report — still beat the S&P, dragged by a Salesforce
        // position. (Quiver's separate estimate was ~18%; this uses UW's figure
        // to stay consistent with the rest of the snapshot.)
        Record(last: "Pelosi", state: "CA", office: .representative, returnPercent: 20.1),
    ]

    /// A member publicly known not to trade individual stocks. Matched the same
    /// way as `Record`; the note is shown verbatim beside the green check.
    private struct Abstainer {
        let last: String
        let state: String
        let office: Office
        let note: String

        func matches(_ representative: Representative) -> Bool {
            office == representative.office
                && state == representative.state
                && representative.name.localizedCaseInsensitiveContains(last)
        }
    }

    /// Members verified not to trade individual stocks. Kept conservative on
    /// purpose — each entry is a factual claim shown as a positive. Ron Wyden is
    /// deliberately absent: despite backing a ban he still trades (his portfolio
    /// posted outsized gains), so he correctly falls through to the "trades but
    /// not ranked" state.
    private static let abstainers: [Abstainer] = [
        Abstainer(
            last: "Merkley",
            state: "OR",
            office: .senator,
            note: "Holds no individual stocks — lead sponsor of the Senate bill to ban congressional stock trading."
        ),
    ]
}
