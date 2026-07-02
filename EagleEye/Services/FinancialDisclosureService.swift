//
//  FinancialDisclosureService.swift
//  EagleEye
//
//  Loads members' stock-trade disclosures — the Periodic Transaction Reports
//  (PTRs) required under the STOCK Act — and summarizes them for the profile's
//  trading-activity indicator.
//
//  Source: the Office of the Clerk of the U.S. House publishes a daily ZIP of
//  every financial-disclosure filing for the year at
//  https://disclosures-clerk.house.gov/public_disc/financial-pdfs/{YEAR}FD.zip
//  Inside is a tab-separated index ({YEAR}FD.txt); rows with FilingType "P" are
//  the periodic transaction reports (individual stock trades). No key, no terms
//  gate — plain HTTPS.
//
//  Scope: this covers the House only. The Senate publishes its filings through
//  a separate, agreement-gated portal (efdsearch.senate.gov), so senators carry
//  a link to that portal rather than a computed count. The quantitative
//  "beats the market" analysis is a follow-on: it needs each PTR's PDF parsed
//  into transactions plus historical prices, neither of which this index has.
//
//  Note on use: the Clerk's data carries a usage restriction prohibiting
//  commercial use other than dissemination to the public by news/communications
//  media. EagleEye surfaces it for civic transparency, but that limit is worth
//  keeping in mind.
//

import Foundation
import Compression

/// Summarizes a member's STOCK Act periodic transaction reports from the House
/// Clerk's public disclosure index.
struct FinancialDisclosureService {
    var session: URLSession = .shared

    /// The Senate's disclosure portal, used as the senators' link-out since the
    /// House index doesn't cover them.
    static let senateSearchURL = URL(string: "https://efdsearch.senate.gov/search/")!

    /// How far back a Periodic Transaction Report still counts toward the
    /// "recent" trading-activity total.
    private static let trailingWindow: TimeInterval = 365 * 24 * 60 * 60

    /// Loads and merges the House Clerk's periodic-transaction-report index for
    /// the current and previous year, so a trailing-12-month window is covered
    /// even early in a new year. Returns an empty list on any failure, which
    /// simply leaves every member's trading section hidden.
    func houseTransactionReports(now: Date = Date()) async -> [FilingRecord] {
        let year = Calendar(identifier: .gregorian).component(.year, from: now)
        let (thisYear, lastYear) = await (reports(forYear: year), reports(forYear: year - 1))
        return thisYear + lastYear
    }

    /// Builds the trading-activity summary for a member from the shared House
    /// index. House members get a real report count and a link to their most
    /// recent filing; senators get a link to the Senate portal only.
    func tradingActivity(
        for representative: Representative,
        houseReports: [FilingRecord],
        now: Date = Date()
    ) -> TradingActivity {
        guard representative.office == .representative else {
            // The House index doesn't cover senators — point at the Senate's
            // own portal instead of implying we have their reports.
            return TradingActivity(disclosureURL: Self.senateSearchURL, isCovered: false)
        }

        let mine = houseReports.filter { $0.matches(representative) }
        let cutoff = now.addingTimeInterval(-Self.trailingWindow)
        let recent = mine.filter { ($0.filingDate ?? .distantPast) >= cutoff }
        let latest = mine.max { ($0.filingDate ?? .distantPast) < ($1.filingDate ?? .distantPast) }

        return TradingActivity(
            recentReportCount: recent.count,
            latestReportDate: latest?.filingDate,
            disclosureURL: latest?.ptrURL ?? URL(string: "https://disclosures-clerk.house.gov/FinancialDisclosure"),
            isCovered: true
        )
    }

    // MARK: - Per-year fetch & parse

    /// Downloads and parses one year's periodic transaction reports. Returns an
    /// empty list for a year with no published file yet or on any failure.
    private func reports(forYear year: Int) async -> [FilingRecord] {
        let url = URL(
            string: "https://disclosures-clerk.house.gov/public_disc/financial-pdfs/\(year)FD.zip"
        )!
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              let tsv = ZipReader.entry(named: "\(year)FD.txt", in: data),
              let text = String(data: tsv, encoding: .utf8) else {
            return []
        }
        return Self.parse(tsv: text)
    }

    /// Parses the tab-separated disclosure index, keeping only periodic
    /// transaction reports (FilingType "P"). Columns are:
    /// Prefix, Last, First, Suffix, FilingType, StateDst, Year, FilingDate, DocID.
    static func parse(tsv text: String) -> [FilingRecord] {
        // The index is CRLF-delimited; splitting on `isNewline` treats "\r\n" as
        // one break (Swift sees it as a single grapheme) so no stray carriage
        // returns leak into the last column.
        text.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
            let f = line.components(separatedBy: "\t")
            guard f.count >= 9, f[4].trimmingCharacters(in: .whitespaces) == "P" else { return nil }
            return FilingRecord(
                last: f[1].trimmingCharacters(in: .whitespaces),
                stateDistrict: f[5].trimmingCharacters(in: .whitespaces),
                year: f[6].trimmingCharacters(in: .whitespaces),
                filingDate: filingDateFormatter.date(from: f[7].trimmingCharacters(in: .whitespaces)),
                docID: f[8].trimmingCharacters(in: .whitespaces)
            )
        }
    }
}

/// One periodic-transaction-report row from the House disclosure index.
struct FilingRecord {
    let last: String
    /// Combined state + zero-padded district, e.g. "CA12".
    let stateDistrict: String
    let year: String
    let filingDate: Date?
    let docID: String

    /// Whether this filing belongs to the given representative — same district
    /// and a last name that appears in the member's display name. Matching on
    /// district alone would also catch challengers who filed as candidates in
    /// the same district within the year.
    func matches(_ representative: Representative) -> Bool {
        guard stateDistrict == representative.houseDistrictCode else { return false }
        return representative.name.localizedCaseInsensitiveContains(last)
    }

    /// A link to the report's PDF on the Clerk's site.
    var ptrURL: URL? {
        URL(string: "https://disclosures-clerk.house.gov/public_disc/ptr-pdfs/\(year)/\(docID).pdf")
    }
}

private extension Representative {
    /// The state + zero-padded district code the House index uses, e.g. "CA12".
    /// At-large districts are recorded as "00".
    var houseDistrictCode: String {
        String(format: "%@%02d", state, district ?? 0)
    }
}

/// The "M/d/yyyy" dates the House disclosure index uses, e.g. "6/11/2026".
private let filingDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/New_York")
    formatter.dateFormat = "M/d/yyyy"
    return formatter
}()

// MARK: - Minimal ZIP reader

/// A read-only ZIP extractor for a single named entry. The House index ships as
/// a ZIP with no first-party Swift decoder available, so this parses the archive
/// directly: it walks the central directory (which always carries accurate
/// sizes) and inflates the entry's DEFLATE stream with the Compression
/// framework. Only what this app needs — enough for the disclosure index.
enum ZipReader {
    /// Returns the decompressed bytes of the entry with the given name, or nil if
    /// it isn't present or can't be decoded.
    static func entry(named name: String, in data: Data) -> Data? {
        guard let eocd = endOfCentralDirectory(in: data) else { return nil }
        var offset = eocd.centralDirectoryOffset

        for _ in 0..<eocd.entryCount {
            guard offset + 46 <= data.count, u32(data, offset) == 0x02014b50 else { return nil }
            let method = u16(data, offset + 10)
            let compressedSize = u32(data, offset + 20)
            let uncompressedSize = u32(data, offset + 24)
            let nameLength = u16(data, offset + 28)
            let extraLength = u16(data, offset + 30)
            let commentLength = u16(data, offset + 32)
            let localHeaderOffset = u32(data, offset + 42)

            let entryName = String(
                data: data.subdata(in: (offset + 46)..<(offset + 46 + nameLength)),
                encoding: .utf8
            )

            if entryName == name {
                return payload(
                    in: data,
                    localHeaderOffset: localHeaderOffset,
                    method: method,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize
                )
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
        return nil
    }

    /// Reads and (if needed) inflates one entry's data, locating its start from
    /// the local file header — whose name/extra lengths can differ from the
    /// central directory's.
    private static func payload(
        in data: Data,
        localHeaderOffset: Int,
        method: Int,
        compressedSize: Int,
        uncompressedSize: Int
    ) -> Data? {
        guard localHeaderOffset + 30 <= data.count,
              u32(data, localHeaderOffset) == 0x04034b50 else { return nil }
        let nameLength = u16(data, localHeaderOffset + 26)
        let extraLength = u16(data, localHeaderOffset + 28)
        let start = localHeaderOffset + 30 + nameLength + extraLength
        guard start + compressedSize <= data.count else { return nil }

        let compressed = data.subdata(in: start..<(start + compressedSize))
        switch method {
        case 0: return compressed // stored, no compression
        case 8: return inflate(compressed, expectedSize: uncompressedSize)
        default: return nil
        }
    }

    /// Inflates a raw DEFLATE stream (ZIP method 8) into a buffer of the known
    /// uncompressed size. `COMPRESSION_ZLIB` decodes raw DEFLATE without a zlib
    /// wrapper, which is exactly what a ZIP entry holds.
    private static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        return data.withUnsafeBytes { raw -> Data? in
            guard let src = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: expectedSize)
            defer { dst.deallocate() }
            let written = compression_decode_buffer(
                dst, expectedSize, src, data.count, nil, COMPRESSION_ZLIB
            )
            return written > 0 ? Data(bytes: dst, count: written) : nil
        }
    }

    /// Locates the End of Central Directory record by scanning backward for its
    /// signature, returning the entry count and central-directory offset.
    private static func endOfCentralDirectory(
        in data: Data
    ) -> (entryCount: Int, centralDirectoryOffset: Int)? {
        guard data.count >= 22 else { return nil }
        var i = data.count - 22
        while i >= 0 {
            if u32(data, i) == 0x06054b50 {
                return (u16(data, i + 10), u32(data, i + 16))
            }
            i -= 1
        }
        return nil
    }

    private static func u16(_ data: Data, _ offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
            | (Int(data[offset + 2]) << 16) | (Int(data[offset + 3]) << 24)
    }
}
