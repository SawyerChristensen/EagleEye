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
- [ ] Add another pill after the "passed house" pill that shows what the next step for the bill is or where the bill is now in the detail view. either in the senate, or if passed both, on the presidents desk, etc. show the future one in grey as it hasnt happened yet. also maybe show the past step behind it to the left, blur where the pills is exceeding bounds similar to how the topic pill blurs out in the home feed if that same approach is advisable.
- [ ] Some bills say "last action on" and then a date that is older than when the last vote was. 
- [ ] Make the sample topic list only have one topic to reflect real bills. also match it to the real 32 list the library of congress uses. also, append a best-matching SF symbol to what the topic is
- [ ] Something happened to the ranking algorithm. no "enacted laws" are displayed in the top 20
- [x] **QOL:** Skip the location loading screen when we already have the user's location
- [ ] **Bug:** Apple's location is sometimes vague (for privacy) and returns the wrong representative — let the user type in a ZIP code manually as a fallback (or as an option before we even ask for location)

---

## 0.3 — Richer Representative Data *(requires new external sources)*

- [ ] Voting History for Senators *(needs senate.gov API — Congress.gov roll calls are House-only)*
- [ ] Office contact information in the profile
  - [ ] Link to their social media
- [ ] Top Funders *(OpenFEC API)*
- [ ] "Beats the market" / insider-trading / corruption meter *(needs a trading-disclosure data source)*
- [ ] Evaluate ProPublica API for voting records and sponsored bills — is it needed on top of Congress.gov?

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
#### Release!



---

## ⚙️ Refactoring & Code Optimization
#### None
