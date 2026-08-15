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

# PHASE G — ADMIN INTERVENTION

## OBJECTIVE

Implement Phase G of the CampusBite Pickup Reliability System.

Previous phases completed:

✓ Phase A — No-show foundation
✓ Phase B — Pickup Reliability calculation
✓ Phase B.1 — 2-minute order cancellation
✓ Phase C — Grace period & automatic NO_SHOW
✓ Phase D — Student reliability experience
✓ Phase E — Graduated ordering restrictions
✓ Phase F — Reliability recovery

Phase G introduces controlled administrator intervention.

The objective is to allow authorized cafe administrators to correct legitimate exceptional cases without recreating the old strike/pardon system.

Examples of legitimate exceptions:

- Student had an emergency.
- Cafe instructed the student not to collect.
- Cafe was unable to fulfill the order.
- System malfunction caused an incorrect NO_SHOW.
- Other documented exceptional circumstances.

The admin must NOT be able to arbitrarily set a student's reliability score.

The admin must act on a specific order/event.

The reliability engine remains authoritative.

---

# 1. CORE PRINCIPLE

Admins can:

EXCUSE a specific NO_SHOW

but cannot:

- set reliabilityScore directly
- set collectionRate directly
- set noShowOrders directly
- set restrictionLevel directly
- set arbitrary recovery points
- erase the original order
- rewrite historical timestamps

An administrative intervention is a correction to an event.

The reliability engine then recalculates the affected metrics.

---

# 2. AUTHORIZATION

Only authorized cafe administrators may perform intervention.

Before every intervention verify:

- Firebase Authentication session exists.
- User has admin role.
- Admin account is active.
- Admin is authorized to manage the cafe associated with the order.
- Target order exists.

Do NOT trust the Flutter UI role alone.

Do NOT rely on hidden buttons as authorization.

The backend must enforce authorization.

---

# 3. CAFE OWNERSHIP

An admin should normally be allowed to intervene only on orders belonging to their authorized cafe.

Example:

Admin for:

Cafe A

must NOT excuse:

Cafe B

orders unless their role explicitly grants cross-cafe administrative access.

Use the existing cafe/admin authorization model.

Do not invent a second role system.

---

# 4. WHAT AN ADMIN MAY DO

For this phase implement:

## Excuse No-Show

This changes the administrative treatment of a specific no-show.

The admin selects:

Order

↓

Excuse No-Show

↓

Select reason

↓

Optional note

↓

Confirm

↓

Backend validates

↓

Reliability recalculates

↓

Audit log created

---

# 5. DO NOT CALL IT "REMOVE STRIKE"

There are no strikes.

Use product language such as:

- Excuse No-Show
- Mark as Excused
- Correct No-Show

Do NOT use:

- Remove Strike
- Pardon Strike
- Strike Removal
- Clear Strike

The old strike engine has been removed.

---

# 6. ELIGIBLE ORDERS

An order can be excused only if:

status == NO_SHOW

and:

noShowAt exists

and:

the order has not already been excused.

Do not allow excusing:

PENDING

ACCEPTED

PREPARING

READY

COLLECTED

CANCELLED

Only NO_SHOW is eligible.

---

# 7. EXCUSE REASONS

Provide predefined reasons.

Recommended initial choices:

- Student reported emergency
- Cafe unable to fulfill order
- System/application issue
- Pickup information was incorrect
- Admin-approved exception
- Other

Do not allow arbitrary uncontrolled categories.

If:

Other

is selected:

allow an optional note.

Maximum note length:

200 characters.

Trim whitespace.

Reject excessively long input.

---

# 8. OPTIONAL ADMIN NOTE

Allow a short administrative note.

Maximum:

200 characters.

Do not allow:

HTML

scripts

URLs

massive payloads

Use the application's existing input sanitization and validation mechanisms.

Do not expose internal notes publicly.

---

# 9. DATA MODEL

Do NOT delete the original NO_SHOW data.

The order should preserve:

status = NO_SHOW

noShowAt

The intervention should add fields such as:

noShowExcused
excusedAt
excusedBy
excuseReason
excuseNote

Use the project's existing naming conventions.

Recommended conceptual structure:

{
  status: "NO_SHOW",

  noShowAt: Timestamp,

  noShowExcused: true,

  excusedAt: Timestamp,

  excusedBy: adminUid,

  excuseReason: "Student reported emergency",

  excuseNote: "Student informed cafe after emergency."
}

Do not duplicate existing fields.

---

# 10. IMPORTANT — DO NOT CHANGE ORDER STATUS

Excusing a no-show MUST NOT change:

NO_SHOW → COLLECTED

That would create false operational history.

The food was not actually collected.

The order remains:

NO_SHOW

but becomes:

EXCUSED

for reliability purposes.

Use a separate boolean/state field rather than rewriting the historical order outcome.

---

# 11. RELIABILITY EFFECT

An excused NO_SHOW must no longer count as an unexcused failed pickup.

Conceptually:

Before:

eligibleOrders += 1
noShowOrders += 1

After excusal:

exclude that event from reliability failure calculations.

The exact recalculation must use the existing Phase B architecture.

Do NOT simply subtract 1 from:

reliabilityScore

or:

noShowOrders

inside the admin app.

---

# 12. RECALCULATION STRATEGY

The backend must recalculate the reliability summary after an excuse.

Do NOT make the Flutter app calculate the corrected score.

Do NOT query the entire order history from the Flutter app.

Reuse the existing reliability service/processor.

---

# 13. RECENT HISTORY CORRECTION

If the excused order exists in:

recentPickupHistory

it must be removed or converted so that it no longer counts as:

NO_SHOW

Do not replace it with:

COLLECTED

because the order was not collected.

The preferred representation is:

EXCUSED

or omission from the reliability event window.

Use whichever approach best matches the existing Phase B implementation.

The important rule is:

EXCUSED must not count as success or failure.

---

# 14. LIFETIME METRIC CORRECTION

After excuse:

eligibleOrders

must represent only eligible unexcused pickup outcomes according to the established reliability model.

noShowOrders

must exclude the excused event.

collectedOrders

must remain unchanged.

Do not incorrectly turn:

NO_SHOW → COLLECTED.

---

# 15. RESTRICTION RECALCULATION

After reliability recalculation:

recalculate:

reliabilityScore

reliabilityStatus

restrictionLevel

Use existing Phase B + Phase E logic.

Example:

Before:

reliabilityScore = 40
restrictionLevel = LIMITED

After excusing a no-show:

reliabilityScore = 55
restrictionLevel = NORMAL

The change should happen automatically if the corrected reliability crosses a threshold.

Do not manually set:

restrictionLevel = NORMAL

---

# 16. ATOMICITY

The intervention must be atomic.

The following must not become partially updated:

1. Order excuse state
2. Reliability summary
3. Recent history
4. Restriction level
5. Audit log

Use a Firestore transaction or appropriate backend atomic mechanism.

If the operation fails:

none of the changes should be committed.

---

# 17. IDEMPOTENCY

An already excused order cannot be excused again.

If:

noShowExcused == true

return:

ALREADY_EXCUSED

or an equivalent safe business result.

Do not create another audit record.

Do not recalculate reliability unnecessarily.

---

# 18. RACE CONDITION

Handle:

Admin A excuses order

while:

Admin B excuses same order

Only one intervention may succeed.

The second request must detect:

noShowExcused == true

and stop.

Do not create duplicate corrections.

---

# 19. ADMIN UI

In the Admin App, on the student/order management screen:

For an eligible NO_SHOW order display:

Excuse No-Show

Do not display the option for other statuses.

---

# 20. CONFIRMATION DIALOG

Before intervention display:

Excuse this no-show?

Explain:

"This removes this no-show from the student's pickup reliability calculation. The original order history will remain unchanged."

Buttons:

Cancel

Confirm

Do not execute immediately without confirmation.

---

# 21. REASON SELECTION

Before confirmation require:

Excuse Reason

Use a dropdown/bottom-sheet selection.

Do not default silently to:

Other

unless the UI explicitly allows it.

---

# 22. AUDIT LOGGING

Every successful intervention MUST create an immutable audit record.

Use the existing:

audit_logs

collection.

Record:

action = NO_SHOW_EXCUSED

orderId

studentId

cafeId

adminId

timestamp

reason

adminNote

previousReliabilitySummary
(optional only if existing architecture safely supports it)

newReliabilitySummary
(optional only if needed)

Do not store unnecessary personal information.

---

# 23. AUDIT LOG IMMUTABILITY

Admins must NOT be able to edit or delete excuse audit logs.

Students must NOT be able to read private administrative notes unless a future policy explicitly allows it.

Audit logs are append-only.

---

# 24. STUDENT VISIBILITY

The student should see that the no-show was excused.

The order can display:

NO-SHOW

Excused

The student should understand that the order itself was not collected, but it was excluded from their reliability calculation.

Do not expose:

admin UID

private admin note

internal authorization details

---

# 25. STUDENT NOTIFICATION

If the existing notification architecture supports appropriate account/order notifications, create:

"Your missed pickup has been excused."

Example:

"An administrator reviewed Order #CB-1234 and excused the missed pickup. It will not affect your pickup reliability."

Do not send a notification if the intervention did not succeed.

Use the existing:

notifications

collection

and existing FCM pipeline.

Do not create a second notification system.

---

# 26. NOTIFICATION IDEMPOTENCY

If the backend retries:

do not send duplicate excuse notifications.

Use the existing eventId/deduplication mechanism.

For example:

NO_SHOW_EXCUSED_{orderId}

Reuse the existing notification architecture.

---

# 27. SECURITY RULES

Students:

READ own orders

READ own reliability

CANNOT:

excuse no-show

modify:

noShowExcused
excusedAt
excusedBy
excuseReason
excuseNote

Admins:

read authorized orders

request an excuse through the approved backend operation

Do not allow direct arbitrary client writes to excuse fields.

---

# 28. ADMIN BACKEND OPERATION

Prefer a dedicated callable HTTPS Cloud Function or another trusted backend operation:

excuseNoShow(orderId, reason, note)

The backend must:

1. Authenticate requester.
2. Verify admin role.
3. Verify cafe authorization.
4. Read order.
5. Verify status == NO_SHOW.
6. Verify not already excused.
7. Update order.
8. Recalculate reliability.
9. Recalculate restriction.
10. Create audit log.
11. Create notification.
12. Commit atomically where feasible.

Reuse existing backend service abstractions.

---

# 29. DO NOT TRUST CLIENT-PROVIDED STUDENT ID

The client should provide:

orderId

The backend should derive:

studentId

from:

orders/{orderId}

Do not accept:

studentId

as an authoritative client-provided argument.

Similarly derive:

cafeId

from the order.

---

# 30. COST OPTIMIZATION

Do not query:

all student orders

all reviews

all notifications

all food items

for an excuse action.

Use:

target order

existing reliability summary

existing reliability history

only as needed.

If Phase B stores sufficient recent/lifetime summary data, use it.

Do not perform a full order-history scan unless the existing data model absolutely requires it.

If a full recalculation is required for correctness, document why and assess whether the Phase B data model should be extended rather than adding repeated expensive scans.

---

# 31. NO DIRECT ADMIN PROFILE EDIT

Do NOT allow admins to edit:

reliabilityScore

collectionRate

restrictionLevel

directly.

The only allowed intervention in this phase is:

EXCUSE NO_SHOW

The reliability engine recalculates all affected values.

---

# 32. STUDENT SUPPORT FLOW

Add a clear path for students to request an intervention.

Recommended later UI:

"Report an issue"

Can be added in help and support screen where a student can report via the support email

But do NOT build a full support/ticketing system in this phase.

For now, only ensure the backend can record legitimate admin intervention.

---

# 33. MULTIPLE CAFE ADMINISTRATORS

If multiple admins manage the same cafe:

all authorized admins may review and excuse eligible no-shows.

The audit log must identify exactly which admin performed the action.

---

# 34. CROSS-CAFE SECURITY

Admin for Cafe A:

MUST NOT excuse:

Cafe B

orders.

Unless the existing role model explicitly defines a higher-level administrator.

Do not weaken cafe isolation.

---

# 35. PRIVACY

Do not expose:

student location

email

phone

FCM token

private admin note

to unauthorized users.

The excuse record should contain only the minimum information needed for auditing and reliability correction.

---

# 36. TESTING

Create/update tests for:

## TEST 1 — Valid no-show

NO_SHOW

not excused

Expected:

Excuse No-Show button visible.

---

## TEST 2 — Excuse

Admin selects:

Student reported emergency

Confirm.

Expected:

noShowExcused = true

reliability recalculates.

---

## TEST 3 — Already excused

Attempt excuse again.

Expected:

rejected.

No duplicate audit log.

No duplicate notification.

---

## TEST 4 — Wrong status

Attempt excuse on:

READY

Expected:

rejected.

---

## TEST 5 — Collected order

Attempt excuse.

Expected:

rejected.

---

## TEST 6 — Cancelled order

Attempt excuse.

Expected:

rejected.

---

## TEST 7 — Unauthorized admin

Cafe A admin attempts to excuse Cafe B order.

Expected:

PERMISSION_DENIED.

---

## TEST 8 — Student attempt

Student attempts excuseNoShow.

Expected:

PERMISSION_DENIED.

---

## TEST 9 — Reliability correction

Before:

eligible = 10
collected = 7
noShow = 3

Excuse one no-show.

Expected:

reliability calculations no longer count the excused event as an unexcused failure.

---

## TEST 10 — Restriction recovery

Before:

restrictionLevel = LIMITED

After excusing a no-show:

reliability crosses threshold.

Expected:

restrictionLevel = NORMAL

if the existing Phase E rules produce that result.

---

## TEST 11 — Recent history

If the excused order exists in recent history:

Expected:

it no longer counts as NO_SHOW.

---

## TEST 12 — Notification

Successful excuse:

one student notification.

Repeated attempt:

no duplicate notification.

---

## TEST 13 — Audit

Successful excuse:

one immutable audit log.

Repeated attempt:

no duplicate audit log.

---

## TEST 14 — Concurrent admin actions

Two admins attempt to excuse the same order simultaneously.

Expected:

one succeeds.

one is rejected as already processed.

---

# 37. PERFORMANCE TESTING

Verify:

- no full order-history query from the admin UI
- no unnecessary listeners
- no repeated reads
- no duplicate writes
- one controlled backend operation per intervention

Admin UI should not continuously poll for intervention state.

---

# 38. BACKWARD COMPATIBILITY

Do not break:

- authentication
- cart
- orders
- cancellation
- grace period
- NO_SHOW processing
- reliability calculation
- reliability recovery
- graduated restrictions
- notifications
- FCM
- reviews
- favourites
- admin order management

Do not reintroduce:

- strikes
- suspension
- bans
- automatic punishment

---

# 39. FINAL ACCEPTANCE CRITERIA

Phase G is complete only when:

✓ Authorized admins can excuse legitimate NO_SHOW orders.

✓ Admin cafe authorization is enforced server-side.

✓ Students cannot excuse orders.

✓ Only NO_SHOW orders are eligible.

✓ Original order remains NO_SHOW.

✓ Excused no-shows are excluded from reliability failure calculations.

✓ Collected orders remain collected.

✓ Cancelled orders remain cancelled.

✓ Reliability recalculates correctly.

✓ Restriction level recalculates automatically.

✓ Audit log is created.

✓ Audit log is immutable.

✓ Student receives an appropriate notification if enabled.

✓ Duplicate excuses are prevented.

✓ Concurrent admin actions are handled safely.

✓ Admins cannot directly edit reliability score.

✓ No unnecessary Firestore reads are introduced.

✓ No unnecessary Firestore writes are introduced.

✓ Existing recovery system remains functional.

✓ Existing graduated restrictions remain functional.

✓ No old strike functionality returns.

---

# REQUIRED FINAL REPORT

After implementation, provide:

1. Files inspected.
2. Files modified.
3. Files created.
4. Admin intervention architecture.
5. Backend authorization mechanism.
6. Excuse data model.
7. Reliability recalculation strategy.
8. Restriction recalculation strategy.
9. Transaction/idempotency strategy.
10. Audit log implementation.
11. Notification implementation.
12. Firestore security changes.
13. Firestore reads introduced.
14. Firestore writes introduced.
15. Cost analysis.
16. Security test results.
17. Functional test results.
18. Any unresolved risks.

STOP AFTER PHASE G.

Do not begin Phase H.

---

# Phase Completion Criteria

Phase C is complete when:

* The new features works well with past features.
* App runs successfully.
* No runtime errors occur.
