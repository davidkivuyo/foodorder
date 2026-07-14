# 🍔 CampusBite — Student Food Ordering App

A Flutter mobile application that lets university students browse the campus cafeteria menu, place food orders in advance, and skip the queue. Built with **Flutter** and **Firebase**.

> **This repository** (`foodorder`) contains the **Student App**. There is the admin companion app which will not be published.

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
- [Search System](#search-system)
- [Order Lifecycle](#order-lifecycle)
- [Student Discipline System](#student-discipline-system)
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
| No accountability for no-shows | Automated strike system for missed pickups |

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
7. If student doesn't collect → strike recorded

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

#### f) Create the First Admin User
1. this is created in the admin app but consider doing manually in firestore database.

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
│   │   ├── cart_item.dart         #   CartItem model
│   │   ├── strike_model.dart      #   Strike model for discipline system
│   │   └── audit_log.dart         #   Audit log model
│   │
│   ├── services/                  # Business logic & Firebase interactions
│   │   ├── auth_service.dart      #   Email/password auth (register, login, logout)
│   │   ├── cart_service.dart      #   Cart management (add, remove, Firestore sync)
│   │   ├── search_service.dart    #   Firestore search with in-memory caching
│   │   ├── search_helper.dart     #   Generates searchable fields (prefixes, keywords)
│   │   ├── pickup_deadline_service.dart  # Format deadline timestamps for UI
│   │   └── strike_service.dart    #   Student discipline/strike tracking
│   │
│   ├── screens/                   # Full-page screens
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
│   │   ├── strike_status_card.dart#   Displays student's strike status
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

## Project Structure — Admin App(just to give an overview)- (ADMIN APP IS NOT PUBLISHED)

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

Located in `adminview/functions/index.js`. Two functions are deployed: (NOTE: ADMINVIEW IS NOT PUBLISHED)

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

### Deploying Functions

Write your firebase.rules and deploy them. It is added in .gitignore by default so consider that.

```bash
npx firebase-tools deploy --only functions
```

To set Cloudinary secrets:

```bash
firebase functions:secrets:set CLOUDINARY_CLOUD_NAME
firebase functions:secrets:set CLOUDINARY_API_KEY
firebase functions:secrets:set CLOUDINARY_API_SECRET
```

---

## Firestore Data Schema

### `food_items/{docId}`

| Field | Type | Description |
|---|---|---|
| `title` | string | Food item name |
| `titleLower` | string | Lowercase title (for search) |
| `subtitle` | string | Short description |
| `description` | string | Full description |
| `image` | string | Cloudinary image URL |
| `price` | number | Price in TZS |
| `rating` | number | Average rating (default 4.5) |
| `category` | string | e.g. "Breakfast", "Lunch" |
| `availableCafes` | array\<string\> | Cafes serving this item |
| `section` | string | e.g. "campus_favourite" |
| `time` | string | Preparation time |
| `available` | boolean | Currently available for ordering |
| `featured` | boolean | Show on home screen |
| `quantity` | number | Stock quantity |
| `dietaryTags` | array\<string\> | e.g. ["Spicy", "Vegan"] |
| `keywords` | array\<string\> | Search keywords (auto-generated) |
| `searchPrefixes` | array\<string\> | Prefix substrings (auto-generated) |
| `createdAt` | timestamp | Creation date |
| `updatedAt` | timestamp | Last update |

### `orders/{docId}`

| Field | Type | Description |
|---|---|---|
| `userId` | string | Student's UID |
| `items` | array | List of ordered items (JSON) |
| `totalPrice` | number | Order total in TZS |
| `status` | string | `pending` → `accepted` → `preparing` → `ready` → `collected` |
| `cafe` | string | Selected cafe |
| `createdAt` | timestamp | When the order was placed |
| `readyAt` | timestamp | Set by Cloud Function when status → ready |
| `pickupDeadline` | timestamp | readyAt + 20 minutes (set by Cloud Function) |
| `pickupWindowMinutes` | number | 20 (set by Cloud Function) |
| `deadlineStatus` | string | `NOT_READY`, `ACTIVE`, `COLLECTED`, `EXPIRED` |
| `updatedAt` | timestamp | Last update |

### `users/{userId}`

| Field | Type | Description |
|---|---|---|
| `fullName` | string | Student's full name |
| `email` | string | Email address |
| `role` | string | the role |
| `strikeCount` | number | Current discipline strikes |
| `isSuspended` | boolean | Whether the student is suspended |
| `createdAt` | timestamp | Registration date |

### `users/{userId}/cart/{itemId}` (subcollection)

| Field | Type | Description |
|---|---|---|
| `foodItemId` | string | Reference to food_items doc |
| `quantity` | number | Number of this item in cart |
| `cafe` | string | Selected cafe |

### Other Collections

- **`categories`** — `{ name, order }`
- **`cafes`** — `{ name, location }`
- **`section`** — `{ name }`
- **`reviews`** — `{ userId, text, rating, ... }`
- **`notifications`** — `{ userId, title, body, ... }`
- **`audit_logs`** — `{ action, userId, timestamp, ... }`

---

## Firestore Security Rules

Read and write your own firestore rules. follow best practices in the official documentations.

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
| 4 | Account | `AccountScreen` — profile, strikes, settings, logout |

---

## Key Features

### For Students
- **Registration & Login** — Email/password via Firebase Auth
- **Browse Menu** — Real-time Firestore stream of available food items
- **Categories** — Filter by Breakfast, Lunch, Dinner, Teasers, Drinks
- **Search** — Prefix-based Firestore search with 300ms debounce and in-memory caching
- **Cart** — Add items, select cafe, view cart, checkout
- **Orders** — Track order status in real-time with countdown timers
- **Account** — View profile, strike status, notifications, help & support

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

## location based calculation

0–250 metres

10 minutes

250–600 metres

15 minutes

600–1200 metres

20 minutes

Above 1200 metres

25 minutes

----

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
        └── Deadline expires ──→ NO_SHOW (deadlineStatus = EXPIRED)
                                  └──→ Strike issued to student
```

---

## Student Discipline System

- Students who fail to collect orders receive **strikes**
- Strike data is stored on the user document (`strikeCount`, `isSuspended`)
- The `StrikeService` manages strike issuance and suspension logic
- Suspended students cannot place new orders
- Admins can view and manage strikes via the `IntegrityScreen` in the admin app

---

## Environment & Secrets

| Secret | Where | Purpose |
|---|---|---|
| `CLOUDINARY_CLOUD_NAME` | Cloud Functions secrets | Cloudinary account name |
| `CLOUDINARY_API_KEY` | Cloud Functions secrets | Cloudinary API key |
| `CLOUDINARY_API_SECRET` | Cloud Functions secrets | Cloudinary API secret |

The admin app also stores Cloudinary upload config in `lib/constants/app_config.dart` (for the unsigned upload preset — not a secret).

> **Never commit** `google-services.json`, `firebase_options.dart` with real keys, or `.env` files to public repos. Add them to `.gitignore`.

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

## Contributing (contributions are restricted to maintainers only)

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
