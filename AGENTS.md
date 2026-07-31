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

PHASE 13

# TASK

Implement Phase 13 of CampusBite.

This phase focuses exclusively on performance optimization and Firestore efficiency.

The objective is to reduce Firestore reads and writes, improve perceived application speed, optimize memory usage, and prepare the application for production-scale usage.

This phase MUST NOT modify business logic.

Do not modify:

- Authentication
- Orders
- Strike Engine
- Notifications
- Reviews
- Favourite Engine

Only optimize the implementation.

---

# OBJECTIVES

Improve:

• Firestore efficiency

• UI responsiveness

• Startup speed

• Image loading

• Scroll performance

• Memory usage

• Network usage

without changing application behaviour.

---

# GENERAL RULES

Do not rewrite existing features.

Preserve backwards compatibility.

Every optimization must be measurable.

Avoid premature optimization.

Prefer simple improvements over architectural rewrites.

---

# PART 1 — FIRESTORE READ OPTIMIZATION

Audit every Firestore query.

Remove duplicate queries.

Never read the same document twice during a single screen session.

Reuse previously loaded data where appropriate.

---

Replace one-time polling with realtime listeners only where realtime behaviour is required.

Examples:

Cart

Order Status

Notifications

Do NOT use realtime listeners for static menu data.

---

Menu data should be loaded once and cached.

---

Limit every Firestore query.

Never download an entire collection unless required.

Examples:

Reviews

Notifications

Orders

must always paginate.

---

Use projections where supported by future SDK updates.

---

# PART 2 — FIRESTORE WRITE OPTIMIZATION

Avoid writing unchanged data.

Before updating a document:

Compare values.

If unchanged:

Do not write.

---

Batch related writes.

Example:

Order completed

↓

Update order

↓

Create notification

↓

Update favourite counters

↓

Commit together when appropriate.

---

Avoid repeated server timestamps.

Only write timestamps when data actually changes.

---

# PART 3 — LOCAL CACHE

Enable Firestore offline persistence.

Use Firestore local cache.

Menu

Food details

Categories

Reviews

should display immediately from cache before refreshing.

---

Do not manually duplicate cached Firestore data unless required.

---

# PART 4 — IMAGE OPTIMIZATION

Replace Image.network with CachedNetworkImage.

Cache all Cloudinary images.

Show lightweight placeholders.

Display error fallback images.

Precache homepage images.

Lazy-load images outside the viewport.

---

Do not reload identical image URLs.

---

# PART 5 — HOME SCREEN PERFORMANCE

Avoid rebuilding the entire Home Screen.

Split widgets into smaller reusable components.

Use const constructors wherever possible.

Use selectors or equivalent state filtering to rebuild only affected widgets.

---

Horizontal food sections must not rebuild when unrelated state changes.

---

# PART 6 — LIST PERFORMANCE

Use ListView.builder.

Use GridView.builder.

Avoid List.generate for long lists.

Provide stable Keys.

Avoid rebuilding list items unnecessarily.

---

# PART 7 — STATE MANAGEMENT

Review ChangeNotifier usage.

Avoid notifyListeners() when nothing changed.

Notify only affected consumers.

Avoid nested listeners.

Dispose controllers correctly.

Cancel StreamSubscriptions.

Dispose AnimationControllers.

Dispose ScrollControllers.

Dispose Timers.

Dispose TextEditingControllers.

---

# PART 8 — STARTUP PERFORMANCE

Initialize services lazily.

Only initialize:

Authentication

Firestore

Messaging

Cloudinary helpers

when required.

Avoid heavy work inside main().

Avoid synchronous initialization.

---

# PART 9 — SEARCH PERFORMANCE

Search locally whenever possible.

Avoid querying Firestore for every keystroke.

Debounce user input.

Delay search requests by approximately 300 milliseconds.

Cancel previous searches.

---

# PART 10 — NETWORK OPTIMIZATION

Reduce unnecessary HTTP requests.

Avoid duplicate Cloudinary downloads.

Reuse existing network responses.

Cache release metadata.

Cache configuration.

Cache static application settings.

---

# PART 11 — MEMORY OPTIMIZATION

Avoid retaining large image objects.

Release unused controllers.

Avoid memory leaks.

Profile allocations.

Ensure scrolling remains smooth.

---

# PART 12 — LOGGING

Replace debugPrint spam.

Create a centralized logging service.

Debug logs enabled only in debug mode.

Production builds should emit only warnings and errors.

Never log:

Email addresses

Authentication tokens

UIDs

Precise locations

Personal information

---

# PART 13 — CODE QUALITY

Remove dead code.

Remove duplicate services.

Remove unused imports.

Standardize formatting.

Follow repository architecture.

Improve documentation.

---

# PART 14 — PERFORMANCE METRICS

Measure:

App startup

Home loading

Menu loading

Cart loading

Order loading

Review loading

Notification loading

Document improvements.

---

# TESTING

Verify:

✓ No feature regressions

✓ Firestore reads reduced

✓ Firestore writes reduced

✓ Home screen loads faster

✓ Scrolling remains smooth

✓ Images cache correctly

✓ Notifications unchanged

✓ Orders unchanged

✓ Strike Engine unchanged

✓ Reviews unchanged

✓ Favourite Engine unchanged

✓ Offline cache works

✓ Memory leaks eliminated

---

# DELIVERABLES

Provide:

1. Files modified

2. Performance improvements implemented

3. Firestore read reductions

4. Firestore write reductions

5. Widget rebuild optimizations

6. Caching improvements

7. Image optimization summary

8. Startup optimization summary

9. Testing checklist

Stop after Phase 13.

---

# Phase Completion Criteria

Phase 13 is complete when:

* the new features works well with past features.
* App runs successfully.
* No runtime errors occur.
