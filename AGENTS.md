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

PHASE 1

## Goal:

# Backend Pickup Deadline Engine

## Project Context

CampusBite foodapp consists of:

• Flutter Student App(customerview)

• Flutter Cafe Admin App(adminview)

• Firebase Authentication

• Cloud Firestore

• Firebase Cloud Functions

Previous phases completed successfully:

✓ Authentication

✓ Food CRUD

✓ Shared Backend

✓ Ordering System

✓ Student Discipline System

Do NOT modify completed functionality.

Only extend it.

---

# OBJECTIVE

Implement a backend-driven Pickup Deadline Engine.

The backend becomes the ONLY authority responsible for pickup deadlines.

The Admin App MUST NEVER calculate:

• readyAt

• pickupDeadline

• pickupWindow

Students MUST NEVER calculate deadlines.

The client only displays the values returned by Firestore.

---

# ARCHITECTURE

Admin presses:

READY FOR PICKUP

↓

Admin App updates:

status = READY

↓

Cloud Function triggers

↓

Cloud Function writes:

readyAt

pickupDeadline

pickupWindowMinutes

deadlineStatus

↓

Firestore updates

↓

Student App updates automatically

↓

Admin App updates automatically

No client performs calculations.

---

# IMPORTANT RULES

MAKE the firestore functions operations efficient to avoid unnecessary reads and writes.

DO NOT rewrite the order system.

DO NOT refactor unrelated code.

DO NOT duplicate business logic.

DO NOT calculate timestamps inside Flutter.

DO NOT use device clocks.

The backend must be the single source of truth.

---

# PHASE 1.1

Firestore

Extend existing orders.

Add:

readyAt

Timestamp

pickupDeadline

Timestamp

pickupWindowMinutes

number

deadlineStatus

string

Allowed values:

NOT_READY

ACTIVE

COLLECTED

EXPIRED

updatedAt

Timestamp

Do not remove existing fields.

---

# PHASE 1.2

Cloud Functions

Create a Firestore Trigger.

Trigger:

onDocumentUpdated

orders/{orderId}

When:

status changes

Preparing

↓

READY

The Cloud Function shall:

1.

Verify this is the FIRST transition into READY.

If readyAt already exists:

Return immediately.

Do nothing.

2.

Compute:

readyAt

using server timestamp.

3.

Set

pickupWindowMinutes

=

20

4.

Compute

pickupDeadline

=

readyAt

+

20 minutes

5.

Set

deadlineStatus

=

ACTIVE

6.

Write changes atomically.

Never overwrite existing deadlines.

---

# PHASE 1.3

Admin App

When admin presses:

Ready for Pickup

ONLY update:

status

Nothing else.

Remove all deadline calculations from Flutter.

No DateTime.now()

No timestamp calculations.

No countdown calculations.

Flutter simply updates order status.

---

# PHASE 1.4

Student App

Display:

Ready At

Pickup Before

Remaining Time

Deadline Status

Values come directly from Firestore.

Never calculate deadline.

Only calculate:

Remaining Duration

using

pickupDeadline

-

Current Time

Countdown exists only for UI.

---

# PHASE 1.5

Countdown Widget

Create

pickup_countdown.dart

Responsibilities:

Display remaining time.

Stop automatically when:

Collected

Expired

Widget disposed.

Timer updates every second.

Never writes to Firestore.

Never changes status.

Pure UI component.

---

# PHASE 1.6

Admin Dashboard

Display:

Ready At

Deadline

Remaining Time

Visual status:

Green

>10 minutes

Orange

5-10 minutes

Red

<5 minutes

Grey

Expired

No calculations.

Only UI formatting.

---

# PHASE 1.7

Deadline Service

Create:

PickupDeadlineService

Responsibilities:

Convert Firestore timestamps.

Calculate remaining duration.

Format countdown.

Determine countdown colour.

This service MUST NOT calculate pickupDeadline.

Backend already provides it.

---

# PHASE 1.8

Security

Students

Read:

readyAt

pickupDeadline

deadlineStatus

Cannot modify them.

Admins

Can change:

status

Cannot manually edit:

readyAt

pickupDeadline

pickupWindowMinutes

deadlineStatus

Only Cloud Functions write those fields.

Prepare Firestore Rules accordingly.

---

# PHASE 1.9

Cloud Function Requirements

Must be:

Idempotent.

Running twice produces the same result.

Never overwrite:

readyAt

pickupDeadline

if already present.

Must use:

Firestore server timestamps.

No client timestamps.

---

# PHASE 1.10

Performance

No polling Firestore.

Use one Firestore Stream.

Countdown runs locally.

No writes every second.

Avoid rebuilding entire screens.

---

# PHASE 1.11

Testing

Verify:

✓ Existing ordering still works.

✓ Admin can mark READY.

✓ Cloud Function executes.

✓ readyAt created.

✓ pickupDeadline created.

✓ Student receives updates instantly.

✓ Countdown starts.

✓ Refresh preserves countdown.

✓ Existing orders remain compatible.

✓ No duplicate deadlines.

✓ No regression.

---

# DELIVERABLES

Provide:

1.

Files modified.

2.

Files created.

3.

Firestore schema updates.

4.

Cloud Function implementation.

5.

Firestore Rule changes.

6.

Testing checklist.

Stop after Phase 1.

Do NOT implement:

Distance calculations.

Location permissions.

Automatic strikes.

Scheduled deadline expiry.

Cloud Scheduler.

Those belong to later phases.

---

# Phase Completion Criteria

Phase 1 is complete when:

* App runs successfully.
* No runtime errors occur.
