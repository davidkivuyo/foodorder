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

PHASE 8

# TASK

Implement Phase 8 of CampusBite.

This phase integrates Firebase Cloud Messaging (FCM) into the existing notification platform.

Firebase Cloud Messaging has already been configured in Firebase Console.

Do NOT recreate the Firebase project.

Do NOT modify Firebase Console settings.

Only implement the application and backend integration.

The implementation must be production-ready.

The implementation must be secure.

The implementation must minimise Firestore reads and writes.

The implementation must minimise Cloud Function invocations.

Do NOT change existing business logic.

Do NOT redesign the notification platform.

---

# CURRENT SYSTEM

Already completed:

✓ Student App

✓ Cafe Admin App

✓ Authentication

✓ Firestore

✓ Notification Platform

✓ NotificationService

✓ Cloud Functions

✓ Automatic Strike Engine

✓ Automatic No Show

✓ Admin Dashboard

✓ Audit Logs

✓ Distance Based Pickup Logic

Reuse all existing components.

---

# OBJECTIVE

Whenever NotificationService creates a notification:

Store notification in Firestore.

Immediately send a Firebase Cloud Messaging push notification to the recipient.

Firestore remains the source of truth.

FCM is only the delivery mechanism.

If push delivery fails:

The notification must still exist in Firestore.

---

# ARCHITECTURE

Business Event

↓

NotificationService

↓

Create Firestore Notification

↓

Send Push Notification

↓

Student Device

or

Admin Device

Never send push notifications directly from Flutter.

All push notifications must originate from backend Cloud Functions.

---

# DEVICE TOKEN MANAGEMENT

Each authenticated device must register its FCM token.

Store tokens inside Firestore.

Collection:

device_tokens

Document ID:

Automatically generated.

Fields:

userId

role

token

platform

deviceId

appVersion

createdAt

updatedAt

lastSeen

active

Example:

device_tokens

tokenDoc

userId

uid123

role

student

token

xxxxxx

platform

android

deviceId

abcdef

active

true

---

# TOKEN LIFECYCLE

When app starts:

Retrieve current FCM token.

If token changed:

Update Firestore.

When Firebase refreshes token:

Automatically update Firestore.

When user logs out:

Deactivate token.

Do not delete immediately.

Set:

active = false

updatedAt = serverTimestamp()

---

# MULTIPLE DEVICES

One user may own multiple devices.

Never overwrite tokens.

Each device receives its own document.

NotificationService must send notifications to all active tokens belonging to the recipient.

---

# NOTIFICATION DELIVERY

NotificationService already creates Firestore notifications.

Extend it.

After successful Firestore write:

Send push notification.

Never send push first.

Firestore write is always first.

---

# CLOUD FUNCTIONS

NotificationService must call:

PushDeliveryService

Responsibilities:

Load active tokens

Send multicast notification

Handle invalid tokens

Clean expired tokens

Return delivery results

NotificationService must never contain FCM code.

Keep responsibilities separated.

---

# PUSH PAYLOAD

Notification:

title

body

Data:

notificationId

type

orderId

deepLink

eventId

Do not include sensitive information.

Never include:

Email

Phone

Location

Authentication data

---

# CLICK ACTION

When user taps notification:

Open application.

Navigate using:

deepLink

Examples:

/orders/{orderId}

/notifications

/account

/strike-history

Navigation must reuse the existing deep link implementation.

If the deep linking is not yet configured in the app, configure it cleanly without breaking existing features.

---

# DELIVERY FAILURES

If Firebase returns:

UNREGISTERED

INVALID_ARGUMENT

NOT_FOUND

Deactivate token.

Do not retry.

Other transient failures may be retried according to Firebase best practices.

Never delete tokens during temporary failures.

---

# DUPLICATE PROTECTION

NotificationService already uses:

eventId

Continue using it.

Never send duplicate push notifications.

One business event must produce:

One Firestore notification

One push notification

per device.

---

# FOREGROUND HANDLING

If app is open:

Display in-app notification banner.

Still save notification to Firestore.

Do not suppress notifications.

---

# BACKGROUND HANDLING

Support:

Background messages.

Terminated application.

Notification tap navigation.

Do not duplicate notifications.

---

# FIRESTORE READ OPTIMISATION

Notification creation:

No additional reads.

Push delivery:

One indexed query:

device_tokens

WHERE

userId == recipientId

AND

active == true

Nothing else.

---

# FIRESTORE WRITE OPTIMISATION

Write notification.

Update invalid tokens only when necessary.

Do not rewrite valid tokens.

---

# SECURITY

Students

Cannot create tokens for other users.

Cannot modify another user's tokens.

Admins

Same restriction.

Cloud Functions

Read all active tokens.

Flutter clients

Only update their own device token.

---

# FIRESTORE RULES

Protect:

device_tokens

Allow authenticated users to:

Create their own token.

Update their own token.

Deactivate their own token.

Deny access to tokens belonging to others.

Cloud Functions retain administrative access.

---

# PERFORMANCE

Target:

One notification write.

One token query.

One multicast send.

No polling.

No unnecessary listeners.

No duplicate Cloud Functions.

---

# PRIVACY

Tokens are sensitive identifiers.

Never expose another user's token.

Never return tokens to clients.

Never include tokens inside notifications.

Never log token values in audit_log or anywhere.

---

# CLEANUP

Create scheduled Cloud Function.

Runs weekly.

Removes:

Inactive tokens older than 90 days.

Removes invalid tokens.

Keeps Firestore small.

---

# ADMIN APP

Admins receive push notifications for:

NEW_ORDER

Only.

Student notifications must never reach admins.

---

# STUDENT APP

Receive push notifications for:

ORDER_ACCEPTED

ORDER_PREPARING

ORDER_READY

PICKUP_REMINDER

ORDER_NO_SHOW

STRIKE_ISSUED

STRIKE_REMOVED

ACCOUNT_SUSPENDED

ACCOUNT_REACTIVATED

---

# OFFLINE SUPPORT

If device is offline:

Notification remains in Firestore.

Push is delivered when Firebase reconnects (subject to FCM behavior).

Users always have the notification history inside the app.

---

# CODE QUALITY

Create:

push_delivery_service.dart

fcm_service.dart

device_token_repository.dart

Keep responsibilities separate.

Business logic must never contain FCM implementation.

Avoid duplicate code.

Reuse NotificationService.

---

# TESTING

Verify:

✓ Student token registration

✓ Admin token registration

✓ Token refresh

✓ Multiple devices receive notifications

✓ Invalid tokens are deactivated

✓ Order Accepted push

✓ Preparing push

✓ Ready push

✓ Pickup Reminder push

✓ No Show push

✓ Strike Issued push

✓ Strike Removed push

✓ Account Suspended push

✓ Account Reactivated push

✓ Admin New Order push

✓ Foreground notifications

✓ Background notifications

✓ Terminated app notifications

✓ Notification tap opens correct screen

✓ Firestore notification always exists

✓ Push failures do not affect Firestore notifications

✓ Existing business logic unchanged

✓ Existing notification platform unchanged

✓ Existing strike engine unchanged

✓ Existing admin workflow unchanged

---

# DELIVERABLES

Provide:

1. Files created

2. Files modified

3. PushDeliveryService implementation

4. FCM client implementation

5. Firestore schema changes (device_tokens)

6. Firestore Security Rule updates

7. Cloud Function updates

8. Testing checklist

Stop after completing Phase 8.

Do NOT redesign NotificationService.

Do NOT redesign Firestore notifications.

Do NOT implement notification preferences.

Do NOT implement topic messaging.

Do NOT implement marketing notifications.

Maintain backward compatibility with the existing notification platform.

---

# Phase Completion Criteria

Phase 8 is complete when:

* the new features works well with past features.
* App runs successfully.
* No runtime errors occur.
