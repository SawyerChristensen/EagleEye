# To Do
---
- [ ] Test all API keys
- [ ] AS listing via Photoshop

## Post Launch
- [ ] Modify ReadME
- [ ] Organize the project's functions and file structure for maximum maintainability and understanding
- [ ] Test if notifications works
- [ ] Re-add governor information
- [ ] Load "No representatives found" if there is some error retrieving the representatives and "Error collecting recent bill information" if there is an error loading bills. If there is an error finding representatives, offer the user to type in a zip code to load representatives with the text "On vacation? Type in your home zip code to find your representatives:"
- [ ] Organize the map code into different files with clear purposes and outline a feature for adding state flags after being zoomed out, but dont implement it. Just add filler files for that task and keep hte current approach while cleaning up the files/organizing them. Keeping the project organized, modular, and maintainable is a priority
- [ ] Refactor the loading district detail section to just check if the variables we are loading have information in them yet. while they are nil, we should show the progress bar. When they are loaded but empty, skip displaying the section (ie, no universities in the district) or populated, show the data. Be sure to test
- [ ] Dark mode onboarding animation
- [ ] Reuse the onboarding animation every app open to cover while the app loads new information?
- [ ] Re-add stock trades metric
  - [ ] OpenFEC API duplication? 
- [ ] Add accessibility labeling
- [ ] If a district is a U around a dot, the representative could be misplaced within the dot instead of actually in their district
- [ ] "Beats the market" quantitative metric — parse each PTR PDF into transactions (ticker, buy/sell, amount range, date) + pull historical prices to compute returns vs. a benchmark *(backend job: PDF parsing + a historical price data source; moved here from 0.3)*
- [ ] Add information about if a senator beats the market. Pre calculate this and add this as a hard value in an update if there is no online source readily available
- [ ] Add information on state legislatures somewhere behind a Poltica+ IAP
- [ ] Detect if an election is going on, default to the map view and report information about the election through the Poltica+ IAP
- [ ] Add information about other countries presidents & congresses behind a Poltica+ IAP
  - [ ] Update the map to have other countries outlines, do what google does when referencing disputed areas
  - [ ] Each country should have its flag as its outline, with the president/prime minister/king/leader of the country as the icon
  - [ ] Tapping on a country should give a country level description of its political process. This summary should roughly look the same across countries. IE similar paragraph topics
- [ ] Add timing curve to onboarding animation?

---

## ⚙️ Refactoring & Code Optimization
- [x] Maybe make enacted laws have a higher waiting in the algorithm
- [x] Apple's location is sometimes vague (for privacy) and returns the wrong representative — let the user type in a ZIP code manually as a fallback (or as an option before we even ask for location)

Include
"This product uses the Census Bureau Data API but is not endorsed or certified by the Census Bureau." somewhere in the app
