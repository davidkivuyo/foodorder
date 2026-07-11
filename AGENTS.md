# AGENTS.md

## Project Overview

Build a Flutter mobile application for university students to order food from the campus cafeteria.

The purpose of the application is to:

* Reduce cafeteria queues.
* Allow students to see available meals before arriving.
* Allow students to place food orders in advance.
* Help cafeteria staff manage orders efficiently.
* Minimize food waste caused by abandoned orders.

This application will eventually use Firebase for authentication and data storage, but Firebase must not be implemented until its phase is activated.

---

# Product Vision (Future Features)

The completed system may include:

Student Features

* Registration
* Login
* Browse daily menu
* Categories
* Place orders
* View order history
* Account management

Cafe Admin Features

* Registration
* Login
* Add food items
* Edit food items
* Remove food items
* Manage orders
* Mark orders as collected

Order Management

* Order status tracking
* Collection confirmation
* Prevention of abandoned orders

Backend

* Firebase Authentication
* Cloud Firestore
* Firebase Storage
* firebase notifications

These features are future phases and must not be implemented unless activated.

---

# Application Navigation

Bottom Navigation Bar must contain:

1. Home
2. Categories
3. Search
3. Orders
4. Account

This navigation structure should remain consistent throughout development.

---

# Agent Development Rules

## Rule 1

Implement only the active phase.

Do not implement future phases.

All changes made are must be **production ready** hence solve any security and performance issues arise during development.

---

## Rule 2

Before writing code, answer:

1. Current phase?
2. Requirement being implemented?
3. Files being modified?
4. Possible regressions?

Then proceed.

---

## Rule 3

Use simple Flutter architecture.

Preferred structure:

lib/
├── data/
├── screens/
├── widgets/
├── models/
├── services/
├── navigation/

Avoid unnecessary complexity.

Do not introduce advanced architecture unless requested.

---

## Rule 4

Preserve working functionality.

Never rewrite entire screens when small modifications are sufficient.

---

## Rule 5

After completing a feature:

* Verify build succeeds.
* Verify navigation works.
* Verify all features still work.

---

# Current Phase

PHASE 1

Goal:

Start implementing order logic, When user places an order, the details of the order will be sent to the database including the food item unique orderid, quantity, userId for the user who ordered and date and time. All under the database collection "orders". Then admin will receive the order and its details including the name of the user who ordered, the order unique ID which is automatically generated in cart_services.dart on a variable on line 227, the status of the order as shown in the order screen in adminview app, the amount and the food item name including the total order price amount. All in order screen in the admin view app.

Requirements:

* the admin will have the choice to accept and reject the order and after that. with a confirmation pop up message if he or she accidentally press reject button.
* the order screens of admin app should show choices and status for prepairing when the food is still being cooked, a choice to mark the food ready for pickup, and if it is collected or No show(Where its striking logic will be added in the future phases) if the student has not collected.
* At the same time the student app order status is updated in real time.

Restrictions:

* Do not change anything not related to the task in the goal and requirements

---

# Phase Completion Criteria

Phase 1 is complete when:

* App runs successfully.
* No runtime errors occur.
