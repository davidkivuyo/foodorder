# future implementation plans

# TODOS
1. REMOVE THE STRIKING ENGINE.
* Instead of percentage put words from encouraging to reminders.
* THE RELIABILITY SCORE- The order banning will be calculated based on the number of times they missed their food and the number of times they collected their food on time. The more they collect on time, the more reliable they are and the less likely they will be banned from ordering.
* WHEN THEY COLLECT ON TIME, A POP UP WILL SHOW UP AND CONGRATS THEM. "KEEP UP".

Order Ready
      │
      ▼
Send Notification
      │
      ▼
Pickup Countdown
      │
      ▼
Reminder Notifications
      │
      ▼
Grace Period
      │
      ▼
Collected? ─────────► Yes → Increase reliability (up to 100)
      │
      ▼ No
Mark as Expired
      │
      ├── Lower reliability score
      ├── Notify student
      ├── Notify cafe
      └── Allow cafe to mark food as rescued, donated, discounted, or discarded


2. migrate CI to blacksmith- "runs-on: blacksmith-4vcpu-ubuntu-2404" when you start an organization on Github

3. modify account screen to add app appearance settings, your ratings and meal plans.

4. wire up adminview github release apk workflow to build the app apk on git push tags

5. Make the student app and admin app choose which university there in and ensure that the FOOD ITEM and CAFE(add a field to specify which university there in) in university A is not shown or mixed into university B, including their orders.
* Also add a university collection to list all available universities in which the app serve

6. create a new branch to add restaurants other than university ones

7. Performance Analytics: Daily/weekly revenue, top-selling dishes, peak order hours, average prep time, customer rating trends.

8. add products for off_campus food items. the section field will be changed to off_campus, cafe field to offcampus, and the location field will be added to indicate the location of the offcampus cafes.
// Row for deals outside campus cafes on home screnn
* CardRowItems(title: "Deals outside campus cafes",items: offCampus,),
// If cafe is 'offcampus', show 'OFF-CAMPUS', otherwise show 'CAFE(X)'
* item.cafe.toLowerCase() == 'offcampus' ? '${item.rating} • offcampus' : '${item.rating} • CAFE(${item.cafe})',
