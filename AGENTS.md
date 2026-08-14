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

# PHASE F — RELIABILITY RECOVERY

## OBJECTIVE

Implement Phase F of the CampusBite Pickup Reliability System.

Previous phases completed:

✓ Phase A — No-show foundation
✓ Phase B — Pickup Reliability calculation
✓ Phase B.1 — 2-minute order cancellation window
✓ Phase C — Grace period and automatic NO_SHOW
✓ Phase D — Student reliability experience
✓ Phase E — Graduated ordering restrictions

Phase F introduces the reliability recovery system.

The purpose is to allow students to naturally recover their pickup reliability through successful order collections.

The system must:

- reward consistent successful pickups through improved reliability
- automatically relax ordering restrictions when reliability improves
- avoid permanent punishment
- avoid manual recovery requirements
- preserve the existing reliability calculation
- preserve the existing restriction model
- minimize Firestore reads and writes

IMPORTANT:

Do NOT create a second reliability algorithm.

Do NOT create a second score.

Do NOT create recovery points.

Do NOT create a new strike system.

Do NOT create account bans.

Do NOT create permanent suspension.

Use the existing Phase B reliability calculation as the single source of truth.

---

# 1. FIRST — AUDIT EXISTING IMPLEMENTATION

Before modifying code, inspect:

- PickupReliability model
- PickupReliability service
- Reliability calculation
- Recent pickup history
- Lifetime counters
- Reliability score
- Reliability status
- Phase E restriction level
- Active-order limit
- COLLECTED processing
- NO_SHOW processing
- Firestore user schema
- Firestore order schema
- Cloud Functions
- Firestore security rules
- AccountScreen reliability UI

Do not assume names or locations.

Reuse the actual implementation.

---

# 2. CORE PRINCIPLE

Recovery must happen automatically through successful collections.

The flow is:

COLLECTED

↓

Reliability Engine processes successful pickup

↓

Lifetime counters update

↓

Recent history updates

↓

Recent collection rate updates

↓

Reliability score updates

↓

Reliability status updates

↓

Restriction level is re-evaluated

↓

Restrictions may relax automatically

No separate recovery counter is needed.

---

# 3. COLLECTION IS THE RECOVERY EVENT

Only a genuine:

READY → COLLECTED

transition can improve reliability.

Do not count:

- PENDING
- ACCEPTED
- PREPARING
- READY
- CANCELLED
- NO_SHOW
- REJECTED

as recovery events.

A successful collection is the only positive pickup outcome.

---

# 4. DO NOT ARTIFICIALLY ADD POINTS

Do NOT implement something like:

successfulCollection += 5 points

or:

reliabilityScore += 10

The score must continue to be calculated from the existing Phase B metrics.

The existing model is:

lifetimeCollectionRate

+

recentCollectionRate

↓

reliabilityScore

Use the existing formula unchanged.

---

# 5. RECENT HISTORY IS THE PRIMARY RECOVERY MECHANISM

The existing recent pickup history contains the latest eligible outcomes.

For example:

recentPickupHistory = [
    COLLECTED,
    COLLECTED,
    NO_SHOW,
    COLLECTED,
    COLLECTED
]

When a new order is collected:

1. Add COLLECTED.
2. Keep only the latest configured number of eligible outcomes.
3. Recalculate recentCollectedOrders.
4. Recalculate recentNoShowOrders.
5. Recalculate recentCollectionRate.
6. Recalculate the existing reliabilityScore.
7. Recalculate the existing reliabilityStatus.

Do not create another history list.

---

# 6. LIFETIME HISTORY

A successful collection must also increment the existing:

eligibleOrders

and:

collectedOrders

exactly once.

The existing:

noShowOrders

must not change.

Therefore:

eligibleOrders += 1

collectedOrders += 1

noShowOrders unchanged

---

# 7. EVENT-DRIVEN RECOVERY

Recovery must happen only when an eligible order becomes:

COLLECTED.

Do NOT recalculate reliability:

- every app launch
- every AccountScreen open
- every minute
- every countdown tick
- every login
- every notification
- every app resume

This is critical for Firestore cost control.

---

# 8. IDEMPOTENCY

A collected order must only contribute to reliability once.

If the same event is processed twice:

eligibleOrders must increase once.

collectedOrders must increase once.

recent history must contain the order once.

The reliability score must not be double-counted.

Use the existing Phase B event-processing mechanism.

If the current implementation uses:

reliabilityProcessed

or equivalent:

reuse it.

Do not create another duplicate idempotency field unless necessary.

---

# 9. CONCURRENT PROCESSING

Safely handle:

two different orders becoming COLLECTED nearly simultaneously.

Example:

Before:

eligible = 10
collected = 7
noShow = 3

Order A → COLLECTED

Order B → COLLECTED

Expected final state:

eligible = 12
collected = 9
noShow = 3

Not:

eligible = 11
collected = 8

Do not allow lost updates.

Use Firestore transactions or the project's existing atomic backend mechanism.

---

# 10. RESTRICTION RECOVERY

Phase E already defines:

NORMAL
LIMITED
HIGHLY_LIMITED

Do not create new restriction states.

After reliability is recalculated, automatically determine the appropriate restriction level using the existing Phase E thresholds.

For example:

90–100:
NORMAL

75–89:
NORMAL

50–74:
NORMAL

25–49:
LIMITED

0–24:
HIGHLY_LIMITED

If eligibleOrders < 3:

NORMAL

Do not change the thresholds in Phase F.

---

# 11. AUTOMATIC RESTRICTION RELAXATION

When the calculated reliability crosses a restriction threshold:

automatically update:

pickupReliability.restrictionLevel

Example:

HIGHLY_LIMITED
    ↓
successful collections
    ↓
score improves to 30
    ↓
LIMITED

Then:

LIMITED
    ↓
successful collections
    ↓
score improves to 52
    ↓
NORMAL

Do not require:

- admin approval
- student request
- logout/login
- app reinstall
- manual refresh

---

# 12. DO NOT RELY ON THE CLIENT

Flutter must never decide:

"Restriction should be removed."

The backend remains authoritative.

The client only displays the current state.

Do not allow:

student → write restrictionLevel = NORMAL

---

# 13. MINIMIZE WRITES

When a COLLECTED event is processed, update the user only if the reliability summary actually changes.

At minimum, the event may update:

eligibleOrders

collectedOrders

recent history

recentCollectionRate

collectionRate

reliabilityScore

reliabilityStatus

restrictionLevel

updatedAt

Use the existing structure.

Do not rewrite unrelated user fields.

If a computed field has not changed, do not write it separately.

Prefer one atomic user-document update/transaction.

---

# 14. NO ADDITIONAL FIRESTORE READS FROM STUDENT UI

The AccountScreen must continue using the existing user/reliability data.

Do not query historical orders to determine whether recovery occurred.

Do not add a new recovery listener.

Do not add a new recovery collection.

If an existing user snapshot listener already supplies:

pickupReliability

reuse it.

---

# 15. RECOVERY MESSAGE

Phase D already provides the student reliability UI.

Extend it only if necessary to reflect recovery naturally.

Examples:

After successful collections:

"Your pickup record is improving."

"Great job collecting your recent orders."

"Keep it up — your ordering limits have been reduced."

When restriction improves:

"Your pickup reliability has improved. Your ordering limit is now 2 active orders."

When NORMAL is restored:

"Your pickup reliability is back to normal."

Keep language positive.

Do not mention:

- punishment
- strikes
- bans
- penalties

---

# 16. DO NOT OVERREWARD

Recovery should be proportional.

Do not give bonus points.

Do not automatically raise reliability above what the existing calculation produces.

Do not skip the lifetime component.

Do not ignore previous no-shows.

The system should reflect:

recent improvement

while still preserving:

historical behavior

This is exactly why Phase B uses lifetime + recent performance.

---

# 17. RECENT VS LIFETIME BEHAVIOR

The existing weighted reliability model remains authoritative.

Example:

Lifetime:

50 eligible
45 collected
5 no-show

lifetimeRate = 90%

Recent:

4 collected
1 no-show

recentRate = 80%

Existing weighted score:

90 × 0.70 + 80 × 0.30

Do not change the formula.

If a student continues collecting successfully, recent performance improves naturally.

---

# 18. RECOVERY EXAMPLE

Example:

Initial state:

reliabilityScore = 22
restrictionLevel = HIGHLY_LIMITED
activeOrderLimit = 1

Student successfully collects orders.

After several valid collections:

reliabilityScore = 31

Expected:

restrictionLevel = LIMITED
activeOrderLimit = 2

More successful collections:

reliabilityScore = 52

Expected:

restrictionLevel = NORMAL
No artificial active-order limit.

This recovery must happen automatically.

---

# 19. RESTRICTION CHANGES MUST BE ATOMIC

When the reliability engine recalculates the score and restriction:

update them together.

Avoid a temporary inconsistent state such as:

reliabilityScore = 52
restrictionLevel = HIGHLY_LIMITED

unless unavoidable during a transaction.

Use an atomic backend operation where appropriate.

---

# 20. NO-SHOW PROCESSING MUST REMAIN UNCHANGED

Do not alter Phase C's:

- grace period
- hard cutoff
- automatic NO_SHOW processor
- server time validation
- transaction logic

Phase F only handles the recovery side.

NO_SHOW remains:

eligibleOrders += 1

noShowOrders += 1

recent history += NO_SHOW

---

# 21. CANCELLATION MUST REMAIN EXCLUDED

A valid cancellation during the 2-minute cancellation window must not:

improve reliability

or:

reduce reliability.

It simply remains excluded.

Do not change Phase B.1.

---

# 22. EXCUSED NO-SHOW COMPATIBILITY

Phase F must be compatible with a future admin "Excuse No-show" feature.

Do not permanently design reliability data so a historical no-show cannot later be corrected.

If a future phase changes:

NO_SHOW → EXCUSED

the reliability engine must be capable of recalculating affected metrics.

Do not implement admin excuse functionality in Phase F.

---

# 23. SECURITY

Students can:

READ their own reliability.

Students cannot:

WRITE reliability.

Students cannot:

WRITE restrictionLevel.

Students cannot:

WRITE collectedOrders.

Students cannot:

WRITE recentPickupHistory.

Students cannot:

WRITE reliabilityScore.

Backend remains authoritative.

---

# 24. ADMIN ACCESS

Admins may read reliability according to the existing Phase E authorization model.

Do not introduce arbitrary admin write access.

Do not add manual recovery controls.

Manual admin intervention will be implemented separately.

---

# 25. PERFORMANCE

The recovery system must:

- run only on COLLECTED events
- use existing reliability infrastructure
- avoid historical order scans
- avoid new listeners
- avoid client polling
- avoid per-minute updates
- avoid per-second writes

---

# 26. TESTING

Create/update automated tests.

## Test 1 — Successful collection

Order:

READY → COLLECTED

Expected:

eligibleOrders + 1

collectedOrders + 1

noShowOrders unchanged

---

## Test 2 — Duplicate collection event

Same order processed twice.

Expected:

counts increase once.

---

## Test 3 — Recent history

New COLLECTED order enters recent history.

Expected:

latest event = COLLECTED

oldest event removed if history exceeds configured limit.

---

## Test 4 — Reliability improvement

Start:

reliabilityScore = 24

restrictionLevel = HIGHLY_LIMITED

Process enough successful collections to cross the restriction threshold.

Expected:

restrictionLevel becomes LIMITED.

---

## Test 5 — Full recovery

Continue successful collections until score crosses the NORMAL threshold.

Expected:

restrictionLevel = NORMAL.

---

## Test 6 — Insufficient history

eligibleOrders < 3

Expected:

restrictionLevel = NORMAL

regardless of raw score.

---

## Test 7 — No-show unchanged

Process NO_SHOW.

Expected:

Phase B no-show logic works normally.

Phase F must not treat it as recovery.

---

## Test 8 — Cancellation unchanged

Process CANCELLED.

Expected:

reliability unchanged.

---

## Test 9 — Concurrent collections

Two orders become COLLECTED simultaneously.

Expected:

both are counted exactly once.

No lost update.

---

## Test 10 — Student write attempt

Student tries to modify reliability.

Expected:

PERMISSION_DENIED.

---

## Test 11 — Restriction recovery consistency

Reliability score improves across a threshold.

Expected:

score and restrictionLevel update atomically.

---

## Test 12 — App UI

After backend recovery:

AccountScreen receives updated data.

Expected:

reliability and restriction information update automatically using the existing user listener.

No manual refresh required.

---

# 27. FIRESTORE COST AUDIT

Before completing Phase F:

Inspect every added Firestore operation.

Target:

COLLECTED event
    ↓
one backend reliability transaction/update

Avoid:

- querying all historical orders
- querying all recent orders unnecessarily
- new student-side listeners
- repeated recalculation
- repeated writes when state has not changed

If the existing Phase B engine already performs the required operation:

extend it instead of adding another operation.

---

# 28. BACKWARD COMPATIBILITY

Do not break:

- authentication
- cart
- order creation
- cancellation
- ACCEPTED
- PREPARING
- READY
- COLLECTED
- NO_SHOW
- grace period
- Phase B reliability
- Phase C expiry
- Phase D UI
- Phase E restrictions
- notifications
- reviews
- favourites
- admin order management

Do not reintroduce the old strike system.

---

# 29. DO NOT IMPLEMENT FUTURE PHASES

STOP after Phase F.

Do NOT implement:

❌ Admin excuse/pardon

❌ Food rescue

❌ Food waste analytics

❌ Reliability rewards

❌ New reliability notifications

❌ Permanent suspension

❌ Account banning

❌ Manual reliability editing

❌ New punishment mechanisms

---

# 30. FINAL ACCEPTANCE CRITERIA

Phase F is complete only when:

✓ Successful collections improve reliability naturally.

✓ Lifetime metrics are updated exactly once.

✓ Recent history is updated exactly once.

✓ Reliability score uses the existing Phase B formula.

✓ No artificial recovery points are introduced.

✓ Restriction levels automatically relax when thresholds are crossed.

✓ HIGHLY_LIMITED can become LIMITED.

✓ LIMITED can become NORMAL.

✓ New users remain unrestricted.

✓ Insufficient-history users remain unrestricted.

✓ No-show events do not improve reliability.

✓ Cancelled orders do not affect reliability.

✓ Students cannot manipulate recovery data.

✓ Recovery is server-authoritative.

✓ No additional historical order scans are introduced.

✓ No additional client listeners are introduced unnecessarily.

✓ No unnecessary Firestore writes are introduced.

✓ Existing Phase E restrictions remain intact.

✓ Existing order lifecycle remains intact.

✓ Existing Phase C expiry remains intact.

✓ Existing Phase D UI remains compatible.

---

# REQUIRED FINAL REPORT

After implementation, provide:

1. Files inspected.
2. Files modified.
3. Files created.
4. Existing Phase B reliability architecture reused.
5. Recovery implementation.
6. Recent-history behavior.
7. Restriction relaxation behavior.
8. Transaction/concurrency strategy.
9. Firestore security changes.
10. Firestore reads introduced.
11. Firestore writes introduced.
12. Cost optimization analysis.
13. Tests performed.
14. Security tests.
15. Any unresolved risks.

STOP AFTER PHASE F.

Do not begin Phase G.

---

# Phase Completion Criteria

Phase C is complete when:

* The new features works well with past features.
* App runs successfully.
* No runtime errors occur.
