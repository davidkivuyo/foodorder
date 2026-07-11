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

## Goal:

# Implement Firestore Search in the Campus Bite Flutter App

Implement a complete food search feature using Firebase Firestore only. Do not use Algolia, Typesense, Meilisearch, or any external search service.

## Objective

Users should be able to search for food items by:

* Food name
* Category
* Tags
* Keywords
* Partial words (prefix search)

The implementation should be responsive and efficient while keeping Firestore read costs low.

## Firestore Structure

The `food_items` collection should include the following searchable fields:

```text
title
titleLower
keywords
searchPrefixes
```

Example document:

```json
{
  "title": "Chicken Burger",
  "titleLower": "chicken burger",
  "category": "Burgers",
  "price": 3500,
  "available": true,
  "keywords": [
    "chicken",
    "burger",
    "burgers",
    "fast food",
    "lunch"
  ],
  "searchPrefixes": [
    "c",
    "ch",
    "chi",
    "chic",
    "chick",
    "chicke",
    "chicken",
    "b",
    "bu",
    "bur",
    "burg",
    "burge",
    "burger"
  ]
}
```

## Search Helper

Create a helper class that automatically generates:

* titleLower
* keywords
* searchPrefixes

Requirements:

* Convert everything to lowercase.
* Remove duplicate values.
* Generate prefixes for every word in the title.
* Generate prefixes for category and tags as well.

## Food Model

Update the FoodItem model to support:

* titleLower
* keywords
* searchPrefixes

Update both:

* fromMap()
* toMap()


## Admin Side

Modify the Add Food and Edit Food functionality so that every time a food item is created or updated:

* titleLower is generated automatically.
* keywords are generated automatically.
* searchPrefixes are generated automatically.

The administrator should never type these fields manually.

the admin app is available in the the /home/davidkivuyo/StudioProjects/foodapp/adminview path alongside this customerview app

## Search Service

Create a new file:

```
lib/services/search_service.dart
```

The service should expose:

* searchFoods(String query)

Requirements:

* Trim whitespace.
* Convert query to lowercase.
* Return an empty list for an empty query.
* Query Firestore using searchPrefixes.
* Only return available food items.

## Search UI

Search bar is in home screen which is read only and when user taps it, it navigates to search screen inside lib/data/search_bar.dart file, where the search operation will take place.

Requirements:

* Search begins while typing.
* Debounce user input by about 300 milliseconds.
* Display a loading indicator while querying.
* Show:

  * Food image
  * Food title
  * Category
  * Price
  * Availability
* Tapping a result opens the existing Food Details screen.
* If no results exist, show:
  "No matching food found."

## Performance

Implement the following optimizations:

* Debounce typing.
* Cache previous search results in memory.
* Avoid duplicate Firestore requests.
* Dispose controllers and timers correctly.
* Prevent memory leaks.


## Error Handling

Handle:

* Network unavailable
* Firestore exceptions
* Permission denied
* Empty search query

Display friendly messages instead of crashing.

## Code Quality

* Follow the existing project architecture.
* Keep business logic inside services.
* Keep widgets clean.
* Use ChangeNotifier where appropriate.
* Add comments explaining complex logic.
* Avoid code duplication.
* Use null safety throughout.

## Deliverables

Provide complete, production-ready code for:

* Search helper
* Search service
* Updated FoodItem model
* Updated Add/Edit Food logic
* Search screen
* Home screen integration
* Any required Firestore index information

The implementation should compile without errors and integrate seamlessly into the existing Campus Bite application.

## Restrictions:

* Do not change anything not related to the task in the goal and requirements

---

# Phase Completion Criteria

Phase 1 is complete when:

* App runs successfully.
* No runtime errors occur.
