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
- [x] "Beats the market" / insider-trading / corruption meter *(needs a trading-disclosure data source)* — trading-activity transparency shipped; quantitative scoring deferred to post-launch (see Version 1.1)
  - [x] Trading-activity indicator — House Periodic Transaction Report (PTR) count for the past year, latest-filing date, and a link to the filing, from the free House Clerk disclosure index (on-device ZIP + TSV parsing, no key). Senators link out to the Senate eFD portal.
  - [x] Senate coverage — parse efdsearch.senate.gov (agreement + CSRF + DataTables JSON) for senators' PTRs
  - [-] "Beats the market" quantitative metric — moved to Version 1.1 (post-launch); realistically a backend job (PDF parsing + historical price data source), not feasible on-device
- [x] Add 3 tabs to the representative view. 1st tab is about (Committees, Bills, Contact info), 2nd tab is voting history (show the full title for each bill as it appears on the home feed, with an arrow to view the bills full details, should go to the same screen we end up on if tapped on from the home screen), 3rd tab should be the money tab the ("Beats the market"/ insider-trading / corruption meter), stock trades, top PAC funders,  top individual funders
  - [x] Add top individual funders, specify they are employees if the category is a company. if "Attorney" expand to plural form ie "Attornies"
  - [x] About section shoud have an "i" icon, Votes the voting history icon, and money a dollar bill sf symbol in the tab view next to the text
- [x] Expand the recent bills section to load more if the user reaches the bottom of the feed
- [x] Locating seems to take a LONG time. How about we progress to the home "recent bills" section while this is happening and location detection continues in the background? Only kicking back to the loading screen if theres some sort of error?
  - [x] This works, but kind of. right now the user taps "locate" and view instantly progresses to the home recent bills section at the same time apple system prompt shows up asking the user if they want to share their exact or approximate location. the view should only progress after the user makes a choice in this selection. before then, while the apple location prompt is up on the screen, the user should still see the onboarding location view in the background.
- [x] Transition the "Your Representatives" section into having their party color as a shadow rather than an outline. Have a simpler list. Maybe comment out how we build the current view so that we can use it later. Now it should be a list where the most senior senator is one top, followed by the other senator, with the representative on bottom. This should replace the 2-a-row feature we have right now and there should be lines in between each
- [x] Some of the icons are a little dark. Is there anything similar to the photos app "magic wand" feature that automatically makes photos look good? That should be applied to each photo we get to automatically fix any lighting issues in their official portrait
- [x] The icons for each representative should be a little bigger, as well as the text. Also, the partisan glow/shadow color around the candidates icons should be centered, and not a little south, which it appears to be

---

## 0.4 — Interactive Map

- [ ] Build the interactive map view (evaluate performance and utility)
  - [x] The icons of representatives are currently misplaced. Jeff Merkley appears off the coast of Africa instead of in Washington DC. Actually, skip placing senators for now. but something wasnt working for him to be placed there
    - [x] Pictures dont show up over the representatives name. Their icons should show up like they do in the list view
  - [x] Find borders of all congressional districts give them small borders. Find borders for states and give them thicker borders
  - [x] The current map is too detailed. Switch map modes so that it doesnt have all of the geographic features this one does. 
  - [x] App crashed with: "Thread 45: EXC_RESOURCE (RESOURCE_TYPE_MEMORY: high watermark memory limit exceeded) (limit=3376 MB)"
  - [x] Fill the congressional districts with party color, with each representative in the middle of the district or the district capitol (if there is one) (THIS WAS PREVIOUSLY MARKED AS DONE. IT DOES NOT WORK. THE DISTRICTS DO NOT FILL WITH PARTY COLOR
    - [x] If a distrct is tapped on, the name of the district should pop up on a sheet that only fills the bottom half of the screen. the sheet should be draggable if the user wants to drag it up so that it fills all of the screen (it can still be dragged down and dismissed)
    - [x] The sheet should have the district name with a copy of the district outline on the right and the representatives profile underneath it. This of course can be expanded as described above
  - [x] Fix all project warnings
  - [x] When the map is opened, the user should be centered on their home district and zoomed in so that district is roughly edge to edge width or heightwise, whichever comes first
    - [x] ^ this takes awhile to center. is this because everything is being retrieved, and then the users location is found? what if we center on the user at a certain wide zoom, and then adjust later?
    - [x] There should be a button that recenters the user on their home district. I CANNOT SEE THIS BUTTON. You have previously commit twice saying that there is a button. I cannot see any recentering button in the actual map
  - [x] Everything outside the US should be tinted a little grey, and geographic information like mountain ranges/basins shouldnt be visible. it clutters the map
  - [x] Retrieve ALL state representatives and their associated district in the backend of the app. we only display this in the map section
    - [ ] Do the same ^ for governors
    - [ ] Currently the district map filled with each parties color does not work. mine only worked when I tapped on the land around my location. Only then did it fill in with color and my local representatives icon appear. When I tap on other districts, they dont have a color, but a sheet still shows up. it just says something like "Oregon's 5th District" with no outline next to it or representative under it. Fix this first
    - [ ] After this is fixed ^ we should add more information per district. Each district should display some basic information about the district, like the population count, top sectors/industry, top cities by population, top universties, and anything else relevant to the district. it should still show the representative
    - [ ] Zoom out to state level to see governors. display the governor icons in the middle of the state. The state outline should be filled with the state flag instead of a single party color.
      - [ ] The transition between the different color coded district outlines and the state flag/state level representatives should be smooth
      - [x] The "go back to user location" button in the top right should not adjust zoom level too much. it shouldnt zoom in to their neighborhood. just their district, as that is what is relevant in this context

---

## 0.5 — Platform & Reach

- [x] Implement local caching for offline viewing *(bills, bill detail/roll-calls, and the full delegation — including committees, contact info, funders, trading activity, and voting history — are cached on disk)*
  - [x] Representatives icons
  - [x] Bills
  - [x] Representative information *(cached as part of the delegation in `RepresentativesStore`'s `DelegationCache`; survives offline relaunches since `refreshUsingCachedLocation` runs silently and leaves the cache untouched on failure)*
  - [x] Voting histories *(`CongressService.enrichedProfile`/`SenateService.votingHistory` populate `Representative.keyVotes`, which is part of the same cached delegation)*
- [x] Localization framework setup for multi-language support (Spanish, other languages most spoken in america, etc.) start with spanish
  - [x] A complete spanish trnaslation in localizable
  - [x] localized cf bundle display names

---

## 0.6 — iOS integration

- [x] Add home screen widgets that show what would be shown as the top bill in the recent bills feed
  - [x] Currently the home screen widgets are broken. While I can add one to my home screen, it says "No bill available" and doesnt display anything. It should display the bill title as shown in in app, the description. The background of the widget should match the color of the status of the bill. In committee, grey. Passed house or senate, blue, and enacted, green. Instead of a progress pill, it should just have the status text on the top of the widget as a header above the title. This color should of course be deactived if the user has a clear or tinted homescreen. The background should be the only "colored" thing. The text should be either white or some sort of greys
  - [ ] Expand the text vertically and horizontally. the text should take up more space in the widget
  - [ ] When tapping on the widget, the user should automatically be sent to the bill that was displayed detail view, with a back button sending them to recent bills.
- [x] Add system notifications for new bills being passed
  - [x] Recently enacted laws should be a push notification
  - [x] Add the ability to bookmark a bill to recieve all notifications about it

---

## Version 1.0
- [ ] Organize the project's functions and file structure for maximum maintainability and understanding
- [x] Modify ReadME
#### Release!


---

## Version 1.1 DO 
NOT DO UNLESS EVERYTHING BEFORE 1.0 IS DONE

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
