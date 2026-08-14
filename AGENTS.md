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

# PHASE E — GRADUATED ORDERING RESTRICTIONS

## OBJECTIVE

Implement Phase E of the CampusBite Pickup Reliability System.

Previous phases completed:

✓ Phase A — No-show foundation
✓ Phase B — Pickup Reliability calculation
✓ Phase B.1 — 2-minute order cancellation window
✓ Phase C — Grace period and automatic NO_SHOW
✓ Phase D — Student reliability experience and warnings

Phase E introduces proportional ordering restrictions for students whose pickup reliability remains persistently poor.

The system must protect cafe operations and reduce repeated food waste WITHOUT recreating the previous strike/suspension system.

IMPORTANT:

There are NO strikes.

There is NO automatic permanent ban.

There is NO "2 no-shows = suspension" rule.

Restrictions must be gradual, reversible and based on the existing Pickup Reliability System.

---

# 1. CORE PRINCIPLE

Reliability measures behavior.

Restrictions protect cafe operations.

The reliability engine remains the source of truth.

The restriction system consumes:

reliabilityScore

reliabilityStatus

eligibleOrders

recent performance

The restriction system must NOT recalculate reliability independently.

---

# 2. DO NOT CHANGE THE RELIABILITY ENGINE

Do not duplicate:

collectionRate

recentCollectionRate

reliabilityScore

reliabilityStatus

calculations.

Use the existing Phase B backend-maintained values.

If the backend changes the reliability summary:

the restriction state must be recalculated from that authoritative data.

Do not calculate restrictions inside Flutter.

---

# 3. RECOMMENDED RESTRICTION LEVELS

Use the following policy.

## LEVEL 0 — NORMAL

Reliability:

90–100

Status:

EXCELLENT

or

GOOD

Behavior:

Normal ordering.

No restrictions.

---

## LEVEL 1 — WARNING

Reliability:

50–89

Status:

GOOD

or

NEEDS_IMPROVEMENT

Behavior:

Normal ordering.

Show helpful reminder.

No order-limit restriction yet.

This level is primarily informational.

---

## LEVEL 2 — LIMITED

Reliability:

25–49

Status:

POOR

Behavior:

Maximum:

2 active orders

at the same time.

The student may still:

Browse

Search

Add to cart

Place orders

Collect orders

View history

Do not block ordering completely.

---

## LEVEL 3 — HIGHLY LIMITED

Reliability:

0–24

Status:

CRITICAL

Behavior:

Maximum:

1 active order

at a time.

Show a stronger pickup reminder before checkout.

Do not suspend the account.

Do not ban the account.

Do not permanently block ordering.

---

# 4. IMPORTANT — MINIMUM HISTORY

Do NOT apply restrictions to users with insufficient history.

If:

eligibleOrders < 3

restrictionLevel must remain:

NORMAL

regardless of reliability score.

Reason:

A student with one missed order should not receive meaningful restrictions based on insufficient evidence.

---

# 5. NEW USERS

If:

eligibleOrders == 0

restrictionLevel:

NORMAL

No restrictions.

No warning.

---

# 6. INSUFFICIENT HISTORY

If:

eligibleOrders = 1 or 2

restrictionLevel:

NORMAL

The account remains unrestricted.

The user can build a reliable pickup history naturally.

---

# 7. RESTRICTED USER DATA

Extend the existing user reliability summary.

Do not create unnecessary collections.

Prefer adding:

pickupReliability.restrictionLevel

and:

pickupReliability.restrictionReason

Example:

pickupReliability: {
    reliabilityScore: 42,
    status: "POOR",
    restrictionLevel: "LIMITED",
    restrictionReason: "Low pickup reliability",
    ...
}

Use actual project schema conventions.

Do not duplicate reliability fields elsewhere.

---

# 8. DERIVE RESTRICTIONS SERVER-SIDE

The authoritative restriction level must be calculated server-side.

Flutter must never be allowed to write:

restrictionLevel = NORMAL

or:

restrictionLevel = LIMITED

Students cannot manipulate their own restrictions.

---

# 9. RESTRICTION STATES

Use explicit constants/enums.

Recommended:

NORMAL

LIMITED

HIGHLY_LIMITED

Do NOT use:

BANNED

SUSPENDED

STRIKE

PUNISHED

unless these already have an unrelated legitimate use elsewhere in the product.

The new system is intentionally not a strike system.

---

# 10. ACTIVE ORDER DEFINITION

Before implementing an order-limit restriction, define exactly what counts as active.

Recommended active statuses:

PENDING

ACCEPTED

PREPARING

READY

Do NOT count:

CANCELLED

COLLECTED

NO_SHOW

REJECTED

as active orders.

Use the existing canonical OrderStatus values.

Do not create a second definition elsewhere.

---

# 11. ACTIVE ORDER LIMIT

For:

NORMAL

No artificial limit.

For:

LIMITED

maximum:

2 active orders.

For:

HIGHLY_LIMITED

maximum:

1 active order.

---

# 12. CHECK ORDER LIMIT SERVER-SIDE

The Flutter client must not be the sole authority.

Do NOT rely only on:

if (activeOrders >= 2)

inside Flutter.

A malicious client could bypass this.

The backend order-creation workflow must validate:

current restrictionLevel

current active order count

requested new order

before creating the order.

---

# 13. ORDER CREATION FLOW

When the student attempts to place an order:

1. Authenticate user.
2. Read authoritative user reliability/restriction state.
3. Determine active-order limit.
4. Count the user's currently active orders using an efficient indexed query or transaction-compatible approach.
5. If within limit:
   allow order creation.
6. If limit exceeded:
   reject the order.
7. Return a user-friendly business error.

Do not create the order first and cancel it later.

---

# 14. PREVENT RACE CONDITIONS

Two devices may attempt to place orders simultaneously.

Example:

restrictionLevel = HIGHLY_LIMITED

activeOrderLimit = 1

Current active orders:

1

Device A attempts order.

Device B attempts order.

Both must not successfully bypass the limit.

Use a transaction or another server-authoritative mechanism that is compatible with the existing order architecture.

Do not rely on client-side counters.

---

# 15. FIRESTORE COST OPTIMIZATION

Do NOT query all historical orders.

Only count active orders.

Use indexed fields such as:

studentId

status

The query should exclude terminal states.

Do not download every active order to the client.

Where possible, use Firestore aggregation/count queries rather than reading complete order documents.

Use the smallest query necessary.

---

# 16. MY PROFILE SCREEN

Phase D already displays reliability.

Extend the existing UI only where appropriate.

If:

NORMAL

show:

"Normal ordering"

If:

LIMITED

show:

"Your pickup record needs improvement."

"Your account currently allows up to 2 active orders."

If:

HIGHLY_LIMITED

show:

"Your pickup record needs significant improvement."

"Your account currently allows 1 active order at a time."

Do not use threatening language.

---

# 17. CHECKOUT EXPERIENCE

If the user is approaching the active-order limit, provide a clear explanation before attempting checkout.

Example:

"You currently have 2 active orders. Collect one before placing another order."

For HIGHLY_LIMITED:

"You currently have an active order. Please collect it before placing another order."

Do not reveal internal implementation details.

Do not mention Firestore.

Do not mention reliability algorithms.

---

# 18. FAILURE HANDLING

If the backend cannot determine the active order count:

DO NOT assume:

0 active orders.

Fail safely.

Display:

"Unable to verify your active orders. Please try again."

Do not allow a client-side fallback to bypass the restriction.

---

# 19. RECOVERY

Restrictions are NOT permanent.

When reliability improves:

restrictionLevel must automatically improve according to the current authoritative reliability summary.

Example:

HIGHLY_LIMITED
    ↓
successful collections
    ↓
reliability improves
    ↓
LIMITED
    ↓
further improvement
    ↓
NORMAL

Do not require manual admin intervention for normal recovery.

---

# 20. IMPORTANT — DO NOT REMOVE RESTRICTIONS TOO QUICKLY

Use the existing reliability score.

Do not immediately restore NORMAL after a single successful collection if the calculated reliability remains in a restricted range.

The restriction follows the current reliability state.

This prevents users from repeatedly oscillating between:

NORMAL

and:

LIMITED

after one successful order.

---

# 21. NO-SHOW EFFECT

A NO_SHOW does NOT directly set:

restrictionLevel

The correct flow is:

NO_SHOW

↓

Reliability engine updates statistics

↓

Reliability score changes

↓

Restriction engine reevaluates restriction level

This maintains a clean separation of responsibilities.

---

# 22. COLLECTION EFFECT

A COLLECTED order similarly does not directly set:

restrictionLevel

Instead:

COLLECTED

↓

Reliability engine updates statistics

↓

Reliability score changes

↓

Restriction engine reevaluates restriction level

---

# 23. CANCELLATION EFFECT

A valid:

CANCELLED

order does NOT affect reliability.

Therefore it does not directly affect restrictions.

Do not count cancellation as a no-show.

Do not lower reliability for a valid cancellation inside the 2-minute cancellation window.

---

# 24. ADMIN PRIVILEGES

Do not create admin manual restriction controls in this phase.

The restriction level should be automatically derived.

Admins may view the restriction state.

Do NOT allow admins to arbitrarily change:

restrictionLevel

through direct Firestore writes.

Admin override/pardon functionality will be implemented separately.

---

# 25. ADMIN VISIBILITY

The Admin App may display:

Student reliability

Restriction level

Active-order limit

But it must remain read-only in this phase.

Example:

Student:

John Doe

Reliability:

38%

Status:

POOR

Restriction:

LIMITED

Active order limit:

2

---

# 26. SECURITY RULES

Students:

Can read their own:

pickupReliability

restrictionLevel

restrictionReason

Students CANNOT modify them.

Do not allow:

request.resource.data.pickupReliability != resource.data.pickupReliability

from the client.

The backend is authoritative.

---

# 27. CLOUD FUNCTION / BACKEND SEPARATION

Use the existing reliability backend.

Do not create a new independent reliability calculation engine.

Recommended flow:

Order terminal event
        ↓
Reliability Engine
        ↓
Update reliability summary
        ↓
Restriction Engine
        ↓
Update restriction level

If existing server-side code can be extended, extend it.

Do not duplicate business logic.

---

# 28. IDEMPOTENCY

The restriction update must be safe if the same order event is processed more than once.

Example:

NO_SHOW

processed twice.

Expected:

Reliability updates once.

Restriction state remains correct.

No duplicate writes.

Use the existing event-processing/idempotency mechanism.

---

# 29. MINIMIZE FIRESTORE WRITES

Do not write restriction data when it has not changed.

Example:

Current:

LIMITED

New calculation:

LIMITED

Do NOT write again.

Only write if:

restrictionLevel changed

or:

restrictionReason changed.

This prevents unnecessary writes.

---

# 30. MINIMIZE FIRESTORE READS

Do not add a new reliability query to AccountScreen.

The user profile already contains:

reliability summary

and:

restriction level

Reuse that.

Order creation should perform only the minimum required backend reads/count queries.

Do not query:

reviews

food_items

notifications

historical orders

when enforcing active-order limits.

---

# 31. PERFORMANCE

The restriction system must:

- perform no client polling
- perform no periodic reliability calculations
- perform no per-second writes
- perform no full order-history scans
- reuse existing user profile listeners
- use indexed active-order queries

---

# 32. OFFLINE BEHAVIOR

If the user is offline:

The app may display cached restriction information.

However:

placing a new order must require authoritative backend validation.

Do not allow offline order creation to bypass the restriction.

---

# 33. NOTIFICATIONS

Do NOT create new restriction notifications in this phase.

Do not automatically send:

"Your account is restricted."

unless the existing notification architecture already explicitly requires it.

Notification behavior can be added later.

---

# 34. USER-FRIENDLY LANGUAGE

Avoid punitive wording.

Use:

"Pickup reliability"

"Ordering limits"

"Please collect your orders on time"

"Collect an active order before placing another one"

Avoid:

"Bad user"

"Penalty"

"Strike"

"Punishment"

"Ban"

"Suspension"


---

# 35. ACCESSIBILITY

Restriction messages must be accessible.

Use semantic labels.

Do not communicate restriction state using color alone.

Ensure:

- readable text
- sufficient contrast
- screen-reader compatibility
- large text support

---

# 36. TESTING

Create tests for:

## Test 1 — New user

eligibleOrders = 0

Expected:

restrictionLevel = NORMAL

---

## Test 2 — Good reliability

score = 95

Expected:

NORMAL

---

## Test 3 — Needs improvement

score = 65

Expected:

NORMAL

No restriction yet.

---

## Test 4 — Poor reliability

score = 40

eligibleOrders >= 3

Expected:

LIMITED

active-order limit = 2

---

## Test 5 — Critical reliability

score = 20

eligibleOrders >= 3

Expected:

HIGHLY_LIMITED

active-order limit = 1

---

## Test 6 — Insufficient history

eligibleOrders = 1

score low

Expected:

NORMAL

No restriction.

---

## Test 7 — Two active orders

restrictionLevel = LIMITED

activeOrders = 2

Attempt third order.

Expected:

REJECTED.

---

## Test 8 — One active order

restrictionLevel = HIGHLY_LIMITED

activeOrders = 1

Attempt second order.

Expected:

REJECTED.

---

## Test 9 — Active order becomes COLLECTED

LIMITED student:

activeOrders = 2

One becomes COLLECTED.

Expected:

activeOrders = 1

Student may place another order.

---

## Test 10 — Active order becomes NO_SHOW

Order becomes NO_SHOW.

Expected:

It no longer counts toward active-order limit.

Reliability updates.

Restriction reevaluates afterward.

---

## Test 11 — CANCELLED order

Order is CANCELLED.

Expected:

It does not count toward reliability.

It does not count toward active-order limit.

---

## Test 12 — Recovery

Restricted student improves reliability.

Expected:

restriction level changes automatically when score crosses threshold.

---

## Test 13 — Student manipulation

Client attempts:

restrictionLevel = NORMAL

Expected:

PERMISSION_DENIED.

---

## Test 14 — Concurrent order attempts

Restricted student at active-order limit.

Two devices attempt order creation simultaneously.

Expected:

The active-order limit cannot be bypassed.

---

## Test 15 — Backend unavailable

Attempt order creation while authoritative restriction check cannot complete.

Expected:

Order is not created.

User receives a retry message.

---

# 37. SECURITY TESTING

Verify:

✓ Student cannot modify reliability.

✓ Student cannot modify restriction level.

✓ Student cannot modify active-order counts.

✓ Student cannot create orders beyond the limit.

✓ Student cannot use a second device to bypass restrictions.

✓ Students cannot modify another user's data.

✓ Admin cannot arbitrarily modify restriction fields.

✓ Backend remains authoritative.

## Client-side order creation is revoked

Firestore Rules expose NO client create path on /orders: the
validOrderCreateRequest() helper was removed and `allow create` was revoked.
Orders are created exclusively by the placeOrder callable (Admin SDK), so the
active-order limit cannot be bypassed by writing an order document directly,
and server-owned fields (createdAt, cancellationDeadline, readyAt,
pickupDeadline, collectedAt, expiredAt, noShowProcessed, ...) cannot be forged
on create.

Consequence: app builds older than Phase E (which placed orders with a direct
client Firestore write) can no longer place orders and must update — the
current app already routes every order through the callable.

---

# 38. COST AUDIT

Before declaring Phase E complete:

For every new Firestore operation document:

- collection/path
- operation
- reason
- expected frequency

Target:

Reliability update:
only on COLLECTED/NO_SHOW events.

Restriction update:
only when restriction state changes.

Order creation validation:
one minimal active-order query/count per order attempt, or a transaction-compatible mechanism already used by the project.

Account screen:
no additional reliability reads if user profile data is already loaded.

---

# 39. BACKWARD COMPATIBILITY

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
- reliability engine
- grace period
- notifications
- reviews
- favourites
- admin order management
- in-app updates

Do not reintroduce the old strike engine.

---

# 40. DO NOT IMPLEMENT FUTURE PHASES

STOP after Phase E.

Do NOT implement:

❌ temporary ordering cooldowns
❌ admin pardon/override
❌ food rescue
❌ food waste analytics
❌ reliability rewards
❌ reliability notifications
❌ permanent account suspension
❌ account banning
❌ strike system
❌ new punishment system

Those belong to future phases.

---

# 41. FINAL ACCEPTANCE CRITERIA

Phase E is complete only when:

✓ Restriction level derives from existing reliability.

✓ New users are unrestricted.

✓ Insufficient-history users are unrestricted.

✓ Good users are unrestricted.

✓ Poor users can be limited to 2 active orders.

✓ Critical users can be limited to 1 active order.

✓ Active order count is enforced server-side.

✓ Client UI cannot bypass restrictions.

✓ Concurrent order attempts cannot bypass limits.

✓ CANCELLED orders are excluded.

✓ COLLECTED orders are removed from active count.

✓ NO_SHOW orders are removed from active count.

✓ Restrictions automatically recover when reliability improves.

✓ No restriction is applied from a single no-show alone.

✓ No strikes are created.

✓ No accounts are banned.

✓ No accounts are suspended.

✓ No unnecessary Firestore reads are introduced.

✓ No unnecessary Firestore writes are introduced.

✓ Existing reliability system remains authoritative.

✓ Existing order lifecycle remains functional.

✓ Existing cancellation remains functional.

✓ Existing grace period remains functional.

✓ Existing notifications remain functional.

---

# REQUIRED FINAL REPORT

After completion, provide:

1. Files inspected.
2. Files modified.
3. Files created.
4. Restriction model.
5. Restriction thresholds.
6. Active-order definition.
7. Server-side enforcement mechanism.
8. Concurrency strategy.
9. Reliability integration.
10. Firestore security changes.
11. Firestore reads introduced.
12. Firestore writes introduced.
13. Cost analysis.
14. Tests performed.
15. Security tests.
16. Any unresolved risks.

STOP AFTER PHASE E.

Do not begin Phase F.

---

# Phase Completion Criteria

Phase C is complete when:

* The new features works well with past features.
* App runs successfully.
* No runtime errors occur.
