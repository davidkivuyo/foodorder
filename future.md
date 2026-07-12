# future implementation plans

# not fulfilled
2. Goal2:
add products for off_campus food items. the section field will be changed to off_campus, cafe field to offcampus, and the location field will be added to indicate the location of the offcampus cafes.
// Row for deals outside campus cafes on home screnn
* CardRowItems(title: "Deals outside campus cafes",items: offCampus,),
// If cafe is 'offcampus', show 'OFF-CAMPUS', otherwise show 'CAFE(X)'
* item.cafe.toLowerCase() == 'offcampus' ? '${item.rating} • offcampus' : '${item.rating} • CAFE(${item.cafe})',

5. Goal5
display poper messages instead of debugprint eg "debugPrint('[CartService] Cannot add unavailable item: ${item.title}"

6. goal6
in the striking  system, add the condition for an eligible student to look if he/she has a strike fiellld with a value of "no show" and strikeQuaantity with value of 2. so that the authentication will look first if the student is suspendedby looking if the above conditions are met and if not the student will be allowed to login to the app.

7. goal7
an admin can strike students who donot collect their food by pressing no show button in corresponding orders and this will update the corresponding student's strike field to "no show" and add the strikeQuantity according to number of strikes the student got over time if its 2 the account will read suspended if 1 the app will display a non-annoying message in the corresponding student account screen.

9. goal9.
save the users passwords in their google account logged in their device and retrieve it upon attempts to login in both adminview and customerview

10. goal10
display the time which a student is obliged to pickup the food if he or she didnot show on that time the cafe admin can be allowed to strike the student. Also notify the student when order is ready to be collected and show the time required to pickup the food. the time is calculated by the distance of the current user location and the cafe and the time taken to prepare the food.

11. order screen should clean 24hrs and its history will be saved under /users/{userId}/history according to date, food item title and the total price.

12. add rating field in addproducts for admin


# fulfilled✅
1. Goal1:
For offcampus labeled food items the users will only be allowed to call the associated cafe phone number instead of placing an order when added to cart, thus preventing the user from placing an order for offcampus food items. This will also add another field on the food item model to indicate the location of the offcampus cafes.
Requirements:
* Add a new field to the food item model to indicate the location of the offcampus cafes.
* When a user adds an offcampus food item to the cart, instead of allowing them to place an order, display a message prompting them to call the associated cafe phone number.

4. Goal4:
Update the cart logic so as for food items labeled ALL in their "cafe" fields, the user will be able to select the cafe they want to order from. This will be done by adding a new field to the food item model to indicate the available cafes for that food item. When a user adds an ALL labeled food item to the cart, they will be prompted to select the cafe they want to order from before proceeding to placing an order.

8. goal8.
Add a section selection dropdown in the add_products screen where the admin can select which section to place the food item into, the section information is retrieved from the firestore database under collection "section". also add another list from the dropdown which reads "no section" and if the cafe admin selects it the food item will not be placed in any section but will still remain organized according to its category in the category screen.

3. Goal3:
When user places an order, the details of the order will be sent to the database including the food item unique id, quantity, userId for the user who ordered, time. All under the database collection orders/{orderId}.
