# Project Roadmap
---

## ✅ 0.1 — Foundation (Done)

- [x] Initial UI mockups and project architecture
- [x] Implement representative lookup by user location
- [x] Home feed pulls real data via Congress API
  - [x] Summarize each bill
    - [x] Position "H.R. {number}" at end of title, one smaller font size
    - [x] Remove title and "This bill" from summaries
- [x] Populate representative profile: Committees
- [x] Populate representative profile: Bills (sponsored & cosponsored)
- [x] Voting History — House Representatives: summarize votes, discard in-committee ones

---

## 0.2 — Feed & Profile Polish *(no new data sources)*

- [x] Rank each bill by how far it got (introduced → committee → passed → president's desk → enacted); importance trait decays with time so the most important, active bills surface on top
- [x] Each profile bill has a right arrow that opens the expanded bill detail screen
- [x] Voting History uses the same collapsible/fade view that the bills sections use
- [x] Add the roll-call tally to each bill's detail screen — who voted and which way — with the user's representatives surfaced on top
- [x] Each bill should have the HR code next to the "Bill" title on top in the center of the screen, right of the arrow, and not in the main title in the feed
- [x] Center the heading/title abvo
- [x] passed house in home view is squased, also consider removing the pill look
- [x] Some bills say "passed house" but dont display a roll call vote
- [x] Some bills say "last action on" and then a date that is older than when the last vote was. also move this form below the summary to under a dividor under the voting history
- [x] Make the sample topic list only have one topic to reflect real bills. also match it to the real 32 list the library of congress uses. also, append a best-matching SF symbol to what the topic is
- [x] Add another pill after the "passed house" pill that shows what the next step for the bill is or where the bill is now in the detail view. either in the senate, or if passed both, on the presidents desk, etc. show the future one in grey as it hasnt happened yet. also maybe show the past step behind it to the left, blur where the pills is exceeding bounds similar to how the topic pill blurs out in the home feed if that same approach is advisable.
- [x] **QOL:** Skip the location loading screen when we already have the user's location

---

## 0.3 — Richer Representative Data *(requires new external sources)*

- [x] Voting History for Senators *(senate.gov roll-call XML — Congress.gov roll calls are House-only)*
  - [x] Add to profile
  - [x] Add their votes under bill details if something is voted on in the senate
- [x] Office contact information in the profile
  - [x] Link to their social media
  - [x] Add icons in the pill of each social media link
- [x] Top Funders *(OpenFEC API — needs a free api.data.gov key in Secrets.plist as `OpenFECAPIKey`)\*
- [x] change the initial location screen to ask if the user wants to share their location or enter a zipcode. if they tap find, then ask iOS for the system prompt
- [x] When finding initial location, it displays the sample data in the representatives view. it should be blank until the real representatives load in
- [x] Inlcude recent bills that failed in the feed, so you can see if your senator or representative voted against something you wouldve supported.
  - [x] Prioritize recent bills in this priority: 1) recently enacted, 2) recently failed but passed one chamber 3) passed one chamber 4) recently failed but passed committee 5) passed committe 6) introduced and update the progress pills accordingly
- [ ] "Beats the market" / insider-trading / corruption meter *(needs a trading-disclosure data source)*
  - [x] Trading-activity indicator — House Periodic Transaction Report (PTR) count for the past year, latest-filing date, and a link to the filing, from the free House Clerk disclosure index (on-device ZIP + TSV parsing, no key). Senators link out to the Senate eFD portal.
  - [ ] Senate coverage — parse efdsearch.senate.gov (agreement + CSRF + DataTables JSON) for senators' PTRs
  - [ ] "Beats the market" quantitative metric — parse each PTR PDF into transactions (ticker, buy/sell, amount range, date) + pull historical prices to compute returns vs. a benchmark *(realistically a backend job, not on-device)*
- [x] Add 3 tabs to the representative view. 1st tab is about (Committees, Bills, Contact info), 2nd tab is voting history (show the full title for each bill as it appears on the home feed, with an arrow to view the bills full details, should go to the same screen we end up on if tapped on from the home screen), 3rd tab should be the money tab the ("Beats the market"/ insider-trading / corruption meter), stock trades, top PAC funders,  top individual funders
  - [x] Add top individual funders, specify they are employees if the category is a company. if "Attorney" expand to plural form ie "Attornies"
  - [ ] About shoud have an "i" icon, Votes the voting history icon, and money a dollar bill sf symbol in the tab view next to the text
- [ ] Locating seems to take a LONG time. How about we progress to the home "recent bills" section while this is happening? Only kicking back to the loading screen if theres some sort of error?

---

## 0.4 — Interactive Map

- [ ] Build the interactive map view (evaluate performance and utility): fill districts with party color, representative icon in the middle
  - [ ] Zoom out to state level to see governor + senators

---

## 0.5 — Platform & Reach

- [ ] Implement local caching for offline viewing *(partially done: bills and delegation are cached on disk)*
  - [x] Representatives icons
  - [ ] Bills
  - [ ] Representative information
  - [ ] Voting histories
- [ ] Localization framework setup for multi-language support (Spanish, French, etc.)

---

## 0.6 — iOS integration
- [ ] Add home screen widgets
- [ ] Add system notifications for new bills being passed, maybe the ability to bookmark a bill to recieve all notifications about it. 

---

## Version 1.0
Modify ReadME
#### Release!



---

## ⚙️ Refactoring & Code Optimization
- [ ] Maybe make enacted laws have a higher waiting in the algorithm
- [x] Apple's location is sometimes vague (for privacy) and returns the wrong representative — let the user type in a ZIP code manually as a fallback (or as an option before we even ask for location)
