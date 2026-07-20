//
//  SampleData.swift
//  EagleEye
//
//  Placeholder data so the UI has something to show before a real
//  Congress data source (e.g. the Congress.gov API) is wired up.
//

import Foundation

// Placeholder data is compiled into DEBUG builds only, so it never bloats the
// shipping app. Production code paths that used to fall back to this must be
// guarded with `#if DEBUG` (see BillsStore / RepresentativesStore).
#if DEBUG
enum SampleData {
    /// A few representative bills for the home feed.
    static let bills: [Bill] = {
        let now = Date()
        func daysAgo(_ days: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        }

        return [
            Bill(
                title: "H.R. 1842 — Clean Energy Innovation Act",
                summary: "Expands tax credits for residential solar and battery storage, and directs the Department of Energy to fund grid-modernization grants for rural communities.",
                chamber: .house,
                status: .passedHouse,
                latestActionDate: daysAgo(1),
                topics: ["Energy"]
            ),
            Bill(
                title: "S. 920 — Veterans Mental Health Access Act",
                summary: "Removes copays for the first six mental-health visits at VA facilities and funds expanded tele-health counseling for veterans in remote areas.",
                chamber: .senate,
                status: .inCommittee,
                latestActionDate: daysAgo(2),
                topics: ["Armed Forces and National Security"]
            ),
            Bill(
                title: "H.R. 305 — Small Business Relief & Fairness Act",
                summary: "Raises the simplified-expensing threshold for small businesses and streamlines federal loan applications for firms with fewer than 50 employees.",
                chamber: .house,
                status: .introduced,
                latestActionDate: daysAgo(3),
                topics: ["Commerce"]
            ),
            Bill(
                title: "H.R. 448 — Border Infrastructure Modernization Act",
                summary: "Would have authorized new funding for port-of-entry technology and expanded staffing for asylum processing. Passed the House but was voted down in the Senate.",
                chamber: .house,
                status: .passedHouse,
                latestActionDate: daysAgo(4),
                topics: ["Immigration"],
                failedChamber: .senate
            ),
            Bill(
                title: "S. 1156 — Coastal Resilience Funding Act",
                summary: "Authorizes $4B over five years for flood-control infrastructure and wetland restoration in coastal states facing rising sea levels.",
                chamber: .senate,
                status: .passedSenate,
                latestActionDate: daysAgo(5),
                topics: ["Water Resources Development"]
            ),
            Bill(
                title: "H.R. 77 — Digital Privacy Protection Act",
                summary: "Establishes a national standard requiring companies to let consumers delete personal data and opt out of targeted advertising.",
                chamber: .house,
                status: .toPresident,
                latestActionDate: daysAgo(6),
                topics: ["Science, Technology, Communications"]
            ),
            Bill(
                title: "S. 64 — Rural Broadband Expansion Act",
                summary: "Provides matching grants to extend high-speed internet to unserved rural areas and caps installation fees for low-income households.",
                chamber: .senate,
                status: .enacted,
                latestActionDate: daysAgo(9),
                topics: ["Transportation and Public Works"]
            ),
        ]
    }()

    /// The user's current congressional delegation (placeholder).
    static let representatives: [Representative] = {
        let now = Date()
        func yearsAgo(_ years: Int) -> Date {
            Calendar.current.date(byAdding: .year, value: -years, to: now) ?? now
        }
        func daysAgo(_ days: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        }

        return [
            Representative(
                name: "Alex Rivera",
                party: .democrat,
                office: .senator,
                state: "California",
                officeLatitude: 37.7749,
                officeLongitude: -122.4194,
                tenureStart: yearsAgo(11),
                committees: ["Appropriations", "Judiciary", "Energy & Natural Resources"],
                keyVotes: [
                    VoteRecord(billTitle: "H.R. 1842 — Clean Energy Innovation Act", position: .yea, date: daysAgo(1)),
                    VoteRecord(billTitle: "S. 1156 — Coastal Resilience Funding Act", position: .yea, date: daysAgo(5)),
                    VoteRecord(billTitle: "H.R. 305 — Small Business Relief & Fairness Act", position: .nay, date: daysAgo(3)),
                ],
                sponsoredBills: [
                    LegislationRef(title: "S. 1156 — Coastal Resilience Funding Act"),
                    LegislationRef(title: "S. 64 — Rural Broadband Expansion Act"),
                ],
                cosponsoredBills: [
                    LegislationRef(title: "H.R. 1842 — Clean Energy Innovation Act"),
                    LegislationRef(title: "S. 920 — Veterans Mental Health Access Act"),
                ],
                funders: [
                    Funder(name: "Renewable Energy PAC", amount: 412_000, category: "Energy"),
                    Funder(name: "Tech Workers United", amount: 305_500, category: "Technology"),
                    Funder(name: "Education Association", amount: 188_200, category: "Education"),
                ],
                individualFunders: [
                    Funder(name: "University Of California", amount: 128_400, category: "Employees"),
                    Funder(name: "Attorneys", amount: 74_900, category: ""),
                    Funder(name: "Alphabet", amount: 61_250, category: "Employees"),
                ]
            ),
            Representative(
                name: "Jordan Bennett",
                party: .republican,
                office: .senator,
                state: "California",
                officeLatitude: 34.0522,
                officeLongitude: -118.2437,
                tenureStart: yearsAgo(5),
                committees: ["Armed Services", "Finance", "Small Business"],
                keyVotes: [
                    VoteRecord(billTitle: "H.R. 305 — Small Business Relief & Fairness Act", position: .yea, date: daysAgo(3)),
                    VoteRecord(billTitle: "S. 1156 — Coastal Resilience Funding Act", position: .nay, date: daysAgo(5)),
                    VoteRecord(billTitle: "S. 64 — Rural Broadband Expansion Act", position: .yea, date: daysAgo(9)),
                ],
                sponsoredBills: [
                    LegislationRef(title: "H.R. 305 — Small Business Relief & Fairness Act"),
                ],
                cosponsoredBills: [
                    LegislationRef(title: "S. 64 — Rural Broadband Expansion Act"),
                ],
                funders: [
                    Funder(name: "Small Business Coalition", amount: 521_000, category: "Business"),
                    Funder(name: "Defense Industries Group", amount: 398_750, category: "Defense"),
                    Funder(name: "Agriculture Federation", amount: 142_900, category: "Agriculture"),
                ]
            ),
            Representative(
                name: "Sam Carter",
                party: .independent,
                office: .representative,
                state: "California",
                district: 12,
                officeLatitude: 37.8044,
                officeLongitude: -122.2712,
                tenureStart: yearsAgo(3),
                committees: ["Science, Space & Technology", "Transportation & Infrastructure"],
                keyVotes: [
                    VoteRecord(billTitle: "H.R. 77 — Digital Privacy Protection Act", position: .yea, date: daysAgo(6)),
                    VoteRecord(billTitle: "H.R. 1842 — Clean Energy Innovation Act", position: .yea, date: daysAgo(1)),
                    VoteRecord(billTitle: "H.R. 305 — Small Business Relief & Fairness Act", position: .notVoting, date: daysAgo(3)),
                ],
                sponsoredBills: [
                    LegislationRef(title: "H.R. 77 — Digital Privacy Protection Act"),
                ],
                cosponsoredBills: [
                    LegislationRef(title: "H.R. 1842 — Clean Energy Innovation Act"),
                    LegislationRef(title: "S. 64 — Rural Broadband Expansion Act"),
                ],
                funders: [
                    Funder(name: "Digital Rights Network", amount: 96_400, category: "Technology"),
                    Funder(name: "Grassroots Donors", amount: 84_100, category: "Individuals"),
                    Funder(name: "Transit Advocates", amount: 51_300, category: "Infrastructure"),
                ]
            ),
        ]
    }()
}
#endif
