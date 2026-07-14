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

PHASE 5.1

# TASK

Implement Phase 5.1 of CampusBite.

This is a privacy hardening phase.

The goal is to minimise collection and storage of sensitive location data while preserving all existing functionality.

The implementation must be production-ready.

Do NOT change the user experience.

Do NOT change pickup deadline calculations.

Do NOT break any completed feature.

---

# CURRENT IMPLEMENTATION

Current behaviour:

Student places order

↓

Current location obtained

↓

Distance calculated

↓

Pickup window calculated

↓

Order stores:

studentLocation

cafeLocation

distanceMeters

pickupWindowMinutes

pickupDeadline

The feature works correctly.

The objective is only to improve privacy.

---

# OBJECTIVE

CampusBite must follow the principle of Data Minimisation.

Collect only the data required.

Keep it only as long as required.

Delete it immediately after its purpose has been fulfilled.

---

# NEW ARCHITECTURE

Student location must become temporary.

The location is used ONLY for calculating:

distanceMeters

pickupWindowMinutes

After those values are calculated:

The student's coordinates must never be stored in Firestore.

The coordinates must not remain in memory longer than necessary.

---

# REQUIRED CHANGES

The order document must NO LONGER contain:

studentLocation

Remove all writes that persist studentLocation.

Do not replace it with another location field.

---

# KEEP

Continue storing:

distanceMeters

pickupWindowMinutes

pickupDeadline

readyAt

deadlineStatus

status

These values contain no precise location information.

---

# DISTANCE CALCULATION

Continue calculating distance locally inside Flutter.

Do NOT move this calculation to Cloud Functions.

Do NOT introduce any external APIs.

Do NOT introduce Google Directions API.

Do NOT introduce Google Distance Matrix.

---

# CAFE LOCATION

Cafe locations are public business information.

They may continue to exist in:

food_items

or

cafes

Do NOT duplicate them unnecessarily.

If already available in memory when placing the order, reuse the existing value.

Avoid additional Firestore reads.

---

# FIRESTORE OPTIMISATION

Reduce Firestore storage.

Remove all writes of:

studentLocation

Do not introduce replacement writes.

The total number of Firestore writes must not increase.

The total number of Firestore reads must not increase.

---

# MEMORY MANAGEMENT

After calculating:

distanceMeters

pickupWindowMinutes

Clear any temporary location variables.

Do not cache the student's location.

Do not keep location in singleton services.

Do not persist location locally.

---

# ADMIN APP

Admins must never see:

Student coordinates

Maps

Latitude

Longitude

The Admin App should continue displaying only:

Distance

Pickup Window

Pickup Deadline

---

# STUDENT APP

No visible behaviour should change.

Countdown must continue working.

Pickup deadlines must continue working.

Ordering must continue working.

The student should notice no difference.

---

# CLOUD FUNCTIONS

Do NOT modify:

Strike logic

Deadline monitoring

Notification logic

Account suspension

Cloud Scheduler

Cloud Functions should continue using:

pickupWindowMinutes

to generate:

pickupDeadline

Cloud Functions must never receive student coordinates.

---

# FIRESTORE SCHEMA

Remove:

studentLocation

from new order writes.

Existing historical documents containing studentLocation may remain.

Do NOT perform a migration.

Only new orders must follow the new schema.

---

# SECURITY

Student coordinates must never be readable because they are never stored.

No Firestore rule changes should be necessary.

---

# PRIVACY

CampusBite should only retain:

distanceMeters

pickupWindowMinutes

These values cannot be used to reconstruct the student's exact position.

The application must not retain location history.

The application must never track movement.

---

# PERFORMANCE REQUIREMENTS

The implementation must not introduce:

Additional Firestore reads

Additional Firestore writes

Additional Cloud Function invocations

Additional listeners

Additional network requests

The existing architecture should remain O(1) per order.

---

# CODE QUALITY

Remove obsolete location models and fields if they are no longer used.

Avoid dead code.

Avoid duplicate calculations.

Maintain existing service boundaries.

---

# TESTING

Verify:

✓ Ordering still works.

✓ Pickup window still works.

✓ Countdown still works.

✓ Distance calculations remain correct.

✓ No student coordinates are written to Firestore.

✓ Firestore reads do not increase.

✓ Firestore writes do not increase.

✓ Admin App still functions.

✓ Student App still functions.

✓ Strike system unaffected.

✓ Notification system unaffected.

---

# DELIVERABLES

Provide:

1. Modified files.

2. Removed fields.

3. Updated data model.

4. Testing results.

Stop after completing this privacy hardening phase.

Do NOT implement any additional features.

---

# Phase Completion Criteria

Phase 5 is complete when:

* the new features works well with past features.
* App runs successfully.
* No runtime errors occur.
