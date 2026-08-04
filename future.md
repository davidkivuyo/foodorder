# future implementation plans

# NOT FULLFILLED
1. migrate CI to blacksmith- "runs-on: blacksmith-4vcpu-ubuntu-2404" 

2. prepaire updating code to automatically fetch and update app with ease
Preserves all of your current signing and build logic.
Builds both the universal APK and split-per-ABI APKs.
Renames APKs consistently.
Uploads APKs to Firebase Storage.
Generates release.json automatically.
Publishes only release.json and release notes to GitHub Releases.
Keeps your existing version/tag workflow intact.

3. ADD A Verification email step to disallow other peoples emails and stop email misuse-ready

6. add and search filter to search easily the long list of menu items in the admin app-ready

# 5. Add a review screen with review count dashboard, "campusbite customer" reviews with pre-written templates to avoid review abuse and harsh languages 
Users will be able to delete or edit their reviews.
example
* great deal
* great value for money
* not great as expected
* hot food
* served well

6. Make the student app and admin app choose which university there in and ensure that the FOOD ITEM and CAFE(add a field to specify which university there in) in university A is not shown or mixed into university B, including their orders.
* Also add a university collection to list all available universities in which the app serve

11. order screen should clean 24hrs and its history will be saved under /users/{userId}/history according to date, food item title and the total price.-ready

3. create a new branch to add restaurants other than university ones

5. Performance Analytics: Daily/weekly revenue, top-selling dishes, peak order hours, average prep time, customer rating trends.

2. add products for off_campus food items. the section field will be changed to off_campus, cafe field to offcampus, and the location field will be added to indicate the location of the offcampus cafes.
// Row for deals outside campus cafes on home screnn
* CardRowItems(title: "Deals outside campus cafes",items: offCampus,),
// If cafe is 'offcampus', show 'OFF-CAMPUS', otherwise show 'CAFE(X)'
* item.cafe.toLowerCase() == 'offcampus' ? '${item.rating} • offcampus' : '${item.rating} • CAFE(${item.cafe})',

# Updated CampusBite Roadmap

✔ Phase 0
Foundation

✔ Phase 1
Ordering System

✔ Phase 2
Student Discipline & Account Management

↓

✔ Phase 3
Pickup Deadline Engine

↓

✔Phase 4
Distance-Based Pickup Windows

↓

✔Phase 5
Automatic Strike Engine

↓

✔Phase 6
Notifications
starting to finish with notification, very tired exshausted with freebuff, opencode and antigravity

↓

✔Phase 7
Search & Personalization

↓

Phase 8
Reviews & Feedback

↓

Phase 9
Business Analytics

↓

Phase 10
Production Hardening & Release


# ai instructions for updating the app
