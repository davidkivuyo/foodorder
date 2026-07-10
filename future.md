future implementation plans

# not fulfilled❌
2. Goal2:

add products for off_campus food items. the section field will be changed to off_campus, cafe field to offcampus, and the location field will be added to indicate the location of the offcampus cafes.
// Row for deals outside campus cafes on home screnn
* CardRowItems(title: "Deals outside campus cafes",items: offCampus,),
// If cafe is 'offcampus', show 'OFF-CAMPUS', otherwise show 'CAFE(X)'
* item.cafe.toLowerCase() == 'offcampus'
                                          ? '${item.rating} • offcampus'
                                          : '${item.rating} • CAFE(${item.cafe})',

3. Goal3:

When user places an order the details of the order will be sent to the database including the food item unique id, quantity, user ordered. under the database collection orders/{orderId}.

4. Goal4:

Update the cart logic so as for food items labeled ALL in their "cafe" fields, the user will be able to select the cafe they want to order from. This will be done by adding a new field to the food item model to indicate the available cafes for that food item. When a user adds an ALL labeled food item to the cart, they will be prompted to select the cafe they want to order from before proceeding to placing an order.

5. Goal5
display poper messages instead of debugprint eg debugPrint('[CartService] Cannot add unavailable item: ${item.title}

# fulfilled✅
1. Goal1:

For offcampus labeled food items the users will only be allowed to call the associated cafe phone number instead of placing an order when added to cart, thus preventing the user from placing an order for offcampus food items. This will also add another field on the food item model to indicate the location of the offcampus cafes.
Requirements:
* Add a new field to the food item model to indicate the location of the offcampus cafes.
* When a user adds an offcampus food item to the cart, instead of allowing them to place an order, display a message prompting them to call the associated cafe phone number.
