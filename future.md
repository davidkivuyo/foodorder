# future implementation plans

# NOT FULLFILLED
1. migrate CI to blacksmith- "runs-on: blacksmith-4vcpu-ubuntu-2404" when you start an organization on github

2. modify account screen to add app appearance settings, your ratings and meal plans.

3. wire up adminview github release apk workflow to build the app apk on git push tags

6. Make the student app and admin app choose which university there in and ensure that the FOOD ITEM and CAFE(add a field to specify which university there in) in university A is not shown or mixed into university B, including their orders.
* Also add a university collection to list all available universities in which the app serve


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

✔ Phase 4
Distance-Based Pickup Windows

↓

✔ Phase 5
Automatic Strike Engine

↓

✔ Phase 6
Notifications
starting to finish with notification, very tired exshausted with freebuff, opencode and antigravity

↓

✔ Phase 7
Search & Personalization

↓

✔ Phase 8
Reviews & Feedback

↓

✔ Phase 9
Business Analytics

↓

✔ Phase 10
Production Hardening & Release
