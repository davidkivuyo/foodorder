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

# Product Vision

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
├── repositories/

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

PHASE 10

# TASK

Implement the "Your Favourites" feature for CampusBite.

The feature must automatically determine each student's favourite menu items based on completed order history.

Do not ask users to manually mark favourites.

The implementation must be production-ready, scalable, and cost-efficient.

Reuse existing Home Screen widgets and arrangement logic.

---

# OBJECTIVE

Display a new "Your Favourites" section at the top of the Home Screen.

The section must:

- appear only when favourites exist
- use the existing horizontal carousel component
- follow the same section arrangement logic already used throughout the Home Screen
- show a maximum of 5 food items
- include a forward arrow that opens a dedicated "Your Favourites" screen
- never duplicate food data in Firestore

---

# DATA SOURCE

Only use orders with status:

COLLECTED

Ignore:

Accepted
Preparing
Ready
Cancelled
Rejected
No Show

---

# FAVORITE ENGINE

Create:

favorite_service.dart

Responsibilities:

- calculate favourite rankings
- update cached favourites after collected orders
- return favourite food IDs
- ignore unavailable foods
- ignore deleted foods

Do not place this logic inside UI widgets.

---

# CACHE

Store only favourite food IDs under:

users/{uid}/favoriteMenu

Do not store complete food objects.

Maximum cached IDs:

5

Always load current food details from food_items.

---

# UPDATE STRATEGY

Recalculate favourites only when an order changes to:

COLLECTED

Never recalculate during:

- app startup
- login
- Home refresh
- scrolling

---

# RANKING

Rank by:

1. Number of collected orders

2. Most recent collection date

Higher frequency ranks first.

If tied, newer collection wins.

---

# HOME SCREEN

Insert a new section before all other food sections.

Title:

Your Favourites

Use the existing horizontal carousel widget.

Maximum displayed items:

5

Hide the section completely if no favourites exist.

---

# SEE ALL

The forward arrow navigates to:

YourFavouritesScreen

Reuse the existing vertical food list design.

Display all favourite items with no maximum limit.

---

# ARRANGEMENT

Reuse the existing Home Screen section ordering.

Within each section, preserve favourite ranking.

Do not introduce a different sorting system.

---

# PERFORMANCE

Do not scan all orders during Home loading.

Use cached favourite IDs.

Only perform lightweight reads.

Avoid unnecessary Firestore writes.

---

# RESILIENCE

If a favourite food has been deleted or marked unavailable:

Skip it gracefully.

Do not crash.

---

# TESTING

Verify:

✓ favourites appear after collected orders

✓ favourites update after new collections

✓ section hides when empty

✓ maximum 5 items on Home

✓ unlimited items on Your Favourites screen

✓ deleted foods disappear automatically

✓ unavailable foods are skipped

✓ existing Home Screen layout remains unchanged

✓ no unnecessary Firestore reads

✓ no unnecessary Firestore writes

Deliver the implementation without affecting existing ordering, notifications, strike engine, or recommendation features.

---

# Phase Completion Criteria

Phase 10 is complete when:

* the new features works well with past features.
* App runs successfully.
* No runtime errors occur.
