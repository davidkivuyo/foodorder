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
* Reviews

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

# Rule 6

Limit the amount of comments you put in the code to a strict minimum. You should almost never add comments, except sometimes on non-trivial code, function definitions if the arguments aren't self-explanatory, and class definitions and their members.
Do not remove existing comments unless they are directly related to what you are changing.

---

# Current Phase

# PHASE A — NO-SHOW FOUNDATION

## OBJECTIVE

Implement the foundation for the new CampusBite Pickup Reliability System.

The previous Automatic Strike Engine has been completely removed.

DO NOT recreate the old strike system.

DO NOT implement reliability scores yet.

DO NOT implement ordering restrictions yet.

DO NOT implement automatic penalties yet.

DO NOT implement the new student reliability UI yet.

DO NOT implement the admin reliability dashboard yet.

This phase only establishes a reliable, secure and production-ready way of recording whether an order was:

- COLLECTED
- NO_SHOW

The existing order lifecycle must remain the source of truth.

---

# IMPORTANT EXISTING ORDER LIFECYCLE

CampusBite already has an order lifecycle implemented before the old striking system.

The existing order flow is:

PENDING / PLACED
        ↓
ACCEPTED
        ↓
PREPARING
        ↓
READY
        ↓
COLLECTED

or:

READY
        ↓
NO_SHOW

Do not replace or redesign this lifecycle.

First inspect the existing codebase and identify:

- Order model
- OrderStatus enum
- CartService / OrderService
- Student order screen
- Admin order management
- Firestore order document structure
- Existing Ready status implementation
- Existing pickup countdown implementation
- Existing order status update methods
- Existing Cloud Functions related to orders
- Existing Firestore security rules

Reuse existing architecture whenever possible.

Do not create duplicate order systems.

---

# STEP 1 — AUDIT THE EXISTING ORDER IMPLEMENTATION

Before modifying any code:

1. Inspect the complete order model.
2. Inspect OrderStatus.
3. Inspect how orders are written to Firestore.
4. Inspect how admins change order status.
5. Inspect how students receive order status.
6. Inspect how READY is currently stored.
7. Inspect the existing pickup countdown.
8. Inspect whether pickup deadlines already exist.
9. Inspect any existing no-show implementation.
10. Inspect Firestore Security Rules.
11. Inspect Cloud Functions related to orders.

Do not assume the existing structure.

Base all changes on the actual implementation.

After inspection, document:

- Current order document structure
- Current status values
- Current status transition mechanism
- Current pickup timer implementation
- Existing relevant Firestore paths

---

# STEP 2 — DO NOT REINTRODUCE STRIKES

Search the project for remnants of the old striking system.

Look for:

- strike
- strikes
- strikeCount
- strikeStatus
- banned
- suspension caused by no-show
- automatic strike
- strike engine
- strike threshold
- strike calculation
- strike notification

Determine whether any old code remains.

Remove or isolate obsolete strike logic only if it is directly related to the deleted system.

Do NOT remove unrelated functionality.

Do NOT modify historical order data unnecessarily.

Do not replace "strike" with "reliability" in this phase.

The reliability system belongs to a later phase.

---

# STEP 3 — DEFINE NO-SHOW AS AN ORDER STATE

Add a proper NO_SHOW order status if it does not already exist.

Follow the project's existing naming convention.

For example:

OrderStatus.noShow

Do not introduce multiple names such as:

- no_show
- noShow
- missed
- expired
- abandoned

Use ONE canonical application-level status.

The canonical status should be:

NO_SHOW

unless the existing architecture uses a different established convention.

---

# STEP 4 — PRESERVE COLLECTED AS THE SUCCESSFUL TERMINAL STATE

The system must distinguish:

COLLECTED

from:

NO_SHOW

These are mutually exclusive terminal states.

An order must never be both:

COLLECTED

and

NO_SHOW.

Once an order is COLLECTED:

- It must never become NO_SHOW.
- No no-show processing may affect it.

Once an order is finalized as NO_SHOW:

- It must never later become COLLECTED through the automatic no-show process.

If an admin needs to correct a mistake, that must be an explicit authorized administrative operation handled in a later phase.

---

# STEP 5 — ADD PICKUP TIMESTAMP DATA

Inspect the existing order document first.

If these fields already exist, reuse them.

If they do not exist, add the minimum required timestamps.

Recommended fields:

readyAt
pickupDeadline
collectedAt
noShowAt

Example:

{
  "status": "READY",
  "readyAt": Timestamp,
  "pickupDeadline": Timestamp,
  "collectedAt": null,
  "noShowAt": null
}

Do not duplicate timestamps that already exist under another name.

Use the existing project naming convention if different.

---

# STEP 6 — READY TIMESTAMP

When an order transitions into READY:

record:

readyAt

using a trusted server timestamp.

Do NOT rely on the student's device clock.

Do NOT rely on DateTime.now() from the Flutter client for authoritative deadlines.

The authoritative timestamp must originate from the backend/server wherever possible.

If the current backend architecture already generates this timestamp, reuse it.

---

# STEP 7 — PICKUP DEADLINE

The order needs an authoritative pickup deadline.

The deadline should be calculated from the READY event.

Conceptually:

pickupDeadline =
readyAt + configured pickup duration

For example:

readyAt = 12:00

pickup duration = 20 minutes

pickupDeadline = 12:20

Do not hard-code arbitrary values into multiple files.

Create one configurable source for the pickup duration.

Example:

pickupDurationMinutes

However, do not implement cafe-specific configuration yet unless the existing architecture already supports it.

Use the simplest production-safe approach compatible with the existing order system.

---

# STEP 8 — DO NOT TRUST THE CLIENT CLOCK

The Flutter UI may display the countdown using the device clock for visual purposes.

However:

The client countdown is NOT authoritative.

The backend must determine whether the deadline has actually passed.

Never implement:

if (DateTime.now() > pickupDeadline) {
    markNoShow();
}

as the sole mechanism.

The student's phone clock can be incorrect or manipulated.

The countdown is a UI feature.

The backend timestamp is the source of truth.

---

# STEP 9 — NO-SHOW PROCESSING FOUNDATION

Create the backend-ready mechanism required to transition:

READY → NO_SHOW

SCOPE DECISION — scheduled expiry processing IS part of Phase A.

The scheduled processor already exists in production (`processExpiredPickups`, which runs every 5 minutes) and was in service before this phase. Phase A does not build a scheduler from scratch; it hardens and validates the existing one.

STEP 18 Tests 4–7 and 10, and the STEP 23 validation items "NO_SHOW processing is idempotent" / "COLLECTED cannot become NO_SHOW", are only satisfiable by the real scheduled processor — so the scheduler must remain in Phase A scope.

Current phase: Phase A — NO-SHOW FOUNDATION (stop after Phase A; do not proceed to Phase B).

Affected files:

- functions/index.js — processExpiredPickups + processExpiredOrder
- firestore.rules — order update/transition guards
- test/no_show_foundation_test.dart and functions/test/no_show_integration.test.js

Regression risk: the processor is already deployed, so the only risk is behavioural drift during hardening; mitigated by the idempotent transaction guards and the emulator integration suite.

Deferred to later phases (see STEP 22): reliability scores, restrictions, cooldowns, reliability notifications, dashboards.

The transition must verify:

1. Order exists.
2. Order is currently READY.
3. Pickup deadline exists.
4. Pickup deadline has passed.
5. Order has not already been collected.
6. Order has not already been marked NO_SHOW.

If any condition fails:

Do nothing.

The operation must be idempotent.

Running it twice must not create two no-show events.

---

# STEP 10 — IDEMPOTENCY

This is mandatory.

Suppose the no-show processor runs twice.

First execution:

READY → NO_SHOW

Second execution:

NO_SHOW → NO_SHOW

The second execution must have no additional effect.

It must NOT:

- create another no-show
- increment a counter
- send duplicate notifications
- update reliability twice
- create duplicate audit records

Reliability calculations and notifications will be implemented later.

---

# STEP 11 — COLLECTED MUST ALWAYS WIN

Before marking an order NO_SHOW, verify the current server-side order state.

Example:

Processor starts:

READY

Student collects order:

COLLECTED

Processor attempts:

NO_SHOW

The processor must detect:

current status = COLLECTED

and abort the no-show transition.

Never overwrite:

COLLECTED → NO_SHOW

---

# STEP 12 — FIRESTORE WRITE STRATEGY

Keep Firestore operations minimal.

Do not perform unnecessary reads.

Prefer a transaction or another atomic server-side mechanism where appropriate.

The no-show operation should not:

- read the entire user's order history
- calculate reliability
- update the user profile
- write strike information
- generate analytics documents

Those belong to later phases.

For Phase A, only update the affected order.

---

# STEP 13 — ORDER DATA AFTER NO-SHOW

When an order is legitimately marked NO_SHOW:

update only the necessary fields.

For example:

status: NO_SHOW
noShowAt: server timestamp

Preserve:

orderId
studentId
items
totalAmount
cafe
createdAt
readyAt
pickupDeadline

Do not delete the order.

Historical order information is important for later reliability calculations and cafe analytics.

---

# STEP 14 — SECURITY RULES

Review Firestore rules.

Students must NOT be able to arbitrarily set:

status = NO_SHOW

Students must NOT be able to modify:

readyAt
pickupDeadline
noShowAt
collectedAt

unless the existing architecture explicitly requires a safe student-owned operation.

The backend/admin workflow must control authoritative status transitions.

Students should still be able to READ their own order.

Admins should be able to READ orders belonging to cafes they are authorized to manage.

Do not use:

allow read, write: if request.auth != null;

for order documents.

Do not weaken existing security rules.

---

# STEP 15 — ADMIN STATUS TRANSITIONS

Review the admin application.

Admins should continue to be able to perform the existing legitimate transitions:

ACCEPTED
PREPARING
READY
COLLECTED

Do not remove existing functionality.

For NO_SHOW:

Do not add arbitrary "Mark No-show" functionality unless the existing product design already requires it.

Phase A should establish the backend foundation.

The automatic processing engine is part of Phase A (see STEP 9); only the admin "Mark No-show" UI decision is deferred to later phases.

---

# STEP 16 — DATA CONSISTENCY

Ensure these states cannot create contradictory data.

Valid examples:

READY
readyAt = timestamp
pickupDeadline = timestamp
collectedAt = null
noShowAt = null

COLLECTED
readyAt = timestamp
pickupDeadline = timestamp
collectedAt = timestamp
noShowAt = null

NO_SHOW
readyAt = timestamp
pickupDeadline = timestamp
collectedAt = null
noShowAt = timestamp

Invalid:

NO_SHOW + collectedAt != null

COLLECTED + noShowAt != null

READY + collectedAt != null

READY + noShowAt != null

If the existing database contains legacy inconsistent data, do not silently rewrite it.

Report it.

---

# STEP 17 — TIMEZONE HANDLING

Store timestamps using Firestore Timestamp / UTC-compatible server timestamps.

Do not store local formatted strings as authoritative timestamps.

The UI may display local Tanzania time or the user's local time.

The database should remain timezone-safe.

Do not compare formatted date strings.

---

# STEP 18 — TESTING

Create or update tests for the following.

## Test 1 — Ready

Order changes:

PREPARING → READY

Verify:

readyAt exists.

---

## Test 2 — Pickup deadline

Verify:

pickupDeadline exists.

Verify it is based on the authoritative ready timestamp.

---

## Test 3 — Successful collection

READY → COLLECTED

Verify:

collectedAt exists.

noShowAt remains null.

---

## Test 4 — Valid no-show

READY

+

deadline passed

+

not collected

↓

NO_SHOW

Verify:

noShowAt exists.

---

## Test 5 — Not yet expired

READY

+

deadline has not passed

↓

must remain READY.

---

## Test 6 — Already collected

COLLECTED

+

deadline passed

↓

must remain COLLECTED.

---

## Test 7 — Already no-show

NO_SHOW

↓

second processing attempt must do nothing.

---

## Test 8 — Student manipulation

Attempt to modify:

status = NO_SHOW

from the student client.

Expected:

PERMISSION_DENIED.

---

## Test 9 — Timestamp manipulation

Attempt to modify:

pickupDeadline

from the student client.

Expected:

PERMISSION_DENIED.

---

## Test 10 — Concurrent collection/no-show

Simulate:

student collection

and

no-show processing

occurring near the same time.

Verify that the final database state cannot become contradictory.

---

# STEP 19 — UI

Do NOT implement the new reliability UI in Phase A.

Only make the minimum UI changes necessary to correctly display:

NO_SHOW

if the application currently displays order statuses.

Use the existing visual design system.

Do not redesign the account screen.

Do not add reliability cards.

Do not add scores.

Do not add warnings.

Those belong to later phases.

---

# STEP 20 — FIRESTORE COST REQUIREMENTS

This phase must not introduce:

- polling loops
- repeated Firestore reads
- per-second Firestore writes
- client-side countdown writes
- reliability recalculation on every screen open
- background listeners that are not necessary

The countdown must remain a local UI calculation based on the stored authoritative timestamps.

Firestore should only be accessed when the order state actually needs to change.

---

# STEP 21 — LOGGING

Add useful development logging.

Example:

[OrderLifecycle] Order marked READY

[OrderLifecycle] Pickup deadline created

[OrderLifecycle] Order marked COLLECTED

[OrderLifecycle] Order eligible for NO_SHOW

[OrderLifecycle] Order marked NO_SHOW

Do not log:

- student email
- phone number
- exact location
- authentication tokens
- notification tokens

Avoid excessive production logging.

---

# STEP 22 — DO NOT IMPLEMENT FUTURE PHASES

Do NOT implement:

❌ Reliability score

❌ Collection ratio

❌ Recent-order weighting

❌ Restrictions

❌ Ordering cooldown

❌ Student reliability dashboard

❌ Reliability notifications

❌ Admin reliability dashboard

❌ Food rescue system

❌ Food waste analytics

❌ Rewards

❌ Recovery algorithm

❌ Automatic suspension

❌ Strikes

These will be implemented separately.

---

# STEP 23 — FINAL VALIDATION

Before declaring Phase A complete:

Verify:

✓ Old strike engine remains removed.

✓ Order lifecycle still works.

✓ READY remains functional.

✓ COLLECTED remains functional.

✓ NO_SHOW exists as a distinct state.

✓ Ready timestamp is authoritative.

✓ Pickup deadline is authoritative.

✓ Client cannot manipulate no-show state.

✓ Client cannot manipulate authoritative timestamps.

✓ NO_SHOW processing is idempotent.

✓ COLLECTED cannot become NO_SHOW.

✓ Historical order data remains preserved.

✓ No unnecessary Firestore reads/writes were introduced.

✓ Existing student UI still works.

✓ Existing admin UI still works.

✓ Existing notifications are not broken.

✓ Existing order history remains compatible.

---

# REQUIRED FINAL REPORT

When finished, provide:

1. Files inspected.

2. Files modified.

3. Files created.

4. Existing order lifecycle discovered.

5. Existing Firestore order structure.

6. Changes made to OrderStatus.

7. Changes made to order timestamps.

8. Changes made to Firestore rules.

9. Backend/no-show transition mechanism.

10. Firestore read/write impact.

11. Tests performed.

12. Any legacy strike-engine code discovered.

13. Any database inconsistencies discovered.

14. Any risks or remaining work.

IMPORTANT:

Do not proceed to Phase B.

Stop after Phase A and wait for further instructions.

---

# Phase Completion Criteria

Phase A is complete when:

* The new features works well with past features.
* App runs successfully.
* No runtime errors occur.
