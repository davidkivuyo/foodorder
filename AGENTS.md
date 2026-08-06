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

# PHASE 17 — ERROR REPORTING & MONITORING

## OBJECTIVE

Implement production-grade monitoring for CampusBite.

This phase focuses only on:

• crash reporting

• error monitoring

• performance monitoring

• application health

• analytics

• audit logging

Do NOT modify existing business logic.

Do NOT redesign screens.

Do NOT change application workflows.

The implementation must be lightweight, privacy-first and production-ready.

create dedicated services rather than scattering monitoring code throughout the app.

lib/
 ├── services/
 │    ├── error_service.dart
 │    ├── logger_service.dart
 │    ├── analytics_service.dart
 │    ├── performance_service.dart
 │    ├── health_service.dart
 │    ├── crash_reporting_service.dart
 │    └── diagnostics_service.dart
 
---

# EXISTING SYSTEM

The following systems already exist:

✓ Firebase Authentication

✓ Firestore

✓ Cloud Functions

✓ Notifications

✓ Orders

✓ Reviews

✓ Favourite Engine

✓ Strike Engine

✓ Admin App

✓ Cloudinary

✓ In-App Updates

This phase only monitors those systems.

---

# GENERAL REQUIREMENTS

Monitoring must:

• never expose personal information

• avoid unnecessary Firestore writes

• work offline

• recover automatically

• distinguish debug and release builds

Never interrupt normal application usage.

---

# PART 1 — FIREBASE CRASHLYTICS

Integrate Firebase Crashlytics.

Enable automatic crash reporting.

Capture:

Unhandled Flutter exceptions

Platform exceptions

Dart asynchronous exceptions

Cloud Function failures

Fatal application crashes

Record custom keys including:

Application version

Build number

Flutter version

Platform

Current screen

Network status

User role

Do NOT record:

Email

UID (student or admin)

Student registration number

Phone number

Notification token

Review text

Location

Crash reports must remain anonymous.

No UID of any kind — student or admin — may be attached to crash reports.

---

# PART 2 — GLOBAL ERROR HANDLER

Create a centralized ErrorService.

All uncaught exceptions must pass through it.

Responsibilities:

Log locally

Send to Crashlytics

Display user-friendly messages

Categorize errors

Support:

FlutterError

PlatformDispatcher

runZonedGuarded

Future exceptions

Stream exceptions

Never allow uncaught exceptions to terminate the app unnecessarily.

## Error-Routing Contract

Errors fall into exactly four categories. Each category has a fixed path
through the system; do not blur the boundaries.

### 1. Client Dart/Flutter exceptions (routed through ErrorService)

Handled and unhandled exceptions originating on the client (widget errors,
async failures, stream errors, Future errors, platform exceptions).

ErrorService: RECORDS (logs locally, sends anonymous data to Crashlytics),
DISPLAYS a user-friendly message, CONSUMES the error (never rethrows), and
never terminates the app.

### 2. Native fatal crashes (captured automatically by Crashlytics)

Crashes at the platform layer (Android/iOS native code, JVM/NDK/ObjC).

ErrorService: does not see these. Crashlytics CAPTURES them automatically via
the native SDK. No client code records, displays, or consumes them. Crash
reports remain anonymous (no UID, email, phone, token, review text, or
location).

### 3. Client-side Cloud Function invocation failures

Failures calling a callable/HTTP function from the client (network, timeout,
invalid request, permission, function-unavailable).

ErrorService: RECORDS (logs the failure locally, optionally sends an anonymous
analytics/function-error event), DISPLAYS a user-friendly message, CONSUMES
the error (does not rethrow), and retries only when a retry is safe. The
failure is reported from the client; the server logs stay server-side.

### 4. Server-side Cloud Function errors (handled on the server)

Errors thrown inside a deployed Cloud Function (backend exception, quota,
permission, dependency failure).

ErrorService/client: does NOT record, display, consume, or rethrow these.
The server handles its own logging and surfaces failures back to the client
only through the normal invocation-failure path (category 3). Flutter must
never attach UIDs, request payloads, or sensitive content to any of these.

Applies to all categories: never terminate the app due to an error, and never
expose raw exception text to the user.

---

# PART 3 — USER-FRIENDLY ERROR MESSAGES

Replace technical errors.

Instead of:

FirebaseException

Display:

"Something went wrong."

Examples:

Network unavailable

Server unavailable

Permission denied

Update failed

Download interrupted

Review failed

Order failed

Notification failed

Cart failed

Provide retry actions where appropriate.

Never expose internal exception messages.

---

# PART 4 — STRUCTURED LOGGING

Implement LoggerService.

Support log levels:

Debug

Info

Warning

Error

Critical

Debug logs:

Debug builds only.

Release builds:

Only Warning

Error

Critical

Never use print() or debugPrint() throughout the application.

Replace them with LoggerService.

---

# PART 5 — FIREBASE ANALYTICS

Track meaningful application events.

Examples:

User registration

Login

Logout

Food viewed

Food searched

Food favourited

Added to cart

Removed from cart

Order placed

Order cancelled

Order collected

Review submitted

Notification opened

Update installed

Admin added menu item

Admin removed menu item

Strike issued

Strike removed

Never log:

Email

UID (student or admin)

Food review text

Location

Notification content

Search text

Passwords

Analytics must remain anonymous.

UIDs of any kind, including admin UIDs, are never sent to Analytics. The only permitted UID usage is inside immutable audit records (Part 12).

---

# PART 6 — PERFORMANCE MONITORING

Enable Firebase Performance Monitoring.

Measure:

App startup

Authentication

Menu loading

Food details

Search

Cart loading

Checkout

Orders

Notifications

Reviews

Cloud Function execution

Cloudinary image loading

Update check

Record slow traces.

Do not create unnecessary custom traces.

---

# PART 7 — NETWORK MONITORING

Monitor:

Internet connectivity

Cloud Firestore availability

Cloud Functions availability

Cloudinary availability

Worker update endpoint

Detect:

Offline

Slow network

High latency

Timeouts

Automatically recover.

Never continuously poll servers.

---

# PART 8 — FIRESTORE HEALTH

Monitor:

Permission errors

Quota errors

Unavailable errors

Offline cache usage

Synchronization failures

Log only summaries.

Do not create Firestore documents for every error.

---

# PART 9 — CLOUD FUNCTION MONITORING

Capture:

Execution failures

Permission failures

Timeouts

Invalid requests

Retry attempts

Cloud Functions themselves remain responsible for server logs.

Flutter only records client failures.

---

# PART 10 — IMAGE MONITORING

Track:

Failed Cloudinary downloads

Slow image loading

Placeholder frequency

Broken URLs

Cache misses

Do not repeatedly retry broken URLs.

---

# PART 11 — UPDATE MONITORING

Monitor:

Metadata download

Version parsing

Download failures

Checksum validation

Installation failures

Cancellation rate

Successful updates

Never block application use due to monitoring failures.

---

# PART 12 — ADMIN AUDIT LOGS

Maintain immutable audit logs.

Record:

Menu added

Menu edited

Menu deleted

Strike issued

Strike removed

Account suspended

Review removed

Notification broadcast

Cloudinary deletion

Each log includes:

Timestamp

Admin UID

Action

Target document ID

No personal content.

Audit logs are append-only.

## Audit data model and storage

Audit records form a separate compliance data class, distinct from telemetry
events, with an explicitly specified storage backend.

Storage backend: a dedicated Firestore collection reserved exclusively for
audit records (e.g. `audit_logs`). No other monitoring data is written there,
and audit records are never written to any telemetry store.

Records are IMMUTABLE once written: they are never updated in place, never
edited, and never overwritten. The ONLY permitted deletion is the configured
retention purge (records older than the retention window). No manual deletion,
no client deletion, and no edit path exists.

Admin UIDs are the ONLY identifiers permitted in monitoring data, and ONLY inside these immutable audit records. They must never be copied into Crashlytics, Analytics, Performance, or any other monitoring channel.

## Telemetry exclusion

Audit records are excluded from telemetry-cost rules (Part 15): the near-zero
cost requirement applies to monitoring telemetry, not to the compliance audit
store. However, audit records are NEVER exported or mirrored into Analytics,
Crashlytics, Performance Monitoring, Cloud Logging, or any other telemetry
channel.

Audit log access is restricted to:

Authorized administrators

Backend operations

Never expose audit records through client-facing Firestore rules.

Retention policy:

Retain audit records for at least 90 days

Automatically purge records older than the configured retention window

Never export or mirror audit records into monitoring or analytics tools

---

# PART 13 — APPLICATION HEALTH DASHBOARD

Implement HealthService.

Track:

Firestore connected

Authentication available

Cloud Functions reachable

Cloudinary reachable

Notification service active

Update service reachable

Return overall status:

Healthy

Degraded

Offline

Unknown

Use lightweight checks.

Do not continuously ping services.

---

# PART 14 — DEBUG DIAGNOSTICS

Create hidden diagnostics screen.

## Visibility rule

Visible only when `isDebugBuild OR isAdministrator`:

* Debug builds — always visible (regardless of role)

* Release + administrator accounts — visible

* Release + non-administrator accounts — NEVER accessible

This is an inclusive OR: a release administrator is allowed, while a release
non-administrator account is denied. Both cases must be covered by tests.

Display:

Application version

Build number

Flutter version

Firebase versions

Firestore cache size

Current user role

Notification status

Analytics status

Crashlytics status

Performance status

Last synchronization

Never expose secrets.

---

# PART 15 — COST OPTIMIZATION

Do NOT store monitoring events in Firestore.

Prefer:

Crashlytics

Analytics

Performance Monitoring

Cloud Logging

Avoid:

Firestore logging

Repeated writes

Heartbeat documents

Polling every few seconds

Monitoring must generate near-zero Firestore costs.

## Audit-record exclusion

The near-zero-cost rule applies to monitoring telemetry only. The compliance
audit store (Part 12) is exempt from this limit, but audit records are NEVER
exported or mirrored into Analytics, Crashlytics, Performance Monitoring,
Cloud Logging, or any other telemetry channel.

---

# PART 16 — PRIVACY

Comply with privacy-first principles.

Never collect:

Email

Phone

Location

Review text

Notification text

Payment information

Authentication tokens

Passwords

Student ID

Logs must contain technical diagnostics only.

The sole exception to identifier prohibitions is the Admin UID inside immutable audit records (Part 12). Admin UIDs remain prohibited in Crashlytics, Analytics, Performance, and all other monitoring data.

---

# PART 17 — TESTING

Verify:

✓ Crash reports reach Crashlytics

✓ Analytics events recorded

✓ Performance traces visible

✓ Structured logging works

✓ User-friendly messages displayed

✓ No sensitive data logged

✓ Health service detects offline state

✓ Monitoring survives app restart

✓ No Firestore monitoring writes

✓ Update monitoring works

✓ Cloudinary monitoring works

✓ Debug diagnostics screen hidden in release

✓ Existing features unchanged

---

# DELIVERABLES

Provide:

1. Files created

2. Files modified

3. Crashlytics implementation summary

4. Analytics events list

5. Performance traces implemented

6. LoggerService architecture

7. HealthService architecture

8. Audit logging summary

9. Privacy compliance summary

10. Testing checklist

Stop after Phase 17

---

# Phase Completion Criteria

Phase 17 is complete when:

* The new features works well with past features.
* App runs successfully.
* No runtime errors occur.
