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
    /// variable, then a key drawn from the pool in the bundled `Secrets.plist`
    /// (`CensusAPIKey`) or the `CensusAPIKey` Info.plist entry. `Secrets.plist`
    /// may hold either a single key or an array of keys; when it holds several,
    /// each install is randomly assigned one (see `APIKeyPool`) so no single key
    /// hits its rate limit. Falls back to the placeholder.
    static var configured: String {
        if let env = ProcessInfo.processInfo.environment["CENSUS_API_KEY"], !env.isEmpty {
            return env
        }
        let pool = APIKeyPool.keys(forKey: "CensusAPIKey", placeholder: placeholder)
        if let key = APIKeyPool.assignedKey(from: pool, persistenceKey: "apiKeyPool.census") {
            return key
        }
        return placeholder
    }

    /// Whether a real key (not the placeholder) is available.
    static var isConfigured: Bool {
        let key = configured
        return !key.isEmpty && key != placeholder
    }
}
