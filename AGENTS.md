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

# PHASE D — PICKUP RELIABILITY EXPERIENCE

## OBJECTIVE

Implement Phase D of the CampusBite Pickup Reliability System.

Previous phases completed:

✓ Phase A — No-show foundation
✓ Phase B — Pickup Reliability calculation
✓ Phase B.1 — 2-minute order cancellation window
✓ Phase C — Pickup grace period and automatic NO_SHOW

Phase D introduces the student-facing reliability experience.

This phase must:

- display the student's pickup reliability clearly
- explain the reliability status
- provide gentle warnings when performance declines
- encourage successful future collections
- distinguish information from punishment
- preserve the existing order/reliability architecture

IMPORTANT:

This phase does NOT introduce restrictions.

This phase does NOT suspend accounts.

This phase does NOT ban users.

This phase does NOT introduce strikes.

This phase does NOT limit the number of active orders.

This phase does NOT introduce ordering cooldowns.

The system remains non-punitive in this phase.

---

# 1. FIRST — AUDIT EXISTING IMPLEMENTATION

Before changing the UI or services, inspect:

- AccountScreen
- Myprofile Screen
- Student profile/user model
- Pickup reliability model
- Pickup reliability service
- Firestore user document
- Existing account status UI
- Existing order history screen
- Existing notification system
- Existing theme/design system
- Existing localization/string architecture
- Existing state management

Reuse existing components.

Do not create duplicate user streams.

Do not create duplicate reliability calculations.

---

# 2. SOURCE OF TRUTH

The student's reliability information must come from the existing backend-maintained reliability summary.

Do NOT calculate reliability in the AccountScreen.

Do NOT query all historical orders from the AccountScreen.

Do NOT calculate recent performance on every screen load.

Use the existing Phase B reliability fields.

Expected fields may include:

pickupReliability.eligibleOrders

pickupReliability.collectedOrders

pickupReliability.noShowOrders

pickupReliability.collectionRate

pickupReliability.recentEligibleOrders

pickupReliability.recentCollectedOrders

pickupReliability.recentNoShowOrders

pickupReliability.recentCollectionRate

pickupReliability.reliabilityScore

pickupReliability.status

Use actual field names from the current implementation.

---

# 3. MY PROFILE SCREEN

use an existing reusable:

PickupReliabilityCard

It is already in place and used in the Myprofile screen in myprofile.dart

Do not implement it again on Account Screen.

The card should communicate:

- reliability score
- reliability status
- collection history
- missed pickup count
- short explanatory text

Example:

Pickup reliability

92%

Excellent

18 collected · 2 missed

"Thanks for collecting your orders on time."

---

# 4. NEW USER STATE

If:

eligibleOrders == 0

display:

"New pickup record"

or equivalent wording.

Do NOT display:

0% reliability

Do NOT imply that a new user has poor performance.

Suggested message:

"Your pickup record will appear after you complete an order."

---

# 5. INSUFFICIENT HISTORY STATE

If:

eligibleOrders >= 1
AND
eligibleOrders <= 2

show:

"Building your pickup record"

Do not classify the student as:

Poor

Critical

Needs Improvement

unless that is already part of the backend status definition.

Do not introduce punishment.

---

# 6. RELIABILITY STATUS DISPLAY

Use the backend status.

Expected statuses:

NEW

INSUFFICIENT_HISTORY

EXCELLENT

GOOD

NEEDS_IMPROVEMENT

POOR

CRITICAL

Do not create a second status calculation in Flutter.

If the backend uses different names, adapt the UI to the existing canonical status values.

---

# 7. STATUS MESSAGES

Use calm, constructive language.

EXCELLENT:

"Excellent pickup record. Thank you for collecting your orders on time."

GOOD:

"Good pickup record. Keep collecting your orders on time."

NEEDS_IMPROVEMENT:

"Your pickup record needs improvement. Please try to collect your orders within the pickup period."

POOR:

"Please remember to collect your orders during the pickup window to help reduce food waste."

CRITICAL:

"Please make every effort to collect future orders within the pickup period."

Avoid threatening language.

Do not mention:

strike

ban

punishment

suspension

penalty

unless those terms already exist elsewhere for an unrelated feature.

---

# 8. RELIABILITY PROGRESS INDICATOR

Display the reliability score visually.

Example:

92 / 100

with a progress bar or equivalent existing design component.

Do not create a new color system if the app already has an established design system.

Use existing theme colors.

The UI must remain accessible.

Do not rely only on color to communicate status.

---

# 9. COLLECTION SUMMARY

Display concise supporting metrics:

Collected orders

No-show orders

Collection rate

Avoid exposing unnecessary technical fields.

Do not show:

internal IDs

backend status values

timestamps

Firestore fields

---

# 10. RECENT PERFORMANCE

If Phase B stores recent metrics, optionally display a small summary such as:

"Last 10 pickups"

8 collected
2 missed

Only display this if it improves user understanding.

Do not show raw technical arrays.

Do not create another Firestore query.

---

# 11. RECENT SUCCESS ENCOURAGEMENT

When the user has successfully collected multiple recent orders, show positive reinforcement.

Examples:

"Great job — you've collected your recent orders on time."

"Nice work — your pickup record is improving."

Do not reward with discounts or account privileges in this phase.

Only provide informational feedback.

---

# 12. NO-SHOW EXPERIENCE

When an order becomes:

NO_SHOW

the order details screen should show clearly:

"No-show recorded"

and explain:

"The pickup window and grace period ended before the order was collected."

Do NOT display:

"You received a strike."

There is no strike system.

---

# 13. GRACE PERIOD EXPERIENCE

During the grace period, the student UI should distinguish it from the normal pickup period.

For example:

"Pickup window ended"

"Grace period active"

"Please collect your order now."

Use the existing local countdown.

Do not add Firestore writes.

Do not modify the backend deadline.

---

# 14. HARD CUTOFF

When:

currentServerTime >= noShowEligibleAt

the student is no longer eligible to collect the order.

The client must not allow the UI to falsely show:

"Collect now"

if the backend has confirmed expiry.

The app may temporarily show:

"Pickup window expired — updating order..."

until the backend state becomes:

NO_SHOW.

---

# 15. NO CLIENT-SIDE RELIABILITY CALCULATION

Do NOT implement:

collectionRate calculation

recentRate calculation

weighted score calculation

status classification

inside the AccountScreen or UI.

The backend-maintained summary remains authoritative.

Flutter only presents the results.

---

# 16. REAL-TIME UPDATES

If the application already listens to the user's Firestore document:

reuse the existing listener.

Do not add another listener solely for reliability.

If no appropriate existing listener exists:

create one well-scoped listener for the authenticated user's own profile.

Never listen to all users.

---

# 17. FIRESTORE COST REQUIREMENTS

Opening AccountScreen should NOT:

- query orders
- query review history
- query no-show history
- recalculate reliability
- execute a Cloud Function
- write a Firestore document

Use the existing user/profile data.

Target:

0 additional Firestore reads if an existing user listener already supplies the reliability data.

Otherwise:

1 user document read/listener.

---

# 18. ACCESSIBILITY

The reliability card must support:

- screen readers
- large text
- sufficient contrast
- readable percentages
- meaningful semantic labels

Do not rely only on color.

Example semantic label:

"Pickup reliability: 92 percent, Excellent."

---

# 19. RESPONSIVE DESIGN

Verify the reliability card on:

- small phones
- large phones
- tablets where supported

Prevent:

- overflow
- text clipping
- cramped controls
- layout shifts

Reuse existing responsive helpers.

---

# 20. NOTIFICATIONS

Do not build the notification system in this phase.

However, make the UI compatible with the existing notification architecture.

Reliability notifications, if later added, must use the existing:

notifications

collection

and existing FCM pipeline.

Do not create a new notification implementation.

---

# 21. PRIVACY

Reliability information is private.

Students can see:

- their own reliability
- their own collection history summary

Students must never see another student's reliability.

Do not display reliability publicly on food reviews or profiles.

Do not include reliability data in:

- food documents
- public reviews
- notifications visible to other users
- analytics payloads

unless explicitly required in a future phase.

---

# 22. ADMIN APP

Do not implement the admin reliability-management dashboard yet.

However, ensure the backend fields remain readable by properly authorized admins according to the existing architecture.

Do not expose all student reliability data to ordinary authenticated users.

---

# 23. NO PUNISHMENT

This phase must not change ordering privileges.

Regardless of reliability status, the student should still have the same ordering permissions as before.

Do not disable:

Place Order

Add to Cart

Checkout

unless an unrelated existing system already requires it.

---

# 24. TESTING

Create/update tests for:

## Test 1 — New user

eligibleOrders = 0

Expected:

New pickup record

No negative message.

---

## Test 2 — Insufficient history

eligibleOrders = 2

Expected:

Building your pickup record.

No restriction.

---

## Test 3 — Excellent

reliabilityScore = 95

Expected:

Excellent

---

## Test 4 — Good

reliabilityScore = 82

Expected:

Good

---

## Test 5 — Needs improvement

reliabilityScore = 65

Expected:

Needs improvement

Constructive message shown.

---

## Test 6 — Poor

reliabilityScore = 40

Expected:

Poor

Constructive reminder shown.

No restriction.

---

## Test 7 — Critical

reliabilityScore = 20

Expected:

Critical

Constructive reminder shown.

No restriction.

---

## Test 8 — No-show order

Order status = NO_SHOW

Expected:

No-show explanation displayed.

No strike language.

---

## Test 9 — Grace period

Order is still READY during grace period.

Expected:

Grace-period UI.

---

## Test 10 — Hard cutoff

Server confirms:

currentTime >= noShowEligibleAt

Expected:

Collection unavailable.

---

## Test 11 — Real-time reliability update

Backend changes reliability.

Expected:

AccountScreen updates without manual refresh if existing realtime user stream is available.

---

## Test 12 — Student isolation

Student A must never receive Student B's reliability data.

---

# 25. PERFORMANCE TESTING

Verify:

AccountScreen does not query orders.

AccountScreen does not perform reliability calculations.

AccountScreen does not create listeners repeatedly.

Navigating:

Account → Home → Account

must not create duplicate listeners.

Dispose all subscriptions correctly.

---

# 26. VISUAL TESTING

Verify:

- reliability card matches CampusBite design
- typography matches existing theme
- spacing matches existing AccountScreen
- icons follow existing style
- dark/light mode if supported
- accessibility text scaling
- no overflow

---

# 27. LOGGING

Do not log reliability data in production logs.

Avoid logging:

score

collection history

student UID

email

phone

Use generic diagnostics only if required.

---

# 28. BACKWARD COMPATIBILITY

Do not break:

- authentication
- cart
- ordering
- order cancellation
- pickup countdown
- grace period
- NO_SHOW
- reliability calculations
- notifications
- reviews
- favourites
- admin order management

Do not modify existing Firestore schema unnecessarily.

---

# 29. DO NOT IMPLEMENT FUTURE PHASES

STOP after Phase D.

Do NOT implement:

❌ ordering restrictions

❌ active-order limits

❌ ordering cooldowns

❌ automatic suspension

❌ account banning

❌ admin excuse/pardon

❌ food rescue

❌ food waste dashboard

❌ reliability rewards

❌ reliability-based notifications

Those belong to later phases.

---

# 30. FINAL ACCEPTANCE CRITERIA

Phase D is complete only when:

✓ Student can see pickup reliability.

✓ Reliability data comes from the existing backend summary.

✓ No order-history scan occurs on AccountScreen.

✓ New users are not shown as unreliable.

✓ Insufficient-history users are not punished.

✓ Reliability statuses are presented clearly.

✓ No-show explanation is clear and non-punitive.

✓ Grace-period state is clear.

✓ Hard cutoff state is respected.

✓ No new Firestore writes are generated by viewing reliability.

✓ No duplicate listeners are created.

✓ No reliability calculations are duplicated in Flutter.

✓ Privacy is preserved.

✓ Existing ordering remains unchanged.

✓ Existing cancellation remains unchanged.

✓ Existing NO_SHOW processing remains unchanged.

✓ Existing reliability calculation remains unchanged.

✓ Old strike language/system is not reintroduced.

---

# REQUIRED FINAL REPORT

After implementation, provide:

1. Files inspected.
2. Files modified.
3. Files created.
4. Existing reliability data structure used.
5. AccountScreen changes.
6. Reliability card implementation.
7. No-show UI changes.
8. Grace-period UI changes.
9. Firestore reads introduced.
10. Firestore writes introduced.
11. Listener changes.
12. Accessibility improvements.
13. Test results.
14. Performance findings.
15. Any UI/architecture risks.

STOP AFTER PHASE D.

Do not begin Phase E without explicit instructions.

---

# Phase Completion Criteria

Phase C is complete when:

* The new features works well with past features.
* App runs successfully.
* No runtime errors occur.
