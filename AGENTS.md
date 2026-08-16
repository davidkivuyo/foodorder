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

# PHASE I — TESTING & PRODUCTION HARDENING

## OBJECTIVE

Implement Phase I of the CampusBite Pickup Reliability and Food Waste Management system.

This is the final validation and production-hardening phase for:

- Order cancellation
- Pickup deadlines
- Grace period
- Automatic NO_SHOW
- Pickup Reliability
- Graduated Restrictions
- Reliability Recovery
- Admin No-show Excusal
- Cafe Food Disposition

The objective is NOT to add new features.

The objective is to:

1. Validate the complete system.
2. Find and fix defects.
3. Validate security.
4. Validate concurrency and race conditions.
5. Validate Firestore efficiency.
6. Validate Cloud Functions.
7. Validate offline and failure behavior.
8. Validate privacy.
9. Validate release readiness.
10. Document any remaining risks.

DO NOT redesign the system.

DO NOT introduce new punishment mechanisms.

DO NOT reintroduce the old Strike Engine.

---

# 1. CRITICAL PRINCIPLE

Treat this phase as a production release gate.

Do not make speculative architectural changes.

Only modify implementation when:

- a test fails
- a security issue is discovered
- a performance issue is demonstrated
- a reliability issue is demonstrated
- a production blocker is identified

Every change must have a reason.

---

# 2. SYSTEM UNDER TEST

The complete system includes:

## Student App

- Registration
- Email verification
- Login
- Forgot password
- Menu
- Search
- Cart
- Order placement
- 2-minute cancellation
- Pickup countdown
- Grace period
- Order collection
- No-show display
- Pickup reliability
- Graduated restrictions
- Reliability recovery
- Reviews
- Notifications
- FCM
- Favourite menu
- In-app updates

## Admin App

- Admin authentication
- Menu management
- Cloudinary upload
- Order management
- Accept
- Preparing
- Ready
- Collected
- Student reliability visibility
- Admin No-show excusal
- Food disposition
- Notifications
- Audit logs

## Backend

- Firebase Authentication
- Firestore
- Firestore Security Rules
- Cloud Functions
- Scheduled functions
- Notification system
- FCM
- Cloudinary integration
- Cloudflare update proxy

---

# 3. BEFORE TESTING

Create a production-hardening branch.

Example:

production-hardening

Do not perform testing directly against production data unless explicitly approved.

If a staging Firebase project exists:

USE IT.

If no staging project exists:

create a safe testing strategy using controlled test accounts and test documents.

Never use real student personal data for automated testing.

---

# 4. ENVIRONMENT AUDIT

Document:

Flutter version

Dart version

Android Gradle version

Java version

Firebase project

Cloud Functions runtime

Node.js version

Cloudinary configuration

Cloudflare Worker endpoint

Build signing configuration

Current application version

Do not expose secrets in the report.

---

# 5. DEPENDENCY AUDIT

Run:

flutter pub outdated

flutter pub deps

flutter analyze

Review:

- outdated packages
- abandoned packages
- conflicting dependencies
- deprecated APIs
- unused packages

Do not blindly upgrade all dependencies.

Only update packages when:

- compatible with current Flutter version
- stable
- tested
- required for security or production compatibility

Run the full test suite after every dependency change.

---

# 6. STATIC ANALYSIS

Run:

flutter analyze

Fix:

errors

warnings

unused imports

deprecated APIs

unreachable code

unsafe casts

null-safety issues

Do not suppress warnings without understanding their cause.

---

# 7. FORMATTING

Run:

dart format

on changed Dart files.

Do not perform a massive unrelated formatting rewrite.

---

# 8. TEST ORDER LIFECYCLE

Test the complete lifecycle.

## TEST A — Normal order

Student:

Place order

↓

Admin:

Accept

↓

Preparing

↓

Ready

↓

Student collects

↓

Collected

Expected:

- order succeeds
- reliability records one collection
- no NO_SHOW
- no restriction change caused by failure
- no false notification
- order history correct

---

# 9. TEST ORDER CANCELLATION

## TEST B — Cancel within 2 minutes

Student places order.

Cancel before:

cancellationDeadline

Expected:

CANCELLED

Verify:

- cafe cannot accept
- order does not become READY
- order does not become NO_SHOW
- order does not affect reliability
- no false food-waste record

---

# 10. TEST CANCELLATION CUTOFF

## TEST C

Attempt cancellation at or after:

currentServerTime >= cancellationDeadline

Expected:

Cancellation rejected.

Do not trust device clock.

---

# 11. TEST CANCELLATION RACE

## TEST D

Simultaneously attempt:

Student cancellation

and:

Admin acceptance

before cancellation deadline.

Verify only one transaction succeeds.

Possible final states:

CANCELLED

or:

ACCEPTED

Never both.

The application must never create contradictory state.

---

# 12. TEST PICKUP DEADLINE

## TEST E

Admin marks order READY.

Verify:

readyAt exists.

pickupDeadline exists.

pickup deadline is server-authoritative.

Countdown appears correctly.

No Firestore writes occur every second.

---

# 13. TEST NORMAL PICKUP

## TEST F

Student collects before pickup deadline.

Expected:

COLLECTED.

No NO_SHOW.

Reliability:

+ eligible order

+ collected order

---

# 14. TEST GRACE PERIOD

## TEST G

Allow:

pickupDeadline

to pass.

Verify order remains:

READY

during grace period.

Student can still collect.

---

# 15. TEST HARD CUTOFF

## TEST H

At:

currentServerTime >= noShowEligibleAt

attempt collection.

Expected:

collection rejected.

The grace period is a hard cutoff.

A delayed scheduler must NOT extend collection eligibility.

---

# 16. TEST NO-SHOW

## TEST I

READY order

↓

pickup deadline expires

↓

grace period expires

↓

automatic processor runs

Expected:

READY → NO_SHOW

Set:

noShowAt

Do not change unrelated order data.

---

# 17. TEST NO-SHOW IDempotency

## TEST J

Run the automatic NO_SHOW processor twice.

Expected:

First:

READY → NO_SHOW

Second:

no change

No duplicate:

- reliability update
- notification
- audit log
- food disposition event

---

# 18. TEST NO-SHOW VS COLLECTION RACE

## TEST K

Near the hard cutoff:

Attempt simultaneously:

collection

and:

automatic NO_SHOW

Verify:

BEFORE cutoff:
collection may succeed.

AT/AFTER cutoff:
collection must fail.

NO_SHOW may succeed.

There must never be:

COLLECTED + NO_SHOW

---

# 19. TEST RELIABILITY CALCULATION

Verify:

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

Use known test datasets.

Compare actual calculations against expected results.

---

# 20. TEST NEW USERS

User with:

eligibleOrders = 0

Expected:

status = NEW

No restrictions.

No poor-reliability warning.

---

# 21. TEST INSUFFICIENT HISTORY

User with:

1–2 eligible orders.

Expected:

INSUFFICIENT_HISTORY

Restriction:

NORMAL

---

# 22. TEST RESTRICTIONS

Verify Phase E:

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

Verify:

minimum-history rule is respected.

---

# 23. TEST ACTIVE ORDER LIMIT

For:

LIMITED

Maximum active orders:

2

For:

HIGHLY_LIMITED

Maximum active orders:

1

Verify the limit is enforced by backend.

Do not rely only on Flutter UI.

---

# 24. TEST CONCURRENT ORDER ATTEMPTS

A restricted student uses two devices.

Both attempt to place orders simultaneously.

Verify active-order limit cannot be bypassed.

---

# 25. TEST RELIABILITY RECOVERY

Start with a restricted account.

Process successful collections.

Verify:

HIGHLY_LIMITED → LIMITED

and eventually:

LIMITED → NORMAL

when the existing reliability score crosses the appropriate thresholds.

Do not create bonus recovery points.

Use the existing reliability engine.

---

# 26. TEST EXCUSED NO-SHOW

Create:

NO_SHOW

Admin:

Excuse No-show

Expected:

- order remains NO_SHOW
- no-show is excluded from reliability failure calculations
- reliability recalculates
- restriction recalculates
- audit log created
- student notification created if enabled

---

# 27. TEST ADMIN AUTHORIZATION

Test:

Admin from Cafe A

attempting to manage:

Cafe B

Expected:

PERMISSION_DENIED

Test non-admin user attempting the same action.

Expected:

PERMISSION_DENIED

---

# 28. TEST ADMIN AUDIT LOGS

Verify:

- excuse action
- food disposition action
- menu modifications
- other existing privileged actions

create immutable audit records where required.

Verify audit records cannot be edited or deleted through the client.

---

# 29. TEST FOOD DISPOSITION

For a NO_SHOW:

test:

UNRESOLVED

RESOLD

DISCOUNTED

DONATED

STAFF_USE

DISPOSED

OTHER

Verify:

order remains NO_SHOW

reliability does not change

disposition is stored correctly

audit log is created

---

# 30. TEST DISPOSITION CORRECTION

Example:

DONATED

↓

DISPOSED

Verify:

current disposition = DISPOSED

audit history records:

DONATED → DISPOSED

No duplicate current-state record.

---

# 31. TEST UNAUTHORIZED DISPOSITION

Student attempts to change:

foodDisposition

Expected:

PERMISSION_DENIED

Admin from another cafe:

PERMISSION_DENIED

---

# 32. NOTIFICATION TESTING

Verify:

Student:

ORDER_ACCEPTED

ORDER_PREPARING

ORDER_READY

PICKUP_REMINDER

ORDER_NO_SHOW

STRIKE notifications must NOT exist.

Instead use the new reliability/no-show terminology.

Admin:

NEW_ORDER

Food disposition should not create unnecessary student notifications.

---

# 33. FCM TESTING

Test:

Foreground

Background

Terminated

No internet

Token refresh

Invalid token

Duplicate event

Notification tap

Deep link

Verify:

notification is stored in Firestore

push notification is sent

duplicate push is prevented

---

# 34. SECURITY RULE AUDIT

Review every Firestore rule.

Explicitly test:

Student:

- cannot modify reliability
- cannot modify restrictions
- cannot modify NO_SHOW
- cannot modify food disposition
- cannot modify another user's order
- cannot modify another user's cart
- cannot create admin data
- cannot modify audit logs

Admin:

- cannot manage unauthorized cafe
- cannot directly rewrite reliability
- cannot edit audit logs

Public:

- can only read intentionally public content

No rule should contain:

allow read, write: if true;

unless deliberately justified.

---

# 35. CLOUD FUNCTION SECURITY AUDIT

Review every Cloud Function.

Verify:

- authentication
- admin authorization
- ownership
- input validation
- idempotency
- retry safety
- error handling
- secret access

Never expose:

API secrets

stack traces

tokens

private data

---

# 36. FIREBASE SECRETS AUDIT

Verify sensitive credentials are not present in:

- Flutter source
- git history
- GitHub Actions logs
- public release metadata
- Cloudflare responses

Sensitive backend credentials must remain in Firebase Secret Manager or GitHub Secrets as appropriate.

---

# 37. CLOUDINARY SECURITY

Verify:

Flutter never contains:

Cloudinary API Secret

Cloudinary private credentials

Image deletion goes through the authorized backend function.

Only secure URLs/public IDs required by the application are stored.

---

# 38. PRIVACY AUDIT

Verify no unnecessary storage of:

student coordinates

location history

passwords

authentication tokens

FCM tokens in logs

private review content in logs

private admin notes in public documents

Review:

Firestore

Crashlytics

Analytics

Cloud Logging

FCM payloads

---

# 39. FIRESTORE COST AUDIT

Measure and document:

- order creation reads/writes
- order cancellation reads/writes
- READY transition
- NO_SHOW processing
- reliability update
- restriction update
- admin excuse
- food disposition
- notifications
- account screen

Look for:

- duplicate reads
- duplicate writes
- full collection scans
- unnecessary listeners
- per-second writes
- unnecessary scheduled functions

Eliminate unnecessary operations where safe.

---

# 40. FIRESTORE QUERY AUDIT

Every major query must have:

- a clear purpose
- appropriate filters
- appropriate limit/pagination
- necessary indexes

Review:

orders

notifications

reviews

food_items

admin student searches

food disposition records

Do not download unbounded collections.

---

# 41. CLOUD FUNCTION COST AUDIT

Document all:

- scheduled functions
- Firestore triggers
- callable functions
- HTTP functions

For each function document:

- trigger frequency
- expected invocations
- Firestore reads
- Firestore writes
- external API calls
- retry behavior

Remove redundant functions if they duplicate another backend responsibility.

---

# 42. OFFLINE TESTING

Test:

- app starts offline
- menu cache
- account cache
- existing order view
- notification cache
- cart synchronization
- reconnect after offline
- failed writes
- retry behavior

Never allow offline behavior to bypass:

- order limits
- authorization
- cancellation deadlines
- NO_SHOW cutoff

---

# 43. NETWORK FAILURE TESTING

Simulate:

- slow network
- lost network
- intermittent network
- Firebase unavailable
- Cloud Function timeout
- FCM failure
- Cloudflare Worker failure
- GitHub release metadata failure

The application must fail gracefully.

---

# 44. UPDATE SYSTEM TESTING

Test the Cloudflare update proxy:

https://dl.larason.space

Verify:

latest metadata

version comparison

minimum version

force update

optional update

ABI detection

universal fallback

APK download

SHA-256 verification

installation flow

offline update-check failure

Do not allow an invalid or unverified APK to proceed to installation.

---

# 45. APK RELEASE TESTING

For each production tag verify:

CampusBite-universal.apk

CampusBite-arm64-v8a.apk

CampusBite-armeabi-v7a.apk

CampusBite-x86_64.apk

Check:

- package name
- versionName
- versionCode
- signing
- APK opens
- Firebase connection
- update metadata
- checksum

---

# 46. ANDROID PERMISSION AUDIT

Review AndroidManifest.xml.

Remove unused permissions.

Pay particular attention to:

location

internet

notifications

storage

install packages

Only request permissions actually needed.

Location permission must NOT include background tracking unless explicitly required.

---

# 47. DATA RETENTION AUDIT

Document retention for:

- orders
- notifications
- audit logs
- reviews
- reliability summaries
- food disposition records
- device tokens
- logs

Do not implement destructive cleanup without verifying legal/business requirements.

---

# 48. UI/UX REGRESSION TEST

Verify:

- no layout overflow
- dialogs work
- snackbars work
- loading states work
- error states work
- dark/light mode if supported
- accessibility
- large text
- keyboard behavior
- navigation back behavior

---

# 49. ACCESSIBILITY AUDIT

Review:

- semantic labels
- button sizes
- contrast
- screen readers
- text scaling
- focus order
- meaningful error messages

Do not rely solely on colors for status.

---

# 50. PERFORMANCE TESTING

Measure:

- cold startup
- warm startup
- home load
- menu load
- cart load
- checkout
- order status update
- AccountScreen
- notification screen
- review screen
- admin dashboard

Identify regressions.

Document baseline vs final.

---

# 51. MEMORY & RESOURCE LEAK TESTING

Check:

- timers
- streams
- subscriptions
- controllers
- animations
- listeners

Verify they are disposed.

Pay particular attention to:

pickup countdown

Firestore listeners

notification listeners

FCM listeners

image caches

---

# 52. CRASH TESTING

Verify Crashlytics receives:

- controlled Flutter exception
- async exception
- platform exception
- backend failure where appropriate

Do not send test crash noise into production monitoring.

Use a controlled test environment where possible.

---

# 53. SECURITY REGRESSION TESTS

Attempt:

- privilege escalation
- unauthorized document writes
- cross-student reads
- cross-cafe admin access
- client-side restriction bypass
- client-side NO_SHOW bypass
- fake collected status
- fake cancellation
- fake reliability
- fake food disposition
- fake notification creation

All must fail appropriately.

---

# 54. PENETRATION-STYLE CLIENT TESTING

Treat the Flutter client as untrusted.

Attempt to manipulate:

status

timestamps

reliability

restrictions

roles

food dispositions

admin fields

notification recipients

The backend must reject unauthorized changes.

---

# 55. DATABASE CONSISTENCY AUDIT

Identify inconsistent documents such as:

COLLECTED + noShowAt

NO_SHOW + collectedAt

CANCELLED + pickupDeadline state that incorrectly participates in no-show

READY + collectedAt

Excused no-show without noShowAt

Invalid restriction level

Invalid reliability status

Do NOT automatically rewrite corrupted production data.

Generate a report first.

---

# 56. MIGRATION SAFETY

If schema changes are required:

- do not perform destructive migration automatically
- use backward-compatible fields
- deploy readers before writers where appropriate
- document migration order
- provide rollback strategy

---

# 57. ROLLBACK PLAN

Document rollback procedures for:

Flutter release

Cloud Functions

Firestore Rules

Cloudflare Worker

Firestore indexes

Notification changes

Reliability changes

Food disposition changes

Do not deploy a change without knowing how to reverse it.

---

# 58. PRODUCTION CONFIGURATION AUDIT

Verify production builds use:

- release mode
- correct Firebase project
- correct Cloudflare endpoint
- production Cloudinary configuration
- production notification configuration
- production API endpoints

Ensure debug configuration cannot accidentally ship.

---

# 59. BUILD REPRODUCIBILITY

Run the release workflow from a clean environment.

Verify:

- dependencies resolve
- keystore is decoded
- builds succeed
- APKs are signed
- release metadata is generated
- checksums are generated
- GitHub Release succeeds

---

# 60. FINAL FIRESTORE RULE DEPLOYMENT CHECK

Before production:

1. Deploy rules to staging/test project if available.
2. Run security tests.
3. Review diff.
4. Confirm expected permissions.
5. Deploy production rules only after approval.

Do not deploy experimental rules directly to production.

---

# 61. FINAL CLOUD FUNCTION DEPLOYMENT CHECK

Verify:

- all required secrets exist
- runtime supported
- functions compile
- no unused functions
- correct region
- correct service account permissions
- retries configured appropriately
- scheduled functions deployed
- no test functions remain active

---

# 62. FINAL USER JOURNEY TEST

Perform a complete student journey:

Register

↓

Verify email

↓

Login

↓

Browse

↓

Search

↓

Add to cart

↓

Place order

↓

Cancellation window

↓

Admin accepts

↓

Preparing

↓

Ready

↓

Pickup countdown

↓

Grace period

↓

Collect OR no-show

↓

Reliability update

↓

Restriction if applicable

↓

Recovery through later collection

↓

Review

↓

Notification

↓

Update app

Verify all transitions work.

---

# 63. FINAL ADMIN JOURNEY TEST

Admin:

Register/login

↓

Verify account

↓

Manage food

↓

Upload image

↓

Receive new order

↓

Accept

↓

Preparing

↓

Ready

↓

Collected/No-show

↓

Excuse no-show if legitimate

↓

Record food disposition

↓

View audit trail

↓

Receive notifications

Verify all transitions work.

---

# 64. DOCUMENTATION

Update:

README.md

ARCHITECTURE.md

DATABASE.md

BUSINESS_RULES.md

ROADMAP.md

SECURITY.md

DEPLOYMENT.md

TROUBLESHOOTING.md

Include:

- architecture
- Firestore structure
- security model
- reliability model
- restriction model
- no-show workflow
- cancellation workflow
- admin intervention
- food disposition
- notification system
- FCM
- update system
- release workflow
- environment setup

Do not document secrets.

---

# 65. PRODUCTION CHECKLIST

Create:

PRODUCTION_CHECKLIST.md

Include:

- tests passed
- security rules reviewed
- Cloud Functions deployed
- indexes deployed
- secrets verified
- Cloudinary verified
- FCM verified
- Crashlytics verified
- update proxy verified
- APK signatures verified
- release notes verified
- rollback plan verified
- smoke tests completed

---

# 66. RELEASE CANDIDATE

Create a release candidate build.

Do not immediately publish as final release.

Perform:

- manual smoke testing
- automated tests
- security tests
- performance tests
- update tests

Only promote after all release gates pass.

---

# 67. FINAL ACCEPTANCE CRITERIA

Phase I is complete only when:

✓ All previous phases work together.

✓ No old strike engine remains.

✓ Order cancellation is secure.

✓ 2-minute cancellation cutoff is enforced.

✓ Pickup deadline is authoritative.

✓ Grace period works.

✓ NO_SHOW is automatic and idempotent.

✓ COLLECTED vs NO_SHOW race handling is correct.

✓ Reliability is calculated correctly.

✓ Reliability recovery works.

✓ Restrictions are proportional and recoverable.

✓ Admin excuse is secure and audited.

✓ Food disposition is secure and audited.

✓ Reliability is not affected by food disposition.

✓ Notifications are correct.

✓ FCM works.

✓ Security rules pass testing.

✓ Cloud Functions pass testing.

✓ No sensitive data is exposed.

✓ Privacy principles are respected.

✓ Firestore costs are reviewed.

✓ No unnecessary polling exists.

✓ No per-second Firestore writes exist.

✓ Firestore queries are indexed and bounded.

✓ Crash reporting works.

✓ Monitoring works.

✓ Update system works.

✓ APK integrity verification works.

✓ Production builds are signed.

✓ Documentation is complete.

✓ Rollback procedures are documented.

✓ Release candidate passes smoke testing.

---

# 68. BLOCKING ISSUES

The agent MUST classify findings as:

CRITICAL

HIGH

MEDIUM

LOW

Examples of CRITICAL:

- unauthorized admin access
- students can modify reliability
- students can modify order status
- incorrect authentication bypass
- APK integrity failure
- corrupt order lifecycle
- data leakage
- duplicated financial/order state

A CRITICAL issue blocks release.

HIGH issues should normally block release unless explicitly accepted.

MEDIUM/LOW issues may be documented as technical debt.

---

# 69. FINAL REPORT

At the end of Phase I provide:

## A. Summary

What was tested and hardened.

## B. Files modified

Complete list.

## C. Tests

Automated tests.

Integration tests.

Security tests.

Performance tests.

Manual smoke tests.

## D. Firestore Analysis

Reads.

Writes.

Indexes.

Potential cost risks.

## E. Security Findings

Severity.

Issue.

Fix.

Remaining risk.

## F. Privacy Findings

Data collected.

Data retained.

Data exposed.

Changes made.

## G. Performance Findings

Before/after measurements.

## H. Release Validation

APK versions.

APK signatures.

Checksums.

Update system.

## I. Remaining Technical Debt

Anything that should be addressed after release.

## J. Final Recommendation

One of:

READY FOR PRODUCTION

READY WITH ACCEPTED RISKS

NOT READY

If:

NOT READY

clearly list the blocking issues.

---

# 70. IMPORTANT STOP CONDITION

This is the final hardening phase.

Do not add new product features.

Do not redesign business rules.

Do not reintroduce the old strike system.

Do not implement new restrictions.

Do not implement experimental functionality.

Fix defects and improve production readiness only.

STOP after Phase I.

---

# Phase Completion Criteria

Phase H is complete when:

* The new features works well with past features.
* App runs successfully.
* No runtime errors occur.
