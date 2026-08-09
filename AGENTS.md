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

# PHASE 18 — PRODUCTION READINESS & FINAL VALIDATION

## OBJECTIVE

This is the final implementation phase.

No new features are to be developed.

The purpose of this phase is to prepare CampusBite for long-term production use.

The AI agent must review, validate, optimize, and polish the entire project while ensuring all previously implemented features continue working correctly.

This phase must improve reliability, maintainability, accessibility, testing, documentation, and release readiness.

Business logic must remain unchanged.

---

# EXISTING SYSTEM

The following features already exist:

✓ Student Application

✓ Cafe Admin Application

✓ Firebase Authentication

✓ Email Verification

✓ Forgot Password

✓ Firestore

✓ Orders

✓ Favourite Menu

✓ Reviews

✓ Notifications

✓ Cloudinary

✓ In-app Updates

✓ Security Hardening

✓ Crash Reporting

✓ Monitoring

✓ Analytics

This phase validates these systems.

---

# GENERAL RULES

Do not redesign the application.

Do not change Firestore structure unless required to fix production issues.

Do not introduce breaking API changes.

Maintain backward compatibility.

Prioritize stability over optimization.

---

# STEP 1 — COMPLETE PROJECT AUDIT

Perform a complete review of the project.

Inspect:

Flutter code

Architecture

Services

Repositories

Widgets

Providers

Firebase usage

Cloud Functions

Firestore Rules

Cloudinary integration

GitHub Actions

Cloudflare Worker

Identify:

Dead code

Duplicate code

Unused classes

Unused assets

Unused imports

Deprecated APIs

Document findings.

---

# STEP 2 — DEPENDENCY REVIEW

Review pubspec.yaml.

Update packages to stable versions where compatible.

Remove unused dependencies.

Replace abandoned packages.

Verify compatibility with the current Flutter stable release.

Do not introduce beta or experimental packages.

---

# STEP 3 — CODE QUALITY

Improve code readability.

Standardize naming conventions.

Ensure consistent formatting.

Refactor overly complex methods.

Extract reusable widgets.

Extract reusable services.

Reduce widget nesting where practical.

Improve comments and documentation.

Remove TODOs that are no longer relevant.

---

# STEP 4 — ACCESSIBILITY

Review accessibility.

Ensure:

Meaningful semantics

Screen reader compatibility

Adequate touch target sizes

Keyboard navigation where applicable

Sufficient color contrast

Support for larger text scaling

Do not change the application's visual identity.

---

# STEP 5 — RESPONSIVE LAYOUT REVIEW

Test common screen sizes.

Verify:

Small Android phones

Large phones

Tablets (basic usability)

Portrait orientation

Landscape orientation (where supported)

Prevent overflow and clipping.

---

# STEP 6 — LOCALIZATION PREPARATION

Prepare the application for future localization.

Extract user-facing strings into localization resources.

Do not translate yet.

Default language remains English.

---

# STEP 7 — FIRESTORE INDEX VALIDATION

Review all Firestore queries.

Identify composite index requirements.

Document any required indexes.

Ensure queries are efficient.

Avoid collection scans.

---

# STEP 8 — OFFLINE RELIABILITY

Validate offline behavior.

Verify:

Cached menu loading

Cached orders

Cached notifications

Graceful offline messaging

Automatic synchronization when connectivity returns

Prevent duplicate writes during reconnection.

---

# STEP 9 — PERFORMANCE BENCHMARKING

Measure:

Cold startup time

Warm startup time

Home screen load

Menu load

Order placement

Review submission

Notification loading

Update check

Document baseline measurements.

Highlight bottlenecks.

---

# STEP 10 — END-TO-END TESTING

Verify complete workflows.

Student:

Register

Verify email

Login

Browse menu

Search food

Add to cart

Place order

Receive notifications

Collect order

Leave review

Favourite food

Receive updates

Admin:

Login

Add menu item

Edit menu

Delete menu

Receive new orders

Change order status

Issue strike

Remove strike

Broadcast notification

Delete Cloudinary image

Verify every workflow succeeds.

---

# STEP 11 — FAILURE TESTING

Test:

No internet

Firestore unavailable

Cloud Function unavailable

Cloudinary unavailable

Worker unavailable

Notification failure

Download interruption

Authentication expiration

Unexpected application termination

Verify graceful recovery.

---

# STEP 12 — SECURITY REGRESSION REVIEW

Confirm:

Firestore Rules still enforce permissions

Cloud Functions validate authorization

Cloudinary secrets remain protected

No secrets committed

Update system verifies integrity

Admin-only operations remain protected

App Check configuration (if implemented) remains valid

No regression from previous phases.

---

# STEP 13 — RELEASE PIPELINE VALIDATION

Review GitHub Actions.

Verify:

Universal APK generation

Split APK generation

release.json generation

SHA-256 checksum generation

Release notes

Version naming

Cloudflare update compatibility

Artifact naming consistency

---

# STEP 14 — DOCUMENTATION

Update project documentation.

Include:

Architecture overview

Firestore structure

Cloud Functions overview

Notification flow

Strike Engine flow

Favourite Engine flow

Update system architecture

Environment setup

Release process

Deployment steps

Troubleshooting guide

Developer onboarding instructions

---

# STEP 15 — FINAL RELEASE CHECKLIST

Create a production release checklist.

Include:

Release version

Build number

Git tag

Firestore Rules deployed

Cloud Functions deployed

Indexes deployed

Secrets configured

Cloudinary verified

Crashlytics enabled

Analytics enabled

Performance Monitoring enabled

GitHub Release verified

Cloudflare Worker verified

APK signatures verified

Manual smoke testing completed

---

# TESTING

Verify:

✓ All existing features function correctly

✓ No new regressions introduced

✓ Performance maintained or improved

✓ Accessibility improved

✓ Offline behavior verified

✓ Security unchanged

✓ Monitoring operational

✓ Documentation complete

✓ Release pipeline operational

✓ Application ready for production deployment

---

# DELIVERABLES

Provide:

1. Files modified

2. Architecture improvements

3. Refactoring summary

4. Accessibility improvements

5. Performance benchmark report

6. Firestore index recommendations

7. Documentation updates

8. Release readiness checklist

9. Outstanding technical debt (if any)

10. Final production readiness assessment

This concludes the implementation roadmap.

No additional features should be implemented during this phase.

---

# Phase Completion Criteria

Phase 18 is complete when:

* The new features works well with past features.
* App runs successfully.
* No runtime errors occur.
