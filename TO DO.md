# To Do
---

- [x] ADD GOVERNORS TO THE REPRESENTATIVES LIST (if there is a central list of governors to pull from so that we can fill all 50 states) (check if already done) (no big deal if unfeasible, but try)
  - [x] Instead of a Committees and bills section, just have a "Pills passed into law" section above the contact information. Find a source to pull recently enacted laws per state
  - [x] Still have the money section for governors like we do representatives and fill it with top pac funders/top individual funders just like we do representatives
    - [x] Add the "Top PAC Funders" / "Top Individual Funders" sections to the governor profile (mirroring `RepresentativeDetailView`), backed by a new `GovernorFunderDirectory` keyed by state — seeded empty for now since, unlike representatives' live OpenFEC lookup, there's no free API for gubernatorial campaign finance across all 50 states
    - [x] Populate `GovernorFunderDirectory` with real, sourced top PAC/individual funder entries per state (hand-curated like `StateLawDirectory`, or wired to a verified state campaign-finance data source)
      - [x] Add sourced PAC/individual funder entries for IL, MI, and FL (OpenSecrets / Transparency USA, 2022 races)
      - [x] Add sourced PAC/individual funder entries for TX, GA, and CO
      - [x] Add sourced PAC/individual funder entries for CA, NY, and OH, etc
  - [x] Pull governors headshots from the national governors association

- [~] Build the interactive map view (evaluate performance and utility)
  - [~] Add more information per district. Each district should display some basic information about the district, like the population count, top sectors/industry, top cities by population, top universties, and anything else relevant to the district. it should still show the representative. Feel free to split this into smaller tasks and add to-do list items under it. Right now the district detail section just shows the representative, but it should show more information
    - [x] Show each district's total population (Census ACS estimate) in the district detail sheet
    - [x] Show each district's top sectors/industries in the district detail sheet
    - [x] Show each district's top cities by population in the district detail sheet
    - [x] Show each district's top universities in the district detail sheet
  - [~] Once a certain zoom level is reached, out to the state level, display the governors icons in the middle of the state. The state outline should be filled with the state flag instead of a single party color.
    - [x] Add a `StateFlagDirectory` (postal code -> Wikimedia Commons flag image URL, resolved via `Special:FilePath` so no per-state upload hash is needed) and a `StateFlagImage` view that loads/caches it, mirroring `GovernorPortrait`
    - [x] Detect the map's zoom level and, once zoomed out to state level, swap each state polygon's fill from its district party-color tint to its `StateFlagImage` and show the state's governor (via `GovernorPortrait`) annotated at the state's centroid instead of per-district representative pins
    - [x] The transition between the different color coded district outlines and the state flag/state level representatives should be smooth
    - [x] Like the district information view, the state should show an outline of the state with the flag inside of it. this should also not be squashed and be recreated similar to how the mini district previews are rendered.
    - [~] The state level information view should have information about the state, similar to what the districts have. total population, top sectors/industry, top cities by population, top universities, etc. this view should should show the governor on top, the two senators, and list of all house representatives in the state under the senators
      - [x] Show the state's governor at the top of the state-level detail sheet (mirroring `GovernorRow`/`GovernorDetailView`)
      - [x] Show the state's two senators in the state-level detail sheet, below the governor
      - [ ] Show a list of all House representatives for the state in the state-level detail sheet, below the senators
      - [ ] Add total population, top sectors/industries, top cities, and top universities sections to the state-level detail sheet (new state-keyed data directories, mirroring the district ones)

- [ ] In the voting history for an enacted law, I only see how my house of representatives representative voted. I want to see how my senators voted as well, but their votes dont show up (at least in the same section as my representatives vote shows up). I want to see my senators vote in the same spot
- [ ] Improve the general performance of the map. Improve the fps, and maybe fix artifacts like the black overlay on the rest of the world having to fill in when the user zooms out fast. currently it only seems to take up the part of the screen the user is looking at
- [ ] Some districts dont have representatives on file. theres one in california that I see, one in texas, one in florida. Do those districts truly not have a representative, or is that a glitch?

- [x] Add home screen widgets that show what would be shown as the top bill in the recent bills feed
  - [ ] This is broken ^ currently the text is larger than the actual widget. is it possible to detect the widget's bounds?
  - [ ] Center the progress text at the top of the widget
  - [x] When tapping on the widget, the user should automatically be sent to the bill that was displayed detail view, with a back button sending them to recent bills.
- [x] Add system notifications for new bills being passed
  - [x] Recently enacted laws should be a push notification
  - [x] Add the ability to bookmark a bill to recieve all notifications about it

---

## Version 1.0
ONLY DO THIS WHEN EVERYTHING ABOVE IS IMPLEMENTED
- [ ] Organize the project's functions and file structure for maximum maintainability and understanding
- [ ] Modify ReadME
#### Release!


---

## Version 1.1 DO 
DO NOT DO UNLESS EVERYTHING BEFORE 1.0 IS DONE

- [ ] "Beats the market" quantitative metric — parse each PTR PDF into transactions (ticker, buy/sell, amount range, date) + pull historical prices to compute returns vs. a benchmark *(backend job: PDF parsing + a historical price data source; moved here from 0.3)*
- [ ] Add information about if a senator beats the market. Pre calculate this and add this as a hard value in an update if there is no online source readily available
- [ ] Add information on state legislatures somewhere behind a Poltica+ IAP
- [ ] Detect if an election is going on, default to the map view and report information about the election through the Poltica+ IAP
- [ ] Add information about other countries presidents & congresses behind a Poltica+ IAP
  - [ ] Update the map to have other countries outlines, do what google does when referencing disputed areas
  - [ ] Each country should have its flag as its outline, with the president/prime minister/king/leader of the country as the icon
  - [ ] Tapping on a country should give a country level description of its political process. This summary should roughly look the same across countries. IE similar paragraph topics

---

## ⚙️ Refactoring & Code Optimization
- [x] Maybe make enacted laws have a higher waiting in the algorithm
- [x] Apple's location is sometimes vague (for privacy) and returns the wrong representative — let the user type in a ZIP code manually as a fallback (or as an option before we even ask for location)
