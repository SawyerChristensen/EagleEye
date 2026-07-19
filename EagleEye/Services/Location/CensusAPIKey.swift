//
//  CensusAPIKey.swift
//  EagleEye
//
//  Resolves the Census Bureau Data API key shared by the ACS-backed lookups
//  (`DistrictPopulationService`, `DistrictIndustryService`,
//  `DistrictDemographicsService`). The Census Data API used to serve keyless
//  requests, but now rejects them with a "Missing Key" HTML page, so every
//  ACS request must carry a `key` parameter.
//
//  Get a free key instantly at https://api.census.gov/data/key_signup.html,
//  then add it to the gitignored `Secrets.plist` under `CensusAPIKey` (or set
//  the `CENSUS_API_KEY` environment variable). Without a key, the ACS-backed
//  sections simply stay empty — the keyless city and university lookups still
//  work.
//

import Foundation

enum CensusAPIKey {
    static let placeholder = "YOUR_CENSUS_API_KEY"

    /// Resolves the key from, in order: the `CENSUS_API_KEY` environment
    /// variable, the bundled `Secrets.plist` (`CensusAPIKey`), or the
    /// `CensusAPIKey` Info.plist entry. Falls back to the placeholder.
    static var configured: String {
        if let env = ProcessInfo.processInfo.environment["CENSUS_API_KEY"], !env.isEmpty {
            return env
        }
        if let secret = secretsValue(forKey: "CensusAPIKey") {
            return secret
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "CensusAPIKey") as? String,
           !plist.isEmpty {
            return plist
        }
        return placeholder
    }

    /// Whether a real key (not the placeholder) is available.
    static var isConfigured: Bool {
        let key = configured
        return !key.isEmpty && key != placeholder
    }

    /// Reads a string from the bundled `Secrets.plist`, if present.
    private static func secretsValue(forKey key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any],
              let value = dict[key] as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
