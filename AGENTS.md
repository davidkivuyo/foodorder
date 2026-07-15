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

PHASE 6

# TASK

Implement Phase 6 of CampusBite.

This phase introduces automatic pickup deadline enforcement and the automatic strike engine.

The implementation must be production-ready.

The implementation must prioritise:

• Data consistency

• Privacy

• Minimal Firestore reads

• Minimal Firestore writes

• Minimal Cloud Function executions

Also now Instead of storing strikePercentage in Firestore, store only:

strikeCount

accountStatus

Then derive the percentage in the app:

final strikePercentage = strikeCount * 50;

This will have several advantages:

It eliminates one field that can become inconsistent.

It reduces writes because only strikeCount changes.

It simplifies transactions.

It ensures there's a single source of truth.

Your UI can still display:

Strike 1 → 50%

Strike 2 → 100%

Do not modify completed features.

Do not introduce unnecessary complexity.

---

# OBJECTIVE

When a student fails to collect an order before the pickup deadline:

Automatically:

1.

Mark the order as:

NO_SHOW

2.

Issue exactly one strike.

3.

Update the student's strike information.

4.

Suspend the account after two strikes.

5.

Create an immutable audit log.

The entire operation must be atomic.

No partial updates are allowed.

---

# EXISTING FEATURES

Already completed:

✓ Student App

✓ Cafe Admin App

✓ Authentication

✓ Food CRUD

✓ Cart

✓ Orders

✓ Ready workflow

✓ Pickup deadline calculation

✓ Distance-aware pickup windows

✓ Strike UI

✓ Admin pardon

Do not modify these features.

---

# ARCHITECTURE

Use ONE scheduled Cloud Function.

Schedule:

Every 5 minutes.

No additional scheduled functions.

No polling clients.

No listeners.

---

# QUERY

Each execution should query ONLY:

orders

WHERE

status == READY

AND

deadlineStatus == ACTIVE

AND

pickupDeadline <= current server time

This query must use Firestore composite indexes.

Never scan the entire orders collection.

---

# PROCESSING

For every expired order:

Run ONE Firestore transaction.

Do NOT use independent writes.

Do NOT update the order before updating the user.

Everything must succeed together.

If anything fails:

Nothing should be committed.

---

# TRANSACTION STEPS

Inside the transaction:

Step 1

Read the order document.

Immediately verify:

status == READY

deadlineStatus == ACTIVE

strikeProcessed == false

If any condition fails:

Abort immediately.

Do nothing.

---

Step 2

Read ONLY:

users/{studentId}

No other reads.

Do NOT read:

food_items

cafes

notifications

cart

Everything required already exists.

---

Step 3

Calculate:

newStrikeCount

Never exceed:

2

Calculate:

strikePercentage = strikeCount × 50

Determine:

accountStatus

Rules:

0

ACTIVE

1

ACTIVE

WARNING shown in UI

2

SUSPENDED

---

Step 4

Update order.

Fields:

status = NO_SHOW

deadlineStatus = EXPIRED

expiredAt = server timestamp

strikeProcessed = true

strikeIssuedAt = server timestamp

updatedAt = server timestamp

Nothing else.

Never rewrite:

items

pickupDeadline

distanceMeters

pickupWindowMinutes

price

student information

---

Step 5

Update user.

Fields:

strikeCount

strikePercentage

accountStatus

updatedAt

Nothing else.

---

Step 6

Create one audit log.

Collection:

audit_logs

Fields:

action = automatic_no_show

orderId

studentId

previousStrikeCount

newStrikeCount

performedBy = system

timestamp

reason = pickup_deadline_expired

The audit log must never be modified afterwards.

---

Step 7

Commit transaction.

Everything succeeds together.

If one write fails:

Everything rolls back automatically.

---

# IDEMPOTENCY

The implementation must be completely idempotent.

Running the scheduled function multiple times must never:

Issue two strikes.

Suspend twice.

Duplicate audit logs.

Use:

strikeProcessed

as the processing lock.

If:

strikeProcessed == true

Exit immediately.

---

# FIRESTORE READ OPTIMISATION

Target:

One query

↓

One order read

↓

One user read

↓

Transaction

↓

Commit

Nothing else.

Never query users collection.

Never query orders collection twice.

Never perform nested queries.

---

# FIRESTORE WRITE OPTIMISATION

Transaction updates:

One order

One user

One audit log

Only changed fields.

Never overwrite unchanged values.

---

# STUDENT APP

When order changes to:

NO_SHOW

Display:

Order Expired

Strike Issued

If strikeCount == 1

Display:

Warning

50%

If strikeCount == 2

Display:

Account Suspended

Disable:

Place Order

Students may still:

Browse food

View previous orders

View strikes

Log out

---

# ADMIN APP

Admins should immediately see:

NO_SHOW badge

Strike issued

Strike count

Suspended status

Admins may:

Pardon students

Remove strikes

Restore account

Do not change existing pardon workflow.

---

# PARDON

Existing pardon feature remains.

Decrease:

strikeCount

Never below zero.

Automatically recalculate:

strikePercentage

Automatically restore:

accountStatus = ACTIVE

when strikeCount < 2.

Create:

audit_logs

action = admin_pardon

---

# SECURITY

Students cannot modify:

status

deadlineStatus

strikeProcessed

strikeCount

strikePercentage

accountStatus

expiredAt

strikeIssuedAt

Admins cannot manually issue strikes.

Only backend may issue strikes.

Admins may only pardon.

---

# PERFORMANCE TARGET

The entire backend should process each expired order using:

One transaction

One order read

One user read

One commit

Zero duplicate writes

Zero unnecessary reads

Zero repeated calculations

The complexity must remain:

O(1)

per expired order.

---

# ERROR HANDLING

If one order fails:

Log the error.

Continue processing remaining expired orders.

One failed transaction must never stop processing of other expired orders.

---

# CODE QUALITY

Create:

automatic_strike_service.dart

Responsibilities:

Detect expired order

Validate processing state

Run Firestore transaction

Issue strike

Suspend account

Create audit log

Avoid duplicated business logic.

Widgets must contain no strike logic.

Reuse existing models and services.

---

# TESTING

Verify:

✓ Countdown reaches zero.

✓ Order automatically becomes NO_SHOW.

✓ First NO_SHOW issues one strike.

✓ Second NO_SHOW suspends account.

✓ Transaction rolls back correctly on failure.

✓ Duplicate executions never duplicate strikes.

✓ Audit log created.

✓ Existing countdown unchanged.

✓ Existing ordering unchanged.

✓ Existing pickup deadlines unchanged.

✓ Existing admin workflow unchanged.

✓ Existing cart unchanged.

✓ Existing notifications unchanged.

---

# DELIVERABLES

Provide:

1. Files modified.

2. Cloud Function implementation.

3. Transaction flow explanation.

4. Firestore rule updates.

5. Required Firestore indexes.

6. Testing checklist.

Stop after completing Phase 6.

Do not implement future phases.

Do not refactor unrelated code.

Maintain backwards compatibility.

---

# Phase Completion Criteria

Phase 6 is complete when:

* the new features works well with past features.
* App runs successfully.
* No runtime errors occur.
