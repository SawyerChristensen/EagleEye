//
//  Representative.swift
//  EagleEye
//
//  A member of Congress representing the user.
//

import Foundation
import CoreLocation

/// A political party affiliation.
enum Party: String, Codable {
    case democrat = "Democrat"
    case republican = "Republican"
    case independent = "Independent"

    /// Single-letter abbreviation, e.g. "D", "R", "I".
    var abbreviation: String { String(rawValue.prefix(1)) }
}

/// The office a member of Congress holds.
enum Office: String, Codable {
    case senator = "Senator"
    case representative = "Representative"
}

/// How a member voted on a particular bill.
enum VotePosition: String, Codable {
    case yea = "Yea"
    case nay = "Nay"
    case notVoting = "Did Not Vote"
}

/// A single recorded vote, used on the member's profile.
struct VoteRecord: Codable, Hashable {
    let billTitle: String
    let position: VotePosition
    let date: Date
}

/// A source of campaign funding, used on the member's profile.
struct Funder: Codable, Hashable {
    let name: String
    /// Total contributions in whole dollars.
    let amount: Int
    /// Broad industry or interest category, e.g. "Technology".
    let category: String
}

/// A congressional representative the user can follow and track.
struct Representative: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let party: Party
    let office: Office
    let state: String
    /// District number for House members; `nil` for senators.
    let district: Int?
    /// Congress.gov Bioguide identifier (e.g. "P000197"); `nil` for sample data.
    let bioguideID: String?
    /// Approximate location of the member's district office, used on the map.
    let officeLatitude: Double
    let officeLongitude: Double

    // MARK: - Profile

    /// Official portrait image. When `nil`, the UI falls back to initials.
    let portraitURL: URL?
    /// The date the member first took office, used to compute tenure.
    let tenureStart: Date
    /// Congressional committees the member sits on.
    let committees: [String]
    /// A sampling of notable votes (placeholder until a votes API is wired up).
    let keyVotes: [VoteRecord]
    /// Titles of bills the member sponsored.
    let sponsoredBills: [String]
    /// Titles of bills the member cosponsored.
    let cosponsoredBills: [String]
    /// Top campaign funders (placeholder until a finance API is wired up).
    let funders: [Funder]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: officeLatitude, longitude: officeLongitude)
    }

    /// Returns a copy with the sponsored and cosponsored bill lists replaced,
    /// used to fill in those profile sections after the member's legislation is
    /// loaded from Congress.gov.
    func withBills(sponsored: [String], cosponsored: [String]) -> Representative {
        Representative(
            id: id,
            name: name,
            party: party,
            office: office,
            state: state,
            district: district,
            bioguideID: bioguideID,
            officeLatitude: officeLatitude,
            officeLongitude: officeLongitude,
            portraitURL: portraitURL,
            tenureStart: tenureStart,
            committees: committees,
            keyVotes: keyVotes,
            sponsoredBills: sponsored,
            cosponsoredBills: cosponsored,
            funders: funders
        )
    }

    /// Returns a copy with the voting history replaced, used to fill in that
    /// profile section after the member's recent floor votes are loaded.
    func withVotes(_ keyVotes: [VoteRecord]) -> Representative {
        Representative(
            id: id,
            name: name,
            party: party,
            office: office,
            state: state,
            district: district,
            bioguideID: bioguideID,
            officeLatitude: officeLatitude,
            officeLongitude: officeLongitude,
            portraitURL: portraitURL,
            tenureStart: tenureStart,
            committees: committees,
            keyVotes: keyVotes,
            sponsoredBills: sponsoredBills,
            cosponsoredBills: cosponsoredBills,
            funders: funders
        )
    }

    /// Returns a copy with the committee list replaced, used to fill in that
    /// profile section after the member's assignments are loaded.
    func withCommittees(_ committees: [String]) -> Representative {
        Representative(
            id: id,
            name: name,
            party: party,
            office: office,
            state: state,
            district: district,
            bioguideID: bioguideID,
            officeLatitude: officeLatitude,
            officeLongitude: officeLongitude,
            portraitURL: portraitURL,
            tenureStart: tenureStart,
            committees: committees,
            keyVotes: keyVotes,
            sponsoredBills: sponsoredBills,
            cosponsoredBills: cosponsoredBills,
            funders: funders
        )
    }

    /// A short subtitle like "Senator · California (D)".
    var subtitle: String {
        switch office {
        case .senator:
            "Senator · \(state) (\(party.abbreviation))"
        case .representative:
            "Rep. · \(state)\(district.map { "-\($0)" } ?? "") (\(party.abbreviation))"
        }
    }

    /// Office and party only, e.g. "Senator, Democrat".
    var roleDescription: String {
        "\(office.rawValue), \(party.rawValue)"
    }

    /// A human-readable tenure length, e.g. "In office 8 years".
    var tenureDescription: String {
        let years = Calendar.current.dateComponents([.year], from: tenureStart, to: Date()).year ?? 0
        if years < 1 {
            return "In office less than a year"
        }
        return "In office \(years) year\(years == 1 ? "" : "s")"
    }

    init(
        id: UUID = UUID(),
        name: String,
        party: Party,
        office: Office,
        state: String,
        district: Int? = nil,
        bioguideID: String? = nil,
        officeLatitude: Double,
        officeLongitude: Double,
        portraitURL: URL? = nil,
        tenureStart: Date = Date(),
        committees: [String] = [],
        keyVotes: [VoteRecord] = [],
        sponsoredBills: [String] = [],
        cosponsoredBills: [String] = [],
        funders: [Funder] = []
    ) {
        self.id = id
        self.name = name
        self.party = party
        self.office = office
        self.state = state
        self.district = district
        self.bioguideID = bioguideID
        self.officeLatitude = officeLatitude
        self.officeLongitude = officeLongitude
        self.portraitURL = portraitURL
        self.tenureStart = tenureStart
        self.committees = committees
        self.keyVotes = keyVotes
        self.sponsoredBills = sponsoredBills
        self.cosponsoredBills = cosponsoredBills
        self.funders = funders
    }
}
