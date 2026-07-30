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

PHASE 12

# TASK

Implement Phase 8 of CampusBite.

This phase introduces the Reviews & Feedback System.

The implementation must be production-ready.

The implementation must be secure.

The implementation must minimize Firestore reads.

The implementation must minimize Firestore writes.

Reuse existing architecture.

Do not modify existing ordering logic.

Do not modify notifications.

Do not modify strike engine.

Do not modify favourite engine.

---

# OBJECTIVE

Allow students to rate and review food items.

Reviews are only allowed after a successfully collected order.

Each review belongs to one collected order.

Students may edit or delete their own reviews.

Food ratings are automatically updated.

The review screen already exists:

reviews_screen.dart

Reuse it.

---

# USER FLOW

Student

↓

Places Order

↓

Order Collected

↓

Food Item becomes reviewable

↓

Student opens Food Details

↓

Tap

Write Review

↓

Submit Review

↓

Food rating updates

↓

Review appears in Reviews Screen

---

# REVIEW ELIGIBILITY

A student may review only if:

Order status == COLLECTED

AND

The order contains that food item.

Do not allow reviews before collection.

Do not allow reviews for:

Cancelled

Rejected

Preparing

Accepted

Ready

No Show

---

# ONE REVIEW PER ORDER

Each collected order may create only one review for each purchased food item.

Example

Order:

Burger

Chips

Soda

Student may review:

Burger

Chips

Soda

Each once.

Ordering Burger again in another collected order allows another review linked to the new order.

---

# FIRESTORE STRUCTURE

Create collection:

reviews

Document ID:

Auto generated.

Fields:

foodId

orderId

userId

displayName

anonymous

rating

templateTags

comment

createdAt

updatedAt

deleted

deletedAt

verifiedPurchase

---

# FIELD DEFINITIONS

foodId

Food document ID.

orderId

Collected order ID.

userId

Reviewer UID.

displayName

Displayed reviewer name.

anonymous

Boolean.

Default:

true

rating

Integer

1-5

templateTags

Array<String>

Predefined review tags.

comment

Optional short text.

createdAt

Server timestamp.

updatedAt

Server timestamp.

deleted

Boolean.

deletedAt

Server timestamp.

verifiedPurchase

Always true.

---

# REVIEWER NAME

Default display name:

CampusBite Customer

Students may enable:

Display My Name

If enabled:

Use their profile name.

Otherwise:

Always display:

CampusBite Customer

Never display email.

Never display UID.

---

# REVIEW TEMPLATES

Do not allow unrestricted review text.

Use predefined review templates.

Examples:

Great deal

Great value for money

Hot food

Served well

Fresh ingredients

Very delicious

Fast preparation

Large portion

Friendly service

Worth the price

Would order again

Not great as expected

Too salty

Too spicy

Too cold

Small portion

Late preparation

Not good at all

The student may select multiple tags.

Maximum:

5 tags.

---

# OPTIONAL COMMENT

Allow an optional short comment.

Maximum:

120 characters.

Filter profanity before saving.

Reject offensive language.

Do not allow HTML.

Do not allow URLs.

Do not allow scripts.

Trim whitespace.

---

# RATING

Allow:

1

2

3

4

5 stars

No half stars.

---

# FOOD DETAILS SCREEN

If eligible:

Display

Write Review

Otherwise

Hide the review button.

If already reviewed:

Display

Edit Review

---

# REVIEWS SCREEN

Reuse:

reviews_screen.dart

Implement the Deliveroo-style layout.

Top dashboard contains:

Average rating

Total review count

5-star distribution

4-star distribution

3-star distribution

2-star distribution

1-star distribution

Rating bars

Average stars

Review count

Exactly like Deliveroo.

---

# REVIEW SORTING

Allow:

Most Recent

Highest Rated

Lowest Rated

Oldest

Default:

Most Recent

---

# REVIEW CARD

Each card displays:

Avatar

Reviewer Name

Rating

Date

Selected review templates

Optional comment

Verified Purchase badge

If current user owns review:

Show:

Edit

Delete

---

# VERIFIED PURCHASE

Every review created through collected orders displays:

Verified Purchase

Students cannot manually create verified reviews.

---

# FOOD RATING SUMMARY

Each food item stores:

averageRating

reviewCount

ratingDistribution

Example:

ratingDistribution

5

120

4

40

3

8

2

4

1

2

Update automatically after:

Create

Edit

Delete

Never calculate on every page load.

---

# AGGREGATION

When review changes:

Update:

Food statistics.

Avoid scanning all reviews.

Incrementally maintain:

Average

Count

Distribution

---

# DELETE REVIEW

Never hard delete.

Instead:

deleted = true

deletedAt = serverTimestamp()

Exclude deleted reviews from queries.

---

# EDIT REVIEW

Students may edit:

Rating

Templates

Comment

Update:

updatedAt

Refresh food statistics.

---

# PERFORMANCE

Reviews screen:

Paginate.

Load:

20 reviews

Load more when scrolling.

Never download all reviews.

---

# FIRESTORE QUERIES

Food Reviews

WHERE

foodId == selectedFood

deleted == false

ORDER BY createdAt DESC

LIMIT 20

---

# SECURITY

Students

Create only their own review.

Edit only their own review.

Delete only their own review.

Cannot edit another user's review.

Cannot modify:

verifiedPurchase

food statistics

Admins

Read all reviews.

Future moderation only.

No moderation implementation in this phase.

---

# FIRESTORE RULES

Protect:

reviews

Allow:

Authenticated student

Create

Update own review

Soft delete own review

Read public reviews

Reject all other writes.

Food statistics updated only by backend.

---

# REVIEW SERVICE

Create:

review_service.dart

Responsibilities:

Create review

Update review

Delete review

Load reviews

Update food statistics

Check eligibility

Widgets must never manipulate Firestore directly.

---

# REPOSITORY

Create:

review_repository.dart

Use repository pattern.

Avoid duplicated code.

---

# REVIEW ANALYTICS

Prepare architecture for future:

Most reviewed food

Highest rated food

Lowest rated food

Most improved food

Do not implement analytics.

---

# TESTING

Verify:

✓ Only collected orders may review

✓ One review per collected order

✓ Anonymous name works

✓ Display real name works

✓ Templates save correctly

✓ Rating saves correctly

✓ Edit works

✓ Delete works

✓ Dashboard updates

✓ Average rating updates

✓ Rating bars update

✓ Review count updates

✓ Verified Purchase badge appears

✓ Deleted reviews disappear

✓ Pagination works

✓ Existing order flow unchanged

✓ Existing favourite engine unchanged

✓ Existing notifications unchanged

✓ Existing strike engine unchanged

---

# DELIVERABLES

Provide:

1. Files created

2. Files modified

3. Firestore schema

4. ReviewService

5. Repository

6. Firestore Security Rule updates

7. Dashboard implementation

8. Testing checklist

Stop after completing Phase 8.

Do NOT implement AI sentiment analysis.

Do NOT implement review replies.

Do NOT implement image reviews.

Do NOT implement video reviews.

Maintain backward compatibility.

---

# Phase Completion Criteria

Phase 12 is complete when:

* the new features works well with past features.
* App runs successfully.
* No runtime errors occur.
