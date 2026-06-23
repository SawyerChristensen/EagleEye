//
//  Bill.swift
//  EagleEye
//
//  A piece of legislation moving through Congress.
//

import Foundation

/// The chamber a bill originates in.
enum Chamber: String, Codable {
    case house = "House"
    case senate = "Senate"

    var symbolName: String {
        switch self {
        case .house: "building.columns"
        case .senate: "building.columns.fill"
        }
    }
}

/// Where a bill currently sits in the legislative process.
enum BillStatus: String, Codable, CaseIterable {
    case introduced = "Introduced"
    case inCommittee = "In Committee"
    case passedHouse = "Passed House"
    case passedSenate = "Passed Senate"
    case toPresident = "To President"
    case enacted = "Enacted"

    var tint: String {
        switch self {
        case .introduced, .inCommittee: "secondary"
        case .passedHouse, .passedSenate, .toPresident: "blue"
        case .enacted: "green"
        }
    }
}

/// A single bill shown in the home feed. `title` is the name of the bill and
/// `summary` is the human-readable description displayed underneath it.
struct Bill: Identifiable, Codable, Hashable {
    let id: UUID
    /// The official short name, e.g. "H.R. 1234 — Clean Water Act".
    let title: String
    /// A plain-language summary used as the feed description.
    let summary: String
    let chamber: Chamber
    let status: BillStatus
    /// The date of the most recent action on the bill.
    let latestActionDate: Date
    /// Broad policy areas the bill touches, used for quick scanning.
    let topics: [String]

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        chamber: Chamber,
        status: BillStatus,
        latestActionDate: Date,
        topics: [String] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.chamber = chamber
        self.status = status
        self.latestActionDate = latestActionDate
        self.topics = topics
    }
}
