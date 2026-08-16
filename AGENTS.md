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

# PHASE H — CAFE FOOD WASTE MANAGEMENT

## OBJECTIVE

Implement Phase H of the CampusBite Pickup Reliability System.

Previous phases completed:

✓ Phase A — No-show foundation
✓ Phase B — Pickup Reliability
✓ Phase B.1 — 2-minute order cancellation
✓ Phase C — Grace period & automatic NO_SHOW
✓ Phase D — Student reliability experience
✓ Phase E — Graduated ordering restrictions
✓ Phase F — Reliability recovery
✓ Phase G — Admin intervention / Excuse No-show

Phase H introduces Cafe Food Waste Management.

The purpose of this phase is to help cafe administrators record and manage what happens to food from uncollected NO_SHOW orders.

This phase must:

- identify uncollected food
- let authorized cafe admins record its disposition
- preserve the original order history
- prevent duplicate disposition records
- support future food-waste analytics
- minimize Firestore reads and writes
- avoid exposing unnecessary student information
- avoid changing the reliability system

IMPORTANT:

A NO_SHOW does NOT automatically mean FOOD WASTE.

The cafe decides what happened to the food.

---

# 1. CORE PRINCIPLE

The order lifecycle answers:

"What happened to the order?"

Food disposition answers:

"What happened to the prepared food?"

Keep these concepts separate.

Example:

Order:

NO_SHOW

Food disposition:

DONATED

The order remains:

NO_SHOW

Do NOT change it to:

COLLECTED

Do NOT change the student's reliability based on food disposition.

---

# 2. SUPPORTED FOOD DISPOSITIONS

Create the following controlled disposition types:

UNRESOLVED

RESOLD

DISCOUNTED

DONATED

STAFF_USE

DISPOSED

OTHER

Use enums/constants.

Do not use arbitrary free-form status strings throughout the codebase.

---

# 3. DEFAULT STATE

When an order becomes:

NO_SHOW

initial food disposition should be:

UNRESOLVED

unless the existing system already determines a valid disposition.

Do not automatically mark:

DISPOSED

because the food may still be recoverable.

---

# 4. ELIGIBILITY

Only orders with:

status == NO_SHOW

may receive a food disposition.

Do not create waste records for:

PENDING

ACCEPTED

PREPARING

READY

COLLECTED

CANCELLED

REJECTED

---

# 5. FOOD DISPOSITION DATA

Prefer storing a compact disposition record on the order if only one final disposition is required.

Recommended fields:

foodDisposition
foodDispositionAt
foodDispositionBy
foodDispositionNote

Example:

{
    "status": "NO_SHOW",
    "foodDisposition": "DONATED",
    "foodDispositionAt": Timestamp,
    "foodDispositionBy": "adminUid",
    "foodDispositionNote": "Donated to campus support staff."
}

Reuse existing order fields if equivalent fields already exist.

Do not create duplicate structures.

---

# 6. DO NOT STORE STUDENT LOCATION

Food waste management must not introduce any location storage.

Do not copy:

studentLocation

coordinates

address

device location

into waste records.

The cafe only needs operational order information.

---

# 7. ADMIN AUTHORIZATION

Only authorized cafe administrators can set or change a food disposition.

Before allowing a disposition:

1. Authenticate admin.
2. Verify admin role.
3. Verify admin account is active.
4. Verify admin is authorized for the order's cafe.
5. Verify order.status == NO_SHOW.

Do not trust the Flutter UI.

Do not rely only on hiding buttons.

Backend validation is mandatory.

---

# 8. STUDENTS MUST NOT MODIFY DISPOSITION

Students may:

READ their own order status if the existing product experience requires it.

Students must NOT:

- set foodDisposition
- change foodDisposition
- mark food as donated
- mark food as disposed
- edit cafe waste notes

All disposition changes belong to authorized cafe admins/backend operations.

---

# 9. ADMIN UI

In the Admin Order Details screen:

When:

status == NO_SHOW

show:

Food Disposition

If unresolved:

"Record food outcome"

Available actions:

- Resold
- Discounted
- Donated
- Staff Use
- Disposed
- Other

Do not show this control for active or completed collected orders.

---

# 10. CONFIRMATION

Before saving a final disposition, require confirmation.

Example:

"Record food as donated?"

"The order will remain marked as No-show. This only records what happened to the prepared food."

Buttons:

Cancel

Confirm

Do not silently save an irreversible operational action.

---

# 11. OPTIONAL NOTE

Allow an optional admin note.

Maximum:

200 characters.

Examples:

"Donated to campus support staff."

"Sold at 50% discount."

"Food was disposed because it was no longer safe to serve."

Trim whitespace.

Reject excessively long input.

Do not allow HTML or scripts.

---

# 12. DISPOSITION CORRECTIONS

Admins may need to correct an incorrectly recorded disposition.

Do NOT delete historical information silently.

Preferred approach:

Allow changing:

DISPOSITION A → DISPOSITION B

while preserving an immutable audit history.

Example:

DONATED

changed to:

DISPOSED

The current order reflects:

DISPOSED

The audit trail shows:

DONATED → DISPOSED

---

# 13. AUDIT LOG

Use the existing:

audit_logs

collection.

Record every successful disposition change.

Fields:

action

orderId

studentId

cafeId

adminId

previousDisposition

newDisposition

timestamp

note

Do not store unnecessary student personal information.

Do not expose audit records publicly.

---

# 14. AUDIT IMMUTABILITY

Audit records must be append-only.

Admins must not be able to:

edit

delete

rewrite

audit history.

Students must not access private cafe audit records unless a future feature explicitly permits it.

---

# 15. ATOMIC UPDATE

Changing a food disposition and creating its audit record should be atomic.

Use a Firestore transaction or appropriate backend mechanism.

If the operation fails:

the order disposition must not partially change.

---

# 16. IDEMPOTENCY

Repeated requests must not create duplicate effects.

If the same disposition is submitted twice:

do not create duplicate audit records if nothing changed.

If:

currentDisposition == requestedDisposition

return a safe "already recorded" result.

Do not perform unnecessary Firestore writes.

---

# 17. ADMIN BACKEND OPERATION

Prefer a dedicated backend operation such as:

setFoodDisposition(
    orderId,
    disposition,
    note
)

The client should provide:

orderId

disposition

note

The backend should derive:

studentId

cafeId

from the order document.

Do not trust client-provided studentId/cafeId.

Refactor functions to reduce cognitive complexity.

Avoid declarations of unused variables.

---

# 18. FIRESTORE READ OPTIMIZATION

For a disposition update, do not read:

- all student orders
- food_items
- reviews
- notifications
- reliability history

Only the target order and whatever existing authorization mechanism requires.

Reuse existing admin authorization data where possible.

Do not introduce unnecessary role lookups if the existing architecture already has a secure admin claim/service.

---

# 19. FIRESTORE WRITE OPTIMIZATION

A successful disposition change should normally require:

1. One order update.
2. One audit log creation.

Prefer one transaction.

Do not write:

- analytics documents
- daily summaries
- user profile updates
- reliability updates

in this phase.

Analytics belongs later.

---

# 20. NO IMPACT ON RELIABILITY

Food disposition must NOT affect:

reliabilityScore

collectionRate

recentCollectionRate

noShowOrders

restrictionLevel

A no-show remains a no-show regardless of whether the food was:

DONATED

RESOLD

DISPOSED

or otherwise handled.

The reliability event has already been processed.

---

# 21. NO IMPACT ON ORDER STATUS

Food disposition must NOT change:

NO_SHOW

to:

COLLECTED

The historical order outcome remains:

NO_SHOW

Food disposition is a separate operational property.

---

# 22. STUDENT EXPERIENCE

Students do not need to see private cafe waste-management details.

At most, the student may continue seeing:

NO_SHOW

and the existing reliability information.

Do not expose:

- disposal reason
- staff notes
- cafe internal comments
- estimated loss
- admin identity

unless explicitly required later.

---

# 23. CAFE DASHBOARD

Add a lightweight operational summary.

For example:

Unresolved No-shows

Donated

Resold

Discounted

Staff Use

Disposed

Do not build advanced analytics yet.

The dashboard should query only the cafe's relevant orders.

---

# 24. FILTERING

Admin should be able to filter:

All

Unresolved

Donated

Resold

Discounted

Staff Use

Disposed

Do not download all historical orders unnecessarily.

Use indexed Firestore queries.

Paginate results.

---

# 25. DATE RANGE

Allow simple date filtering if the existing admin architecture supports it.

Examples:

Today

This week

This month

Do not load all historical data into memory.

Use Firestore date constraints.

---

# 26. COST OPTIMIZATION

Avoid:

- scanning every order
- loading all historical no-shows
- recalculating all disposition totals on every screen load
- writing aggregate counters for every change unless actually needed

Use indexed queries.

Paginate large results.

Only load the records displayed.

---

# 27. OPTIONAL AGGREGATES

If performance later requires aggregate statistics, create them through backend events.

Do NOT introduce aggregate documents in this phase unless current query performance proves they are necessary.

Start with the simplest correct implementation.

---

# 28. FOOD WASTE REPORTING FOUNDATION

Prepare the data model for future reporting.

The system should eventually be able to answer:

- How many NO_SHOW orders occurred?
- How many were donated?
- How many were resold?
- How many were discounted?
- How many were disposed?
- How many remain unresolved?
- How frequently does food go to waste?
- Which cafe has the highest no-show waste rate?

Do not implement advanced analytics in Phase H.

Only make the stored data capable of supporting it.

---

# 29. ESTIMATED WASTE VALUE

Do NOT calculate financial loss unless the application already has a reliable cost model.

Do not assume:

food price == food cost

because:

selling price

and:

actual cafe cost

are different concepts.

If a future phase needs waste value, introduce a separate cost model.

Do not fabricate financial metrics in this phase.

---

# 30. FOOD SAFETY

Do not allow the application to recommend that potentially unsafe food be resold.

The app only records the cafe administrator's chosen disposition.

The cafe is responsible for following its own food-safety policies.

Do not implement food-safety decisions in code.

---

# 31. RESOLD / DISCOUNTED FLOW

For:

RESOLD

or:

DISCOUNTED

the system should record the disposition only.

Do not automatically create a new food listing.

Do not modify the food item price.

Do not create a second order.

These are operational records only.

A future "food rescue" feature can implement actual resale workflows separately.

---

# 32. DONATED FLOW

For:

DONATED

record:

disposition = DONATED

Optional note.

Do not collect recipient personal information unless a future legal/product requirement explicitly requires it.

---

# 33. DISPOSED FLOW

For:

DISPOSED

allow optional note such as:

"Food no longer suitable for service."

Do not collect unnecessary disposal details.

---

# 34. ADMIN UI SAFETY

Never make:

DISPOSED

the default button.

Avoid destructive-looking defaults.

Require confirmation.

If the system allows changing from:

DISPOSED → RESOLD

record the correction in audit history.

---

# 35. ORDER LIST

For NO_SHOW orders, display a clear badge:

NO-SHOW

and a separate disposition badge:

UNRESOLVED

DONATED

RESOLD

DISCOUNTED

STAFF USE

DISPOSED

Do not combine them into one ambiguous status.

---

# 36. NOTIFICATIONS

Do NOT add new student notifications for food disposition in this phase.

Do not notify students:

"Your food was disposed."

unless a future product requirement explicitly asks for it.

The existing:

NO_SHOW

notification remains unchanged.

---

# 37. FCM

Do not add new FCM message types.

No new push notifications in Phase H.

---

# 38. SECURITY RULES

Students must not write:

foodDisposition

foodDispositionAt

foodDispositionBy

foodDispositionNote

Admins must only change disposition through the authorized backend operation.

Audit logs:

readable only to appropriately authorized administrators.

Audit logs:

not writable or deletable directly by students.

Do not weaken existing rules.

---

# 39. PRIVACY

Minimize data.

Do not store:

- student location
- phone number
- email
- FCM token
- private student information

inside food disposition records.

Use:

orderId

studentId

cafeId

adminId

only where required for audit/security.

---

# 40. PERFORMANCE

Admin dashboard must:

- paginate
- use indexed queries
- avoid full collection reads
- avoid unnecessary realtime listeners
- reuse existing order streams where possible

A real-time listener is appropriate only if the screen actually requires live updates.

---

# 41. TESTING

Create/update tests for:

## TEST 1 — No-show eligibility

NO_SHOW order.

Expected:

food disposition can be recorded.

---

## TEST 2 — Collected order

COLLECTED.

Expected:

food disposition controls unavailable.

---

## TEST 3 — Cancelled order

CANCELLED.

Expected:

not eligible.

---

## TEST 4 — Record donated

DONATED.

Expected:

order remains NO_SHOW.

---

## TEST 5 — Record disposed

DISPOSED.

Expected:

order remains NO_SHOW.

---

## TEST 6 — Record resold

RESOLD.

Expected:

order remains NO_SHOW.

---

## TEST 7 — Duplicate disposition

Same disposition submitted twice.

Expected:

no unnecessary write.

No duplicate audit record.

---

## TEST 8 — Change disposition

DONATED → DISPOSED.

Expected:

current disposition = DISPOSED.

Audit history records both events.

---

## TEST 9 — Unauthorized student

Student attempts to change disposition.

Expected:

PERMISSION_DENIED.

---

## TEST 10 — Unauthorized cafe admin

Admin from Cafe A attempts to modify Cafe B order.

Expected:

PERMISSION_DENIED.

---

## TEST 11 — Concurrent admin actions

Two authorized admins modify the same order.

Expected:

transaction prevents inconsistent state.

---

## TEST 12 — Reliability isolation

Change food disposition.

Expected:

reliability remains unchanged.

---

## TEST 13 — Order status isolation

Change food disposition.

Expected:

order status remains NO_SHOW.

---

# 42. COST AUDIT

Before completing Phase H, document:

- number of reads for disposition update
- number of writes for disposition update
- dashboard query strategy
- pagination strategy
- required Firestore indexes
- any realtime listeners
- any aggregate calculations

Remove unnecessary Firestore operations.

Target:

Disposition update:
one target-order read/transaction + one atomic commit containing order update + audit log.

Dashboard:
indexed paginated query only.

---

# 43. BACKWARD COMPATIBILITY

Do not break:

- authentication
- cart
- ordering
- cancellation
- grace period
- NO_SHOW
- reliability calculation
- reliability recovery
- graduated restrictions
- admin intervention
- notifications
- FCM
- reviews
- favourites
- Cloudinary
- update system

Do not reintroduce the old strike system.

---

# 44. DO NOT IMPLEMENT FUTURE PHASES

STOP after Phase H.

Do NOT implement:

❌ advanced food-waste analytics
❌ financial loss calculations
❌ food rescue marketplace
❌ automatic discounting
❌ automatic donation matching
❌ student resale
❌ loyalty rewards
❌ reliability notifications
❌ new punishment systems

These belong to future phases.

---

# 45. FINAL ACCEPTANCE CRITERIA

Phase H is complete only when:

✓ NO_SHOW orders can receive a food disposition.

✓ Only authorized cafe admins can set disposition.

✓ Students cannot modify disposition.

✓ Cafe isolation is enforced.

✓ NO_SHOW remains the order status.

✓ Reliability remains unchanged by disposition.

✓ Dispositions include UNRESOLVED, RESOLD, DISCOUNTED, DONATED, STAFF_USE, DISPOSED, OTHER.

✓ Admin can correct an existing disposition.

✓ Every successful disposition change is audited.

✓ Audit logs are immutable.

✓ Duplicate operations are prevented.

✓ Concurrent updates are safe.

✓ Dashboard can filter disposition status.

✓ Dashboard queries are paginated/indexed.

✓ No unnecessary historical scans are introduced.

✓ No unnecessary Firestore writes are introduced.

✓ No student location or unnecessary personal data is stored.

✓ Existing order lifecycle remains functional.

✓ Existing cancellation remains functional.

✓ Existing grace period remains functional.

✓ Existing reliability system remains functional.

✓ Existing restrictions remain functional.

✓ Existing admin intervention remains functional.

✓ Existing notifications remain functional.

---

# REQUIRED FINAL REPORT

After implementation, provide:

1. Files inspected.
2. Files modified.
3. Files created.
4. Food disposition data model.
5. Admin UI implementation.
6. Backend authorization mechanism.
7. Audit log implementation.
8. Firestore security changes.
9. Firestore indexes.
10. Firestore reads introduced.
11. Firestore writes introduced.
12. Cost optimization analysis.
13. Privacy considerations.
14. Test results.
15. Security test results.
16. Remaining technical risks.

STOP AFTER PHASE H.

Do not begin the next phase.

---

# Phase Completion Criteria

Phase H is complete when:

* The new features works well with past features.
* App runs successfully.
* No runtime errors occur.
