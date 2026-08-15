# 🍔 CampusBite — Student Food Ordering App

A Flutter mobile application that lets university students browse the campus cafeteria menu, place food orders in advance, and skip the queue. Built with **Flutter** and **Firebase**.

> **This repository** (`foodorder`) contains the **Student App**. There is the admin companion app which will not be published.


This Project code changes must be reviewed by:
* Coderabbit [coderabbit.ai](https://coderabbit.link/the-larason)
* Qodo ai [qodo.ai](https://www.qodo.ai)
* SonarCloud [sonarcloud.io](https://sonarcloud.io/project/overview?id=davidkivuyo_foodorder) 

## Scan the QR code to visit the web app

![Qr code](designs/assets/qrcode.svg "The Web app")
---

## Table of Contents

- [Project Overview](#project-overview)
- [System Architecture](#system-architecture)
- [Repository Structure](#repository-structure)
- [Tech Stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [1. Clone the Repository](#1-clone-the-repository)
  - [2. Firebase Setup](#2-firebase-setup)
  - [3. Install Dependencies](#3-install-dependencies)
  - [4. Run the App](#4-run-the-app)
- [Project Structure — Student App](#project-structure--student-app)
- [Project Structure — Admin App](#project-structure--admin-app)
- [Cloud Functions](#cloud-functions)
- [Firestore Data Schema](#firestore-data-schema)
- [Firestore Security Rules](#firestore-security-rules)
- [App Navigation](#app-navigation)
- [Key Features](#key-features)
- [Authentication & Hardening](#authentication--hardening)
- [Your Favourites Section](#your-favourites-section)
- [Review & Moderation System](#review--moderation-system)
- [In-App Update System & Cloudflare Workers Proxy](#in-app-update-system--cloudflare-workers-proxy)
- [GitHub Release APK Workflow](#github-release-apk-workflow)
- [Search System](#search-system)
- [Distance-Based Pickup Deadline & Location-Based Calculations](#distance-based-pickup-deadline--location-based-calculations)
- [Order Lifecycle](#order-lifecycle)
- [Meal Planning & Reordering System](#meal-planning--reordering-system)
- [Pickup Extension & No-Show Handling](#pickup-extension--no-show-handling)
- [Production Notification Platform](#production-notification-platform)
- [Environment & Secrets](#environment--secrets)
- [Running Tests](#running-tests)
- [Contributing](#contributing)
- [AI Agent Usage](#ai-agent-usage)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Project Overview

CampusBite solves common problems at university cafeterias:

| Problem | Solution |
|---|---|
| Long queues at meal times | Students order in advance from their phone |
| No visibility into today's menu | Live menu synced from Firestore in real-time |
| Abandoned orders causing food waste | Pickup deadline engine with countdown timers |
| No accountability for no-shows | Missed pickups are marked as no-show and the student is notified |

The system consists of **three components** only the foodorder student app is in this directory but all two share a single Firebase project:

```
foodorder/   ← Student Flutter App (this repo)
```

---

## System Architecture

```
┌──────────────┐         ┌──────────────┐
│  Student App │         │  Admin App   │
│  (Flutter)   │         │  (Flutter)   │
└──────┬───────┘         └──────┬───────┘
       │                        │
       │   Firestore Streams    │   Firestore CRUD
       ▼                        ▼
┌─────────────────────────────────────┐
│         Cloud Firestore             │
│  ┌────────┐ ┌──────┐ ┌───────────┐  │
│  │ food_  │ │orders│ │  users    │  │
│  │ items  │ │      │ │  /cart    │  │
│  └────────┘ └──┬───┘ └───────────┘  │
│               │                     │
│         onDocumentUpdated           │
│               ▼                     │
│  ┌────────────────────────────┐     │
│  │   Cloud Functions (v2)    │      │
│  │  • Pickup Deadline Engine │      │
│  │  • Cloudinary Image Delete│      │
│  └────────────────────────────┘     │
└─────────────────────────────────────┘
       │
       ▼
┌──────────────┐     ┌──────────────┐
│ Firebase Auth│     │  Cloudinary  │
│ (Email/Pass) │     │ (Food Images)│
└──────────────┘     └──────────────┘
```

**Data flow:**
1. Admin creates/updates food items → Firestore `food_items` collection
2. Student app streams `food_items` in real-time → displays live menu
3. Student places order → writes to `orders` collection
4. Admin updates order status to "ready" → Cloud Function triggers
5. Cloud Function computes `readyAt`, `pickupDeadline` → writes back to order
6. Student app displays countdown timer from Firestore data
7. If student doesn't collect → order marked no-show and student notified

---

## Tech Stack

| Layer | Technology |
|---|---|
| **Framework** | Flutter (Dart SDK ^3.12.2) |
| **State Management** | Streams + `setState` (simple architecture) |
| **Routing** | `go_router` with auth-aware redirects |
| **Authentication** | Firebase Auth (Email/Password) |
| **Database** | Cloud Firestore (real-time sync) |
| **Cloud Functions** | Firebase Functions v2 (Node.js) |
| **Image Hosting** | Cloudinary (via admin app) |
| **Image Caching** | `cached_network_image` |
| **Typography** | Google Fonts (`DM Sans`) |
| **Offline Detection** | `dash_no_internet_screen` |

---

## Prerequisites

Before you begin, ensure you have the following installed:

- **Flutter SDK** ≥ 3.12.2 — [Install Flutter](https://docs.flutter.dev/get-started/install)
- **Dart SDK** — bundled with Flutter
- **Android Studio** or **VS Code** with Flutter extensions
- **An Android emulator** or physical device (API 21+)
- **Node.js** ≥ 18 — required for Cloud Functions
- **Firebase CLI** — `npm install -g firebase-tools` or use `npx firebase-tools`
- **A Firebase project** — [Create one here](https://console.firebase.google.com/)

Verify your setup:

```bash
flutter doctor
firebase --version        # or: npx firebase-tools --version
node --version
```

---

## Getting Started

### 1. Clone the Repository

```bash
git clone <repository-url>
cd foodorder
```

### 2. Firebase Setup

The app requires a Firebase project with **Authentication**, **Cloud Firestore**, and **Cloud Functions** enabled.

#### a) Create a Firebase Project
1. Go to the [Firebase Console](https://console.firebase.google.com/)
2. Create a new project (or use an existing one)
3. Enable **Email/Password** under Authentication → Sign-in method

#### b) Generate Configuration Files

```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure for this project (run from customerview/)
flutterfire configure --project=<your-firebase-project-id>
```

This generates `lib/firebase_options.dart` and `android/app/google-services.json`.

#### c) Create Firestore Database
1. In Firebase Console → Firestore Database → Create database
2. Start in **production mode**
3. create and update security rules (see [Firestore Security Rules](#firestore-security-rules))

#### d) Deploy Cloud Functions

create your firebase rules and deploy them

```bash
npx firebase-tools deploy --only functions
```

#### e) Seed Required Collections

Create these collections manually in the Firestore Console (or through the admin app):

| Collection | Required Documents |
|---|---|
| `categories` | `{ name: "Breakfast", order: 1 }`, `{ name: "Lunch", order: 2 }`, etc. |
| `cafes` | `{ name: "Main Cafeteria", location: "Building A" }` |
| `section` | `{ name: "campus_favourite" }` |

### 3. Install Dependencies

```bash
cd foodorder
flutter pub get
```

### 4. Run the App

**Android Studio:**
Click the ▶ Run button in the toolbar.

**VS Code:**
Open `lib/main.dart` and press F5, or:

```bash
flutter run
```

**Web (experimental):**

```bash
flutter run -d chrome
```

---

## Project Structure — Student App

```
foodorder/
├── lib/
│   ├── main.dart                  # Entry point, Firebase init, WelcomeScreen
│   ├── firebase_options.dart      # Auto-generated Firebase config
│   │
│   ├── data/                      # Data models & data-oriented widgets
│   │   ├── food_data.dart         #   FoodItem model, FoodData streams, Section model
│   │   └── search_bar.dart        #   Search screen with Firestore prefix-search
│   │
│   ├── models/                    # Domain models
│   │   ├── order.dart             #   Order model, OrderStatus enum, DeadlineStatus
│   │   └── cart_item.dart         #   CartItem model
│   │
│   ├── services/                  # Business logic & Firebase interactions
│   │   ├── auth_service.dart      #   Email/password auth (register, login, logout)
│   │   ├── cart_service.dart      #   Cart management (add, remove, Firestore sync)
│   │   ├── search_service.dart    #   Firestore search with in-memory caching
│   │   ├── search_helper.dart     #   Generates searchable fields (prefixes, keywords)
│   │   ├── pickup_deadline_service.dart  # Format deadline timestamps for UI
│   │   └── pickup_extension_service.dart # One-tap +10 min pickup extension
│   │
│   ├── screens/                   # Full-page screens
|   |   |-- welcome_screen.dart        #   Landing page with login/register buttons
│   │   ├── home_screen.dart       #   Home feed, featured items, food detail view
│   │   ├── category_screen.dart   #   Browse food by category
│   │   ├── common_food.dart       #   Shared food listing used by category/section
│   │   ├── order_screen.dart      #   Active & past orders with countdown timers
│   │   ├── account_screen.dart    #   Profile, notifications, settings
│   │   ├── login_screen.dart      #   Sign in screen
│   │   ├── register_screen.dart   #   Registration screen
│   │   ├── reset_password.dart    #   Password reset
│   │   ├── help_support.dart      #   FAQ & contact support
│   │   └── terms.dart             #   Terms of service & privacy policy
│   │
│   ├── widgets/                   # Reusable UI components
│   │   ├── auth_fields.dart       #   Styled form fields for auth screens
│   │   ├── cart_bottom_sheet.dart  #   Cart modal with checkout flow
│   │   ├── cart_fab.dart          #   Floating action button for cart
│   │   ├── cafe_selection_dialog.dart  # Cafe picker when ordering
│   │   ├── pickup_countdown.dart  #   Countdown timer widget (pure UI)
│   │   └── logout_confirmation_dialog.dart
│   │
│   └── navigation/                # Routing & navigation
│       ├── router.dart            #   GoRouter config with auth redirects
│       ├── bottom_navigation.dart #   Bottom nav bar (Home, Categories, Search, Orders, Account)
│       └── auth_wrapper.dart      #   Listens to auth changes, notifies router
│
├── designs/                       # UI mockups & design assets
├── test/                          # Unit & widget tests
├── android/                       # Android platform files
├── web/                           # Web platform files
├── AGENTS.md                      # AI agent rules (see AI Agent Usage)
├── pubspec.yaml                   # Dependencies
└── firebase.json                  # Firebase project config
```

---

## Project Structure — Admin App(just to give an overview)- ADMIN APP IS NOT PUBLISHED

```
adminview/
├── lib/
│   ├── main.dart                  # Entry point
│   ├── constants/
│   │   └── app_config.dart        # Cloudinary setups
│   ├── models/
│   │   ├── food_item.dart         # Shared FoodItem model
│   │   └── order.dart             # Order model
│   ├── screens/
|   |   |-- home_screen.dart         # Admin dashboard home
│   │   ├── auth_gate.dart         # Auth-gated entry
│   │   ├── login_screen.dart      # Admin login
│   │   ├── register_screen.dart   # Admin registration
│   │   ├── main_screen.dart       # Admin dashboard shell
│   │   ├── menu_screen.dart       # View/edit/delete food items
│   │   ├── add_product.dart       # Create/update food items
│   │   ├── order_screen.dart      # Manage orders, mark ready/collected
│   │   ├── integrity_screen.dart  # Student discipline management
│   │   └── report_screen.dart     # Analytics & reports
│   ├── services/
│   │   ├── auth_service.dart
│   │   ├── food_service.dart      # CRUD for food_items collection
│   │   ├── cloudinary_service.dart # Image upload/delete via Cloudinary
│   │   ├── order_service.dart
│   │   └── search_helper.dart     # Generates search fields on save
│   ├── providers/
│   └── widgets/
│
└── functions/                     # Firebase Cloud Functions (Node.js)
    ├── index.js                   # onOrderStatusChanged, deleteCloudinaryImage
    ├── package.json
    └── .gitignore
```

---

## Cloud Functions

Located in `functions/index.js` (shared with the admin app).

### 1. `onOrderStatusChanged` (Firestore Trigger)

**Trigger:** `onDocumentUpdated` on `orders/{orderId}`

When an order's status changes to `"ready"`, the function:
1. Checks idempotency — if `readyAt` already exists, returns immediately
2. Computes `readyAt` using the server timestamp
3. Sets `pickupWindowMinutes = 20`
4. Computes `pickupDeadline = readyAt + 20 minutes`
5. Sets `deadlineStatus = "ACTIVE"`
6. Writes all fields atomically

**The backend is the single source of truth.** Neither the student app nor the admin app calculates deadlines.

### 2. `deleteCloudinaryImage` (Callable Function)

Admin-only callable function that securely deletes food images from Cloudinary using server-side secrets. Logs all deletions to `audit_logs`.

### 3. `processExpiredPickups` (Scheduled — every 5 minutes)

Runs every 5 minutes and marks orders whose pickup deadline has passed as `no_show` (`deadlineStatus = "EXPIRED"`), then sends the student an `ORDER_NO_SHOW` notification. It also sends `PICKUP_REMINDER` notifications for orders nearing their deadline. **The automatic strike engine has been removed** — expired orders are never linked to strikes or auto-suspension here; strike management is exclusively an admin-app concern.

### 4. `extendPickupDeadline` (Callable Function)

Student-facing callable that extends an order's pickup deadline by **10 minutes**. Enforced invariants (all inside a Firestore transaction):
- The caller must be authenticated (App Check enforced) and own the order.
- The order must still be `ready` with an `ACTIVE` deadline.
- The extension is consumable **once per order**.
- The current deadline must not have passed yet.

The customer app surfaces this as the one-tap **"Extend pickup by 10 min"** button on ready orders.

### 5. `excuseNoShow` (Callable — Phase G admin intervention)

Admin-only callable that excuses a specific NO_SHOW order. Enforced server-side:
- The caller must be an authenticated, **ACTIVE** admin whose `cafeName` is in the order's `cafes` list (cross-cafe denied); a cafeless order (absent/empty `cafes`, or tagged `UNASSIGNED`) is excusable by any active admin.
- The order must be `NO_SHOW` with a recorded `noShowAt`, not already excused.
- The reason must be one of the predefined reasons; the note is optional, ≤ 200 chars, no URLs/HTML.
- Atomically marks the order `noShowExcused`, corrects the student's reliability summary (event excluded from failure counts, restriction recomputed), and writes an immutable `audit_logs/NO_SHOW_EXCUSED_{orderId}` record.
- Commits the order state, reliability correction, audit record, and the `NO_SHOW_EXCUSED_{orderId}` notification outbox event in one transaction; FCM push is delivered by the post-commit `onNewNotification` trigger (eventId-deduped).

### 6. `reactivateStudent` (Callable — admin account action)

Admin-only callable that reactivates a genuinely SUSPENDED student account:
- The caller must be an authenticated, **ACTIVE** admin.
- The target must exist and be exactly `accountStatus: "SUSPENDED"` (checked inside the transaction, atomic with the ACTIVE flip).
- The account-status flip and the immutable `audit_logs` REACTIVATE record commit in **one Firestore transaction**; actor identity (`adminId`) and `timestamp` are derived server-side from the authenticated caller.
- Creates exactly one `ACCOUNT_REACTIVATED` student notification after commit (eventId-deduped).

`firestore.rules` grants **no** client create/update/delete on `audit_logs` — audit records are backend-only (AGENTS.md §23).

### Deploying Functions

Write your firebase.rules and deploy them. It is added in .gitignore by default so consider that.

```bash
npx firebase-tools deploy --only functions
```

Cloudinary api:

Get the api keys on your cloudinary account or any other storage providers.

---

## Firestore Data Schema

## Collections

- **`categories`** — `{ name, order }`
- **`food_items`** — `{ title, subtitle, description, image, price, rating, category, availableCafes, section, time, available, featured, quantity, dietaryTags, keywords, searchPrefixes, createdAt, updatedAt }`
- **`orders`** — `{ orderId, userId, userName, items, totalPrice, status, cafe, cafeId, cafes, cafeLocation, distanceMeters, distanceCalculated, pickupWindowMinutes, readyAt, pickupDeadline, deadlineStatus, noShowProcessed, noShowAt, noShowExcused, excusedAt, excusedBy, excuseReason, excuseNote, expiredAt, deadlineExtended, extensionAt, createdAt, updatedAt }`
- **`users`** — `{ fullName, email, role, strikeCount, accountStatus, lastPardonAt, createdAt, updatedAt, pickupReliability }`
- **`users/{userId}/cart`** — `{ foodItemId, quantity, cafe }`
- **`users/{userId}/plans`** — `{ title, note, totalAmount, plannedDate, createdAt, items }`
- **`notifications`** — `{ recipientId, recipientRole, type, title, message, orderId, eventId, deepLink, metadata, read, readAt, deleted, deletedAt, createdAt, createdBy }`
- **`audit_logs`** -- `{action, studentId, orderId, adminId, cafeId, previousStrikeCount, newStrikeCount, previousStrike, newStrike, reason, note, timestamp}`
- **`cafes`** — `{ name, location, geopoint }`
- **`section`** — `{ name }`
- **`reviews`** — `{ userId, text, rating, ... }`

---

## Firestore Security Rules

Read and write your own firestore rules. follow best practices in the official documentations.

**Order creation is server-exclusive:** `firestore.rules` exposes **no** client `create` on `/orders` (the old `validOrderCreateRequest()` helper was removed). Orders are created only by the `placeOrder` Cloud Function callable — the client invokes it via `OrderPlacementService` (wired through `CartService.placeOrder`) — so the Phase E active-order limit cannot be bypassed by writing an order document directly, and server-owned fields (`createdAt`, `cancellationDeadline`, `readyAt`, `pickupDeadline`, `collectedAt`, `expiredAt`, `noShowProcessed`, ...) cannot be forged on create. App builds older than Phase E that placed orders with a direct client write must be updated before the new rules are deployed.

**Per-cafe admin scoping:** admins can read/update/delete only orders belonging to their own cafe. Each order carries a server-authoritative `cafes` array (cafe names derived from the validated line items' `selectedCafe`); the `adminServesOrder()` helper requires the admin's `users/{uid}.cafeName` to appear in that array, and `cafes` is in `adminNotModifyingProtectedOrderFields()` so no client (admin included) can forge it. The admin app queries orders with `where('cafes', 'array-contains', cafeName)` — the matching Firestore composite index (`cafes` CONTAINS + `createdAt` DESC) is declared in `firestore.indexes.json`.

**Cafeless orders (UNASSIGNED):** a genuinely cafeless order — one whose line items have no resolvable `selectedCafe` (e.g. off-campus listings) — is tagged by `placeOrder`/`backfillOrderCafes` with the sentinel `cafes: ['UNASSIGNED']` instead of omitting the field. `adminServesOrder()` grants every active admin read/update/delete on such orders, so an admin who receives a NEW_ORDER notification can always open and process the order — mirroring the notification fallback that delivers cafeless orders to every admin. A legacy order whose `cafes` is still absent/empty/malformed is **unreadable by every admin** until the backfill normalizes it — no client can access unscoped data. `backfillOrderCafes` (used by `onNewOrder`/`onOrderStatusChanged` and the scheduled `migrateLegacyOrderCafes`) repairs absent/empty/malformed `cafes` values to the derived cafe list, or to `UNASSIGNED` when nothing is derivable; valid non-empty lists are never clobbered.

---

## App Navigation

The student app uses `go_router` with authentication-aware redirects:

```
/              → WelcomeScreen  (unauthenticated landing)
/register      → RegisterScreen
/login         → LoginScreen
/main          → MainScreen     (authenticated, contains bottom nav)
/terms         → TermsScreen
/support       → SupportScreen
/support/faq   → FaqScreen
/support/contact → ContactScreen
```

**Auth redirects:**
- Logged in + on `/`, `/login`, or `/register` → redirected to `/main`

**Bottom Navigation Bar** (inside `/main`):

| Index | Tab | Screen |
|---|---|---|
| 0 | Home | `HomeScreen` — featured items, sections, food feed |
| 1 | Categories | `CategoryScreen` — browse by Breakfast, Lunch, etc. |
| 2 | Search | `SearchBarScreen` — Firestore prefix-based search |
| 3 | Orders | `OrdersScreen` — active orders with countdown, history |
| 4 | Account | `AccountScreen` — profile, settings, logout |

---

## Key Features

### For Students
- **Registration, Verification & Password Recovery** — Email/password authentication via Firebase Auth, complete with mandatory verification of email addresses before ordering and clean self-serve password recovery options.
- **Your Favourites** — Personalized carousel of student's top favourite food items computed from order history.
- **Reviews & Ratings** — Leave reviews for completed orders, view average food ratings, and view customer feedback.
- **In-App Update System** — Automatic updates with resume-able downloads and SHA-256 checksum verification to guarantee authentic builds*.
- **Browse Menu** — Real-time Firestore stream of available food items sorted by category.
- **Categories** — Quick navigation to browse food items by categories (e.g. Breakfast, Lunch, Dinner, Teasers, Drinks).
- **Search** — Fast, prefix-based Firestore search with 300ms debounce and in-memory caching.
- **Cart & Checkout** — Add items, choose target cafe, and review total amount before placing orders.
- **Distance-Based Pickup Window** — Automatically calculates walking distance to target cafe using GPS/Geolocator and requests corresponding pickup time window at checkout (from 10 to 25 minutes) to ensure freshness.
- **Orders & Countdown Timers** — Track active order statuses and see real-time pickup countdown timers synced with server-enforced deadlines.
- **One-Tap Reordering** — Reorder entire past orders with one tap from the order history. Automatically checks current availability/stock levels for each item before loading them into the active cart.
- **Meal Planning** — Pre-plan customized meals for upcoming days, study breaks, or campus events. Save custom plans directly from the active cart or convert a past order into a plan, then load and purchase in one click when ready.
- **Pickup Extension** — One-tap **"Extend pickup by 10 min"** action (once per order, before the deadline) available on the order card and in the order details sheet.
- **Pickup Reliability** — Your pickup reliability score, status, and collection history shown in **My Profile** (Phases D–F). Informational only: new users and limited-history users are never shown a poor rating. Status is informational; the Phase E graduated ordering limit is derived from the same server-maintained summary and relaxes automatically as you collect orders (Phase F).
- **Notification Center** — In-app notification feed supporting real-time alerts for order status changes, pickup reminders, missed-pickup (no-show) alerts, and account suspension events.

### For Cafeteria Admins
- **New Order Alerts** — Automatic notification of incoming student orders in real time.
- **Order Flow Manager** — Control order stages from pending, accepted, preparing, to ready for collection.
- **No-Show Tracking** — Missed pickups are automatically marked `no_show` and logged to `audit_logs`; no strikes are issued by the customer backend.
- **Account Management** — Reactivate a genuinely suspended student account via the backend `reactivateStudent` callable: the ACTIVE flip and the immutable `audit_logs` REACTIVATE record are written server-side (audit_logs are backend-only — no client create/update/delete).

---

## Search System

The search feature uses a **prefix-based array-contains** strategy for Firestore:

1. **When admin creates/updates a food item**, `SearchHelper` auto-generates:
   - `titleLower` — lowercase title
   - `keywords` — unique lowercase words from title, category, and dietary tags
   - `searchPrefixes` — all prefix substrings of each word (e.g. "chicken" → `["c", "ch", "chi", "chic", "chick", "chicke", "chicken"]`)

2. **When a student searches**, `SearchService`:
   - Trims and lowercases the query
   - Checks an in-memory cache before hitting Firestore
   - Queries `food_items` where `available == true` AND `searchPrefixes array-contains query`

3. **The search UI** (`SearchBarScreen`) debounces input by 300ms and displays results with food images, price, category, and cafe info.

> **Note:** For existing food items created before search was implemented, re-save them through the admin app to generate the search fields.

---

## Distance-Based Pickup Deadline & Location-Based Calculations

To minimize food waste from abandoned orders while keeping pickup schedules fair for students, CampusBite calculates a dynamic pickup window based on the student's walking distance to the cafeteria at the moment they checkout:

1. **GPS Distance Calculation:** 
   When the student clicks "Place Order", the app requests temporary, single-use access to device location. It computes the straight-line walking distance (in meters) between the student's coordinates and the selected cafe's geographic coordinates using the `Geolocator.distanceBetween` API.
   
2. **Dynamic Pickup Windows:**
   The calculated distance maps to specific pickup windows via the `PickupWindowService`:
   - **0 – 250 meters:** 10-minute pickup window
   - **251 – 600 meters:** 15-minute pickup window
   - **601 – 1200 meters:** 20-minute pickup window
   - **Above 1200 meters:** 25-minute pickup window

3. **Privacy Protections:**
   To protect student privacy, the app **never** uploads, stores, or transmits precise GPS coordinates or location history to Firestore or any external server. Location data is calculated strictly client-side. Only the resulting distance (in meters) and the pickup window (in minutes) are persisted inside the order document under `distanceMeters` and `pickupWindowMinutes`.

4. **Deadline Enforcement:**
   When a cafeteria admin marks the order's status as `"ready"`, the `onOrderStatusChanged` Cloud Function reads the stored `pickupWindowMinutes` from the order document and atomically calculates the deadline:
   $$\text{pickupDeadline} = \text{readyAt} + (\text{pickupWindowMinutes} \times 60 \text{ seconds})$$
   The function updates `pickupDeadline` and sets `deadlineStatus` to `"ACTIVE"`. If `pickupWindowMinutes` is missing, it defaults to a 20-minute fallback.

---

## Order Lifecycle

```
Student places order
        │
        ▼
    ┌────────┐
    │PENDING │ ← Awaiting admin review
    └───┬────┘
        │ Admin accepts
        ▼
    ┌────────┐
    │ACCEPTED│
    └───┬────┘
        │ Admin starts cooking
        ▼
    ┌──────────┐
    │PREPARING │
    └───┬──────┘
        │ Admin marks "Ready for Pickup"
        │ (only updates status field)
        ▼
    ┌───────┐ ── Cloud Function triggers ──→ writes readyAt,
    │ READY │                                pickupDeadline,
    └───┬───┘                                deadlineStatus = ACTIVE
        │
        ├── Student collects ──→ COLLECTED (deadlineStatus = COLLECTED)
        │
        ├── Student extends pickup ──→ +10 min to pickupDeadline (once per order)
        │
        └── Deadline expires ──→ NO_SHOW (deadlineStatus = EXPIRED)
                                  └──→ Student notified (ORDER_NO_SHOW)

COLLECTED and NO_SHOW are the only reliability-eligible outcomes:
                COLLECTED ──→ reliability +collected, +eligible
                NO_SHOW   ──→ reliability +no-show, +eligible
                (cancelled / rejected / never-ready orders are never counted)
```

---

## Meal Planning & Reordering System

CampusBite provides students with tools to plan meals in advance and quickly repeat past orders. These features improve convenience and decrease checkout friction, especially during busy campus hours.

### 1. One-Tap Reordering
To speed up the checkout process for recurring meals, students can reorder all items from any past order with a single click.

#### Reorder Flow
1. **Access History**: The student navigates to the **Orders** tab and selects the **History** sub-tab showing past completed or cancelled orders.
2. **Trigger Reorder**:
   - Tap the **Reorder** button directly on the past order card.
   - Or open the order's detailed bottom sheet and tap the **Reorder All** button.
3. **Availability & Validation Check**:
   - The system retrieves the items from the past order and verifies each item's current `available` status in real-time.
   - **Available Items**: Automatically added to the student's active shopping cart with the original quantities and selected cafes.
   - **Unavailable / Out-of-Stock Items**: Excluded from the cart.
4. **User Feedback**:
   - If items are successfully added, a green SnackBar is displayed: `Reordered X items to cart!`. It includes an **OPEN CART** action button to proceed directly to checkout.
   - If some items are unavailable, the SnackBar notifies the user: `Reordered X items to cart! (Y item out of stock)`.
   - If all items in the order are unavailable, a red SnackBar alerts the user: `Items in this order are currently unavailable.` and no changes are made to the cart.

### 2. Meal Planning
Students can pre-schedule meals for upcoming study sessions, exam weeks, or daily schedules. Planned meals are saved to Firestore and can be transferred to the cart instantly.

#### Creating a Meal Plan
* **From Cart**: If a student has items in their active cart, they can navigate to the **Orders** tab → **Planned** tab and click **Create Your First Plan** / **Plan an Upcoming Meal** (or click the Calendar icon at the top of the Orders tab).
* **From Past Orders**: When viewing details of a past order, the user can click **Save as Plan** to create a plan pre-populated with those items.
* **Plan Customization**: The **Plan an Upcoming Meal** dialog prompts the user to enter:
  - **Plan Name** (e.g., "Monday Study Group Lunch", "Post-Exam Dinner").
  - **Target Date & Time**: Selected using an interactive date/time picker.
  - **Custom Note** (e.g., "Add extra spicy sauce").
  - The dialog displays a summary of the items and the estimated total cost.
* **Storage**: Clicking **Save Plan** uploads the plan as a document in the `users/{userId}/plans` subcollection on Firestore.

#### Managing & Checkout of Planned Meals
* **Viewing Plans**: Saved plans are streamed in real-time under the **Planned** tab, ordered chronologically by their planned date.
* **Instant Load-to-Cart**: Each plan card features a shopping cart button (`Order`). Clicking it iterates through the plan's saved items, adding them directly to the active cart, and displays a SnackBar saying `Loaded "[Plan Title]" into cart!` with an **OPEN CART** action to check out.
* **Deleting Plans**: Students can permanently delete plans by tapping the trash icon on the card, which executes a direct Firestore delete operation on that document.

---

## Pickup Extension & No-Show Handling

CampusBite keeps pickup schedules fair and prevents food waste by enforcing server-authoritative deadlines, giving students a one-time grace action, and notifying them when an order is missed.

### 1. Pickup Deadline (`onOrderStatusChanged`)
When an admin marks an order `ready`, the Cloud Function computes `readyAt` and sets `pickupDeadline = readyAt + pickupWindowMinutes` (default 20 minutes) with `deadlineStatus = "ACTIVE"`. The backend is the single source of truth — the app only renders the countdown.

### 2. Extend Pickup (`extendPickupDeadline` callable)
Before the deadline passes, a student can tap **"Extend pickup by 10 min"** on a ready order (order card or details sheet). The callable:
- Verifies the caller is authenticated (App Check enforced) and owns the order.
- Verifies the order is still `ready` with an `ACTIVE` deadline.
- Extends `pickupDeadline` by 10 minutes — **consumable once per order**.

All checks run inside a Firestore transaction, so two concurrent taps cannot both consume the extension.

### 3. No-Show Processing (`processExpiredPickups`)
A scheduled Cloud Function runs every 5 minutes and marks any ready order whose `pickupDeadline` has passed as `no_show` (`deadlineStatus = "EXPIRED"`), then sends the student an `ORDER_NO_SHOW` notification. It also sends `PICKUP_REMINDER` notifications for orders nearing their deadline.

**The automatic strike engine has been removed from the customer app and its backend.** No strikes are issued and accounts are never auto-suspended for missed pickups; only the no-show notification remains. Strike management is exclusively an admin-app concern.

### 3b. Pickup Reliability Engine (Phase B.2)
The `onOrderStatusChanged` trigger feeds a server-side reliability engine that measures — never punishes — how consistently a student collects their food:
- **Eligible events only:** an order counts only when it reaches `COLLECTED` (success) or `NO_SHOW` (miss). Cancelled, rejected, or never-`READY` orders never affect reliability.
- **Idempotent & atomic:** each order carries a `reliabilityProcessed` marker written in the **same Firestore transaction** as the summary update, so redelivered or concurrent events can never double-count.
- **Never silently dropped:** if a terminal event arrives before the student's `users/{uid}` document exists (e.g. restored account), the event is **deferred** — a `reliabilityPending` + `reliabilityPendingSince` marker is recorded, the trigger retries, and the event is counted once the user doc appears. Because Cloud Functions only redelivers a failed trigger for a bounded window, the 5-minute scheduled processor also **reconciles** pending orders (`reconcilePendingReliabilityOrders`): it counts them when the user doc appears and retries the rest, so an event can never be stranded. Only after 7 days (`RELIABILITY_MISSING_USER_RETRY_MS`) does the engine give up **explicitly and audibly** (`reliabilitySkippedReason: "MISSING_USER"` + `reliabilitySkippedAt`), never by silently marking the order processed.
- **No history scans:** updates are event-driven; the account screen reads the existing `users/{uid}` document (≈1 read) — reliability is never recomputed by scanning order history.
- **Recent window:** the last 10 eligible outcomes are kept in `recentPickupHistory` (bounded, per-order unique).
- **Score:** `reliabilityScore = collectionRate × 0.70 + recentCollectionRate × 0.30` (rounded to 1 decimal).
- **Status:** 0 eligible → `NEW`; 1–2 → `INSUFFICIENT_HISTORY`; 3+ → `EXCELLENT` (90+), `GOOD` (75+), `NEEDS_IMPROVEMENT` (50+), `POOR` (25+), `CRITICAL` (<25). New users are `NEW` with score 100 — never 0%.
- **Security:** `pickupReliability` is server-authoritative. Firestore rules deny any student write to the nested map and any client write of `reliabilityProcessed` or the immutable `reliabilityOutcome` (`COLLECTED`/`NO_SHOW`, written atomically with the processed marker); students read only their own summary via the existing owner read rule.
- **Restrictions (Phase E):** graduated ordering limits derive from this same server-maintained summary (see §3d below) — there are no suspensions, bans, cooldowns, or permanent penalties, and restrictions relax automatically as the summary improves (Phase F).

### 3c. Pickup Reliability Experience (Phase D)
The student app surfaces the reliability summary in the **My Profile** screen (reached from Account → My Profile → Reliability Status):
- **PickupReliabilityCard** shows the reliability score, status label, collection history (`X collected · Y missed`), a progress bar, and a short explanatory message.
- **New users** (`eligibleOrders == 0`) see "New record" — never 0% — and insufficient-history users see "Building record", both with constructive messages and no punishment language.
- **Recent performance** shows "Last N pickups: X collected · Y missed" from the server-maintained recent window, and **positive reinforcement** ("Great job — you've collected your recent orders on time.") appears when the recent window is fully collected.
- **No-show orders** display a non-punitive **"No-show recorded"** notice in the order details sheet: "The pickup window and grace period ended before the order was collected." — no strike or penalty language.
- **Grace period** is visually distinct in the countdown chip ("Grace period active · MM:SS" in orange), and once the grace window has passed the chip reads "Pickup window expired" (hard cutoff — the client never advertises collection after expiry).
- **Privacy & cost:** the card reads the existing `users/{uid}` listener (≈0 additional reads, 0 writes); it never queries order history and never recalculates reliability client-side. Students see only their own reliability.

### 3d. Graduated Ordering Restrictions (Phase E)
The reliability summary also drives a graduated, reversible ordering limit — never a ban or suspension:
- **Levels:** `NORMAL` (no limit), `LIMITED` (max 2 active orders), `HIGHLY_LIMITED` (max 1 active order). `NORMAL` is also used for students with fewer than 3 eligible outcomes (insufficient evidence).
- **Thresholds (server-derived):** score ≥ 50 → `NORMAL`; 25–49 → `LIMITED`; < 25 → `HIGHLY_LIMITED`. Active orders are `pending`/`accepted`/`preparing`/`ready` — terminal states never count.
- **Enforcement:** order creation runs exclusively through the server-authoritative `placeOrder` callable, which counts the student's active orders inside the same transaction that creates the order (plus a contention write to the shared user document) so the limit cannot be raced. `firestore.rules` exposes no client `create` on `/orders`.
- **Read-only everywhere:** students and admins can read `restrictionLevel`/`restrictionReason` (nested inside `pickupReliability`) but only the backend engine writes them. The profile shows a non-punitive notice with the current limit.

### 3e. Reliability Recovery (Phase F)
Recovery is automatic — no admin approval, student request, or manual reset:
- **Successful collections are the only recovery event:** each genuine `READY → COLLECTED` transition recomputes the existing Phase B summary (lifetime + recent weighted score) and re-derives the restriction level in the same atomic write. No artificial recovery points, bonus points, or second score exist — the Phase B formula is unchanged.
- **Restrictions relax naturally:** `HIGHLY_LIMITED` → `LIMITED` when the score crosses 25, and `LIMITED` → `NORMAL` when it crosses 50. The level is derived on every event, so the change is immediate and never requires a refresh.
- **Idempotent & race-free:** the same `reliabilityProcessed` marker and Firestore transaction that guard Phase B counting also guarantee each collection contributes exactly once, even when two orders are collected simultaneously.
- **What does NOT recover a student:** `NO_SHOW` never improves reliability (it degrades it), cancelled/rejected/never-`READY` orders are ignored, and the Phase C grace period / automatic no-show processor is unchanged.
- **UI:** the reliability card shows positive reinforcement ("Keep it up — your ordering limits are relaxing…") when a restricted student has a fully collected recent window, and the ordering-limit notice uses forward-looking recovery language — no punishment, strikes, bans, or penalties.
- **Cost:** recovery adds zero new Firestore operations — it reuses the one event-driven reliability transaction and the existing `users/{uid}` listener (no order-history scans, no client polling, no per-minute recalculations).

### 3f. Admin Intervention — Excuse No-Show (Phase G)
Authorized cafe admins can correct a legitimate exceptional NO_SHOW without recreating the old strike/pardon system. The reliability engine stays authoritative — the only intervention is **Excuse No-Show**, a correction to a specific event:
- **Eligibility:** only orders with `status == NO_SHOW` and a recorded `noShowAt` that have **not** already been excused. PENDING/ACCEPTED/PREPARING/READY/COLLECTED/CANCELLED orders are rejected (`failed-precondition`).
- **Backend (`excuseNoShow` callable):** enforces authentication, the `admin` role, an `ACTIVE` account, and **per-cafe authorization** — the caller's `users/{uid}.cafeName` must appear in the order's server-authoritative `cafes` list (cross-cafe excuses are `permission-denied`). The student ID is derived from the order, never accepted from the client. Predefined reasons only ("Student reported emergency", "Cafe unable to fulfill order", "System/application issue", "Pickup information was incorrect", "Admin-approved exception", "Other"), optional note ≤ 200 chars with URLs/HTML rejected — except that a **non-empty note is required when the reason is "Other"** (the catch-all needs an explanation for the audit trail); the admin UI enforces this before submitting.
- **Data model:** the order **stays NO_SHOW** with the original `noShowAt` intact; the excuse is additive — `noShowExcused: true`, `excusedAt`, `excusedBy`, `excuseReason`, `excuseNote`. No field is rewritten, and `NO_SHOW → COLLECTED` is never produced.
- **Reliability correction:** the excused event is removed from `recentPickupHistory` (omission — it counts as neither success nor failure), `eligibleOrders`/`noShowOrders` are decremented by one, and the Phase B formulas recompute `reliabilityScore`, `status`, and the Phase E `restrictionLevel` — so a LIMITED student can recover to NORMAL automatically. The correction runs only when the no-show was actually counted (`reliabilityProcessed === true` && `reliabilityOutcome === "NO_SHOW"`); an uncounted event never corrupts the summary.
- **Atomicity & idempotency:** the eligibility check, excuse fields, summary correction, the immutable `audit_logs/NO_SHOW_EXCUSED_{orderId}` record, and the deterministic `notifications/NO_SHOW_EXCUSED_{orderId}` outbox event commit in **one Firestore transaction** — a transaction failure commits none of them. A concurrent or duplicate excuse is rejected (`failed-precondition` — already excused) with no duplicate audit record or outbox event.
- **Student notification:** one `NO_SHOW_EXCUSED` notification ("An administrator reviewed Order #CB-1234 and excused the missed pickup…") is written **inside the same transaction** as the intervention; FCM push is delivered exclusively by the post-commit `onNewNotification` trigger, so a failed intervention never notifies and retries never duplicate.
- **Student visibility:** the order card/sheet show "No-show recorded · Excused" / a green "No-show excused" notice — the order was not collected, but it is excluded from reliability. Admin UID and private notes are never exposed.
- **Security rules:** `noShowExcused`/`excusedAt`/`excusedBy`/`excuseReason`/`excuseNote` are added to `adminNotModifyingProtectedOrderFields()` (server-written only), `NO_SHOW_EXCUSED` joins the notification allowed types, and audit logs remain append-only.
- **Admin UI:** on the admin order screen, eligible NO_SHOW orders show an **Excuse No-Show** action → reason selection sheet → confirmation dialog ("Excuse this no-show? … The original order history will remain unchanged."). Already-excused orders render an "Excused" badge with the reason and no action.

### 4. Suspension Enforcement
Account suspension is still honoured when ordering: if `accountStatus == "SUSPENDED"` (managed by the admin app), `CartService.isAccountSuspended()` blocks the student from placing new orders or adding items to the cart.

---

## Production Notification Platform

CampusBite features a scalable, production-ready notification platform that decouples notification delivery from core business logic.

### 1. Architectural Flow
```
Business Event (Order Placed, Marked Ready, Order Missed, etc.)
                   │
                   ▼
   Cloud Functions — createNotification (Admin SDK)
                   │
        (Checks Event ID for Dupes)
                   │
                   ▼
    Firestore "notifications" Collection
         │                       │
         ▼                       ▼
   Student App Stream      Admin App Stream
   (Real-time Listeners)   (Real-time Listeners)
         │                       │
         ▼                       ▼
  Deep-link Nav on Tap    Deep-link Nav on Tap
         │
         ▼
  (Future) FCM Push Delivery
```

> **Where notifications are created:** In production, notification documents are written **server-side** by Cloud Functions (`createNotification` in `functions/index.js`) using the Admin SDK, which bypasses Firestore client rules. `NotificationService.dart` is the **client-side helper** — it mirrors the same idempotent creation logic for parity/future use and powers all read, unread-count, and read/delete operations in the apps. The client never writes notifications directly in the current flows.

### 2. Key Features
- **Duplicate Prevention (Idempotency):** Every business event generates a unique `eventId` (e.g., `ORDER_READY_order123`, `ORDER_NO_SHOW_order123`). The server-side `createNotification` (mirrored by the client `NotificationService` helper) queries for existing notifications with this event ID and skips creation if found, and each notification is written under a document ID deterministically derived from its `eventId`. Concurrent deliveries of the same event therefore target the same document, so at most one notification ever exists per event — notifications are written exactly once even under retries or overlapping invocations.
- **Decoupled Logic:** The notification layer only reacts to business events. It never drives, modifies, or blocks core business logic.
- **Future-Proof FCM Abstraction:** The delivery interface is fully abstracted within `NotificationService` so that Firebase Cloud Messaging (FCM) can be added in a future phase without modifying widgets or business service files.
- **Real-Time Streams:** The client apps subscribe only to documents where `recipientId == currentUser.uid` AND `recipientRole == "student" | "admin"` AND `deleted == false` ordered by `createdAt DESC` with a query limit of 50. This avoids collection scans.
- **Read & Delete Status:**
  - **Read Single:** Updates `read = true` and `readAt = serverTimestamp()`.
  - **Mark All Read:** Performs a batch write updating only currently unread notifications to avoid rewriting already-read documents.
  - **Soft Delete:** Sets `deleted = true` and `deletedAt = serverTimestamp()`. Soft-deleted notifications are immediately filtered out of app UI streams.
  - **Auto-Cleanup:** A scheduled Cloud Function (`cleanupDeletedNotifications`) runs once every 24 hours to permanently delete soft-deleted notifications older than 180 days.
- **Deep Linking:** Notifications include a `deepLink` string (e.g. `/orders/{orderId}`, `/account`, `/notifications`). Clicking a notification navigates the user directly to the target screen.

---

## Authentication & Hardening

CampusBite enforces strict rules on authentication and user accounts to ensure security and prevent abuse:
1. **Email Verification:** Unverified accounts are barred from ordering meals. Upon registration, users must verify their email. A dedicated `VerifyEmailScreen` manages re-sending verification links and checking verification status.
2. **Password Recovery:** Students and admins can securely reset forgotten passwords through the `ForgotPasswordScreen`, triggering a standard recovery flow via Firebase Auth.
3. **Role Enforcement:** Account types (`student` vs `admin`) are verified on both backend (Firestore security rules, Cloud Functions) and frontend.

---

## Your Favourites Section

CampusBite dynamically computes a student's top favorite food items to provide a personalized, frictionless ordering experience:
1. **Recalculation Engine:** The `FavoriteService` listens to the user's order history. Whenever a new order transitions to the `"COLLECTED"` state, the service recalculates the most frequently ordered items.
2. **Persistence & Caching:** The top 5 favorite food IDs are cached inside the student's Firestore user document (`favouriteFoodIds`) to minimize database queries.
3. **Live Stream Integration:** The app builds a combined stream that watches the cached ID array and dynamically streams the corresponding `FoodItem` records, including real-time availability and pricing updates.
4. **UI Presentation:** A dedicated `"Your Favourites"` horizontal feed is rendered on the home screen if any favourites exist. Tapping "See All" navigates to the `YourFavouritesScreen` where the full list is displayed vertically.

---

## Review & Moderation System

To ensure genuine feedback and maintain quality standards, CampusBite features a structured review and rating system:
1. **Eligibility Check:** Only students who have successfully ordered and collected a meal can write a review for that food item, preventing review spam and fake ratings.
2. **Review Integrity:** Students can only edit or delete their own reviews. They cannot modify review data or ratings written by others.
3. **One Review Per Meal:** A student has at most one live review per food item. Once a meal is reviewed, the app always offers "Edit Review" (never "Write a Review") and `ReviewService.createReview` refuses to create a second live review for the same meal via a different order, so `reviewCount` and the rating distribution can never be inflated by duplicates.
4. **Firestore Enforcement:** Rules explicitly prevent writing rating values outside the 1–5 range, or writing reviews for items the user has not collected.
5. **Cafeteria Quality Control:** The average rating of each item is dynamically visible to help cafeteria staff maintain standard dining options.

---

## In-App Update System & Cloudflare Workers Proxy

CampusBite includes a robust, production-grade in-app update framework to distribute updates securely:
1. **Cloudflare Worker Proxy (`dl.larason.space`):** A custom worker caches release metadata and APK binaries from GitHub. It intercepts GitHub API rate limits and proxies downloads, supporting HTTP range requests so interrupted downloads can resume.
2. **Update Metadata Verification:** The app periodically requests update data from `https://dl.larason.space/latest`.
3. **Secure Installation Workflow:**
   - **Update Check:** The `UpdateService` checks the current version against the edge metadata. If a new version exists, it prompts either an optional or mandatory update.
   - **Resume-able Downloads:** If interrupted, downloads are resumed from the last byte using HTTP Range requests.
   - **SHA-256 Checksum Validation:** Before launching the installer, the downloaded APK's SHA-256 hash is calculated and verified against the checksum provided in `release.json`. If verification fails, the installer is rejected.
   - **Local Cache TTL:** Metadata responses are cached locally on the device for 12 hours to minimize unnecessary network traffic.

---

## GitHub Release APK Workflow

The release compilation and deployment pipeline is automated via GitHub Actions (`.github/workflows/release-apk.yml`):
1. **Trigger:** The workflow is automatically triggered when a new version tag (`v*.*.*`) is pushed, or manually run via `workflow_dispatch`.
2. **Compilation & Obfuscation:** The runner compiles universal and split-per-abi APKs (for `arm64-v8a`, `armeabi-v7a`, and `x86_64`) using Dart obfuscation and split debug info.
3. **Keystore Signing:** Builds are signed using a secure base64-encoded keystore passed via GitHub Actions secrets.
4. **Artifact Checksums:** SHA-256 hashes are automatically generated for all built APK files.
5. **Metadata Assembly (`release.json`):** A `release.json` file is compiled from a template and validated by a Python validation script to ensure all asset URLs conform to proxy specifications.
6. **Publishing:** APKs, checksum files, and `release.json` are uploaded to the GitHub Release page, and the Cloudflare worker proxy is deployed automatically using Wrangler.

---

## Environment & Secrets

| Secret | Where | Purpose |
|---|---|---|
| `CLOUDINARY_CLOUD_NAME` | Cloud Functions secrets | Cloudinary account name |
| `CLOUDINARY_API_KEY` | Cloud Functions secrets | Cloudinary API key |
| `CLOUDINARY_API_SECRET` | Cloud Functions secrets | Cloudinary API secret |

The admin app also stores Cloudinary upload config in `lib/constants/app_config.dart` (for the unsigned upload preset — not a secret).

> although we commited and it is safe to do that but **Never commit** `google-services.json`, `firebase_options.dart` with real keys, or `.env` files to public repos. Add them to `.gitignore`.

---

## Running Tests

```bash
# Run all tests
flutter test

# Run a specific test file
flutter test test/search_helper_test.dart

# Run with verbose output
flutter test --reporter expanded

# Run static analysis
flutter analyze
```

---

## Contributing

* Push access are restricted to maintainers only

### Branch Workflow

```bash
# Create a feature branch
git checkout -b feature/my-new-feature

# Make your changes, commit frequently
git add .
git commit -m "Add descriptive commit message explaining what changed and why"

# When ready to merge
git checkout main
git pull origin main
git merge feature/my-new-feature
```

### Guidelines

1. **Always run `flutter pub get`** after pulling changes
2. **Write descriptive commit messages** — even if they're long
3. **Add comments** when writing new features
4. **Create a branch** for new features to avoid merge conflicts
5. **Run `flutter analyze`** before committing — no warnings allowed
6. **Run `flutter test`** to make sure nothing is broken
7. **Don't break existing features** — verify navigation and build after changes

### Code Style

- Follow the project structure: `screens/`, `widgets/`, `services/`, `models/`, `data/`, `navigation/`
- Keep widgets focused and reusable
- Use Firestore streams (not polling) for real-time data
- Never calculate timestamps in Flutter — the backend is the source of truth for deadlines

---

## AI Agent Usage

This project includes an `AGENTS.md` file that defines strict rules for AI coding assistants. When using AI tools:

- **Always** instruct the AI to follow `AGENTS.md` rules
- The file defines the current development phase, architecture constraints, and what must/must not be implemented
- AI agents must not rewrite working code, introduce unnecessary complexity, or implement features outside the active phase

---

## Troubleshooting

| Issue | Solution |
|---|---|
| `firebase_core` initialization fails | Ensure `google-services.json` is in `android/app/` and `firebase_options.dart` exists |
| Firestore permission denied | Check security rules match the schema above, and the user document has the correct `role` |
| Search returns no results | Re-save food items through the admin app to generate `searchPrefixes` |
| Cloud Function not triggering | Verify functions are deployed: `npx firebase-tools functions:list` |
| Countdown timer shows wrong time | Ensure device clock is roughly accurate; the countdown uses `pickupDeadline - DateTime.now()` |
| Build fails after `git pull` | Run `flutter pub get` and `flutter clean` |
| Emulator not connecting to Firestore | Check internet connection and Firebase project configuration |

---

# License

This project is licensed under the Apache 2.0 License terms specified in the [LICENSE](LICENSE) and [NOTICE](NOTICE) files.

# Credits

To all maintainers and contributors of this app. We hope this gives an idea of the working behind the Campus Bite student app.
