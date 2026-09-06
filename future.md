# future implementation plans

# TODOS

---

## FIXES NEEDED
2. remove the add to cart shadow **checked**

3. update the cafe details in food item appearing in desktop to also be tappable and push the use to cafe details screen

4. remove the prices **checked**

5 . fix the orange overlay **checked**

6. fix the home searchbar layout issue **checked**

7. fix the padding issue **checked**

8.  fix the text cafe overflows **checked**

9. remove any border and elevation and hovers in all food cards **checked**

11. fix the review button not showing up--orders deleted (investigate if the review buttons nd logic work as intended)

12. increase slightly the width of the food images in homescreen

13. Fix the searchbar logic in homescreen **checked**

14. Remove duplicate icons in the categories filter in the top header section **checked**

15. change the food details popup model design to adapt that of uber eats in the screenshots
16. remove the overlay in desktop **checked**

----

## FUTURE FEATURES
1. remove old food items in the firebase console

1. add explicit description for the corresponding food item (even add swahili translation). to explain how the food is priced and at what quantity per the food image representation which is not neccessarilly equal.

1. add preorder meals e.g in morning one can pre order lunch or dinner

1. apply ai to view and monitor images uploaded to be for food only no harm or dangerous materials

2. Add a 'for' field on every food items which  is for univerisity with a value of "for university"
* and food items for outer restaurants will have a value of "for restaurants"

3. use n8n to automate creating newsletters for furnitures to subscribers in mailchimp

5. add a search to view if the written cafe is already in database to avoid duplication

6. create a new branch to add restaurants other than university ones
* Their menu items will be able to link to whatsapp easily
* Or start a messaging platform inside the app

5. Make the student app and admin app choose which university there in and ensure that the FOOD ITEM and CAFE(add a field to specify which university there in) in university A is not shown or mixed into university B, including their orders.
* Also add a university collection to list all available universities in which the app serve

7. Performance Analytics: Daily/weekly revenue, top-selling dishes, peak order hours, average prep time, customer rating trends.

8. add products for off_campus food items. the section field will be changed to off_campus, cafe field to offcampus, and the location field will be added to indicate the location of the offcampus cafes.
// Row for deals outside campus cafes on home screnn
* CardRowItems(title: "Deals outside campus cafes",items: offCampus,),
// If cafe is 'offcampus', show 'OFF-CAMPUS', otherwise show 'CAFE(X)'
* item.cafe.toLowerCase() == 'offcampus' ? '${item.rating} • OFFCAMPUS' : '${item.rating} • CAFE(${item.cafe})',
