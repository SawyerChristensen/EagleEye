//
//  RepresentativesStore.swift
//  EagleEye
//
//  Loads and holds the user's congressional delegation for the UI.
//

import Foundation
import CoreLocation
import Observation

/// Owns the list of representatives shown in the app. It resolves the user's
/// location into a state (for senators) and a congressional district (for their
/// House member), then loads that delegation from the Congress.gov API. Falls
/// back to bundled sample data when no API key is configured, so the app still
/// has something to show out of the box.
///
/// The resolved coordinate and delegation are cached on disk, so after the very
/// first launch the app shows the user's representatives immediately and never
/// has to ask for their location again — meaning "Allow Once" is enough.
@MainActor
@Observable
final class RepresentativesStore {
    /// Where the store is in the launch flow, used to drive the location prompt.
    enum LoadState: Equatable {
        /// Waiting on the user to grant access and a location fix to arrive.
        case locating
        /// Have a coordinate; fetching the delegation.
        case loading
        /// Delegation (or sample data) is ready to show.
        case ready
        /// The user declined location access.
        case denied
    }

    private(set) var representatives: [Representative] = []
    // Governor disabled until v1.1.
    // /// The user's state governor, resolved from `GovernorDirectory` alongside
    // /// the congressional delegation. `nil` until a location has been resolved.
    // private(set) var governor: Governor?
    private(set) var loadState: LoadState = .locating
    /// A user-facing note when live data could not be loaded (e.g. no API key).
    private(set) var statusMessage: String?

    private let service: CongressService
    private let geocoder: CensusGeocoder
    private let committeeService: CommitteeService
    private let contactService: MemberContactService
    private let financeService: OpenFECService
    private let disclosureService: FinancialDisclosureService
    private let marketService: MarketPerformanceService

    /// The last coordinate we successfully resolved a delegation for. Persisted
    /// so future launches can refresh without prompting for location again, and
    /// exposed so the map can center on it right away instead of waiting on the
    /// slower district-boundary lookup.
    private(set) var cachedCoordinate: CLLocationCoordinate2D?

    init(
        service: CongressService = CongressService(),
        geocoder: CensusGeocoder = CensusGeocoder(),
        committeeService: CommitteeService = CommitteeService(),
        contactService: MemberContactService = MemberContactService(),
        financeService: OpenFECService = OpenFECService(),
        disclosureService: FinancialDisclosureService = FinancialDisclosureService(),
        marketService: MarketPerformanceService = MarketPerformanceService()
    ) {
        self.service = service
        self.geocoder = geocoder
        self.committeeService = committeeService
        self.contactService = contactService
        self.financeService = financeService
        self.disclosureService = disclosureService
        self.marketService = marketService

        #if DEBUG
        // Pass "-ResetDelegationCache" as a launch argument in the Run scheme to
        // wipe the cached delegation on startup, so the location prompt shows
        // again without deleting the app. Off unless the argument is present.
        if ProcessInfo.processInfo.arguments.contains("-ResetDelegationCache") {
            UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        }
        #endif

        // If we resolved the delegation on a previous launch, show it right away
        // and skip the location prompt entirely.
        if let cache = Self.loadCache(), !cache.representatives.isEmpty {
            representatives = cache.representatives
            cachedCoordinate = cache.coordinate
            // Governor disabled until v1.1.
            // governor = cache.stateCode.flatMap(GovernorDirectory.governor(forState:))
            // Seed the on-demand profile cache from the persisted delegation so
            // opening one of these members from the map reuses it immediately,
            // even before the first background refresh.
            representatives.forEach(RepresentativeProfileCache.store)
            loadState = .ready
        }
    }

    /// Whether a coordinate was cached from a previous launch, letting the app
    /// refresh the delegation without asking for location again.
    var hasCachedLocation: Bool { cachedCoordinate != nil }

    /// Resolves `coordinate` into a state and district, then loads the user's
    /// senators and their one House member.
    ///
    /// When `silent` is true the visible state is left untouched while the fetch
    /// runs (and the cached delegation is kept on failure), so a background
    /// refresh never flashes a spinner or wipes out good data.
    func loadDelegation(at coordinate: CLLocationCoordinate2D, silent: Bool = false) async {
        if !silent {
            // Clear any stale delegation (e.g. sample data shown after a
            // decline) so the grid is blank while we resolve the real members,
            // rather than flashing the previous list during the fetch.
            representatives = []
            loadState = .loading
            statusMessage = nil
        }

        await Task {
            do {
                let stateCode = try await stateCode(for: coordinate)
                // A missing district just means we can't single out the House
                // member; the senators are still correct.
                let district = try? await geocoder.congressionalDistrict(at: coordinate)

                let members = try await service.currentMembers(forState: stateCode)
                let delegation = Self.delegation(from: members, district: district)

                // Publish the basic roster right away — it already carries each
                // member's name and portrait URL, everything the list needs to
                // render — so the delegation appears immediately instead of
                // blocking on the slow per-member enrichment below (bills, votes,
                // committees, funders, trade disclosures, and rate-limited office
                // geocoding). The profiles fill in in the background and the list
                // updates in place when they arrive. Skip this when a delegation
                // is already on screen (a silent refresh over cached data) so we
                // don't briefly strip the richer cached profiles back to basics.
                if representatives.isEmpty {
                    representatives = delegation
                    // Governor disabled until v1.1.
                    // governor = GovernorDirectory.governor(forState: stateCode)
                    loadState = .ready
                }

                let enriched = await Self.enrichedProfiles(
                    for: delegation,
                    using: service,
                    committeeService: committeeService,
                    contactService: contactService,
                    financeService: financeService,
                    disclosureService: disclosureService,
                    marketService: marketService
                )
                representatives = enriched
                // Governor disabled until v1.1.
                // governor = GovernorDirectory.governor(forState: stateCode)
                cachedCoordinate = coordinate
                Self.saveCache(coordinate: coordinate, stateCode: stateCode, representatives: representatives)
                // Share the freshly enriched delegation with the on-demand
                // profile cache so opening one of these members from the map
                // reuses this data instead of fetching it all over again.
                representatives.forEach(RepresentativeProfileCache.store)
                loadState = .ready
            } catch CongressService.ServiceError.missingAPIKey {
                // No key configured: keep any cached delegation on a silent
                // refresh, otherwise show sample data.
                if !silent {
                    #if DEBUG
                    representatives = SampleData.representatives
                    statusMessage = "Showing sample data — add a Congress.gov API key to load live representatives."
                    #else
                    statusMessage = "Representatives are temporarily unavailable. Please try again later."
                    #endif
                    loadState = .ready
                }
            } catch {
                // A background refresh that fails should leave the cached
                // delegation exactly as it was.
                if !silent {
                    statusMessage = error.localizedDescription
                    #if DEBUG
                    if representatives.isEmpty {
                        representatives = SampleData.representatives
                    }
                    #endif
                    loadState = .ready
                }
            }
        }.value
    }

    /// Refreshes the delegation using the coordinate saved on a previous launch,
    /// without re-prompting for location. No-op when nothing has been cached yet.
    func refreshUsingCachedLocation() async {
        guard let coordinate = cachedCoordinate else { return }
        await loadDelegation(at: coordinate, silent: true)
    }

    /// Resolves a five-digit U.S. ZIP code to a coordinate and loads the
    /// delegation there. This is the manual fallback for when device location is
    /// unavailable, denied, or too vague to pin down the right district.
    func loadDelegation(forZIP zip: String) async {
        let trimmed = zip.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 5, trimmed.allSatisfy(\.isNumber) else {
            statusMessage = "Enter a valid 5-digit ZIP code."
            return
        }

        loadState = .loading
        statusMessage = nil

        do {
            // Constrain to a U.S. postal code so a bare number geocodes reliably.
            let placemarks = try await CLGeocoder().geocodeAddressString("\(trimmed), USA")
            guard let coordinate = placemarks.first?.location?.coordinate else {
                throw CLError(.geocodeFoundNoResult)
            }
            await loadDelegation(at: coordinate)
        } catch {
            statusMessage = "Couldn't find that ZIP code — please check it and try again."
            // Fall back to the prompt (first launch) or the existing delegation.
            loadState = representatives.isEmpty ? .denied : .ready
        }
    }

    /// Marks a location request as in flight, moving straight to `.loading` so
    /// the main tabs (and the home feed, which doesn't depend on the
    /// delegation) render immediately instead of blocking on the location
    /// prompt while CoreLocation waits for a fix.
    func beginLocating() {
        loadState = .loading
        statusMessage = nil
    }

    /// Records that location access was denied, keeping the user on the prompt
    /// so they can retry, open Settings, or enter a ZIP code instead.
    func locationAccessDenied() {
        statusMessage = "Location access is off — try again or enter your ZIP code to find your representatives."
        loadState = .denied
    }

    // MARK: - Delegation

    /// Narrows a state's full membership down to the three representatives the
    /// app shows: both senators and the single House member for the user's
    /// district. When the district is unknown, falls back to the
    /// lowest-numbered district so there's still a House member to show.
    private static func delegation(from members: [Representative], district: Int?) -> [Representative] {
        let senators = members.filter { $0.office == .senator }
        let houseMembers = members.filter { $0.office == .representative }

        let houseMember: Representative?
        if let district,
           let match = houseMembers.first(where: { ($0.district ?? 0) == district }) {
            houseMember = match
        } else {
            // Unknown district (or no exact match): show the first by district.
            houseMember = houseMembers.min { ($0.district ?? 0) < ($1.district ?? 0) }
        }

        return (senators + (houseMember.map { [$0] } ?? [])).sorted(by: delegationOrder)
    }

    /// Fills in each member's profile: sponsored/cosponsored bills and office
    /// contact details from Congress.gov and top funders from OpenFEC (fetched
    /// per member, concurrently); committee assignments, social-media links, and
    /// the FEC candidate crosswalk from shared datasets (each fetched once for the
    /// whole delegation). Everything runs concurrently and member order is
    /// preserved. Funders are skipped entirely unless an OpenFEC key is set.
    private static func enrichedProfiles(
        for delegation: [Representative],
        using service: CongressService,
        committeeService: CommitteeService,
        contactService: MemberContactService,
        financeService: OpenFECService,
        disclosureService: FinancialDisclosureService,
        marketService: MarketPerformanceService
    ) async -> [Representative] {
        // Kick off the shared single-dataset fetches (committees, social media,
        // House trade disclosures, and — only when an FEC key is configured —
        // the campaign-finance crosswalk) alongside the per-member lookups so
        // they all overlap.
        async let assignments = committeeService.committeeAssignments()
        async let socialLinks = contactService.socialLinksByBioguide()
        async let houseReports = disclosureService.houseTransactionReports()
        async let senateReports = disclosureService.senateTransactionReports()
        async let fecCandidates = financeService.isConfigured
            ? financeService.candidateIDsByBioguide()
            : [:]

        let billEnriched = await withTaskGroup(of: (Int, Representative).self) { group in
            for (index, rep) in delegation.enumerated() {
                group.addTask {
                    let enriched = await service.enrichedProfile(for: rep)
                    let office = await contactService.officeInfo(forBioguideID: rep.bioguideID)
                    // Stash the office fields on `contact` for now; social links
                    // are folded in below once the shared dataset resolves.
                    var withOffice = office.map {
                        enriched.withContact(ContactInfo(
                            officeAddress: $0.officeAddress,
                            phone: $0.phone,
                            website: $0.website
                        ))
                    } ?? enriched
                    // Geocode the Washington office address for the map tab, so
                    // members show up on Capitol Hill instead of at (0, 0).
                    if let address = office?.officeAddress,
                       let coordinate = try? await CLGeocoder().geocodeAddressString(address).first?.location?.coordinate {
                        withOffice = withOffice.withCoordinate(
                            latitude: coordinate.latitude, longitude: coordinate.longitude
                        )
                    }
                    return (index, withOffice)
                }
            }
            var enriched = delegation
            for await (index, rep) in group {
                enriched[index] = rep
            }
            return enriched
        }

        let committeesByID = await assignments
        let socialByID = await socialLinks
        let candidatesByID = await fecCandidates
        let reports = await houseReports
        let senateFilings = await senateReports

        // Look up each member's top PAC and individual funders concurrently,
        // keyed off the FEC crosswalk. Skipped entirely (empty crosswalk) when no
        // key is set. Both pulls share a candidate → committee resolution, so
        // they overlap per member.
        let fundersByIndex = await withTaskGroup(
            of: (index: Int, pac: [Funder], individual: [Funder]).self
        ) { group in
            for (index, rep) in billEnriched.enumerated() {
                guard let id = rep.bioguideID,
                      let candidateIDs = candidatesByID[id], !candidateIDs.isEmpty else {
                    continue
                }
                group.addTask {
                    async let pac = financeService.topFunders(
                        candidateIDs: candidateIDs, office: rep.office
                    )
                    async let individual = financeService.topIndividualFunders(
                        candidateIDs: candidateIDs, office: rep.office
                    )
                    return (index, await pac, await individual)
                }
            }
            var collected: [Int: (pac: [Funder], individual: [Funder])] = [:]
            for await result in group {
                collected[result.index] = (result.pac, result.individual)
            }
            return collected
        }

        return billEnriched.enumerated().map { index, rep in
            let funders = fundersByIndex[index] ?? (pac: [], individual: [])
            var rep = funders.pac.isEmpty && funders.individual.isEmpty
                ? rep
                : rep.withFunders(pac: funders.pac, individual: funders.individual)
            rep = rep.withTradingActivity(
                disclosureService.tradingActivity(for: rep, houseReports: reports, senateReports: senateFilings)
            )
            if let performance = marketService.performance(for: rep) {
                rep = rep.withMarketPerformance(performance)
            }
            let withCommittees: Representative = {
                guard let id = rep.bioguideID,
                      let committees = committeesByID[id], !committees.isEmpty else {
                    return rep
                }
                return rep.withCommittees(committees)
            }()

            // Fold the per-member office details already loaded above together
            // with this member's social links into one ContactInfo.
            let social = rep.bioguideID.flatMap { socialByID[$0] } ?? []
            let office = withCommittees.contact
            let contact = ContactInfo(
                officeAddress: office?.officeAddress,
                phone: office?.phone,
                website: office?.website,
                socialLinks: social
            )
            return contact.hasContent ? withCommittees.withContact(contact) : withCommittees
        }
    }

    /// Reverse-geocodes a coordinate to its two-letter state postal code.
    private func stateCode(for coordinate: CLLocationCoordinate2D) async throws -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        guard let stateCode = placemarks.first?.administrativeArea, !stateCode.isEmpty else {
            throw CLError(.geocodeFoundNoResult)
        }
        return stateCode
    }

    /// Senators first, then House members ordered by district — matching the
    /// grid's "senators on top" layout.
    private static func delegationOrder(_ lhs: Representative, _ rhs: Representative) -> Bool {
        if lhs.office != rhs.office {
            return lhs.office == .senator
        }
        return (lhs.district ?? 0) < (rhs.district ?? 0)
    }

    // MARK: - Cache

    /// The on-disk snapshot of a resolved delegation: the coordinate it was
    /// resolved for plus the representatives themselves.
    private struct DelegationCache: Codable {
        let latitude: Double
        let longitude: Double
        let representatives: [Representative]
        /// The resolved state postal code, used to look up the governor from
        /// `GovernorDirectory` on load. Optional so caches saved before this
        /// field existed still decode.
        let stateCode: String?

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    private static let cacheKey = "cachedDelegation"

    /// Persists a freshly resolved delegation so the next launch can skip the
    /// location prompt.
    private static func saveCache(
        coordinate: CLLocationCoordinate2D, stateCode: String, representatives: [Representative]
    ) {
        let cache = DelegationCache(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            representatives: representatives,
            stateCode: stateCode
        )
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    /// Loads the delegation saved on a previous launch, if any.
    private static func loadCache() -> DelegationCache? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(DelegationCache.self, from: data)
    }
}
