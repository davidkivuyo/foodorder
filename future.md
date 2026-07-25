# future implementation plans

# NOT FULLFILLED
3. ADD A Verification email step to disallow other peoples emails and stop email misuse

4. add a fetch request to see if the already entered cafe is available or not.

9. save the users passwords in their google account logged in their device and retrieve it upon attempts to login in both adminview and customerview

11. order screen should clean 24hrs and its history will be saved under /users/{userId}/history according to date, food item title and the total price.

12. add rating field in addproducts for admin

2. add products for off_campus food items. the section field will be changed to off_campus, cafe field to offcampus, and the location field will be added to indicate the location of the offcampus cafes.
// Row for deals outside campus cafes on home screnn
* CardRowItems(title: "Deals outside campus cafes",items: offCampus,),
// If cafe is 'offcampus', show 'OFF-CAMPUS', otherwise show 'CAFE(X)'
* item.cafe.toLowerCase() == 'offcampus' ? '${item.rating} • offcampus' : '${item.rating} • CAFE(${item.cafe})',

3. create a new branch to add restaurants other than university ones

4. Order History and Reorder: One-tap reorder from previous purchases — high-impact retention feature.

5. Performance Analytics: Daily/weekly revenue, top-selling dishes, peak order hours, average prep time, customer rating trends.


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

Phase 6
Notifications  ← CURRENT
starting to finish with notification, very tired exshausted with freebuff, opencode and antigravity

↓

Phase 7
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
