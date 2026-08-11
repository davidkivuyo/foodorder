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

# Phase B.2 — PICKUP RELIABILITY CALCULATION

## OBJECTIVE

Implement Phase B.2 of the CampusBite Pickup Reliability System.

Phase A has already established the authoritative order-level foundation for:

- READY
- COLLECTED
- NO_SHOW
- readyAt
- pickupDeadline
- collectedAt
- noShowAt

The old Automatic Strike Engine has been completely removed.

This phase replaces the old strike concept with a non-punitive:

# PICKUP RELIABILITY SYSTEM

The purpose of this phase is to measure how consistently a student collects their food.

The system must:

1. Track eligible pickup orders.
2. Track collected orders.
3. Track no-show orders.
4. Calculate lifetime collection performance.
5. Track recent pickup performance.
6. Calculate a reliability score.
7. Store the calculated summary efficiently.
8. Allow the student to read their reliability information.
9. Prevent the student from modifying reliability data.
10. Avoid unnecessary Firestore reads and writes.

DO NOT implement account suspension in this phase.

DO NOT implement ordering restrictions in this phase.

DO NOT implement ordering cooldowns.

DO NOT implement strikes.

DO NOT implement automatic bans.

DO NOT implement aggressive penalties.

Those belong to later phases.

---

# 1. FIRST — AUDIT PHASE A

Before writing code, inspect the implementation from Phase A.

Confirm the actual existing:

- Order model
- OrderStatus
- Firestore order path
- student UID field
- READY state
- COLLECTED state
- NO_SHOW state
- readyAt
- pickupDeadline
- collectedAt
- noShowAt
- order creation logic
- admin order processing
- backend order processing
- Firestore security rules

Do NOT assume field names.

Use the actual implementation.

If Phase A uses different field names, preserve those names.

Do not create duplicate fields.

---

# 2. IMPORTANT DEFINITION — ELIGIBLE ORDER

An order becomes an eligible pickup event only when it reaches:

COLLECTED

or:

NO_SHOW

An order that is:

- cancelled before pickup
- rejected by cafe
- cancelled by cafe
- failed before READY
- never accepted
- otherwise legitimately cancelled

must NOT count as a failed pickup.

Do not count every order placed as an eligible order.

The reliability system measures:

"Did the student successfully collect an order that was actually prepared and made available for pickup?"

---

# 3. CORE METRICS

Maintain the following metrics:

eligibleOrders

collectedOrders

noShowOrders

collectionRate

recentEligibleOrders

recentCollectedOrders

recentNoShowOrders

recentCollectionRate

reliabilityScore

reliabilityStatus

Use the project's existing naming convention if different.

---

# 4. LIFETIME COLLECTION RATE

Calculate:

collectionRate =
(collectedOrders / eligibleOrders) × 100

Example:

eligibleOrders = 10

collectedOrders = 8

noShowOrders = 2

collectionRate = 80%

Handle zero correctly.

If:

eligibleOrders = 0

then:

collectionRate = 100

and the student should have a neutral/new-user state rather than being considered unreliable.

Do NOT produce NaN.

Do NOT divide by zero.

---

# 5. RECENT PICKUP PERFORMANCE

Do not rely exclusively on lifetime history.

The system must also maintain recent performance.

Use the student's most recent 10 eligible pickup orders as the initial recent window.

IMPORTANT:

Only eligible terminal pickup events count.

Therefore:

COLLECTED = recent success

NO_SHOW = recent failure

Cancelled orders do not enter the recent window.

---

# 6. RECENT COLLECTION RATE

Calculate:

recentCollectionRate =
recentCollectedOrders / recentEligibleOrders × 100

If there are no recent eligible orders:

recentCollectionRate should not incorrectly become 0.

Treat it as neutral.

Do not punish a new user because they have insufficient history.

---

# 7. RELIABILITY SCORE

Use the recommended weighted model:

70% lifetime performance

30% recent performance

Conceptually:

reliabilityScore =
(lifetimeCollectionRate × 0.70) +
(recentCollectionRate × 0.30)

However, when there is insufficient history, avoid creating misleading scores.

For a completely new user:

eligibleOrders = 0

The user should be considered:

NEW

rather than:

0%

Do not display:

"0% reliability"

to someone who has never missed an order.

---

# 8. MINIMUM HISTORY RULE

Do not allow one or two orders to produce aggressive conclusions.

Use the following interpretation:

0 eligible orders:
NEW

1–2 eligible orders:
INSUFFICIENT_HISTORY

3+ eligible orders:
Calculate normal reliability status

Do not introduce restrictions based on this status.

This phase is measurement only.

---

# 9. RELIABILITY STATUS

Create a simple status classification.

Recommended thresholds:

90–100:
EXCELLENT

75–89:
GOOD

50–74:
NEEDS_IMPROVEMENT

25–49:
POOR

0–24:
CRITICAL

For users with:

0 eligible orders:

NEW

For:

1–2 eligible orders:

INSUFFICIENT_HISTORY

Do not attach punishment to these statuses.

They are informational only.

---

# 10. IMPORTANT — NO AUTOMATIC PUNISHMENT

This phase must NOT perform any of the following:

- suspension
- banning
- strike creation
- account disabling
- ordering cooldown
- order limit
- checkout blocking
- forced confirmation
- automatic admin escalation

The reliability score is only a measurement at this stage.

---

# 11. FIRESTORE DATA DESIGN

Use the existing student user document if appropriate.

Recommended structure:

users/{uid}

pickupReliability: {
    eligibleOrders: 0,
    collectedOrders: 0,
    noShowOrders: 0,

    collectionRate: 100,

    recentEligibleOrders: 0,
    recentCollectedOrders: 0,
    recentNoShowOrders: 0,

    recentCollectionRate: 100,

    reliabilityScore: 100,

    status: "NEW",

    updatedAt: Timestamp
}

Adapt this structure to the existing CampusBite user schema.

Do not overwrite unrelated user fields.

Use a nested map rather than creating multiple unnecessary documents unless the existing architecture has a strong reason for a separate collection.

---

# 12. DO NOT CALCULATE BY READING ALL ORDERS ON EVERY SCREEN

This is a critical performance requirement.

DO NOT implement:

Student opens Account screen
    ↓
Query all orders
    ↓
Count collected
    ↓
Count no-show
    ↓
Calculate reliability

This will become increasingly expensive.

Instead:

Order becomes COLLECTED
    ↓
Update reliability summary

Order becomes NO_SHOW
    ↓
Update reliability summary

Account screen
    ↓
Read user reliability summary

The account screen should require approximately one existing user-document read rather than querying the entire order history.

---

# 13. EVENT-DRIVEN UPDATES

Reliability should be updated only when an eligible order reaches a terminal pickup state.

Eligible events:

COLLECTED

NO_SHOW

Do not update reliability when:

PENDING

ACCEPTED

PREPARING

READY

Do not write reliability every time the countdown changes.

Do not write reliability every second.

---

# 14. ATOMICITY

Reliability updates must be safe against duplicate processing.

Suppose the same NO_SHOW event is accidentally processed twice.

The system must NOT produce:

noShowOrders + 2

when there was only one actual no-show.

Likewise, one COLLECTED order must increase:

collectedOrders

by exactly one.

Use an appropriate server-side transaction or idempotent event-processing mechanism.

Do not trust the Flutter client to perform the authoritative reliability update.

---

# 15. SERVER-SIDE AUTHORITY

The student application must never be allowed to write:

pickupReliability

directly.

The student can READ their own reliability summary.

The backend should be responsible for updating it.

Conceptually:

Student:
    READ own reliability = YES
    WRITE reliability = NO

Backend:
    UPDATE reliability = YES

Admin:
    READ authorized reliability = YES

Admin modification:
    NOT direct arbitrary client write

Admin override functionality will be implemented in a later phase.

---

# 16. PREVENT CLIENT MANIPULATION

A malicious client must not be able to send:

{
  "pickupReliability": {
      "eligibleOrders": 1000,
      "collectedOrders": 1000,
      "reliabilityScore": 100
  }
}

and overwrite their actual reliability.

Update Firestore rules accordingly.

Do not weaken the existing user security rules.

Preserve:

users/{userId}

ownership protection.

---

# 17. RECENT HISTORY STORAGE

Do not query the entire order collection every time reliability changes.

Use a small server-maintained recent-history representation.

Recommended conceptual structure:

recentPickupHistory: [
    {
        orderId: "...",
        outcome: "COLLECTED",
        timestamp: Timestamp
    },
    {
        orderId: "...",
        outcome: "NO_SHOW",
        timestamp: Timestamp
    }
]

Maximum:

10 entries.

When a new eligible event occurs:

1. Add the new outcome.
2. Remove entries beyond the latest 10.
3. Recalculate recent counts.
4. Recalculate recent rate.
5. Recalculate reliability score.
6. Update the summary.

Do not allow unbounded history inside the user document.

---

# 18. IMPORTANT — DUPLICATE ORDER PROTECTION

The same order must never appear twice in recentPickupHistory.

Before adding an event, verify that its orderId is not already present.

If the event was already processed:

Do nothing.

This is required for reliability correctness.

---

# 19. PREFERRED EVENT MODEL

If the existing backend architecture supports it, use the order's terminal state transition as the trigger.

Conceptually:

ORDER UPDATE

READY → COLLECTED

or:

READY → NO_SHOW

then:

Reliability Processor
        ↓
Validate transition
        ↓
Check whether already processed
        ↓
Update reliability

Do not trigger reliability calculations merely because an order document was edited.

Only process genuine terminal pickup outcomes.

---

# 20. PROCESSING METADATA

If necessary, maintain a small processing marker on the order.

For example:

reliabilityProcessed: true

or another equivalent mechanism compatible with the architecture.

Do not add redundant markers if the existing transaction/state transition already guarantees idempotency.

Choose the simplest reliable mechanism.

---

# 21. TRANSACTION SAFETY

The reliability update should be atomic with respect to concurrent events.

Consider this scenario:

Student has:

eligibleOrders = 10
collectedOrders = 8

Two orders become terminal simultaneously:

Order A = COLLECTED
Order B = NO_SHOW

The final state must be:

eligibleOrders = 12
collectedOrders = 9
noShowOrders = 3

Not:

eligibleOrders = 11

and not:

collectedOrders = 8

Avoid race conditions.

Use Firestore transactions or another server-side atomic mechanism where appropriate.

---

# 22. CALCULATION PRECISION

Keep stored reliability values predictable.

For example:

collectionRate:
0–100

recentCollectionRate:
0–100

reliabilityScore:
0–100

Round the displayed score to a sensible precision.

For example:

82.6%

Do not repeatedly round intermediate calculations if it causes cumulative errors.

---

# 23. NEW USER BEHAVIOR

A user with:

eligibleOrders = 0

should have:

status = NEW

Do not tell them:

"Your reliability is 0%."

Instead the UI can later display:

"Build your pickup record by collecting your orders on time."

The UI implementation belongs to a later phase.

---

# 24. INSUFFICIENT HISTORY

For:

1–2 eligible orders

set:

status = INSUFFICIENT_HISTORY

Continue calculating the raw metrics.

But do not apply any restriction.

Example:

1 eligible
1 collected

collectionRate = 100%

status = INSUFFICIENT_HISTORY

This means:

"Not enough history to classify behavior."

---

# 25. EXAMPLE CALCULATIONS

## Example A — New user

eligible = 0
collected = 0
noShow = 0

status = NEW

---

## Example B — One successful order

eligible = 1
collected = 1
noShow = 0

collectionRate = 100%

status = INSUFFICIENT_HISTORY

---

## Example C — Two no-shows

eligible = 5
collected = 3
noShow = 2

collectionRate = 60%

Recent history:

COLLECTED
COLLECTED
NO_SHOW
COLLECTED
NO_SHOW

recentRate = 60%

score:

60 × 0.70 + 60 × 0.30 = 60

status:

NEEDS_IMPROVEMENT

No punishment.

---

## Example D — Historically reliable, recent decline

Lifetime:

50 eligible
47 collected
3 no-show

lifetimeRate = 94%

Recent 10:

6 collected
4 no-show

recentRate = 60%

score:

94 × 0.70 + 60 × 0.30
= 83.8

status:

GOOD

This demonstrates why the recent component exists.

---

## Example E — Historically poor, recovering

Lifetime:

20 eligible
10 collected
10 no-show

lifetimeRate = 50%

Recent 10:

8 collected
2 no-show

recentRate = 80%

score:

50 × 0.70 + 80 × 0.30
= 59

status:

NEEDS_IMPROVEMENT

The student is improving, but lifetime history still matters.

---

# 26. ADMIN EXCUSED NO-SHOW COMPATIBILITY

Phase B.2 must be designed so a future admin "Excuse No-show" feature can correct the reliability calculation.

Do not permanently bake a no-show into an irreversible counter architecture.

If a future phase changes:

NO_SHOW → EXCUSED

the reliability system must be capable of recalculating the affected statistics.

Do not implement the admin pardon feature yet.

Only make sure the data model does not make future correction impossible.

---

# 27. DATA PRIVACY

Do not expose reliability information publicly.

A student's:

* reliability score
* collection rate
* no-show count
* recent pickup history

must not be publicly readable.

Only:

* the student
* authorized backend services
* appropriately authorized cafe admins

should have access according to the product requirements.

Do not place reliability information inside public food documents.

---

# 28. DO NOT STORE UNNECESSARY PERSONAL DATA

The reliability system should use:

uid
orderId
outcome
timestamps
aggregated counters

Do not copy:

* student email
* phone number
* physical location
* device identifiers
* FCM token

into reliability records.

---

# 29. PERFORMANCE REQUIREMENTS

The implementation must remain efficient for a large student population.

Avoid:

* full order-history scans
* collection-group scans per login
* periodic polling
* per-minute reliability writes
* per-second Firestore writes
* client-side reliability calculation
* redundant listeners

Reliability updates should be event-driven.

---

# 30. STUDENT ACCOUNT SCREEN

Do not redesign the account screen yet.

Only expose the reliability data through the existing user model/service if necessary so that a future UI phase can consume:

reliabilityScore

status

collectionRate

collectedOrders

noShowOrders

Do not add visual cards or warnings yet.

---

# 31. ADMIN APPLICATION

Do not create the admin reliability dashboard yet.

However, ensure the backend data model can later support authorized admin reads.

Do not expose all students' reliability data to every authenticated user.

---

# 32. NOTIFICATIONS

Do NOT implement reliability notifications in Phase B.2.

No:

"Your reliability decreased."

No:

"Your reliability improved."

No:

"Your account is at risk."

Notifications will be handled separately.

---

# 33. TESTING REQUIREMENTS

Create automated tests for all of the following.

## Test 1 — New user

0 eligible orders

Expected:

status = NEW

---

## Test 2 — First collection

1 eligible
1 collected

Expected:

collectionRate = 100

status = INSUFFICIENT_HISTORY

---

## Test 3 — No-show

1 eligible
0 collected
1 no-show

Expected:

collectionRate = 0

status = INSUFFICIENT_HISTORY

No restriction.

---

## Test 4 — Normal ratio

10 eligible
8 collected
2 no-show

Expected:

collectionRate = 80

---

## Test 5 — Recent history

Verify only the latest 10 eligible outcomes are included.

---

## Test 6 — Old orders

Verify orders older than the recent 10 are not included in recentCollectionRate.

They must still remain represented by lifetime counters.

---

## Test 7 — Duplicate processing

Process the same order twice.

Expected:

eligibleOrders increases only once.

---

## Test 8 — Concurrent events

Process a COLLECTED and NO_SHOW event concurrently.

Expected:

both are reflected exactly once.

---

## Test 9 — Cancelled order

Cancelled order must not affect reliability.

---

## Test 10 — READY order

READY order must not affect reliability.

---

## Test 11 — Student write attack

Attempt to modify:

pickupReliability

from the client.

Expected:

PERMISSION_DENIED.

---

## Test 12 — Recent history limit

Insert more than 10 eligible events.

Expected:

only the newest 10 remain in recentPickupHistory.

---

## Test 13 — Score calculation

Verify:

score =
70% lifetime +
30% recent

using several known datasets.

---

## Test 14 — Zero division

eligible = 0

Expected:

no NaN
no Infinity
status = NEW

---

# 34. FIRESTORE COST AUDIT

Before finishing the phase, inspect every new Firestore operation.

For each read/write explain:

WHY is it necessary?

Remove any operation that isn't required.

The preferred pattern is:

COLLECTED/NO_SHOW event
↓
one server-side reliability update
↓
student account reads existing summary

Do not add a new Firestore listener solely for reliability if the existing user listener already supplies the user document.

---

# 35. BACKWARD COMPATIBILITY

Do not break:

* student authentication
* student account
* cart
* ordering
* admin ordering
* order history
* food menu
* notifications
* Firebase Auth
* existing order lifecycle

Do not modify unrelated collections.

Do not migrate all existing historical orders unless absolutely necessary.

If historical orders must be considered, first determine whether their data is sufficient to classify:

COLLECTED
NO_SHOW

If not, do not guess.

---

# 36. MIGRATION STRATEGY

If users already have historical orders from before Phase B.2:

Do NOT blindly calculate reliability from every historical order.

First determine which orders have a trustworthy terminal state.

Only count:

COLLECTED

and:

NO_SHOW

that can be confidently identified.

If historical data is ambiguous, report it.

Do not fabricate reliability statistics.

A safe initial state may be:

eligibleOrders = 0
status = NEW

for users whose historical data cannot be reliably reconstructed.

---

# 37. LOGGING

Use concise development logs such as:

[PickupReliability] Processing collected order: ORDER_ID

[PickupReliability] Processing no-show order: ORDER_ID

[PickupReliability] Updated user reliability

Do NOT log:

* email
* phone number
* location
* auth token
* FCM token
* sensitive personal information

Do not flood production logs.

---

# 38. SECURITY REVIEW

Before declaring Phase B.2 complete, verify:

✓ Student cannot modify reliability.

✓ Student cannot modify lifetime counters.

✓ Student cannot modify recent history.

✓ Student cannot modify score.

✓ Student can read only their own reliability.

✓ Admin access follows existing cafe authorization.

✓ Backend has authoritative update capability.

✓ No public food document exposes reliability.

✓ No sensitive personal information is duplicated.

---

# 39. FINAL VALIDATION

Phase B.2 is complete only when:

✓ Lifetime eligible count works.

✓ Lifetime collected count works.

✓ Lifetime no-show count works.

✓ Lifetime collection rate works.

✓ Recent 10-event history works.

✓ Recent collection rate works.

✓ Weighted reliability score works.

✓ Reliability status classification works.

✓ NEW state works.

✓ INSUFFICIENT_HISTORY state works.

✓ Duplicate processing is prevented.

✓ Concurrent updates are safe.

✓ Cancelled orders are excluded.

✓ READY orders are excluded.

✓ COLLECTED orders count exactly once.

✓ NO_SHOW orders count exactly once.

✓ Student cannot manipulate reliability.

✓ No unnecessary Firestore reads were introduced.

✓ No unnecessary Firestore writes were introduced.

✓ Existing order functionality still works.

✓ Existing authentication still works.

✓ Existing admin functionality still works.

✓ Old strike logic remains removed.

---

# 40. DO NOT IMPLEMENT FUTURE PHASES

STOP after Phase B.2.

Do NOT implement:

❌ Ordering restrictions

❌ Maximum active orders

❌ Ordering cooldown

❌ Account suspension

❌ Account banning

❌ Automatic punishment

❌ Student reliability UI redesign

❌ Reliability notifications

❌ Admin reliability dashboard

❌ Admin excuse/pardon functionality

❌ Food rescue

❌ Food waste analytics

❌ Rewards

These belong to later phases.

---

# REQUIRED FINAL REPORT

When Phase B.2 is complete, provide a concise technical report containing:

1. Files inspected.
2. Files modified.
3. Files created.
4. Existing Phase A architecture discovered.
5. Reliability data structure implemented.
6. Lifetime calculation implementation.
7. Recent-history implementation.
8. Reliability score formula.
9. Status thresholds.
10. Idempotency mechanism.
11. Transaction/concurrency strategy.
12. Firestore security changes.
13. Firestore reads introduced.
14. Firestore writes introduced.
15. Cost optimization decisions.
16. Tests executed and results.
17. Any historical-data limitations.
18. Any security concerns.
19. Any remaining technical risks.

Do not proceed to Phase C.

Wait for explicit instructions before implementing restrictions or additional reliability features.

````

## The important outcome of Phase B.2

After the agent completes this phase, the architecture should effectively be:

                    ORDER
                      │
          ┌───────────┴───────────┐
          │                       │
      COLLECTED                NO_SHOW
          │                       │
          └───────────┬───────────┘
                      ↓
              Reliability Engine
                      │
        ┌─────────────┴─────────────┐
        ↓                           ↓
 Lifetime History             Recent 10 Orders
        │                           │
        └─────────────┬─────────────┘
                      ↓
              Reliability Score
                      │
          ┌───────────┼───────────┐
          ↓           ↓           ↓
       Excellent     Good      Needs Improvement
````

---

# Phase Completion Criteria

Phase B.2 is complete when:

* The new features works well with past features.
* App runs successfully.
* No runtime errors occur.
