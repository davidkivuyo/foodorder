# future implementation plans

# TODOS
1. apply ai to view and monitor images uploaded to be for food only no harm or dangerous materials

2. Add a 'for' field on every food items which  is for univerisity with a value of "for university"
* and food items for outer restaurants will have a value of "for restaurants"

3. use n8n to automate creating newsletters for furnitures to subscribers in mailchimp

4. in each food description page add a arrow button to view through a popup the cafe/restaurant location on google maps and distance from where the student is.

5. add a search to view if the written cafe is already in database to avoid duplication

6. create a new branch to add restaurants other than university ones
* Their menu items will be able to link to whatsapp easily
* Or start a messaging platform inside the app

3. in myprofile screen screen add app appearance settings, your ratings.

5. Make the student app and admin app choose which university there in and ensure that the FOOD ITEM and CAFE(add a field to specify which university there in) in university A is not shown or mixed into university B, including their orders.
* Also add a university collection to list all available universities in which the app serve

7. Performance Analytics: Daily/weekly revenue, top-selling dishes, peak order hours, average prep time, customer rating trends.

8. add products for off_campus food items. the section field will be changed to off_campus, cafe field to offcampus, and the location field will be added to indicate the location of the offcampus cafes.
// Row for deals outside campus cafes on home screnn
* CardRowItems(title: "Deals outside campus cafes",items: offCampus,),
// If cafe is 'offcampus', show 'OFF-CAMPUS', otherwise show 'CAFE(X)'
* item.cafe.toLowerCase() == 'offcampus' ? '${item.rating} • OFFCAMPUS' : '${item.rating} • CAFE(${item.cafe})',

---

# important
Rule going forward

Keep versions strictly increasing across channels — a production tag must always be greater than the highest dev tag, and dev tags should be prereleases of a future version, not a parallel numbering track:
- Bad: dev  v1.1.0-dev ,  v1.8.0-dev  → production  v1.0.0  (downgrade in name)
- Good: production  v1.9.0  → then dev  v1.10.0-dev  → production  v2.0.0  → dev  v2.1.0-dev  …

Your pipeline enforces this automatically — the  -prerelease  detection in the workflow ( IS_PRERELEASE ) publishes dev tags as GitHub prereleases, the semver validation ensures tags are always well-formed, and a release-ordering gate in the Extract Version step rejects any tag that is not semver-greater than every previously published tag (excluding the candidate itself, so re-runs pass). No manual gate is needed; a lower tag simply fails the build.