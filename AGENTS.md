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

# Product Vision (Future Features)

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
* Verify existing features still work.

---

# Current Phase

PHASE 1

Goal:

add and update **click to view the full list** on home screen food cards

Requirements:

* enable user to click the forward arrow iconbutton and view the extended list of food items from the horizontal row of cards
* in the CategoriesTitles screen instead of using flutter's default back iconbutton navigation use close Iconbutton its the appbar
* on the appbar make sure the title is the same as in the homescreen horizontal list cards sections
* in the CategoriesTitles screen, the food cards should be layed out vetically like in the categories_screen.dart file inside screens folder

Restrictions:

* No Firebase
* No authentication
* No registration
* No database
* No admin functionality

---

# Phase Completion Criteria

Phase 1 is complete when:

* App runs successfully.
* No runtime errors occur.

---




# The following below words are out of scope for the app, **PLEASE do not read or use this implement anything**

**1. Firebase setup + data layer first (not last)**

This should come early, not late, because right now your `FoodItem` lists are hardcoded inline in `home_screen.dart` and `category_screen.dart`. Every other feature you listed — auth, search, admin — depends on having a real, shared data source. If you build auth or search against hardcoded local lists, you'll just have to rewire everything once Firebase lands anyway. Concretely: define your Firestore schema (`foods`, `cafes`, `orders`, `users` collections) and swap your current static lists for Firestore queries/streams first. This also naturally fixes your image-resolution problem, since you'd store image URLs (Firebase Storage, properly resized) instead of bundled assets — but only after you fix the cache-size logic we discussed, since `cached_network_image` still needs `memCacheWidth`/`memCacheHeight` bounds to avoid the same memory issue.

**2. Authentication second**

Auth should come right after the data layer, because almost everything downstream — orders, cart persistence across devices, admin permissions — needs to know *who* the user is. It's also lower-risk to integrate early: Firebase Auth is fairly self-contained and won't require you to re-architect existing screens much, since your current cart/order flow doesn't appear to be user-scoped yet.

**3. Admin app connection third**

This depends entirely on your Firestore schema being stable, since the admin app and the user-facing app will both read/write the same collections (e.g. cafes mark orders "ready", admins add/edit menu items). Building this before your schema is finalized means you'll likely have to change both apps in lockstep every time you adjust a field. Once Firestore + auth + role-based access (e.g. an `isAdmin` flag or custom claims) are in place, the admin app becomes a second client of the same backend rather than a new architectural layer.

**4. Algolia search last**

This is genuinely the right thing to save for last, and not just for convenience — it's a derivative feature. Algolia indexes need to mirror your Firestore data (usually via a Cloud Function that syncs on write), so it can't meaningfully exist until your Firestore schema is finalized and stable. Building search against a schema that's still shifting means re-indexing and re-mapping fields repeatedly. Your current `SearchBarScreen` can keep working against local/Firestore queries in the meantime as a placeholder — Algolia is a performance/relevance upgrade on top of working search, not a prerequisite for having search at all.

**Maintainability framing**

The general principle: *build the things other features depend on first, and the things that depend on other features last.* Your dependency graph here is roughly:

Firestore schema → Auth → (Cart/Orders become user-scoped, Admin app gets a backend to talk to) → Algolia indexing on top of stable Firestore data

Doing Algolia or the admin connection early — before your schema and auth are settled — is the most likely path to throwaway work, since both are tightly coupled to decisions (field names, collection structure, access rules) that are still likely to shift while you're building out core CRUD with Firebase.

One practical suggestion: before wiring any of this up, write out your Firestore schema on paper/in a doc (collections, fields, relationships, who reads/writes what) and get auth + a working CRUD round-trip (read foods, place an order) solid first. That single piece of groundwork is what makes the rest of your list — admin, search, anything else — additive rather than disruptive.
