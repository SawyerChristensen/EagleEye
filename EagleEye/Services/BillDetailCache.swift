//
//  BillDetailCache.swift
//  EagleEye
//
//  Caches a bill's full detail and roll-call vote outcome to disk, keyed by its
//  congress/type/number identifiers, so a bill reached from a representative's
//  profile (or reopened) still shows its detail and votes offline once it has
//  been fetched once.
//

import Foundation

enum BillDetailCache {
    private static let billsKey = "cachedBillDetailsByReference"
    private static let votesKey = "cachedBillVoteOutcomes"

    private static func key(congress: Int, type: String, number: String) -> String {
        "\(congress)-\(type.uppercased())-\(number)"
    }

    // MARK: - Bill detail

    static func cachedBill(for reference: LegislationRef) -> Bill? {
        guard let congress = reference.congress,
              let type = reference.type, !type.isEmpty,
              let number = reference.number, !number.isEmpty else {
            return nil
        }
        return load(billsKey, as: [String: Bill].self)?[key(congress: congress, type: type, number: number)]
    }

    static func cacheBill(_ bill: Bill, for reference: LegislationRef) {
        guard let congress = reference.congress,
              let type = reference.type, !type.isEmpty,
              let number = reference.number, !number.isEmpty else {
            return
        }
        var cache = load(billsKey, as: [String: Bill].self) ?? [:]
        cache[key(congress: congress, type: type, number: number)] = bill
        save(cache, forKey: billsKey)
    }

    // MARK: - Vote outcome

    static func cachedVoteOutcome(congress: Int, type: String, number: String) -> BillVoteOutcome? {
        load(votesKey, as: [String: BillVoteOutcome].self)?[key(congress: congress, type: type, number: number)]
    }

    static func cacheVoteOutcome(_ outcome: BillVoteOutcome, congress: Int, type: String, number: String) {
        var cache = load(votesKey, as: [String: BillVoteOutcome].self) ?? [:]
        cache[key(congress: congress, type: type, number: number)] = outcome
        save(cache, forKey: votesKey)
    }

    // MARK: - Storage

    private static func load<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
