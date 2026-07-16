# future implementation plans

# NOT FULLFILLED
4. add a fetch request to see if the already entered cafe is available or not.

5. display poper messages instead of debugprint eg "debugPrint('[CartService] Cannot add unavailable item: ${item.title}"

9. save the users passwords in their google account logged in their device and retrieve it upon attempts to login in both adminview and customerview

10. display the time which a student is obliged to pickup the food if he or she didnot show on that time the cafe admin can be allowed to strike the student. Also notify the student when order is ready to be collected and show the time required to pickup the food. the time is calculated by the distance of the current user location and the cafe and the time taken to prepare the food.

11. order screen should clean 24hrs and its history will be saved under /users/{userId}/history according to date, food item title and the total price.

12. add rating field in addproducts for admin

2. add products for off_campus food items. the section field will be changed to off_campus, cafe field to offcampus, and the location field will be added to indicate the location of the offcampus cafes.
// Row for deals outside campus cafes on home screnn
* CardRowItems(title: "Deals outside campus cafes",items: offCampus,),
// If cafe is 'offcampus', show 'OFF-CAMPUS', otherwise show 'CAFE(X)'
* item.cafe.toLowerCase() == 'offcampus' ? '${item.rating} • offcampus' : '${item.rating} • CAFE(${item.cafe})',

3. create a new branch to add restaurants other than university ones

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

▶ Phase 4
Distance-Based Pickup Windows   ← CURRENT

↓

Phase 5
Automatic Strike Engine

↓

Phase 6
Notifications

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
