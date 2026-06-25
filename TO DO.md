# Project Roadmap
---

- [x] Initial UI mockups and project architecture
- [x] Implement representative lookup by user location
- [x] Make the home feed pull real data via Congress API
  - [x] Summarize each bill 
    - [x] Position "H.R. {number}" at end of title, one smaller font size
    - [x] Remove title and "This bill" from sumarries
  - [ ] Rank each bill based on how far it got (introduced)/(committee)/(congress)/(presidents desk)/(signed into law) most important information should be on top. there should be an importance trait that decays with time
- [ ] Populate the representatives profile with data in the defined sections
  - [ ] Committees
  - [x] Bills
  - [ ] Voting History
  - [ ] Top Funders
  - [ ] Add office contact information in representatives profile
    - [ ] Link to their social media?
  - [ ] Add statistic on how good they are at beating the market/"insider trading/corruption" meter?
- [ ] Integrate ProPublica API for voting records and sponsored bills? Is this needed?
- [ ] Integrate OpenFEC API for campaign finance data visualizations
- [ ] Build the interactive map view (evaluate performance and utility) (fill with party color, representative icon in the middle)
  - [ ] Zoom out to state level to see governor + senator
- [ ] Implement local caching for offline viewing
- [ ] Localization framework setup for multi-language support (Spanish, French, etc.)


## Version 1.0
#### Release!

---

## 🛑 Known Issues & Critical Bugs

- [ ] Sometimes Apple's location is vague (for user privacy) and gives the wrong representative (type in zip code manually?)
---

## 🧠 Quality of Life (QOL) & UX Polish

- [ ] Skip the location loading screen if we already have the users location
---

## ⚙️ Refactoring & Code Optimization
#### None
