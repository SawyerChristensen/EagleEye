**Politica** is an iOS app that brings transparency and accessibility to US politics. It helps users track Congress, monitor their local representatives, and follow the money behind political campaigns.

## Features

* **Local Representative Tracking:** See who represents you — your House member and both senators — based on your location (precise location, approximate location, or a manually entered ZIP code).
* **Legislative Activity Feed:** A ranked feed of recent bills, weighted by how far each got (introduced → committee → passed a chamber → president's desk → enacted) and by recency, including notable bills that failed.
* **Bill Detail & Roll Calls:** Full bill summaries with House and Senate roll-call tallies, your representatives' votes surfaced first, and bill bookmarking with local notifications when a bookmarked bill's status changes.
* **New Law Notifications:** Local push notifications when a bill you're tracking (or any bill in the feed) is signed into law.
* **Representative Profiles:** Three tabs per representative — About (committees, sponsored/cosponsored bills, office contact info, social media), Votes (full voting history), and Money.
* **Campaign Finance & Trading Transparency:** Top PAC and individual funders (via OpenFEC), plus a trading-activity indicator built from House Periodic Transaction Reports and the Senate eFD portal.
* **Offline Support:** Bills, bill details/roll-calls, and the full representative delegation (committees, contact info, funders, trading activity, voting history) are cached on-device for offline viewing.
* **Localization:** English and Spanish, including a localized app name.
* **Interactive Congressional Map:** Planned — not yet implemented (see `TO DO.md`).

## Tech Stack

* **Platform:** iOS 17+
* **Framework:** SwiftUI
* **Language:** Swift
* **Data Sources:**
  * [Congress.gov API](https://api.congress.gov/sign-up/) — bills, member data, House roll calls
  * senate.gov roll-call XML — Senate roll calls (Congress.gov roll calls are House-only)
  * [OpenFEC API](https://api.open.fec.gov/developers/) — campaign finance / top funders
  * House Clerk financial disclosure index (on-device ZIP/TSV parsing) and efdsearch.senate.gov — trading-activity disclosures
  * Apple's `CLGeocoder`/Census geocoding — representative lookup by location

## Getting Started

### Prerequisites
* macOS running Xcode 16+
* iOS 17.0+ deployment target
* A free [Congress.gov API key](https://api.congress.gov/sign-up/); optionally a free [OpenFEC API key](https://api.data.gov/signup/) for the Top Funders section

### Installation
1.  Clone the repository.
2.  Open `EagleEye.xcodeproj` in Xcode.
3.  Duplicate `EagleEye/Secrets.example.plist`, rename the copy to `Secrets.plist`, and add your Congress.gov API key (and OpenFEC key, if you have one).
4.  Select your target simulator or device and hit **Build and Run** (`Cmd + R`).

Without a `Secrets.plist` key, the app falls back to bundled sample data.

### (See included `TO DO.md` for the project roadmap)
