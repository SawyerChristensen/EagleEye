//
//  StateFlagDirectory.swift
//  EagleEye
//
//  State flag images for the map's state-level view (see TO DO.md). Sourced
//  from Wikimedia Commons via its `Special:FilePath` redirect, which resolves
//  a bare filename straight to that file's current upload — no per-state
//  upload hash to track — and, with a `width` query, redirects again to a
//  rendered PNG of the (otherwise undecodable) source SVG.
//

import Foundation

enum StateFlagDirectory {
    /// The flag image for a state, keyed by two-letter postal code. `nil` for
    /// codes with no known Commons flag file (e.g. territories not covered
    /// below).
    static func flagURL(forState state: String) -> URL? {
        let name = commonsFileNames[state.uppercased()] ?? MapBoundary.stateName(for: state).replacingOccurrences(of: " ", with: "_")
        return URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/Flag_of_\(name).svg?width=800")
    }

    /// Commons file-name overrides for states whose plain name is ambiguous
    /// with another Commons file (Georgia's flag file is disambiguated from
    /// the country of Georgia's).
    private static let commonsFileNames: [String: String] = [
        "GA": "Georgia_(U.S._state)",
    ]
}
