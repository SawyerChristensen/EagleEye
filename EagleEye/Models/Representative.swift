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
    case present = "Present"
    case notVoting = "Did Not Vote"
}

/// A single recorded vote, used on the member's profile.
struct VoteRecord: Codable, Hashable {
    /// Display name of the legislation voted on, e.g.
    /// "Clean Energy Innovation Act — H.R. 1842".
    let billTitle: String
    let position: VotePosition
    let date: Date
    /// The specific floor question, e.g. "On Passage" — surfaced when a vote is
    /// tapped for detail. `nil` for placeholder sample data.
    let question: String?
    /// Identifiers for the measure voted on, used to open its detail screen from
    /// the voting-history tab. `nil` for placeholder sample data.
    let congress: Int?
    let type: String?
    let number: String?

    init(
        billTitle: String,
        position: VotePosition,
        date: Date,
        question: String? = nil,
        congress: Int? = nil,
        type: String? = nil,
        number: String? = nil
    ) {
        self.billTitle = billTitle
        self.position = position
        self.date = date
        self.question = question
        self.congress = congress
        self.type = type
        self.number = number
    }

    /// A navigable reference to the measure voted on, so a vote row can open the
    /// same bill-detail screen the home feed does. `nil` when the identifiers
    /// needed to load the bill aren't available.
    var legislationRef: LegislationRef? {
        guard let congress, let type, !type.isEmpty,
              let number, !number.isEmpty else { return nil }
        return LegislationRef(congress: congress, type: type, number: number, title: billTitle)
    }
}

/// A reference to a piece of legislation a member sponsored or cosponsored.
/// Carries the identifiers needed to open the bill's detail screen, not just a
/// display string, so each row in the profile can navigate to the full bill.
struct LegislationRef: Codable, Hashable, Identifiable {
    let id: UUID
    /// The Congress the measure belongs to, e.g. 119.
    let congress: Int?
    /// The measure type code, e.g. "HR", "S", "HRES".
    let type: String?
    /// The measure number as a string, e.g. "1842".
    let number: String?
    /// The official title, without the "— H.R. 1234" suffix.
    let title: String

    /// The familiar short name shown in the UI, e.g. "Clean Water Act — H.R. 1234".
    var displayTitle: String {
        Bill.displayTitle(type: type, number: number, title: title)
    }

    /// Whether enough identifiers are present to load the bill's detail screen.
    /// Sample data carries only a title, so those rows render without a chevron.
    var isNavigable: Bool {
        congress != nil && type?.isEmpty == false && number?.isEmpty == false
    }

    init(id: UUID = UUID(), congress: Int? = nil, type: String? = nil, number: String? = nil, title: String) {
        self.id = id
        self.congress = congress
        self.type = type
        self.number = number
        self.title = title
    }
}

/// A link to a member's presence on a social-media platform.
struct SocialLink: Codable, Hashable, Identifiable {
    enum Platform: String, Codable, CaseIterable {
        case twitter, facebook, youtube, instagram

        /// Human-readable name, e.g. "X" for the platform formerly Twitter.
        var displayName: String {
            switch self {
            case .twitter: "X"
            case .facebook: "Facebook"
            case .youtube: "YouTube"
            case .instagram: "Instagram"
            }
        }

        /// Name of the monochrome brand-logo asset (template-rendered) shown
        /// beside the platform name.
        var iconName: String {
            switch self {
            case .twitter: "LogoX"
            case .facebook: "LogoFacebook"
            case .youtube: "LogoYouTube"
            case .instagram: "LogoInstagram"
            }
        }
    }

    let platform: Platform
    /// The account handle or ID, without a leading "@".
    let handle: String

    var id: String { platform.rawValue }

    /// The public profile URL for this account.
    var url: URL? {
        switch platform {
        case .twitter: URL(string: "https://x.com/\(handle)")
        case .facebook: URL(string: "https://facebook.com/\(handle)")
        case .youtube: URL(string: "https://youtube.com/\(handle)")
        case .instagram: URL(string: "https://instagram.com/\(handle)")
        }
    }
}

/// Office contact details for a member, shown on the profile.
struct ContactInfo: Codable, Hashable {
    /// The Washington, D.C. office address, as one display string.
    let officeAddress: String?
    /// The office telephone number.
    let phone: String?
    /// The member's official government website.
    let website: URL?
    /// Links to the member's social-media accounts.
    let socialLinks: [SocialLink]

    init(
        officeAddress: String? = nil,
        phone: String? = nil,
        website: URL? = nil,
        socialLinks: [SocialLink] = []
    ) {
        self.officeAddress = officeAddress
        self.phone = phone
        self.website = website
        self.socialLinks = socialLinks
    }

    /// Whether there's anything worth showing in the contact section.
    var hasContent: Bool {
        officeAddress?.isEmpty == false || phone?.isEmpty == false
            || website != nil || !socialLinks.isEmpty
    }
}

/// A summary of a member's stock-trade disclosures under the STOCK Act, shown
/// on the profile. Built from the House Clerk's Periodic Transaction Report
/// (PTR) index; the Senate publishes its filings separately and isn't covered
/// here yet, so senators carry a link-only summary.
struct TradingActivity: Codable, Hashable {
    /// Number of Periodic Transaction Reports filed in the trailing window.
    let recentReportCount: Int
    /// Date of the most recent Periodic Transaction Report, if any.
    let latestReportDate: Date?
    /// A link to view the member's disclosures — the most recent PTR itself for
    /// House members, or the Senate eFD search for senators.
    let disclosureURL: URL?
    /// Whether this reflects the member's real filed reports (House) rather than
    /// just a pointer to where their filings live (Senate).
    let isCovered: Bool

    init(
        recentReportCount: Int = 0,
        latestReportDate: Date? = nil,
        disclosureURL: URL? = nil,
        isCovered: Bool = false
    ) {
        self.recentReportCount = recentReportCount
        self.latestReportDate = latestReportDate
        self.disclosureURL = disclosureURL
        self.isCovered = isCovered
    }
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
    /// Bills the member sponsored.
    let sponsoredBills: [LegislationRef]
    /// Bills the member cosponsored.
    let cosponsoredBills: [LegislationRef]
    /// Top campaign funders — the organizations whose PACs gave most directly.
    let funders: [Funder]
    /// Top individual contributors, grouped by employer (labeled "Employees")
    /// or, for the self-employed and independents, by occupation.
    let individualFunders: [Funder]
    /// Office address, phone, website, and social links; `nil` until loaded.
    let contact: ContactInfo?
    /// Stock-trade disclosure summary; `nil` until loaded.
    let tradingActivity: TradingActivity?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: officeLatitude, longitude: officeLongitude)
    }

    /// Returns a copy with the sponsored and cosponsored bill lists replaced,
    /// used to fill in those profile sections after the member's legislation is
    /// loaded from Congress.gov.
    func withBills(sponsored: [LegislationRef], cosponsored: [LegislationRef]) -> Representative {
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
            funders: funders,
            individualFunders: individualFunders,
            contact: contact,
            tradingActivity: tradingActivity
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
            funders: funders,
            individualFunders: individualFunders,
            contact: contact,
            tradingActivity: tradingActivity
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
            funders: funders,
            individualFunders: individualFunders,
            contact: contact,
            tradingActivity: tradingActivity
        )
    }

    /// Returns a copy with the PAC and individual funder lists replaced, used to
    /// fill in those profile sections after the member's campaign finance data is
    /// loaded from OpenFEC.
    func withFunders(pac: [Funder], individual: [Funder]) -> Representative {
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
            funders: pac,
            individualFunders: individual,
            contact: contact,
            tradingActivity: tradingActivity
        )
    }

    /// Returns a copy with the stock-trade disclosure summary filled in, used
    /// after the member's Periodic Transaction Reports are loaded.
    func withTradingActivity(_ tradingActivity: TradingActivity) -> Representative {
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
            funders: funders,
            individualFunders: individualFunders,
            contact: contact,
            tradingActivity: tradingActivity
        )
    }

    /// Returns a copy with the contact information filled in, used after the
    /// member's office details and social links are loaded.
    func withContact(_ contact: ContactInfo) -> Representative {
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
            funders: funders,
            individualFunders: individualFunders,
            contact: contact,
            tradingActivity: tradingActivity
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
        sponsoredBills: [LegislationRef] = [],
        cosponsoredBills: [LegislationRef] = [],
        funders: [Funder] = [],
        individualFunders: [Funder] = [],
        contact: ContactInfo? = nil,
        tradingActivity: TradingActivity? = nil
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
        self.individualFunders = individualFunders
        self.contact = contact
        self.tradingActivity = tradingActivity
    }
}
