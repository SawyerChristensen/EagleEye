<img align="right" width="128" height="128" alt="PoliticaAppIcon" src="https://github.com/user-attachments/assets/da45cd10-56a1-4a65-b4f6-281acd619029" style="background-color: transparent;" />

**Politica** is an iOS app that brings transparency and accessibility to US politics. It helps users track Congress, monitor their local representatives, follow the money behind political campaigns, and explore an interactive map of every congressional district.

## Features

* **Local Representative Tracking:** See who represents you — your House member and both senators — based on your location (precise location, approximate location, or a manually entered ZIP code).
* **Legislative Activity Feed:** A ranked feed of recent bills, weighted by how far each got (introduced → committee → passed a chamber → president's desk → enacted) and by recency, including notable bills that failed.
* **Bill Detail & Roll Calls:** Full bill summaries with House and Senate roll-call tallies, your representatives' votes surfaced first, and bill bookmarking with local notifications when a bookmarked bill's status changes.
* **Representative Profiles:** Three tabs per representative — About (committees, sponsored/cosponsored bills, office contact info, social media), Votes (full voting history), and Money (supporting PACs).
* **Campaign Finance & Trading Transparency:** Top PAC and individual funders (via OpenFEC), plus a trading-activity indicator built from House Periodic Transaction Reports and the Senate eFD portal.
* **Interactive Congressional Map:** Explore every U.S. congressional district as colored outlines across the country. The map opens centered on your district, and tapping any district reveals who represents it alongside demographic data — population, primary industries, average income, and local universities. Zooming out fades district outlines into a state-level view.
* **Home Screen Widget:** A widget that surfaces the top bill in Congress and deep-links straight into its detail screen when tapped.
* **Offline Support:** Bills, bill details/roll-calls, the full representative delegation (committees, contact info, funders, trading activity, voting history), and map boundaries/demographics are cached on-device for offline viewing once loaded.
* **Privacy First:** Location is resolved entirely on-device and never collected or transmitted — ZIP-code entry works without granting location access at all.
* **Localization:** English and Spanish.

## Tech Stack

* **Platform:** iOS 17+
* **Language:** Swift
* **Frameworks:** SwiftUI, MapKit, WidgetKit
* **Data Sources:**
  * [Congress.gov API](https://api.congress.gov/sign-up/) — bills, member data, House roll calls
  * senate.gov roll-call XML — Senate roll calls (Congress.gov roll calls are House-only)
  * [OpenFEC API](https://api.open.fec.gov/developers/) — campaign finance / top funders
  * House Clerk financial disclosure index (on-device ZIP/TSV parsing) and efdsearch.senate.gov — trading-activity disclosures
  * Apple's `CLGeocoder`/Census geocoding — representative lookup by location
  * [U.S. Census Bureau Data API](https://www.census.gov/data/developers/data-sets.html) — congressional-district demographics powering the interactive map (population, primary industries, and average income from the ACS 5-year estimates; requires a free API key), plus the keyless [Census geocoder](https://geocoding.geo.census.gov/), [TIGERweb](https://tigerweb.geo.census.gov/) place geometry, and Population Estimates Program city populations
  * Bundled Census Bureau cartographic boundary files (`cb_2022_us_cd118_5m`) — the congressional-district outlines drawn on the map

## Getting Started

### Prerequisites
* macOS running Xcode 16+
* iOS 17.0+ deployment target
* A free [Congress.gov API key](https://api.congress.gov/sign-up/); optionally a free [OpenFEC API key](https://api.data.gov/signup/) for the Top Funders section and a free [Census Bureau API key](https://api.census.gov/data/key_signup.html) for the map's district demographics

### Installation
1.  Clone the repository.
2.  Open `EagleEye.xcodeproj` in Xcode.
3.  Duplicate `EagleEye/Secrets.example.plist`, rename the copy to `Secrets.plist`, and add your Congress.gov API key (and OpenFEC and Census Bureau keys, if you have them).
4.  Select your target simulator or device and hit **Build and Run** (`Cmd + R`).

Without a `Secrets.plist` key, the app falls back to bundled sample data.

### (See included `TO DO.md` for the project roadmap)
