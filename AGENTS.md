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

# Implement Student Strike Management System (Phase 1)

## Project Context

This repository contains the CampusBite ecosystem.

There are two Flutter applications:

1. CampusBite Student App
2. CampusBite Cafe Admin App

Both applications already use:

- Firebase Authentication
- Cloud Firestore
- Firebase Cloud Functions
- Shared Firestore backend

The codebase is already stable.

Your responsibility is to ADD the strike management feature WITHOUT breaking existing functionality.

---

# CRITICAL RULES

DO NOT refactor unrelated code.

DO NOT rename existing classes.

DO NOT change existing Firestore collections unless instructed.

DO NOT modify authentication flow.

DO NOT modify ordering flow.

DO NOT modify cart flow.

DO NOT modify notifications.

DO NOT change UI outside the required screens.

DO NOT introduce breaking changes.

If an existing service can be extended, extend it.

Every step must compile successfully before moving to the next.

Keep commits small and isolated.

---

# FEATURE GOAL

Implement a strike management system.

Students receive strikes when they fail to collect orders.

This phase only implements MANUAL strike management.

Automatic strike assignment will be implemented later.

---

# STRIKE MODEL

Use percentage-based strikes.

Allowed values:

0%

50%

100%

Rules:

0%

Active

50%

Warning

100%

Suspended

Never allow:

25%

30%

70%

Any other values.

---

# FIRESTORE

Extend the existing users collection.

Add only the following fields:

strikePercentage

strikeCount

accountStatus

lastStrikeAt

lastPardonAt

updatedAt

Do not remove existing fields.

Do not rename existing fields.

---

# STUDENT APP(customerview)

Account Screen

Display a Strike Status Card.

Position:

Top right.

Immediately below the AppBar.

The widget must be reusable.

Create:

lib/widgets/strike_status_card.dart

The card displays:

Strike Percentage

Account Status

Examples:

🟢 Active

0%

🟠 Warning

50%

🔴 Suspended

100%

The card must update automatically using Firestore streams.

No manual refresh.

---

# ADMIN APP(adminview)

Create Student Strike Management.

Admins can:

Search students

Open a student profile

View:

Name

Email

Strike Percentage

Account Status

Buttons:

Issue Strike (+50%)

Pardon (-50%)

Reset Strikes (0%)

Suspend Account

Reactivate Account

Each action requires a confirmation dialog.

Never execute destructive actions immediately.

---

# BUSINESS LOGIC

Create:

StrikeService

Responsibilities:

issueStrike()

pardonStrike()

resetStrike()

suspendAccount()

reactivateAccount()

calculateAccountStatus()

Business logic must NOT exist inside Widgets.

---

# STRIKE RULES

Issue Strike

0 → 50

50 → 100

100 → 100

Pardon

100 → 50

50 → 0

0 → 0

Reset

Always → 0

Account status:

0 → ACTIVE

50 → ACTIVE

100 → SUSPENDED

---

# AUDIT LOGGING

Create:

audit_logs

Each strike action creates a document.

Fields:

studentId

adminId

action

previousStrike

newStrike

reason

timestamp

Allowed actions:

ISSUE_STRIKE

PARDON

RESET

SUSPEND

REACTIVATE

Audit logs must never be edited or deleted.

---

# SECURITY

Students:

Can read only their own strike status.

Cannot modify:

strikePercentage

strikeCount

accountStatus

Audit logs

Admins:

Can update strike information.

Prepare the architecture so Cloud Functions can replace manual updates later.

---

# FIRESTORE RULES

Update Firestore rules accordingly.

Students:

Read only their own user document.

Admins:

Read all users.

Update strike fields.

Audit logs:

Read/write admins only.

Delete never allowed.

---

# UI REQUIREMENTS

Student App:

Strike card updates live.

Admin App:

Student list updates live.

Use Firestore Streams.

---

# PERFORMANCE

Avoid unnecessary reads.

Avoid duplicate listeners.

Avoid rebuilding the entire Account screen.

Reuse existing services whenever possible.

---

# TESTING

After implementation verify:

✓ Student login still works

✓ Admin login still works

✓ Existing menu loads

✓ Cart still works

✓ Orders still work

✓ Notifications still work

✓ Strike card updates correctly

✓ Admin actions work correctly

✓ No regression in existing features

---

# DELIVERABLES

Provide:

1. List of modified files.

2. List of newly created files.

3. Firestore schema changes.

4. a recommended Firestore security rules(current rules are in firestore.rules inside customerview app).

5. Summary of implementation.

6. Manual testing checklist.

Do NOT continue to Phase 2 (automatic strikes or distance-based pickup).

Stop after completing this phase and run changes review by coderabbit review.

---

# Phase Completion Criteria

Phase 1 is complete when:

* App runs successfully.
* No runtime errors occur.
