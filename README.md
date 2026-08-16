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
- [Tech Stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [1. Clone the Repository](#1-clone-the-repository)
  - [2. Firebase Setup](#2-firebase-setup)
  - [3. Install Dependencies](#3-install-dependencies)
  - [4. Run the App](#4-run-the-app)
- [Firestore Security Rules](#firestore-security-rules)
- [App Navigation](#app-navigation)
- [Key Features](#key-features)
- [Order Lifecycle](#order-lifecycle)
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

## Distance-Based Pickup Deadline & Location-Based Calculations

To minimize food waste from abandoned orders while keeping pickup schedules fair for students, CampusBite calculates a dynamic pickup window based on the student's walking distance to the cafeteria at the moment they checkout:

---

## Meal Planning & Reordering System

CampusBite provides students with tools to plan meals in advance and quickly repeat past orders. These features improve convenience and decrease checkout friction, especially during busy campus hours.

---

## Pickup Extension & No-Show Handling

CampusBite keeps pickup schedules fair and prevents food waste by enforcing server-authoritative deadlines, giving students a one-time grace action, and notifying them when an order is missed.

---

## Production Notification Platform

CampusBite features a scalable, production-ready notification platform that decouples notification delivery from core business logic.

> **Where notifications are created:** In production, notification documents are written **server-side** by Cloud Functions (`createNotification` in `functions/index.js`) using the Admin SDK, which bypasses Firestore client rules. `NotificationService.dart` is the **client-side helper** — it mirrors the same idempotent creation logic for parity/future use and powers all read, unread-count, and read/delete operations in the apps. The client never writes notifications directly in the current flows.

---

## Environment & Secrets

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

More on [Project official Documentation](DOCUMENTATION.md)

---

# License

This project is licensed under the Apache 2.0 License terms specified in the [LICENSE](LICENSE) and [NOTICE](NOTICE) files.

# Credits

To all maintainers and contributors of this app. We hope this gives an idea of the working behind the Campus Bite student app.
