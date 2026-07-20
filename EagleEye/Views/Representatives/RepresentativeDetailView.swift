//
//  RepresentativeDetailView.swift
//  EagleEye
//
//  Profile screen shown when a representative is tapped in the grid. The profile
//  is split into three tabs — About, Votes, and Money — selected with a
//  segmented control below the header. Several sections use placeholder data
//  until the relevant APIs (e.g. a trading-performance source) are wired up.
//

import SwiftUI

struct RepresentativeDetailView: View {
    let representative: Representative

    /// A more complete copy of `representative`, fetched on demand when the
    /// value we were handed is sparse — see `enrichIfNeeded()`. The district
    /// map opens profiles from the nationwide roster, which carries only the
    /// basics (name, party, district) and none of the committee or bill data,
    /// so those are filled in here rather than up front. Nil until (and
    /// unless) that fetch runs.
    @State private var enriched: Representative?

    /// True while the on-demand enrichment fetch is in flight, so the About and
    /// Votes sections can show a spinner instead of an empty note before the
    /// committee, bill, and vote data has arrived.
    @State private var isEnriching = false

    /// The profile actually displayed: the enriched copy once it has loaded,
    /// otherwise the value passed in.
    private var member: Representative { enriched ?? representative }

    private let congressService = CongressService()
    private let committeeService = CommitteeService()
    private let financeService = OpenFECService()

    /// The three top-level sections of a member's profile.
    private enum ProfileTab: String, CaseIterable, Identifiable {
        case about = "About"
        case votes = "Votes"
        case money = "Money"

        var id: Self { self }

        /// The SF Symbol shown beside the tab's title in the segmented control.
        var systemImage: String {
            switch self {
            case .about: "info.circle"
            case .votes: "checklist"
            case .money: "banknote"
            }
        }
    }

    @State private var selectedTab: ProfileTab = .about

    private var partyColor: Color {
        switch member.party {
        case .democrat: .blue
        case .republican: .red
        case .independent: .purple
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                Picker("Section", selection: $selectedTab) {
                    ForEach(ProfileTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.systemImage).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedTab {
                case .about:
                    committeesSection
                    sponsorshipSection
                    contactSection
                case .votes:
                    votingHistorySection
                case .money:
                    // "Beats the Market" is temporarily hidden — to be
                    // re-enabled in a later update. Its declaration and
                    // supporting types are kept below.
                    
                    // marketMeterSection
                    pacFundersSection
                    individualFundersSection
                    tradingSection //this previously under market meter section
                }
            }
            .padding()
        }
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await enrichIfNeeded() }
    }

    /// Fills in committee assignments, sponsored/cosponsored bills (and recent
    /// votes), and top PAC/individual funders when the profile was opened with
    /// a sparse member — as it is from the district map, which lists the
    /// nationwide roster. When the profile already carries this data (e.g.
    /// opened from the Representatives tab, where the store pre-enriches the
    /// delegation) or the member has no Bioguide ID to look up (sample data),
    /// this is a no-op. Funders are skipped unless an OpenFEC key is configured.
    private func enrichIfNeeded() async {
        guard enriched == nil,
              let bioguideID = representative.bioguideID,
              representative.committees.isEmpty,
              representative.sponsoredBills.isEmpty,
              representative.cosponsoredBills.isEmpty
        else { return }

        // Reuse a profile enriched earlier this session (e.g. reopening the
        // same member from the map) instead of fetching it all over again.
        if let cached = RepresentativeProfileCache.profile(forBioguideID: bioguideID) {
            enriched = cached
            return
        }

        isEnriching = true
        defer { isEnriching = false }

        // Kick off the profile, committee, and FEC-crosswalk fetches together
        // so they overlap; the per-member funder lookups depend on the
        // crosswalk and run once it resolves.
        async let profile = congressService.enrichedProfile(for: representative)
        async let assignments = committeeService.committeeAssignments()
        async let candidates = financeService.isConfigured
            ? financeService.candidateIDsByBioguide()
            : [:]

        var result = await profile
        if let id = result.bioguideID {
            if let committees = await assignments[id], !committees.isEmpty {
                result = result.withCommittees(committees)
            }
            if let candidateIDs = await candidates[id], !candidateIDs.isEmpty {
                async let pac = financeService.topFunders(candidateIDs: candidateIDs, office: result.office)
                async let individual = financeService.topIndividualFunders(candidateIDs: candidateIDs, office: result.office)
                let pacFunders = await pac
                let individualFunders = await individual
                if !pacFunders.isEmpty || !individualFunders.isEmpty {
                    result = result.withFunders(pac: pacFunders, individual: individualFunders)
                }
            }
        }
        RepresentativeProfileCache.store(result)
        enriched = result
    }

    /// A small inline spinner shown in a section whose data is still being
    /// fetched on demand, standing in for the "nothing on record" note until
    /// the enrichment fetch finishes.
    private var loadingNote: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            RepresentativePortrait(representative: member, size: 140)

            VStack(spacing: 4) {
                Text(member.name)
                    .font(.title2.bold())
                Text(member.roleDescription)
                    .font(.headline)
                    .foregroundStyle(partyColor)
                Label(member.tenureDescription, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - About tab

    private var committeesSection: some View {
        ProfileSection(title: "Committees", systemImage: "person.3") {
            if member.committees.isEmpty {
                if isEnriching {
                    loadingNote
                } else {
                    EmptyNote("No committee assignments on record.")
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(member.committees, id: \.self) { committee in
                        Text("• \(committee)")
                            .font(.body)
                    }
                }
            }
        }
    }

    private var sponsorshipSection: some View {
        ProfileSection(title: "Bills", systemImage: "doc.text") {
            if isEnriching && member.sponsoredBills.isEmpty && member.cosponsoredBills.isEmpty {
                loadingNote
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    BillGroup(title: "Sponsored", bills: member.sponsoredBills)
                    BillGroup(title: "Cosponsored", bills: member.cosponsoredBills)
                }
            }
        }
    }

    /// Office address, phone, website, and social links. Hidden entirely until
    /// contact details have loaded so the profile doesn't show an empty card.
    @ViewBuilder
    private var contactSection: some View {
        if let contact = member.contact, contact.hasContent {
            ProfileSection(title: "Contact", systemImage: "envelope") {
                VStack(alignment: .leading, spacing: 12) {
                    if let website = contact.website {
                        ContactRow(
                            systemImage: "globe",
                            text: website.host ?? website.absoluteString,
                            url: website
                        )
                    }
                    if let phone = contact.phone {
                        ContactRow(
                            systemImage: "phone",
                            text: phone,
                            url: Self.telURL(for: phone)
                        )
                    }
                    if let address = contact.officeAddress {
                        ContactRow(systemImage: "building.columns", text: address, url: nil)
                    }
                    if !contact.socialLinks.isEmpty {
                        SocialLinksRow(links: contact.socialLinks)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    /// Builds a dialable `tel:` URL from a displayed phone number, keeping only
    /// its digits.
    private static func telURL(for phone: String) -> URL? {
        let digits = phone.filter(\.isNumber)
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    // MARK: - Votes tab

    /// The member's recent floor votes. Each row shows the measure's full title
    /// (as it appears in the home feed) and, when the bill can be resolved, links
    /// to the same detail screen the feed opens.
    private var votingHistorySection: some View {
        ProfileSection(title: "Voting History", systemImage: "checklist") {
            if member.keyVotes.isEmpty {
                if isEnriching {
                    loadingNote
                } else {
                    EmptyNote("No recent votes on record.")
                }
            } else {
                VStack(spacing: 14) {
                    ForEach(member.keyVotes, id: \.self) { vote in
                        VoteRow(vote: vote)
                    }
                }
            }
        }
    }

    // MARK: - Money tab

    /// The published year-end report the "Beats the Market" figures come from,
    /// linked from the states where the member isn't ranked.
    private let tradingReportURL = URL(string: "https://unusualwhales.com/congress-trading-report-2025")

    /// The distinct things the "Beats the Market" section can show, in priority
    /// order: a ranked return, a "doesn't trade" note, or one of the not-ranked
    /// explanations.
    private enum MarketState {
        /// Listed in the year-end snapshot — show the return card.
        case ranked(MarketPerformance)
        /// Publicly known not to trade individual stocks (blind trust / funds).
        case abstains(note: String)
        /// Trades, but disclosed nothing in the past year (House members only).
        case noRecentTrades
        /// Has recent disclosed trades but isn't in the year-end snapshot.
        case tradesUnranked
        /// Trading can't be classified here (e.g. senators) — point at the report.
        case unranked
    }

    /// Resolves which state to show from the snapshot, the curated abstainer
    /// list, and the member's disclosed-trade count.
    private var marketState: MarketState {
        if let performance = member.marketPerformance {
            return .ranked(performance)
        }
        if let note = MarketPerformanceService().abstention(for: member) {
            return .abstains(note: note)
        }
        // Both chambers' disclosure sources give a real recent-trade count; if
        // that source couldn't be reached, fall through to the generic link.
        if let activity = member.tradingActivity, activity.isCovered {
            return activity.recentReportCount > 0 ? .tradesUnranked : .noRecentTrades
        }
        return .unranked
    }

    /// The "Beats the Market" indicator. Shows the member's estimated annual
    /// return vs. the S&P 500 when the year-end report lists them; otherwise a
    /// state that reflects what we do know about their trading.
    @ViewBuilder
    private var marketMeterSection: some View {
        ProfileSection(title: "Beats the Market", systemImage: "gauge.medium") {
            switch marketState {
            case .ranked(let performance):
                MarketMeter(performance: performance)

            case .abstains(let note):
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text("Doesn't trade individual stocks")
                            .font(.subheadline.weight(.semibold))
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .noRecentTrades:
                EmptyNote("No individual stock trades disclosed in the past year.")

            case .tradesUnranked:
                VStack(alignment: .leading, spacing: 10) {
                    EmptyNote("Has disclosed stock trades, but isn't among the top performers named in the latest year-end report.")
                    ContactRow(systemImage: "arrow.up.right.square", text: "View the trading report", url: tradingReportURL)
                }

            case .unranked:
                VStack(alignment: .leading, spacing: 10) {
                    EmptyNote("Isn't among the members named in the latest year-end trading report, which highlights the most notable market-beating traders.")
                    ContactRow(systemImage: "arrow.up.right.square", text: "View the trading report", url: tradingReportURL)
                }
            }
        }
    }

    /// STOCK Act stock-trade disclosures — a real count of Periodic Transaction
    /// Reports from the House Clerk's index or the Senate eFD search, whichever
    /// covers the member's chamber.
    @ViewBuilder
    private var tradingSection: some View {
        if let activity = member.tradingActivity {
            ProfileSection(title: "Stock Trades", systemImage: "chart.line.uptrend.xyaxis") {
                VStack(alignment: .leading, spacing: 10) {
                    if !activity.isCovered {
                        EmptyNote("Stock-trade filings aren't available right now — view them on the disclosure portal.")
                    } else if activity.recentReportCount > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(activity.recentReportCount)")
                                .font(.title.bold())
                                .contentTransition(.numericText())
                            Text(activity.recentReportCount == 1
                                ? String(localized: "stock-trade disclosure in the past year", comment: "Label next to a count of 1, describing a stock-trade disclosure filed in the past year.")
                                : String(localized: "stock-trade disclosures in the past year", comment: "Label next to a count greater than 1, describing stock-trade disclosures filed in the past year."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let date = activity.latestReportDate {
                            Text("Most recent: \(date.formatted(.dateTime.month().day().year()))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } /*else {
                        EmptyNote("No stock-trade disclosures filed in the past year.")
                    }*/

                    if let url = activity.disclosureURL {
                        ContactRow(
                            systemImage: "arrow.up.right.square",
                            text: activity.isCovered ? "View latest filing" : "View disclosure portal",
                            url: url
                        )
                    }

                    Text("Periodic Transaction Reports disclosed under the STOCK Act.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var pacFundersSection: some View {
        ProfileSection(title: "Top PAC Funders", systemImage: "dollarsign.circle") {
            if member.funders.isEmpty {
                if isEnriching {
                    loadingNote
                } else {
                    EmptyNote("Funding data unavailable.")
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(member.funders, id: \.self) { funder in
                        FunderRow(funder: funder)
                    }
                    Text("Direct contributions from each organization's political action committee (PAC). Federal law bars companies and unions from donating to candidates directly.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// Top individual contributors, grouped by employer or occupation.
    private var individualFundersSection: some View {
        ProfileSection(title: "Top Individual Funders", systemImage: "person.2") {
            if member.individualFunders.isEmpty {
                if isEnriching {
                    loadingNote
                } else {
                    EmptyNote("Individual contributor data unavailable.")
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(member.individualFunders, id: \.self) { funder in
                        FunderRow(funder: funder)
                    }
                    Text("Individual donations totaled by the employer or occupation each contributor reported. \"Employees\" means staff of that organization gave personally — the organization itself cannot.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
        }
    }
}

// MARK: - Reusable pieces

/// A titled card-style block used for each profile section.
private struct ProfileSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 14))
    }
}

private struct EmptyNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

/// A titled list of bills that collapses to a few rows when long, fading the
/// overflow under a gradient with a chevron to expand or collapse it.
private struct BillGroup: View {
    let title: String
    let bills: [LegislationRef]

    /// Height of the collapsed list — enough to show a few bills before fading.
    private let collapsedHeight: CGFloat = 132
    /// Only worth collapsing once there are more bills than fit comfortably.
    private var isCollapsible: Bool { bills.count > 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) (\(bills.count))")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            if bills.isEmpty {
                EmptyNote("None.")
            } else if isCollapsible {
                Collapsible(collapsedHeight: collapsedHeight, accessibilityNoun: "\(title.lowercased()) bills") {
                    billRows
                }
            } else {
                billRows
            }
        }
    }

    private var billRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(bills) { bill in
                billRow(bill)
            }
        }
    }

    /// A single bill. When the reference carries identifiers, the whole row is a
    /// link to the bill's detail screen with a trailing chevron; otherwise (e.g.
    /// sample data) it's a plain label.
    @ViewBuilder
    private func billRow(_ bill: LegislationRef) -> some View {
        if bill.isNavigable {
            NavigationLink(value: bill) {
                HStack(spacing: 8) {
                    label(for: bill)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } else {
            label(for: bill)
        }
    }

    private func label(for bill: LegislationRef) -> some View {
        Label(bill.displayTitle, systemImage: "checkmark.seal")
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Wraps a tall list so it collapses to a few rows behind a fading edge, with a
/// chevron to expand or collapse. Shared by the bills and voting-history
/// sections so they animate and look identical.
private struct Collapsible<Content: View>: View {
    let collapsedHeight: CGFloat
    /// Plural noun used in the expand/collapse accessibility label, e.g. "votes".
    let accessibilityNoun: String
    @ViewBuilder let content: () -> Content

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                content()
                expandButton
                    .padding(.top, 10)
            } else {
                ZStack(alignment: .bottom) {
                    content()
                        .frame(maxHeight: collapsedHeight, alignment: .top)
                        .clipped()
                        .mask(fadeMask)

                    expandButton
                }
            }
        }
    }

    /// Fades the bottom of the collapsed content out so the cut-off row trails
    /// off rather than ending abruptly.
    private var fadeMask: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.6),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var expandButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() }
        } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(8)
                .background(.thinMaterial, in: .circle)
                .overlay(Circle().strokeBorder(.quaternary, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Show fewer \(accessibilityNoun)" : "Show all \(accessibilityNoun)")
    }
}

/// A single vote in the voting-history tab. Shows the measure's full title, the
/// date, and how the member voted. When the bill can be resolved the whole row
/// links to its detail screen — the same one the home feed opens.
private struct VoteRow: View {
    let vote: VoteRecord

    private var color: Color {
        switch vote.position {
        case .yea: .green
        case .nay: .red
        case .present: .orange
        case .notVoting: .secondary
        }
    }

    var body: some View {
        if let ref = vote.legislationRef {
            NavigationLink(value: ref) {
                content(showChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            content(showChevron: false)
        }
    }

    private func content(showChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vote.billTitle)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(vote.date, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(vote.position.rawValue)
                .font(.caption.bold())
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color.opacity(0.15), in: .capsule)

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }
}

/// A single contact detail: an icon, a value, and — when the value is
/// actionable (a website, a phone number) — a tap target that opens it.
/// The "Beats the Market" readout: the member's estimated annual portfolio
/// return, colored and badged by whether it cleared the S&P 500, with the
/// benchmark spelled out and a link to the source report.
private struct MarketMeter: View {
    let performance: MarketPerformance

    private var tint: Color { performance.beatsMarket ? .green : .red }

    /// e.g. "78.8%".
    private var returnText: String {
        String(format: "%.1f%%", performance.returnPercent)
    }

    /// e.g. "16.6%".
    private var benchmarkText: String {
        String(format: "%.1f%%", performance.benchmarkPercent)
    }

    /// Signed points above or below the benchmark, e.g. "+62.2".
    private var marginText: String {
        String(format: "%+.1f", performance.marginPercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(returnText)
                    .font(.title.bold())
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())

                Label(
                    performance.beatsMarket ? "Beat the market" : "Trailed the market",
                    systemImage: performance.beatsMarket ? "arrow.up.right" : "arrow.down.right"
                )
                .font(.caption.bold())
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.15), in: .capsule)
            }

            Text("\(marginText) pts vs. the S&P 500, which returned \(benchmarkText) in \(String(performance.year)).")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let url = performance.sourceURL {
                ContactRow(systemImage: "arrow.up.right.square", text: "Read the trading report", url: url)
            }

            Text("Estimated from the member's disclosed stock trades, whose amounts are reported as ranges — so this figure is approximate.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct ContactRow: View {
    let systemImage: String
    let text: String
    /// When non-nil, the whole row becomes a link that opens this URL.
    let url: URL?

    var body: some View {
        if let url {
            Link(destination: url) {
                content(highlighted: true)
            }
            .buttonStyle(.plain)
        } else {
            content(highlighted: false)
        }
    }

    private func content(highlighted: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(highlighted ? Color.accentColor : .secondary)
                .frame(width: 20, alignment: .center)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(highlighted ? Color.accentColor : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A wrapping row of tappable capsules linking out to the member's social
/// accounts.
private struct SocialLinksRow: View {
    let links: [SocialLink]

    var body: some View {
        WrappingHStack(spacing: 8, lineSpacing: 8) {
            ForEach(links) { link in
                if let url = link.url {
                    Link(destination: url) {
                        Label {
                            Text(link.platform.displayName)
                        } icon: {
                            Image(link.platform.iconName)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 11, height: 11)
                        }
                        .font(.caption.bold())
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.quaternary.opacity(0.6), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Lays child views out left-to-right, wrapping onto a new line when the next
/// child would overflow the available width — used for the social-link capsules.
private struct WrappingHStack: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, maxWidth: maxWidth)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = layout(subviews: subviews, maxWidth: bounds.width)
        for placement in rows.placements {
            let position = CGPoint(x: bounds.minX + placement.x, y: bounds.minY + placement.y)
            subviews[placement.index].place(
                at: position,
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    /// Computes each subview's offset within a wrapping layout of the given
    /// width, along with the total size consumed.
    private func layout(
        subviews: Subviews,
        maxWidth: CGFloat
    ) -> (placements: [(index: Int, x: CGFloat, y: CGFloat, size: CGSize)], width: CGFloat, height: CGFloat) {
        var placements: [(index: Int, x: CGFloat, y: CGFloat, size: CGSize)] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            placements.append((index, x, y, size))
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }

        return (placements, usedWidth, y + rowHeight)
    }
}

private struct FunderRow: View {
    let funder: Funder

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(funder.name)
                    .font(.subheadline)
                if !funder.category.isEmpty {
                    Text(funder.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(funder.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        RepresentativeDetailView(representative: SampleData.representatives[0])
    }
}
