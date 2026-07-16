//
//  RepresentativeProfileCache.swift
//  EagleEye
//
//  Remembers profiles that have already been enriched on demand, keyed by
//  Bioguide ID, so reopening a member (e.g. tapping the same district on the
//  map twice) reuses the fetched committee, bill, and funder data instead of
//  loading it all over again.
//

import Foundation

/// A process-lifetime cache of fully enriched representatives. Lives in memory
/// only — the goal is to avoid re-fetching within a session, not to persist
/// across launches (the user's own delegation is already cached to disk by
/// `RepresentativesStore`). Access is confined to the main actor to match the
/// views that read and write it.
@MainActor
enum RepresentativeProfileCache {
    private static var profilesByBioguideID: [String: Representative] = [:]

    /// The enriched profile previously stored for this member, if any.
    static func profile(forBioguideID id: String) -> Representative? {
        profilesByBioguideID[id]
    }

    /// Stores an enriched profile so a later open of the same member can reuse
    /// it. No-op when the member has no Bioguide ID to key on (e.g. sample data).
    static func store(_ representative: Representative) {
        guard let id = representative.bioguideID else { return }
        profilesByBioguideID[id] = representative
    }
}
