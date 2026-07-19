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

- [ ] Build the interactive map view (evaluate performance and utility)
  - [x] Disable the border smoothing technique in the map for now. just comment it out so that we can maybe use it later, but the 0.005 smoothing is making some smaller districts look weird when next to other districts
  - [x] Photos no longer seem to be loading for the representatives. Is this just because we are attempting to load 435 representatives in the map? How can we prioritize loading our representatives first, and then our fellow state representatives on the map, then neighboring states, and then all of them? Instead of 435 in one go
  - [ ] Add more information per district. Each district should display some basic information about the district, like the population count, top sectors/industry, top cities by population, top universties, and anything else relevant to the district. it should still show the representative. Feel free to split this into smaller tasks and add to-do list items under it. Right now the district detail section just shows the representative, but it should show more information. Is the informaiton below loaded in the backend? Wire it to the district detail sheet and display it if we have it in the backend.
    - [ ] In the district sheet, text should extend to the bottom of the district outline. the district outline should occupy a corner of the text instead of an column. this prevents text from extending into the area beneath it. the text should start where it does exactly, the the title and text start shouldnt move, but it should just take advantage of the space being claimed under the district outline
    - [ ] Show each district's total population (Census ACS estimate) in the district detail sheet
    - [ ] Show each district's top sectors/industries in the district detail sheet
    - [ ] Show each district's top cities by population in the district detail sheet
    - [x] Show each district's top universities in the district detail sheet
      - [ ] Starting from the top university, discard the next university if it is less than 2/5 of the last universities size by pop
  - [x] Once a certain zoom level is reached, out to the state level, display the governors icons in the middle of the state. The state outline should be filled with the state flag instead of a single party color.
    - [x] Add a `StateFlagDirectory` (postal code -> Wikimedia Commons flag image URL, resolved via `Special:FilePath` so no per-state upload hash is needed) and a `StateFlagImage` view that loads/caches it, mirroring `GovernorPortrait`
    - [x] Detect the map's zoom level and, once zoomed out to state level, swap each state polygon's fill from its district party-color tint to its `StateFlagImage` and show the state's governor (via `GovernorPortrait`) annotated at the state's centroid instead of per-district representative pins
    - [x] The transition between the different color coded district outlines and the state flag/state level representatives should be smooth
    - [x] Like the district information view, the state should show an outline of the state with the flag inside of it. this should also not be squashed and be recreated similar to how the mini district previews are rendered.
    - [x] The state level information view should have information about the state, similar to what the districts have. total population, top sectors/industry, top cities by population, top universities, etc. this view should should show the governor on top, the two senators, and list of all house representatives in the state under the senators
      - [x] Show the state's governor at the top of the state-level detail sheet (mirroring `GovernorRow`/`GovernorDetailView`)
      - [x] Show the state's two senators in the state-level detail sheet, below the governor
      - [x] Show a list of all House representatives for the state in the state-level detail sheet, below the senators
      - [x] Add total population, top sectors/industries, top cities, and top universities sections to the state-level detail sheet (new state-keyed data directories, mirroring the district ones)
  - [x] We currently dont need to see the rest of the world in our map. Is there a way to just load a map of america? Would that be better for performance? We should just spend computational energy rendering America
  - [x] Create a "toolbar" at the top of the map under the District maps title. this should have a "show icons" toggle as well as the recentering button on the right. the show icons toggle should toggle both district representative icons as well as governor icons
  - [ ] Organize the map code into different files with clear purposes and outline a feature for adding state flags after being zoomed out, but dont implement it. Just add filler files for that task and keep hte current approach while cleaning up the files/organizing them. Keeping the project organized, modular, and maintainable is a priority.

- [ ] For the representatives view, start loading their information immediately if none is found on disk upon app load. The user shouldnt have to open the representatives tab for the loading to start or to kickstart the image loading.
- [ ] Same with the map view. the map should be fully rendered upon app load, not when the map tab is opened for the first time. Upon app load load all recent bills & their details, then your representatives, then map data all at app launch before caching it for future runs.
- [x] In the voting history for an enacted law, I only see how my house of representatives representative voted. I want to see how my senators voted as well, but their votes dont show up (at least in the same section as my representatives vote shows up). I want to see my senators vote in the same spot

- [x] Add home screen widgets that show what would be shown as the top bill in the recent bills feed
  - [x] This is broken ^ currently the text is larger than the actual widget. is it possible to detect the widget's bounds?
  - [x] When tapping on the widget, the user should automatically be sent to the bill that was displayed detail view, with a back button sending them to recent bills.
- [x] Add system notifications for new bills being passed
  - [x] Recently enacted laws should be a push notification
  - [x] Add the ability to bookmark a bill to recieve all notifications about it
  - [ ] Verify these actually work. Does politica every reload bills in the background? How will the app know when a bill has been updated? How frequently should we check? is there a certain time of day the library of congress updates their information

---

## Version 1.0
ONLY DO THIS WHEN EVERYTHING ABOVE IS IMPLEMENTED
Get multiple API keys so the entire app isnt on my personal one
- [ ] Gate the sample data behind the #ifDebug statement so that it doesnt bload the final release
- [ ] Comment out the stock trades metric for now
- [ ] Load "No representatives found" if there is some error retrieving the representatives and "Error collecting recent bill information" if there is an error loading bills. If there is an error finding representatives, offer the user to type in a zip code to load representatives with the text "On vacation? Type in your home zip code to find your representatives:"
- [ ] Organize the project's functions and file structure for maximum maintainability and understanding
- [ ] Modify ReadME
#### Release!


---

## Version 1.1 DO 
DO NOT DO UNLESS EVERYTHING BEFORE 1.0 IS DONE

- [ ] Re-add stock trades metric
- [ ] If a district is a U around a dot, the representative could be misplaced within the dot instead of actually in their district
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
