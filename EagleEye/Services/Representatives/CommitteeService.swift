//
//  CommitteeService.swift
//  EagleEye
//
//  Loads congressional committee assignments for members of Congress.
//
//  ---------------------------------------------------------------------------
//  Why this isn't part of CongressService
//  ---------------------------------------------------------------------------
//  The Congress.gov API does not expose which committees a member sits on — the
//  member endpoints return biography, terms, and legislation, but no committee
//  membership. So that one fact is sourced here from the community-maintained,
//  openly licensed `unitedstates/congress-legislators` dataset, which publishes
//  current committee rosters keyed by Bioguide ID.
//
//  The dataset is two small JSON files covering all of Congress, so it's fetched
//  once per delegation load (not per member) and requires no API key.
//

import Foundation

/// Resolves which committees each member of Congress currently sits on, keyed
/// by Bioguide ID. Returns an empty map on any failure, leaving profiles
/// unchanged rather than surfacing an error.
struct CommitteeService {
    var session: URLSession = .shared

    /// Roster of every committee/subcommittee, keyed by committee code, with the
    /// members on each.
    private static let membershipURL = URL(
        string: "https://unitedstates.github.io/congress-legislators/committee-membership-current.json"
    )!
    /// Metadata (names, types) for the full standing/select committees.
    private static let committeesURL = URL(
        string: "https://unitedstates.github.io/congress-legislators/committees-current.json"
    )!

    /// Returns a map of Bioguide ID → display names of the full committees that
    /// member sits on. Subcommittees are intentionally omitted to keep each
    /// profile concise. Both source files are fetched concurrently; any failure
    /// yields an empty map.
    func committeeAssignments() async -> [String: [String]] {
        async let committees = fetch([CommitteeDTO].self, from: Self.committeesURL)
        async let membership = fetch([String: [MembershipEntry]].self, from: Self.membershipURL)

        guard let committees = await committees, let membership = await membership else {
            return [:]
        }

        // Map each full-committee code to its cleaned display name. Subcommittees
        // carry a suffixed code (e.g. "SSAF17") that won't appear here, so keying
        // the membership pass off this map naturally drops them.
        let nameByCode = Dictionary(
            committees.map { ($0.thomas_id, Self.displayName($0.name)) },
            uniquingKeysWith: { first, _ in first }
        )

        var result: [String: [String]] = [:]
        for (code, members) in membership {
            guard let name = nameByCode[code] else { continue }
            for member in members {
                result[member.bioguide, default: []].append(name)
            }
        }

        // Present each member's committees in a stable, alphabetical order.
        for (id, names) in result {
            result[id] = names.sorted()
        }

        return result
    }

    /// Fetches and decodes a JSON document, returning nil on any network or
    /// decoding failure.
    private func fetch<T: Decodable>(_ type: T.Type, from url: URL) async -> T? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                return nil
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    /// Trims the chamber prefix and "Committee" boilerplate from an official
    /// committee name so it reads like the rest of the profile, e.g.
    /// "House Committee on Agriculture" → "Agriculture".
    private static func displayName(_ name: String) -> String {
        var trimmed = name

        for prefix in ["House ", "Senate ", "Joint "] where trimmed.hasPrefix(prefix) {
            trimmed.removeFirst(prefix.count)
            break
        }
        trimmed = trimmed
            .replacingOccurrences(of: "Committee on the ", with: "")
            .replacingOccurrences(of: "Committee on ", with: "")
        if trimmed.hasSuffix(" Committee") {
            trimmed = String(trimmed.dropLast(" Committee".count))
        }

        let cleaned = trimmed.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? name : cleaned
    }
}

// MARK: - Wire format

/// A committee from `committees-current.json`. Only the full committees appear
/// here; their subcommittees are nested but not needed for the profile.
private struct CommitteeDTO: Decodable {
    let thomas_id: String
    let name: String
}

/// One member's seat on a committee, from `committee-membership-current.json`.
private struct MembershipEntry: Decodable {
    let bioguide: String
}
