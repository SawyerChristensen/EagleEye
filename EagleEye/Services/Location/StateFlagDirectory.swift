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
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum StateFlagDirectory {
    /// The asset-catalog name for a state's bundled flag, keyed by two-letter
    /// postal code (e.g. "CA" → "StateFlag_CA"). All 50 states plus DC and PR
    /// ship in `Assets.xcassets/StateFlags`.
    static func assetName(forState state: String) -> String {
        "StateFlag_\(state.uppercased())"
    }

    /// The bundled flag for a state, if one ships in the asset catalog. Loading
    /// from the bundle is instant and offline, so this is preferred over the
    /// network `flagURL` — the latter is only a fallback for states without a
    /// bundled asset.
    static func bundledImage(forState state: String) -> PlatformImage? {
        #if canImport(UIKit)
        return UIImage(named: assetName(forState: state))
        #elseif canImport(AppKit)
        return NSImage(named: assetName(forState: state))
        #else
        return nil
        #endif
    }

    /// The flag image for a state, keyed by two-letter postal code. `nil` for
    /// codes with no known Commons flag file (e.g. territories not covered
    /// below). Used as a network fallback when no bundled asset exists.
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
