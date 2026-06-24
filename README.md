**Polity** is a mobile application under development designed to bring transparency and accessibility to US politics. It empowers users to track Congress, monitor their local representatives, and follow the money behind political campaigns. 

## Features

* **Local Representative Tracking:** Instantly see who represents you at the federal level based on your location.
* **Legislative Activity:** Track the bills your representatives are sponsoring, co-sponsoring, and how they are voting on the floor.
* **Campaign Finance Transparency:** Follow the money. View funding sources, top contributors, and PAC money for individual politicians to understand who is backing them.
* **Interactive Congressional Map (Beta):** An interactive map to visualize districts, explore nationwide congressional makeup, and see geographic political shifts.

## Tech Stack
<img align="right" height="256" alt="PolityLGAppIcon" src="https://github.com/user-attachments/assets/da45cd10-56a1-4a65-b4f6-281acd619029" style="background-color: transparent;" />


* **Platform:** iOS
* **Framework:** SwiftUI
* **Language:** Swift
* **Data Sources:** 
  * **Currently Used:**
    * [Congress.gov API](https://api.congress.gov/sign-up/) (for official legislative activity and member data)
  * **Proposed:**
    * [OpenFEC API](https://api.open.fec.gov/developers/) (for campaign finance data)
    * [Google Civic Information API](https://developers.google.com/civic-information) (for representative lookup by address)

## Getting Started

### Prerequisites
* macOS running Xcode 16+
* iOS 17.0+ deployment target
* API Keys for chosen civic data providers (ProPublica, OpenFEC)

### Installation
1.  Clone the repository:
    ```bash
    git clone [https://github.com/your-username/polity.git](https://github.com/your-username/polity.git)
    ```
2.  Open `Polity.xcodeproj` in Xcode.
3.  Duplicate the `Secrests.example.plist` file and rename it to `Secrets.plist`.
4.  Add your Congress API key to the `Secrets.plist` file.
5.  Select your target simulator or device and hit **Build and Run** (`Cmd + R`).

### (See included TO DO markdown file)
