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

# Current Phase

# PHASE 15 — SECURITY HARDENING

## OBJECTIVE

Implement comprehensive production-grade security for Campus Bite.

This phase must strengthen the existing implementation without changing business logic or UI behaviour.

The objective is to protect:

- student accounts
- admin accounts
- Firestore data
- Cloud Functions
- Cloudinary resources
- notification system
- review system
- update system
- authentication system

The implementation must remain scalable, maintainable and cost-effective.

Do NOT rewrite existing features.

Do NOT modify application workflows.

Only harden the existing implementation.

---

# EXISTING SYSTEM

Already implemented:

✓ Firebase Authentication

✓ Student registration

✓ Admin application

✓ Firestore database

✓ Orders

✓ Notifications

✓ Strike Engine

✓ Favourite Engine

✓ Reviews

✓ Cloudinary

✓ Cloud Functions

✓ GitHub Release Update System

✓ Cloudflare Worker update proxy

Your responsibility is ONLY to secure these systems.

---

# PART 1 — FIREBASE APP CHECK

Implement Firebase App Check.

Enable App Check for:

• Firestore

• Cloud Functions

• Cloud Storage (if used)

Use:

Android

Play Integrity API

Development mode only for debug builds.

Never disable App Check in release builds.

App Check failures should be logged without crashing the app.

---

# PART 2 — FIRESTORE SECURITY REVIEW

Review every Firestore rule.

Apply least-privilege access.

Students must never be able to:

• modify menu items

• modify strikes

• modify reviews written by others

• modify admin data

• modify notification status belonging to another user

Admins must never receive unrestricted database access.

Every permission must be role-based.

Do not use:

allow read, write: if true;

except for public menu data where intentionally required.

---

# PART 3 — ROLE VERIFICATION

Never trust the Flutter application.

Every privileged operation must verify:

request.auth.uid

and

user role

inside Firestore Rules or Cloud Functions.

Never trust local variables.

Never trust hidden buttons.

Never trust route protection.

Backend validation is mandatory.

---

# PART 4 — ADMIN AUTHORIZATION

Every admin operation must verify:

Admin account exists

Admin role

Account active

Account not suspended

Only then allow:

Food creation

Food deletion

Food editing

Strike issuing

Strike removal

Notification broadcasting

Image deletion

Review moderation

---

# PART 5 — CLOUD FUNCTIONS SECURITY

Review every Cloud Function.

Validate:

Authentication

Authorization

Input

Document existence

Ownership

Prevent:

Null values

Unexpected fields

Oversized payloads

Invalid document IDs

Invalid timestamps

Malformed requests

Reject invalid requests using HttpsError.

Never expose stack traces.

Never expose secrets.

---

# PART 6 — INPUT VALIDATION

Validate every user input.

Examples:

Registration

Login

Forgot password

Food search

Reviews

Orders

Notifications

Reject:

Negative values

Extremely long strings

Empty required fields

Malformed phone numbers

Malformed emails

Duplicate separators

Unexpected Unicode control characters

Sanitize user text before saving.

---

# PART 7 — REVIEW SECURITY

Review system must prevent:

Review spam

Duplicate reviews

Review flooding

Review abuse

Only users with COLLECTED orders may review.

Users may edit only their own reviews.

Users may delete only their own reviews.

Users cannot modify ratings belonging to others.

Template reviews remain enforced.

---

# PART 8 — STRIKE ENGINE SECURITY

Students must never:

Issue strikes

Remove strikes

Modify strike counters

Modify suspension status

Only authorized admin operations and backend automation may update strike data.

Every strike action should create an audit log.

---

# PART 9 — NOTIFICATION SECURITY

Students may:

Read their notifications

Mark their own notifications as read

Students may NOT:

Create notifications

Broadcast notifications

Delete notifications belonging to others

Admins may only create approved notification types.

---

# PART 10 — ORDER SECURITY

Validate every order transition.

Prevent illegal transitions.

Example:

Collected

↓

Preparing

must never occur.

Valid transitions only.

Verify ownership before allowing order cancellation or viewing.

---

# PART 11 — UPDATE SECURITY

Update system communicates only with:

https://dl.larason.space

Reject:

HTTP

Unknown hosts

Redirects to unknown domains

Verify SHA-256 checksum before installation if provided.

Never install an unverified APK.

---

# PART 12 — CLOUDINARY SECURITY

The admin app(adminview) uploads food images to cloudinary.

Store:

public_id

secure_url

Delete operations must use Cloud Function.

Flutter must never possess Cloudinary API Secret.

Cloudinary credentials remain only inside Firebase Secret Manager.

---

# PART 13 — SECRET MANAGEMENT

Verify no secrets exist inside:

Flutter source

Git repository

GitHub workflow logs

Never commit:

API Secret

Private Keys

Service Accounts

Signing Keys

Cloudinary Secret

Firebase Secret Manager remains the only storage location for sensitive backend secrets.

---

# PART 14 — AUTHENTICATION HARDENING

Require:

Verified email

Before allowing ordering.

Reject unverified accounts.

Limit login attempts where feasible.

Do not reveal:

whether an email exists

whether an account is suspended

whether a password was correct

Use generic authentication error messages.

---

# PART 15 — PRIVACY PROTECTION

Do not log:

Email

Phone

Exact location

UID

Notification tokens

Order contents

Review text

Payment information

Production logs should contain only diagnostic information.

---

# PART 16 — TOKEN SECURITY

Never store:

Firebase ID Token

Refresh Token

FCM Token

inside SharedPreferences.

Use secure storage where persistence is required.

Refresh tokens automatically.

Handle expired sessions gracefully.

---

# PART 17 — LOCAL STORAGE SECURITY

Review every locally stored value.

Do not cache:

Passwords

OTP codes

Sensitive admin data

Strike decisions

Cache only non-sensitive data.

---

# PART 18 — DEPENDENCY REVIEW

Audit pubspec.yaml.

Remove unused packages.

Update outdated packages.

Replace abandoned packages.

Prefer actively maintained libraries.

---

# PART 19 — ERROR HANDLING

Replace technical errors with user-friendly messages.

Example:

Instead of:

FirebaseException

Display:

"Something went wrong. Please try again."

Log technical details only in debug mode.

---

# PART 20 — AUDIT LOGGING

Create immutable audit logs for:

Food creation

Food deletion

Food edits

Strike issued

Strike removed

Account suspension

Review deletion

Cloudinary deletion

Notification broadcasts

Each log records:

timestamp

admin UID

action

target document

No personal content beyond identifiers required for auditing.

---

# PART 21 — SECURITY TESTING

Verify:

✓ Student cannot become admin

✓ Student cannot modify menu

✓ Student cannot modify another cart

✓ Student cannot modify another review

✓ Student cannot modify strikes

✓ Student cannot broadcast notifications

✓ Invalid Cloud Function requests rejected

✓ Cloudinary secret never exposed

✓ App Check enabled

✓ Firestore Rules enforced

✓ Update checksum validation works

✓ Review ownership enforced

✓ Audit logs created

✓ No secrets committed

✓ Release build functions correctly

---

# DELIVERABLES

Provide:

1. Files modified

2. Firestore Rules changes

3. Cloud Function security improvements

4. App Check implementation summary

5. Authentication improvements

6. Cloudinary security summary

7. Update security summary

8. Audit logging implementation

9. Security test checklist

10. Remaining security recommendations

Stop after Phase 15.

---

# Phase Completion Criteria

Phase 15 is complete when:

* The new features works well with past features.
* App runs successfully.
* No runtime errors occur.
