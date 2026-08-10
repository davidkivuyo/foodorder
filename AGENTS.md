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

# PHASE B — ORDER CANCELLATION & 2-MINUTE CANCELLATION WINDOW

## OBJECTIVE

Implement a production-ready order cancellation system for CampusBite.

The student must have a 2-minute cancellation window immediately after successfully placing an order.

During this window:

- The student can cancel the order.
- The cafe must NOT be allowed to accept/process the order.
- The order remains in a cancellable state.
- Cancellation must be authoritative on the backend.
- A cancelled order must NOT count as a NO_SHOW.
- A cancelled order must NOT negatively affect Pickup Reliability.
- The system must remain safe if the app closes, crashes, loses network connectivity, or the student changes devices.

IMPORTANT:

The order must still be created in Firestore immediately when the order is placed.

Do NOT attempt to keep the order only in local Flutter memory for two minutes.

The database is the source of truth.

---

# 1. FIRST — AUDIT THE EXISTING ORDER SYSTEM

Before modifying anything, inspect:

- Order model
- OrderStatus enum
- Order creation logic
- CartService / OrderService
- Firestore order collection
- Student checkout screen
- Admin order screen
- Admin status transition code
- Existing order timestamps
- Existing notifications
- Existing Cloud Functions
- Firestore Security Rules
- Phase A NO_SHOW implementation
- Phase B reliability implementation

Do not assume field names.

Reuse existing architecture.

Do not create a second order system.

---

# 2. REQUIRED ORDER STATES

The existing order lifecycle must remain intact.

The cancellation window introduces one important distinction:

PENDING / PLACED
        ↓
CANCELLATION WINDOW
        ↓
ACCEPTED
        ↓
PREPARING
        ↓
READY
        ↓
COLLECTED

Alternative:

PENDING
   ↓
CANCELLED

or:

READY
   ↓
NO_SHOW

The important rule is:

CANCELLED is a terminal state.

A cancelled order must never later become:

ACCEPTED
PREPARING
READY
COLLECTED
NO_SHOW

---

# 3. DO NOT BREAK THE EXISTING ORDER LIFECYCLE

Do not rename existing statuses unless absolutely necessary.

If the current application uses:

PENDING

or:

PLACED

reuse that status.

If the current application already has an appropriate initial status, reuse it.

Only add a new status if the current architecture genuinely requires one.

Preferred conceptual states:

PENDING
ACCEPTED
PREPARING
READY
COLLECTED
NO_SHOW
CANCELLED

---

# 4. REQUIRED CANCELLATION FIELDS

Inspect the existing order document first.

If equivalent fields already exist, reuse them.

Otherwise add:

createdAt
cancellationDeadline
cancelledAt
cancelledBy
cancellationReason

Example:

{
  "status": "PENDING",

  "createdAt": Timestamp,

  "cancellationDeadline": Timestamp,

  "cancelledAt": null,

  "cancelledBy": null,

  "cancellationReason": null
}

Do not duplicate existing timestamps.

Use the existing project naming conventions.

---

# 5. TWO-MINUTE WINDOW

The cancellation window is exactly:

2 minutes

The authoritative deadline should be:

cancellationDeadline =
createdAt + 2 minutes

Do NOT calculate the authoritative deadline using the student's device clock.

Use a trusted server timestamp.

Do not use:

DateTime.now()

as the authoritative source.

The Flutter application may calculate/display the countdown locally, but the backend must enforce the actual deadline.

---

# 6. ORDER CREATION

When the student confirms an order:

1. Create the order in Firestore.
2. Set the initial status to PENDING/PLACED.
3. Set createdAt using a server timestamp.
4. Establish cancellationDeadline.
5. Store the student UID.
6. Store the order items.
7. Store cafe information.
8. Store total amount.
9. Make the order visible to the authorized cafe/admin system.

Do not leave the order only in local state.

---

# 7. IMPORTANT — CAFE MUST RESPECT THE WINDOW

During the cancellation window:

The cafe must not transition:

PENDING → ACCEPTED

unless the cancellation window has expired.

The backend must enforce this.

Do NOT rely solely on the admin Flutter UI hiding the Accept button.

A malicious or outdated client could bypass the UI.

The backend must reject an early acceptance attempt.

---

# 8. BACKEND ACCEPTANCE VALIDATION

Before allowing:

PENDING → ACCEPTED

verify:

1. Order exists.
2. Current status is PENDING.
3. Order has not been cancelled.
4. Cancellation deadline has passed.
5. Student account is valid.
6. Admin is authorized for that cafe.

Conceptually:

if status != PENDING:
    reject

if currentServerTime < cancellationDeadline:
    reject

if status == CANCELLED:
    reject

Otherwise:

PENDING → ACCEPTED

The server must perform the authoritative time comparison.

---

# 9. STUDENT CANCELLATION

The student should see:

"Cancel order"

during the cancellation window.

The UI should display something similar to:

Cancel order
01:42 remaining

The exact design should follow the existing CampusBite UI.

Do not redesign unrelated screens.

---

# 10. CANCELLATION BUTTON

The cancel button should:

1. Check that the user owns the order.
2. Request the backend cancellation operation.
3. Backend verifies the order is still cancellable.
4. Backend verifies the cancellation deadline.
5. Backend verifies current status is PENDING.
6. Backend changes status to CANCELLED.
7. Backend records cancellation metadata.
8. Flutter updates the UI.

Do not let the Flutter client directly set:

status = CANCELLED

unless the existing security architecture explicitly supports a secure conditional update.

Prefer a server-side transaction/callable operation.

---

# 11. CANCELLATION AUTHORIZATION

A student may cancel ONLY their own order.

The backend must verify:

request.auth.uid == order.studentId

or whatever field the existing architecture uses.

Student A must never be able to cancel Student B's order.

---

# 12. ATOMIC CANCELLATION

Cancellation must be atomic.

Example:

Student presses Cancel

while at the same time:

Cafe presses Accept.

Possible race:

Student:
PENDING → CANCELLED

Cafe:
PENDING → ACCEPTED

The system must never produce an inconsistent result.

Only one transition may succeed.

Use a Firestore transaction or another authoritative backend mechanism.

The order's current state must be checked inside the transaction.

---

# 13. CANCELLATION DEADLINE

The cancellation operation must verify the authoritative server time.

Conceptually:

if currentTime <= cancellationDeadline:
    allow cancellation

else:
    reject cancellation

If the deadline has passed:

The student should receive:

"Cancellation window has expired."

Do not silently cancel the order after the deadline.

---

# 14. EXACT TWO-MINUTE BEHAVIOR

Example:

Order created:

10:00:00

Cancellation deadline:

10:02:00

At:

10:01:59

Cancellation:

ALLOWED

At:

10:02:00+

Cancellation:

REJECTED

Use a consistent boundary rule.

Prefer:

currentTime < cancellationDeadline

for the cancellable interval.

Document this decision in the code.

---

# 15. APP CLOSE / REOPEN

The cancellation window must survive:

- app closing
- app restart
- phone restart
- navigation away from order screen
- switching screens
- temporary network loss

When the student reopens the order:

Read:

status
createdAt
cancellationDeadline

Then calculate the remaining UI time.

Do NOT start a new two-minute timer every time the screen opens.

The deadline comes from Firestore.

---

# 16. NETWORK LOSS

If the user presses Cancel while offline:

Do not show:

"Order cancelled"

unless the cancellation was actually confirmed by the backend.

Instead show an appropriate error such as:

"Unable to cancel the order. Check your connection and try again."

When the network returns, the application should refresh the authoritative order state.

---

# 17. CANCELLATION AND RELIABILITY

This is critical.

A CANCELLED order must NOT count as:

NO_SHOW

A CANCELLED order must NOT count as:

COLLECTED

A CANCELLED order must NOT increase:

eligibleOrders

noShowOrders

collectedOrders

A cancelled order must be completely excluded from Pickup Reliability calculations.

The reliability system should only process:

COLLECTED

and:

NO_SHOW

terminal pickup outcomes.

---

# 18. CANCELLATION AND NO-SHOW ENGINE

The NO_SHOW processor must ignore:

CANCELLED

orders.

It must only process orders that are:

READY

and whose:

pickupDeadline

has expired.

A cancelled order must never become NO_SHOW.

---

# 19. CANCELLATION AND NOTIFICATIONS

Review the existing notification system.

When cancellation succeeds, optionally create/send the appropriate order cancellation notification if the existing product notification design requires it.

Do not introduce duplicate notifications.

Do not implement a new notification architecture.

If the independent:

notifications

collection already exists, use the existing architecture.

---

# 20. ADMIN UI

During the cancellation window, the admin should see:

"PENDING — Cancellation window"

rather than treating it as a normal accepted order.

The Accept action should either:

- be disabled until the window expires, or
- display that the order cannot yet be accepted.

However, UI enforcement is NOT sufficient.

The backend must enforce the rule.

After the deadline expires:

Accept becomes available.

---

# 21. ADMIN RACE CONDITION

Consider:

Order placed at 12:00.

Deadline = 12:02.

At 12:01:30:

Admin tries Accept.

Expected:

REJECTED.

At 12:02:01:

Admin tries Accept.

Expected:

ALLOWED.

At 12:01:45:

Student cancels.

At 12:01:50:

Admin tries Accept.

Expected:

REJECTED because status is already CANCELLED.

---

# 22. CANCELLATION REASON

Allow an optional cancellation reason.

Recommended initial choices:

- Changed my mind
- Ordered by mistake
- Need to change my order
- Ordered the wrong item
- Other

Do not require free-form text initially unless the product requires it.

If "Other" is supported, limit the length.

Example:

max 200 characters.

Do not allow arbitrary massive strings.

---

# 23. ORDER ITEM MODIFICATION

Do NOT implement editing of an existing order during the cancellation window unless explicitly required.

The safest initial implementation is:

Cancel existing order
+
Create a new order

if the student wants a different order.

This prevents partial order modifications and pricing inconsistencies.

---

# 24. CART BEHAVIOR

After an order is successfully placed:

Do not automatically restore the cancelled order's items into the cart unless the existing UX explicitly requires this.

If implementing "Reorder" later, handle it separately.

For now:

Order cancellation should only change the order state.

---

# 25. PAYMENT COMPATIBILITY

If the app currently has no payment integration:

Do not implement payment logic.

If payment functionality exists:

Cancellation must be designed so the payment state is not incorrectly represented.

Never mark a payment as refunded unless the backend has actually performed the refund.

Do not invent refund behavior.

---

# 26. SECURITY RULES

Students must be able to:

READ their own orders.

They must NOT be able to arbitrarily modify:

status
createdAt
cancellationDeadline
cancelledAt
cancelledBy

Do not use:

allow read, write: if request.auth != null;

for orders.

Admin writes must be restricted according to cafe/admin authorization.

Backend operations should perform authoritative state transitions.

---

# 27. FIRESTORE COST OPTIMIZATION

Do not implement:

- per-second Firestore writes
- per-second countdown updates
- polling every second
- repeated order reads
- periodic cancellation checks from every student device

The Flutter countdown must be local.

Example:

Firestore:

createdAt
cancellationDeadline

Flutter:

remaining =
cancellationDeadline - current local time

The countdown is UI only.

Only actual cancellation or status transitions should write to Firestore.

---

# 28. SERVER-SIDE DEADLINE ENFORCEMENT

Do not create a Cloud Function that wakes up every second for every order.

That would be unnecessarily expensive.

The system only needs to enforce:

PENDING → ACCEPTED

and:

PENDING → CANCELLED

using the authoritative deadline.

The actual automatic transition to another state is unnecessary at this stage.

After the cancellation deadline expires, the order can simply remain:

PENDING

until an authorized cafe accepts it.

---

# 29. EXPIRED PENDING ORDERS

Do not automatically mark an expired PENDING order as:

NO_SHOW.

NO_SHOW only applies after the order becomes:

READY

and the pickup deadline expires.

An order that remains PENDING after its cancellation window is simply:

PENDING with cancellationExpired = true

or equivalent derived state.

Do not create a new terminal failure state unless the product explicitly requires it.

---

# 30. OPTIONAL DERIVED UI STATE

Do not unnecessarily store:

cancellationWindowActive

in Firestore.

It can be derived from:

status
createdAt
cancellationDeadline
current time

For example:

isCancellable =
status == PENDING &&
currentTime < cancellationDeadline

This avoids unnecessary writes.

---

# 31. ORDER STATUS HISTORY

If the existing system already has an order status history mechanism, add:

CANCELLED

to it.

If no history mechanism exists, do not create a complex audit architecture solely for this phase.

At minimum preserve:

cancelledAt
cancelledBy
cancellationReason

for the cancelled order.

---

# 32. AUDITABILITY

A cancellation should be traceable.

Store:

cancelledAt
cancelledBy
cancellationReason

Use:

cancelledBy = student UID

for student cancellation.

Do not store unnecessary personal information.

---

# 33. TESTING

Create automated tests for:

### Test 1
Order created.

Expected:

PENDING

Cancellation available.

---

### Test 2
Cancel after 30 seconds.

Expected:

CANCELLED.

---

### Test 3
Cancel after 1 minute 59 seconds.

Expected:

CANCELLED.

---

### Test 4
Cancel after 2 minutes.

Expected:

REJECTED.

---

### Test 5
Admin attempts Accept before 2 minutes.

Expected:

REJECTED.

---

### Test 6
Admin accepts after 2 minutes.

Expected:

ACCEPTED.

---

### Test 7
Student cancels while admin attempts Accept.

Expected:

Only one transition succeeds.

Final state must be either:

CANCELLED

or:

ACCEPTED

Never both.

---

### Test 8
Try to cancel an ACCEPTED order.

Expected:

REJECTED.

---

### Test 9
Try to cancel a PREPARING order.

Expected:

REJECTED.

---

### Test 10
Try to cancel a READY order.

Expected:

REJECTED.

---

### Test 11
Try to cancel a COLLECTED order.

Expected:

REJECTED.

---

### Test 12
Try to cancel a NO_SHOW order.

Expected:

REJECTED.

---

### Test 13
Cancelled order reaches pickup deadline.

Expected:

It remains CANCELLED.

It must NOT become NO_SHOW.

---

### Test 14
Cancelled order enters reliability processor.

Expected:

Ignored.

---

### Test 15
Student attempts to cancel another student's order.

Expected:

PERMISSION_DENIED.

---

### Test 16
Student attempts to modify cancellationDeadline.

Expected:

PERMISSION_DENIED.

---

### Test 17
Student closes app and reopens it during cancellation window.

Expected:

Remaining cancellation time is calculated from the stored deadline.

---

### Test 18
Student loses network.

Expected:

No false cancellation confirmation.

---

# 34. UI TESTING

Verify:

- Countdown displays correctly.
- Countdown reaches zero.
- Cancel button disappears/disables after expiry.
- Order status updates after successful cancellation.
- Error state appears when cancellation fails.
- App restart preserves the correct remaining time.
- Admin cannot accept during the window.
- Admin can accept after the window.

---

# 35. PERFORMANCE AUDIT

Before completing this phase, inspect all new Firestore operations.

For every operation document:

WHY is this read required?

WHY is this write required?

Remove unnecessary operations.

The target should be:

Order creation:
1 order write

Cancellation:
1 authoritative order update

Acceptance:
1 authoritative order update

Countdown:
0 Firestore writes

Countdown refresh:
0 Firestore writes

Reliability update:
0 additional work for cancellation

---

# 36. BACKWARD COMPATIBILITY

Do not break:

- authentication
- cart
- checkout
- student orders
- admin orders
- READY
- COLLECTED
- NO_SHOW
- notifications
- reliability system
- Firestore security
- existing order history

Do not modify unrelated collections.

---

# 37. FINAL VALIDATION

Phase B.1 is complete only when:

✓ 2-minute cancellation window works.

✓ Deadline is server-authoritative.

✓ Student can cancel only their own pending order.

✓ Cancellation is atomic.

✓ Admin cannot accept during cancellation window.

✓ Admin can accept after cancellation window expires.

✓ Cancelled orders cannot later become ACCEPTED.

✓ Cancelled orders cannot become PREPARING.

✓ Cancelled orders cannot become READY.

✓ Cancelled orders cannot become COLLECTED.

✓ Cancelled orders cannot become NO_SHOW.

✓ Cancelled orders do not affect reliability.

✓ No per-second Firestore writes exist.

✓ No polling loop has been introduced.

✓ App restart preserves the cancellation window.

✓ Network failures do not create false cancellation confirmations.

✓ Security rules prevent unauthorized modification.

✓ Existing order lifecycle remains functional.

✓ Existing Phase A and Phase B functionality remains functional.

---

# REQUIRED FINAL REPORT

When complete, report:

1. Files inspected.
2. Files modified.
3. Files created.
4. Existing order lifecycle.
5. Cancellation implementation.
6. Cancellation deadline implementation.
7. Backend authorization mechanism.
8. Race-condition handling.
9. Firestore security changes.
10. Firestore reads introduced.
11. Firestore writes introduced.
12. Reliability-system integration.
13. Tests performed.
14. Security tests performed.
15. Performance/cost audit.
16. Any unresolved issues.

STOP AFTER THIS PHASE.

Do not implement account restrictions, suspension, banning, reliability penalties, or additional automatic punishment.

---

# Phase Completion Criteria

Phase B is complete when:

* The new features works well with past features.
* App runs successfully.
* No runtime errors occur.
