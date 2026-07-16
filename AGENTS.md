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

PHASE 7

# TASK

Implement Phase 7 of CampusBite.

This phase introduces the production notification platform.

The implementation must be scalable, production-ready, reusable and future-proof.

Notifications must react to business events.

Notifications must never control business logic.

Business logic remains completely independent from notifications.

The notification platform must be designed so Firebase Cloud Messaging (FCM) can be added later without modifying existing business logic.

---

# EXISTING SYSTEM

Already implemented:

✓ Student App

✓ Cafe Admin App

✓ Authentication

✓ Firestore

✓ Orders

✓ Order Status Workflow

✓ Distance-Based Pickup Deadlines

✓ Automatic No-Show Detection

✓ Automatic Strike Engine

✓ Admin Pardon

✓ Account Suspension

Do NOT modify these features.

---

# OBJECTIVE

Create a reusable notification platform that serves:

• Students

• Cafe Admins

using the existing Firestore collection:

notifications

Do NOT create nested notification collections.

Reuse the existing collection.

---

# ARCHITECTURE

Business Event

↓

NotificationService

↓

Firestore notifications collection

↓

Student/Admin Apps

↓

(Future)

Firebase Cloud Messaging

Business logic must never write directly into Firestore notifications.

Every notification must be created through NotificationService.

---

# NOTIFICATION SERVICE

Create:

notification_service.dart

Responsibilities:

Create notification

Prevent duplicates

Mark notification as read

Mark all notifications as read

Soft delete notification

Support future FCM integration

No widgets may construct notification documents.

Cloud Functions and backend services should call NotificationService only.

---

# FIRESTORE COLLECTION

Use the existing collection:

notifications

One document per notification.

Document IDs:

Auto-generated.

---

# DOCUMENT STRUCTURE

Each notification document must contain:

recipientId

recipientRole

type

title

message

orderId

eventId

deepLink

metadata

read

readAt

deleted

deletedAt

createdAt

createdBy

---

# FIELD DEFINITIONS

recipientId

UID of recipient.

recipientRole

Allowed values:

student

admin

type

Notification type enum.

title

Short title.

message

Human-readable message.

orderId

Optional.

Null when not applicable.

eventId

Unique business event identifier.

Used for duplicate prevention.

deepLink

App navigation target.

Examples:

/orders/{orderId}

/account

/notifications

/strike-history

metadata

Optional structured object.

Examples:

strikeCount

cafeName

pickupDeadline

distanceMeters

Never store sensitive personal information.

read

Boolean.

Default:

false

readAt

Server timestamp.

Null until read.

deleted

Boolean.

Default:

false

deletedAt

Server timestamp.

Null until deleted.

createdAt

Server timestamp.

createdBy

Values:

system

admin

future

---

# DUPLICATE PROTECTION

Every notification must contain:

eventId

Examples:

ORDER_READY_order123

ORDER_ACCEPTED_order123

ORDER_PREPARING_order123

PICKUP_REMINDER_order123

ORDER_NO_SHOW_order123

STRIKE_ISSUED_order123

STRIKE_REMOVED_user123_strike1

ACCOUNT_SUSPENDED_user123

ACCOUNT_REACTIVATED_user123

NEW_ORDER_order123

Before creating a notification:

NotificationService must check for an existing notification with the same eventId.

If found:

Skip creation.

Notification creation must be idempotent.

---

# NOTIFICATION TYPES

Student:

ORDER_ACCEPTED

ORDER_PREPARING

ORDER_READY

PICKUP_REMINDER

ORDER_NO_SHOW

STRIKE_ISSUED

STRIKE_REMOVED

ACCOUNT_SUSPENDED

ACCOUNT_REACTIVATED

Admin:

NEW_ORDER

Use enums/constants.

Never hardcode strings.

---

# BUSINESS EVENT TRIGGERS

Generate notifications ONLY when business state changes.

Student:

Order accepted

Order preparing

Order ready

Pickup reminder

Automatic no-show

Strike issued

Strike removed

Account suspended

Account reactivated

Admin:

Student places new order

Notifications must never trigger business actions.

---

# PICKUP REMINDER

When an order transitions to READY:

Schedule exactly ONE reminder.

Reminder time:

5 minutes before pickupDeadline.

If the order is collected before the reminder:

Cancel the reminder.

If the order becomes NO_SHOW before the reminder:

Cancel the reminder.

Never send reminders for completed or expired orders.

---

# FIRESTORE QUERIES

Student App:

recipientId == currentUser.uid

recipientRole == student

deleted == false

Order by:

createdAt DESC

Limit:

50

Admin App:

recipientId == currentAdmin.uid

recipientRole == admin

deleted == false

Order by:

createdAt DESC

Limit:

50

Never download notifications for other users.

Never perform collection scans.

---

# FIRESTORE INDEXES

Create composite indexes for:

recipientId

recipientRole

deleted

createdAt DESC

Indexes must support all notification queries efficiently.

---

# REAL-TIME LISTENERS

Student App:

Listen ONLY to:

notifications

filtered by:

recipientId

recipientRole

deleted == false

Admin App:

Same pattern.

Never subscribe to the entire notifications collection.

---

# READ STATUS

Opening a notification:

Update ONLY:

read = true

readAt = serverTimestamp()

Never rewrite the document.

---

# MARK ALL READ

Batch update:

Unread notifications only.

Do not rewrite already-read notifications.

---

# SOFT DELETE

Never permanently delete notifications immediately.

Instead:

deleted = true

deletedAt = serverTimestamp()

Apps ignore deleted notifications.

---

# CLEANUP

Create one scheduled Cloud Function.

Runs:

Once every 24 hours.

Deletes notifications:

Older than 180 days

AND

deleted == true

Never delete active notifications.

---

# DEEP LINKS

Each notification contains:

deepLink

Examples:

/orders/{orderId}

/account

/notifications

/strike-history

Notification tap should navigate directly.

Navigation logic must remain outside NotificationService.

---

# SECURITY

Students:

Read only their own notifications.

Update only:

read

readAt

deleted

deletedAt

Cannot modify:

title

message

type

recipientId

eventId

metadata

Admins:

Same permissions.

Only backend creates notifications.

---

# PRIVACY

Never store:

Student location

Email address

Phone number

Authentication data

Only include information required to display the notification.

---

# PERFORMANCE

Target:

Exactly one notification write per event.

Zero unnecessary reads.

Indexed queries only.

No polling.

No duplicate listeners.

No repeated notification generation.

---

# FUTURE FCM SUPPORT

NotificationService must expose a delivery abstraction.

Current delivery:

Firestore

Future delivery:

Firestore

+

Firebase Cloud Messaging

Business services must not require modification when FCM is introduced.

---

# ANALYTICS PREPARATION

Design NotificationService so future analytics can record:

Notification opened

Notification dismissed

Delivery success

Without modifying business logic.

No analytics implementation in this phase.

---

# CODE QUALITY

Create:

notification_service.dart

notification_model.dart

notification_repository.dart

Use repository pattern.

Business logic must remain outside widgets.

Reuse existing architecture.

Avoid duplicate code.

---

# TESTING

Verify:

✓ Order accepted notification

✓ Preparing notification

✓ Ready notification

✓ Pickup reminder

✓ No-show notification

✓ Strike issued notification

✓ Strike removed notification

✓ Suspension notification

✓ Reactivation notification

✓ New order notification for admins

✓ Duplicate events do not create duplicate notifications

✓ Read status updates correctly

✓ Mark all read works

✓ Soft delete works

✓ Real-time updates work

✓ Deep links navigate correctly

✓ Existing ordering unaffected

✓ Existing strike engine unaffected

✓ Existing admin workflow unaffected

✓ Existing pickup countdown unaffected

✓ Existing cart unaffected

---

# DELIVERABLES

Provide:

1. Files created

2. Files modified

3. NotificationService implementation

4. Firestore schema

5. Firestore indexes

6. Firestore Security Rule updates

7. Scheduled cleanup Cloud Function

8. Testing checklist

Stop after completing Phase 7.

Do NOT implement Firebase Cloud Messaging.

Do NOT implement email notifications.

Do NOT implement SMS notifications.

Do NOT implement notification preferences in this phase.

---

# Phase Completion Criteria

Phase 7 is complete when:

* the new features works well with past features.
* App runs successfully.
* No runtime errors occur.
