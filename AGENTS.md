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
* Verify existing features still work.

---

# Current Phase

PHASE 1

Goal:

create a **horizontal scrollable list of circular food items** and their titles and prepairing time as layed in the common_food.dart file in the screens folder. And when user clicks the circular images it would navigate them to the corresponding screen with a vertical column layout list of food items just like in the categories screen and when the user clicks one of the images it will navigate to the food items descriptions screen

Requirements:

* the horizontal scrollable list should have 4 food items titled of Wali, Ugali, chipsi with mockups images which will be fetched from the firestore databse
* the common_food.dart file should be responsible for all the features
* the vertical list of the navigated corresponding screen should have layout its items like in the categories screen with the top title same with the horizontal scrollable corresponding titles and a back button. **NO appbar**


Restrictions:

* Do not change anything not related to the task in the goal and requirements
* No authentication
* No registration
* No admin functionality

---

# Phase Completion Criteria

Phase 1 is complete when:

* App runs successfully.
* No runtime errors occur.
