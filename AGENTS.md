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

# PHASE C — GRACE PERIOD & AUTOMATIC EXPIRY

## OBJECTIVE

Implement Phase C of the CampusBite order reliability system.

Phase C introduces:

1. A configurable pickup grace period after the normal pickup deadline.
2. Automatic conversion of eligible READY orders to NO_SHOW after the grace period expires.
3. Server-authoritative deadline handling.
4. Idempotent NO_SHOW processing.
5. Integration with the existing Pickup Reliability System.
6. Correct interaction with the existing 2-minute order cancellation system.
7. No unnecessary Firestore reads/writes.
8. No automatic strikes, bans, suspensions, or ordering restrictions.

# IMPORTANT:

Also The previous Automatic Striking Engine has been removed.

Do NOT recreate it.

Phase C is ONLY about:

READY → NO_SHOW

after the pickup deadline + grace period.

---

# 1. FIRST — AUDIT THE EXISTING IMPLEMENTATION

Before modifying anything, inspect the current codebase.

Specifically inspect:

- Order model
- OrderStatus enum
- Firestore order structure
- Order creation logic
- Admin order processing
- Student order screen
- Pickup countdown implementation
- pickupDeadline
- readyAt
- collectedAt
- noShowAt
- cancellationDeadline
- cancelledAt
- Phase A NO_SHOW implementation
- Phase B reliability implementation
- Phase B.1 cancellation implementation
- existing Cloud Functions
- existing scheduled functions
- Firestore security rules
- existing notifications collection
- existing FCM implementation

Do NOT assume field names.

Use the existing architecture.

Do not create duplicate order fields if equivalent fields already exist.

Do not create a second NO_SHOW system.

---

# 2. REQUIRED ORDER FLOW

The authoritative lifecycle must remain:

PENDING
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
pickup deadline
    ↓
grace period
    ↓
NO_SHOW

Cancellation remains:

PENDING
    ↓
CANCELLED

The cancellation system is separate from the pickup grace period.

---

# 3. CANCELLATION MUST REMAIN INTACT

The existing 2-minute cancellation window must not be changed.

A student may cancel only while:

status == PENDING

and:

current time < cancellationDeadline

Once the order reaches:

ACCEPTED

the cancellation window is no longer relevant.

Do NOT allow:

ACCEPTED → CANCELLED

unless a future phase explicitly introduces that feature.

---

# 4. PICKUP DEADLINE

Use the existing:

pickupDeadline

field if it already exists.

Do not create another pickup deadline.

The pickup deadline represents the normal time by which the student should collect the order.

Example:

readyAt:
12:00

pickupDeadline:
12:15

The grace period begins after:

12:15

---

# 5. GRACE PERIOD

Introduce a configurable grace period.

Recommended initial value:

5 minutes

Therefore:

pickupDeadline = 12:15

gracePeriod = 5 minutes

automatic NO_SHOW eligibility:

12:20

Do NOT hard-code the value throughout the application.

Create one centralized configuration value.

For example:

DEFAULT_PICKUP_GRACE_PERIOD_MINUTES = 5

Use the project's existing configuration architecture if one already exists.

---

# 6. IMPORTANT — GRACE PERIOD IS NOT AN EXTENSION OF THE DISPLAYED PICKUP TIME

The normal pickup deadline remains unchanged.

Example:

"Pickup by 12:15"

At 12:15:

the normal pickup period has expired.

The system then enters:

GRACE PERIOD

The student may still collect the order during the grace period.

If they collect during the grace period:

READY → COLLECTED

NOT:

READY → NO_SHOW → COLLECTED

NO_SHOW must never happen before the grace period ends.

---

# 7. GRACE PERIOD CALCULATION

Calculate:

noShowEligibleAt =
pickupDeadline + gracePeriod

Do not continuously write this calculated value to Firestore unless the architecture genuinely benefits from storing it.

If the existing order model already stores an equivalent field, reuse it.

Prefer deriving it from:

pickupDeadline

+

configured grace period

where practical.

---

# 8. SERVER-AUTHORITATIVE TIME

The student's device clock must NOT determine whether an order becomes NO_SHOW.

Do not trust:

DateTime.now()

from Flutter

for the authoritative transition.

The backend must determine:

currentTime >= pickupDeadline + gracePeriod

The Flutter app may use local time for countdown display only.

---

# 9. STUDENT COUNTDOWN

The student UI may display:

Pickup deadline

and optionally:

Grace period remaining

Example:

Pickup by 12:15

After 12:15:

"Grace period: 04:32 remaining"

At:

12:20

the grace period expires.

The UI should then show:

"No-show recorded"

after the backend confirms the status.

Do NOT locally change the order to NO_SHOW merely because the device timer reached zero.

---

# 10. AUTOMATIC NO-SHOW

When:

status == READY

and:

currentServerTime >= pickupDeadline + gracePeriod

and:

status != COLLECTED

then the order becomes:

NO_SHOW

The transition must be performed server-side.

---

# 11. NEVER MARK THESE ORDERS AS NO_SHOW

The automatic expiry engine must NOT process:

CANCELLED

COLLECTED

ACCEPTED

PREPARING

PENDING

orders.

Only:

READY

orders are eligible.

This is critical.

---

# 12. COLLECTED DURING GRACE PERIOD

If a student collects during the grace period:

READY → COLLECTED

The automatic NO_SHOW processor must not subsequently change it to NO_SHOW.

Use an atomic transaction or conditional update.

The transition should conceptually be:

IF status == READY
AND current server time >= noShowEligibleAt

THEN:

READY → NO_SHOW

Otherwise:

do nothing.

---

# 13. RACE CONDITION

Handle this race condition:

At exactly the end of the grace period:

Student presses "Collected"

while:

Automatic expiry processor

attempts:

READY → NO_SHOW

Only one transition may succeed.

The system must never end up with an order that is both:

COLLECTED

and:

NO_SHOW

Use a Firestore transaction or secure conditional state transition.

The final state must be authoritative.

---

# 14. IDEMPOTENCY

The automatic expiry process may run more than once.

Therefore:

Processing the same order twice must not produce:

multiple NO_SHOW events.

It must not increment reliability counters twice.

It must not create duplicate notifications.

It must not create duplicate audit records unnecessarily.

Use the order status and/or existing event-processing marker to guarantee idempotency.

Reuse Phase A/B mechanisms if already implemented.

Do not create redundant idempotency infrastructure.

---

# 15. RELIABILITY INTEGRATION

When:

READY → NO_SHOW

the existing Phase B reliability system must process the event.

It should result in:

eligibleOrders + 1

noShowOrders + 1

collectedOrders unchanged

recent history receives:

NO_SHOW

The reliability update must happen exactly once.

Do not recalculate reliability by scanning every historical order.

Do not query the student's entire order history.

Use the existing event-driven Phase B architecture.

---

# 16. COLLECTED ORDERS

When:

READY → COLLECTED

the existing reliability system should process:

eligibleOrders + 1

collectedOrders + 1

noShowOrders unchanged

recent history receives:

COLLECTED

Do not modify this existing behavior unnecessarily.

---

# 17. CANCELLED ORDERS

A:

CANCELLED

order must never become:

NO_SHOW

The expiry processor must explicitly reject:

status != READY

before doing any automatic processing.

---

# 18. SCHEDULED BACKEND PROCESSING

Use a server-side scheduled mechanism.

Preferred architecture:

Cloud Functions for Firebase scheduled function

or the existing server-side scheduler already used by the project.

Do not implement the expiry engine using Flutter background timers.

Do not depend on the student's phone being online.

Do not depend on the admin app being open.

The server must be authoritative.

---

# 19. COST-EFFICIENT SCHEDULER

IMPORTANT:

Do NOT scan every order in the entire database every minute.

That would create unnecessary Firestore reads.

Use the most efficient architecture compatible with the current codebase.

Preferred approach:

Maintain a queryable set of READY orders that are potentially awaiting pickup.

Query only orders whose:

status == READY

and whose:

pickupDeadline/grace deadline

is approaching or has expired.

Use indexed Firestore queries.

Do not perform:

get() on every student's orders.

Do not perform:

collection.get()

across the entire order collection every minute.

---

# 20. SCHEDULER FREQUENCY

Use a reasonable scheduler interval.

Recommended initial approach:

Run every 1 minute.

Do NOT run every second.

Do NOT run every 5 seconds.

Do NOT create a timer per order.

The exact execution time may be slightly delayed by scheduler execution.

That is acceptable.

The system should guarantee:

NO_SHOW is not recorded before the grace period expires.

It does not need to guarantee that NO_SHOW is recorded at the exact millisecond of expiry.

---

# 21. DEADLINE SAFETY

If the scheduler executes late:

pickupDeadline + gracePeriod:
12:20

Scheduler executes:

12:21

The order may be marked NO_SHOW at 12:21.

That is acceptable.

But if scheduler executes:

12:19:59

the order must NOT be marked NO_SHOW.

Server-side time comparison must prevent early processing.

---

# 22. QUERY STRATEGY

Before implementing the scheduler, inspect the existing Firestore order schema and indexes.

Use the fields that already exist.

If the project has:

pickupDeadline

and:

status

use an appropriate compound query/index.

Do not create unnecessary duplicate fields.

If storing a dedicated:

noShowEligibleAt

field significantly simplifies efficient querying, evaluate whether it is justified.

Prefer the simplest architecture that provides reliable indexed querying.

---

# 23. FIRESTORE INDEXES

If the required query needs a composite index:

Create the appropriate Firestore index configuration.

Document why the index exists.

Do not create broad unnecessary indexes.

Verify deployment succeeds.

---

# 24. PROCESSING BATCHES

If the query may return many expired orders:

Process orders in controlled batches.

Do not attempt to load thousands of orders into memory at once.

Use Firestore batch writes or transactions as appropriate.

Do not create a single enormous write batch that could exceed Firestore limits.

---

# 25. TRANSACTIONAL STATE TRANSITION

For each candidate order:

Read the current order state inside the transaction.

Verify:

status == READY

Verify:

currentServerTime >= noShowEligibleAt

Then update:

status = NO_SHOW

noShowAt = server timestamp

Only then should downstream reliability processing occur according to the existing architecture.

If the order is already:

COLLECTED

do nothing.

If it is:

CANCELLED

do nothing.

If it is:

NO_SHOW

do nothing.

---

# 26. DO NOT TRUST QUERY RESULTS ALONE

A query identifies candidates.

It does NOT prove that an order can safely be marked NO_SHOW.

Before updating:

re-check the order state transactionally.

This protects against:

- student collecting at the same time
- admin updates
- cancellation
- retries
- stale query results

---

# 27. ADMIN MANUAL NO-SHOW

Inspect whether the existing admin app already supports manually marking:

NO_SHOW.

If it does:

make sure manual NO_SHOW follows the same reliability/idempotency rules.

Do not create a second incompatible NO_SHOW implementation.

If an admin manually records NO_SHOW before the automatic expiry:

the automatic processor must later ignore that order.

---

# 28. ADMIN COLLECTION

If the admin marks an order:

COLLECTED

during the grace period:

the order must remain:

COLLECTED.

The automatic expiry processor must not overwrite it.

---

# 29. NO-SHOW TIMESTAMP

When NO_SHOW is actually recorded:

set:

noShowAt = server timestamp

Do not use the scheduled function's local clock.

The timestamp represents when the backend recorded the event.

If the architecture already defines noShowAt differently, preserve the established semantics.

---

# 30. EVENT HISTORY

If Phase A has an order event/status history:

record:

READY → NO_SHOW

with:

timestamp
actor/source = system
event type = NO_SHOW

If an event history system does not exist:

do not build a large new event architecture solely for Phase C.

Use the existing architecture.

---

# 31. NOTIFICATIONS

The existing notifications collection is:

notifications

Use the existing notification architecture.

When automatic NO_SHOW is successfully recorded:

create the appropriate student notification:

"No-show recorded"

Do not create the notification if the order transition failed.

Do not send duplicate notifications on retries.

If FCM is already implemented:

use the existing FCM notification pipeline.

Do not create a second notification system.

---

# 32. NOTIFICATION IDEMPOTENCY

If the scheduled function retries:

do not send the same NO_SHOW notification twice.

Tie the notification/event to:

orderId

and the specific:

NO_SHOW

transition.

Reuse the existing notification deduplication mechanism if Phase 7 already implemented one.

---

# 33. NO STRIKE SYSTEM

This phase must NOT implement:

❌ strikes

❌ automatic strikes

❌ strike percentages

❌ account suspension

❌ account banning

❌ ordering restrictions

❌ ordering cooldown

❌ automatic punishment

NO_SHOW is an order outcome.

Reliability is a measurement.

They are not punishment mechanisms.

---

# 34. FOOD WASTE OBJECTIVE

The purpose of automatic NO_SHOW is operational accuracy.

It allows the cafe to know:

"This order was not collected after the allowed pickup period."

It should NOT automatically punish the student.

Future phases may decide how repeated no-shows should be handled.

Do not implement those decisions here.

---

# 35. STUDENT UI STATES

The existing order screen should clearly distinguish:

READY

GRACE PERIOD

NO_SHOW

Suggested conceptual display:

READY:
"Ready for pickup"

During normal pickup period:
"Pickup by 12:15"

During grace period:
"Grace period — please collect your order"

After automatic transition:
"No-show recorded"

Do not redesign the entire order screen.

Use the existing UI components.

---

# 36. COUNTDOWN BEHAVIOR

The client may calculate a countdown locally.

However:

Countdown reaches zero
        ↓
Client refreshes order
        ↓
Backend status is checked
        ↓
If still READY:
show waiting/processing state
        ↓
Backend marks NO_SHOW
        ↓
Client receives updated status

Do not immediately set:

NO_SHOW

from Flutter.

---

# 37. OFFLINE BEHAVIOR

If the student's phone is offline:

the backend must still be capable of marking the order NO_SHOW.

If the student later reconnects:

the order should synchronize to:

NO_SHOW

if it was actually processed.

Do not depend on client-side background execution.

---

# 38. SECURITY RULES

Students must not be allowed to manually write:

NO_SHOW

to their own order.

Do not allow:

status = NO_SHOW

from the client.

Only authorized admin/backend operations may perform the transition.

The existing Firestore security rules must remain restrictive.

Do not weaken security rules to make the feature work.

---

# 39. CLIENT MANIPULATION TEST

Attempt from the Flutter client to update:

status:
NO_SHOW

Expected:

PERMISSION_DENIED.

Attempt to modify:

noShowAt

Expected:

PERMISSION_DENIED.

Attempt to modify:

pickupDeadline

Expected:

PERMISSION_DENIED.

---

# 40. PRIVACY

The NO_SHOW system must not introduce unnecessary personal data.

Do not duplicate:

- student email
- phone number
- location
- device ID
- FCM token

into order expiry records.

Use:

student UID
order ID
timestamps
order state

as necessary.

---

# 41. FIRESTORE COST AUDIT

Before completing Phase C, inspect every new read and write.

The preferred architecture is:

READY order
      ↓
server scheduler
      ↓
query only potentially expired READY orders
      ↓
transactional status validation
      ↓
READY → NO_SHOW
      ↓
existing reliability processor
      ↓
existing notification pipeline

Avoid:

❌ scanning all users

❌ scanning all orders

❌ querying each user's order history

❌ per-order scheduled Cloud Functions

❌ per-second timers

❌ per-second writes

❌ client polling every second

---

# 42. SCHEDULER FAILURE

The system must tolerate temporary scheduler failures.

If the scheduler misses a run:

next run should discover the expired READY order.

Example:

Deadline:
12:20

Scheduler fails at:
12:20

Next successful run:
12:21

The order should still be discovered and processed.

Do not rely on a single execution.

---

# 43. FUNCTION RETRY SAFETY

If the Cloud Function executes twice:

The first execution:

READY → NO_SHOW

The second execution:

status != READY

Therefore:

no change.

No duplicate reliability update.

No duplicate notification.

No duplicate event.

---

# 44. EXISTING RELIABILITY SYSTEM

Do not duplicate the calculations from Phase B.

Phase C should emit the authoritative:

NO_SHOW

event.

Phase B should remain responsible for:

eligibleOrders
noShowOrders
collectedOrders
recent history
collectionRate
reliabilityScore
reliabilityStatus

Reuse existing services/functions.

---

# 45. TEST CASES

Create automated tests for:

## TEST 1 — Before pickup deadline

READY order

current time < pickupDeadline

Expected:

remains READY.

---

## TEST 2 — During grace period

READY order

pickupDeadline passed

grace period not finished

Expected:

remains READY.

---

## TEST 3 — Grace period expired

READY order

current time > pickupDeadline + gracePeriod

Expected:

READY → NO_SHOW.

---

## TEST 4 — Collected during grace period

READY → COLLECTED

before grace expiry.

Expected:

remains COLLECTED.

---

## TEST 5 — Collected after grace expiry but before processor runs

Order is still READY.

Student/admin successfully collects.

Expected:

COLLECTED.

Automatic processor later must not change it.

---

## TEST 6 — Cancelled order

CANCELLED

deadline passes.

Expected:

remains CANCELLED.

---

## TEST 7 — Pending order

PENDING

pickup deadline does not apply.

Expected:

not processed.

---

## TEST 8 — Preparing order

PREPARING.

Expected:

not processed.

---

## TEST 9 — Duplicate scheduler execution

Process same order twice.

Expected:

only one NO_SHOW transition.

---

## TEST 10 — Reliability

NO_SHOW event.

Expected:

eligibleOrders + 1

noShowOrders + 1

exactly once.

---

## TEST 11 — Notification

Automatic NO_SHOW.

Expected:

one notification.

---

## TEST 12 — Notification retry

Process same NO_SHOW again.

Expected:

no duplicate notification.

---

## TEST 13 — Student manipulation

Client attempts:

READY → NO_SHOW.

Expected:

PERMISSION_DENIED.

---

## TEST 14 — Race condition

Student/admin attempts:

READY → COLLECTED

while scheduler attempts:

READY → NO_SHOW.

Expected:

only one terminal transition.

---

## TEST 15 — Late scheduler

Deadline expired by several minutes.

Scheduler runs later.

Expected:

order is still discovered and processed.

---

# 46. INTEGRATION TEST

Perform a complete real-world simulation:

1. Student places order.
2. Cancellation window starts.
3. Cancellation window expires.
4. Admin accepts.
5. Admin marks preparing.
6. Admin marks ready.
7. Pickup deadline begins.
8. Pickup deadline expires.
9. Grace period begins.
10. Student does not collect.
11. Grace period expires.
12. Scheduler processes order.
13. Order becomes NO_SHOW.
14. Reliability updates.
15. Notification is created.
16. Student sees NO_SHOW.

Verify no duplicate writes occur.

---

# 47. SECOND INTEGRATION TEST

Test successful pickup:

1. Student orders.
2. Admin accepts.
3. Preparing.
4. Ready.
5. Pickup deadline approaches.
6. Grace period begins.
7. Student collects.
8. Order becomes COLLECTED.
9. Scheduler runs.
10. Scheduler ignores order.
11. Reliability counts one collection.
12. No NO_SHOW notification is generated.

---

# 48. THIRD INTEGRATION TEST

Test cancellation:

1. Student orders.
2. PENDING.
3. Student cancels within 2 minutes.
4. Order becomes CANCELLED.
5. Cancellation window ends.
6. Pickup deadline logic does not process it.
7. Scheduler ignores it.
8. Reliability ignores it.
9. No NO_SHOW notification is generated.

---

# 49. LOGGING

Use concise logs such as:

[PickupExpiry] Checking expired READY orders

[PickupExpiry] Processing order ORDER_ID

[PickupExpiry] Order transitioned READY → NO_SHOW

[PickupExpiry] Order already terminal, skipping

Do not log:

- student email
- user uid
- phone number
- location
- authentication tokens
- FCM tokens

Avoid excessive logs in production.

---

# 50. PRODUCTION HARDENING

Before completing:

Run:

flutter analyze

Run existing tests.

Run new unit tests.

Run integration tests where available.

Deploy backend changes to a development/staging Firebase environment first if the project has one.

Verify:

- scheduled function deployment
- Firestore indexes
- security rules
- Cloud Functions permissions
- notification integration
- reliability integration

Do not deploy destructive database migrations automatically.

---

# 51. COST REPORT

The final implementation report MUST state:

1. Scheduler frequency.
2. Firestore query used.
3. Number of expected reads per scheduler run.
4. Number of expected writes per expired order.
5. Whether indexes were added.
6. Whether transactions are used.
7. Whether duplicate processing is prevented.
8. Why this architecture is cheaper than polling every order/client.
9. Any potential scaling concerns.

---

# 52. FINAL ACCEPTANCE CRITERIA

Phase C is complete only when:

✓ Grace period exists.

✓ Grace period is configurable.

✓ Server time is authoritative.

✓ READY orders can be collected during grace period.

✓ READY orders are not marked NO_SHOW before grace expires.

✓ Expired READY orders can automatically become NO_SHOW.

✓ Cancellation remains completely separate.

✓ CANCELLED orders never become NO_SHOW.

✓ COLLECTED orders never become NO_SHOW.

✓ PENDING orders never become NO_SHOW.

✓ ACCEPTED orders never become NO_SHOW.

✓ PREPARING orders never become NO_SHOW.

✓ NO_SHOW transition is idempotent.

✓ Race conditions are handled.

✓ Reliability updates exactly once.

✓ Notification is created exactly once.

✓ Student cannot manipulate NO_SHOW.

✓ Student cannot manipulate noShowAt.

✓ Student cannot manipulate pickupDeadline.

✓ No client-side background timer controls the authoritative state.

✓ No per-second Firestore writes exist.

✓ No full order-history scan is performed for each user.

✓ Existing Phase A remains functional.

✓ Existing Phase B remains functional.

✓ Existing Phase B.1 cancellation remains functional.

✓ Existing admin order lifecycle remains functional.

✓ Existing notification architecture remains functional.

✓ Existing FCM implementation remains functional.

✓ No strikes are introduced.

✓ No bans are introduced.

✓ No suspensions are introduced.

✓ No ordering restrictions are introduced.

---

# PHASE C CLARIFICATION — COLLECTION VS NO-SHOW AT GRACE EXPIRY

## AUTHORITATIVE CUTOFF RULE

The pickup grace period has a hard server-side cutoff.

Collection is permitted only when:

currentServerTime < noShowEligibleAt

Collection is NOT permitted when:

currentServerTime >= noShowEligibleAt

This rule applies even when the automatic NO_SHOW processor has not executed yet.

The scheduled processor may run slightly late, but it must never extend the student's pickup entitlement.

---

# COLLECTION TRANSACTION

The transaction that changes:

READY → COLLECTED

MUST verify all of the following using authoritative server time:

1. Order exists.
2. Current status == READY.
3. Order is not CANCELLED.
4. Order is not already NO_SHOW.
5. Current server time < noShowEligibleAt.

If:

currentServerTime >= noShowEligibleAt

the transaction MUST reject the collection attempt.

Return a clear business error such as:

"Pickup window has expired."

Do not silently mark the order as collected.

Do not let the Flutter client override this rule.

---

# NO-SHOW TRANSACTION

The transaction that changes:

READY → NO_SHOW

MUST verify:

1. Order exists.
2. Current status == READY.
3. Current server time >= noShowEligibleAt.

If those conditions are true:

READY → NO_SHOW

Set:

noShowAt = server timestamp

If:

currentServerTime < noShowEligibleAt

the NO_SHOW transaction must do nothing.

The NO_SHOW processor must not create a NO_SHOW before the hard cutoff.

---

# RACE CONDITION RULE

There are two possible situations.

## CASE A — BOTH OPERATIONS OCCUR BEFORE CUTOFF

If:

currentServerTime < noShowEligibleAt

then:

Collection transaction may succeed.

NO_SHOW transaction must reject/do nothing.

The successful COLLECTED transaction wins.

---

## CASE B — BOTH OPERATIONS OCCUR AT OR AFTER CUTOFF

If:

currentServerTime >= noShowEligibleAt

then:

Collection transaction must reject.

NO_SHOW transaction may succeed.

The NO_SHOW outcome wins.

---

## CASE C — SCHEDULER IS DELAYED

Example:

noShowEligibleAt = 12:20

Scheduler does not run at 12:20.

At 12:23 the student attempts to collect.

The collection transaction MUST reject because:

currentServerTime >= noShowEligibleAt

The scheduler may then process:

READY → NO_SHOW

This is intentional.

A delayed scheduler must never extend the grace period.

---

# UPDATED TEST 5

## TEST 5 — Collection Attempt After Grace Expiry Before Processor Runs

Setup:

status = READY

noShowEligibleAt = 12:20

currentServerTime = 12:21

automatic processor has NOT yet run

Student/admin attempts collection.

Expected:

COLLECTION REJECTED.

The order remains:

READY

until the NO_SHOW processor successfully changes it to:

NO_SHOW

The student must not receive a false "Collected" confirmation.

---

# UPDATED TEST 14

## TEST 14 — Concurrent Collection and NO_SHOW Processing

Create two scenarios.

### Scenario A — Before cutoff

currentServerTime < noShowEligibleAt

Collection and NO_SHOW transactions execute concurrently.

Expected:

Collection transaction may succeed.

NO_SHOW transaction must then fail because the order is no longer READY.

Final state:

COLLECTED

---

### Scenario B — At or after cutoff

currentServerTime >= noShowEligibleAt

Collection and NO_SHOW transactions execute concurrently.

Expected:

Collection transaction must reject because the hard cutoff has passed.

NO_SHOW transaction may succeed.

Final state:

NO_SHOW

Never allow:

COLLECTED

after:

noShowEligibleAt

---

# IMPORTANT

Do NOT use:

"first successful transaction wins"

as the sole business rule.

The business rule is:

BEFORE cutoff:
collection is allowed.

AT OR AFTER cutoff:
collection is forbidden.

Transactions only enforce this rule atomically.

---

# CLIENT UI

The Flutter app may display the grace-period countdown locally.

When the displayed countdown reaches zero:

Do NOT assume the order has already become NO_SHOW.

Instead:

1. Disable/close the Collect action.
2. Refresh/read the authoritative order state.
3. Show the current backend status.

Possible temporary state:

"Pickup window expired — updating order..."

Once backend processing completes:

"No-show recorded."

Do not let the client create the NO_SHOW state.

---

# ACCEPTANCE CRITERIA

The implementation is correct only if:

✓ Collection is allowed before noShowEligibleAt.

✓ Collection is rejected at noShowEligibleAt.

✓ Collection is rejected after noShowEligibleAt.

✓ Scheduler delays never extend the grace period.

✓ NO_SHOW cannot happen before noShowEligibleAt.

✓ COLLECTED and NO_SHOW can never both become valid terminal states.

✓ Concurrent transactions respect the cutoff.

✓ Test 5 expects collection rejection after cutoff.

✓ Test 14 contains both pre-cutoff and post-cutoff race scenarios.

✓ Backend uses authoritative server time for both transitions.

---

# REQUIRED FINAL REPORT

After implementation, provide:

1. Files inspected.
2. Files modified.
3. Files created.
4. Existing architecture discovered.
5. Grace period implementation.
6. Scheduler implementation.
7. Firestore query strategy.
8. Indexes added.
9. Server-time enforcement.
10. Transaction strategy.
11. Idempotency strategy.
12. Reliability integration.
13. Notification integration.
14. Security-rule changes.
15. Firestore reads introduced.
16. Firestore writes introduced.
17. Cost analysis.
18. Tests executed.
19. Race-condition tests.
20. Security tests.
21. Remaining risks.

STOP AFTER PHASE C.

DO NOT IMPLEMENT PHASE D OR ANY PUNISHMENT/RESTRICTION SYSTEM.

---

# Phase Completion Criteria

Phase C is complete when:

* The new features works well with past features.
* App runs successfully.
* No runtime errors occur.
