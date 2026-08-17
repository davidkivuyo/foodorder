# PROJECT Official documentation

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

----

## The Pickup Reliability Engine

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

### 3g. Cafe Food Waste Management (Phase H)
Phase H lets authorized cafe admins record what happened to the prepared food of NO_SHOW orders — separate from the order lifecycle and from reliability:
- **Core principle:** the order lifecycle answers "what happened to the order?" (NO_SHOW); the food disposition answers "what happened to the prepared food?" (e.g. DONATED). The order **remains NO_SHOW** and the student's reliability is **never** affected by disposition (AGENTS.md §1, §20-§21).
- **Controlled dispositions (§2):** `UNRESOLVED` (default), `RESOLD`, `DISCOUNTED`, `DONATED`, `STAFF_USE`, `DISPOSED`, `OTHER` — shared enum/constants on the backend and in the admin app, never free-form strings.
- **Default state (§3):** the no-show engine writes `foodDisposition: "UNRESOLVED"` when an order becomes NO_SHOW (both the scheduled expiry processor and the manual trigger path), so every NO_SHOW starts unresolved and is never auto-marked DISPOSED.
- **Backend (`setFoodDisposition` callable, §7, §17):** enforces authentication, the `admin` role, an `ACTIVE` account, and per-cafe authorization from the order's server-authoritative `cafes` list. Only NO_SHOW orders are eligible. The note is optional (≤ 200 chars, URLs/HTML rejected, trimmed). The order update + immutable `audit_logs` FOOD_DISPOSITION record (with `previousDisposition` / `newDisposition`, `orderId`, `studentId`, `cafeId`, `adminId`, `timestamp`, `note`) commit in **one transaction** (§15); a duplicate submission writes nothing (§16); corrections (DONATED → DISPOSED) update the order and append a second audit record (§12).
- **Security rules (§38):** `foodDisposition`/`foodDispositionAt`/`foodDispositionBy`/`foodDispositionNote` are added to `adminNotModifyingProtectedOrderFields()` — no student or admin client can write them directly; only the callable (Admin SDK) can. Audit records remain backend-only and cafe-scoped reads.
- **Admin UI (§9-§11, §34-§35):** NO_SHOW orders show a separate disposition badge (UNRESOLVED / DONATED / …) distinct from the NO-SHOW order badge. The **Record Food Outcome** (or **Change Food Outcome**) action opens a disposition sheet (Resold / Discounted / Donated / Staff Use / Disposed / Other, optional note), always followed by an explicit confirmation dialog that states the order remains No-show. Disposed is never the default.
- **Reports dashboard (§23-§25, §42):** a Food Disposition summary card counts the cafe's NO_SHOW orders by disposition with a disposition filter (All + each disposition) and a simple date-range filter (All / Today / This week / This month). The card is driven by a dedicated **indexed, paginated query** — `cafes` array-contains + `createdAt` DESC + a page limit (`OrderService.foodDispositionStreamForCafe`), served by the existing `cafes` CONTAINS + `createdAt` DESC composite index in `firestore.indexes.json` — never the unbounded full-order stream. Summary counts are therefore **limited to the loaded page** (the most recent 100 cafe orders, stated in the card UI); the date-range and disposition filters apply client-side over that loaded page, preserving the stated range behavior. No aggregate documents or additional indexes are required.
- **Student experience (§22, §36-§37):** unchanged — no disposition details, no new notifications or FCM types.

---

## Notifications System


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

### Key Features
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

##Meal-Planning-and-reordering

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

## Distance-Based Pickup Deadline & Location-Based Calculations

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

## Cloud functions

1. onOrderStatusChanged
**Trigger:** `onDocumentUpdated` on `orders/{orderId}`

When an order's status changes to `"ready"`, the function:
1. Checks idempotency — if `readyAt` already exists, returns immediately
2. Computes `readyAt` using the server timestamp
3. Sets `pickupWindowMinutes = 20`
4. Computes `pickupDeadline = readyAt + 20 minutes`
5. Sets `deadlineStatus = "ACTIVE"`
6. Writes all fields atomically

**The backend is the single source of truth.** Neither the student app nor the admin app calculates deadlines.

2. extendPickupDeadline

Student-facing callable that extends an order's pickup deadline by **10 minutes**. Enforced invariants (all inside a Firestore transaction):
- The caller must be authenticated (App Check enforced) and own the order.
- The order must still be `ready` with an `ACTIVE` deadline.
- The extension is consumable **once per order**.
- The current deadline must not have passed yet.

The customer app surfaces this as the one-tap **"Extend pickup by 10 min"** button on ready orders.

3. processExpiredPickups

Runs every 5 minutes and marks orders whose pickup deadline has passed as `no_show` (`deadlineStatus = "EXPIRED"`), then sends the student an `ORDER_NO_SHOW` notification. It also sends `PICKUP_REMINDER` notifications for orders nearing their deadline. **The automatic strike engine has been removed** — expired orders are never linked to strikes or auto-suspension here; strike management is exclusively an admin-app concern.

4. setFoodDisposition


Admin-only callable that records what happened to the prepared food of a NO_SHOW order. Enforced server-side:
- The caller must be an authenticated, **ACTIVE** admin whose `cafeName` is in the order's `cafes` list (cross-cafe denied), mirroring `excuseNoShow`.
- Only orders with `status == NO_SHOW` are eligible; `studentId` and `cafeId` are derived from the order, never accepted from the client.
- The disposition must be one of the controlled values — `RESOLD`, `DISCOUNTED`, `DONATED`, `STAFF_USE`, `DISPOSED`, `OTHER` (`UNRESOLVED` is the engine default and never an admin target). Optional note ≤ 200 chars, URLs/HTML rejected, whitespace trimmed.
- Atomically writes the compact order record (`foodDisposition`, `foodDispositionAt`, `foodDispositionBy`, `foodDispositionNote`) and an immutable `audit_logs` FOOD_DISPOSITION record (with `previousDisposition` / `newDisposition`) in **one Firestore transaction**.
- Idempotent: submitting the current disposition again returns `alreadyRecorded: true` with **no** write and **no** duplicate audit record; a correction (e.g. `DONATED → DISPOSED`) updates the order and appends a second audit record.
- The order **remains NO_SHOW** and the student's reliability is untouched — disposition is an operational record only.

`firestore.rules` grants **no** client create/update/delete on `audit_logs` — audit records are backend-only (AGENTS.md §23).

5. reactivateStudentAccount


Admin-only callable that reactivates a genuinely SUSPENDED student account:
- The caller must be an authenticated, **ACTIVE** admin.
- The target must exist and be exactly `accountStatus: "SUSPENDED"` (checked inside the transaction, atomic with the ACTIVE flip).
- The account-status flip and the immutable `audit_logs` REACTIVATE record commit in **one Firestore transaction**; actor identity (`adminId`) and `timestamp` are derived server-side from the authenticated caller.
- Creates exactly one `ACCOUNT_REACTIVATED` student notification after commit (eventId-deduped).

6. excuseNoShow

Admin-only callable that excuses a specific NO_SHOW order. Enforced server-side:
- The caller must be an authenticated, **ACTIVE** admin whose `cafeName` is in the order's `cafes` list (cross-cafe denied); a cafeless order (absent/empty `cafes`, or tagged `UNASSIGNED`) is excusable by any active admin.
- The order must be `NO_SHOW` with a recorded `noShowAt`, not already excused.
- The reason must be one of the predefined reasons; the note is optional, ≤ 200 chars, no URLs/HTML.
- Atomically marks the order `noShowExcused`, corrects the student's reliability summary (event excluded from failure counts, restriction recomputed), and writes an immutable `audit_logs/NO_SHOW_EXCUSED_{orderId}` record.
- Commits the order state, reliability correction, audit record, and the `NO_SHOW_EXCUSED_{orderId}` notification outbox event in one transaction; FCM push is delivered by the post-commit `onNewNotification` trigger (eventId-deduped).

7. deleteCloudinaryImage

Admin-only callable function that securely deletes food images from Cloudinary using server-side secrets. Logs all deletions to `audit_logs`.

----

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

----


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

---

## Cloud Functions

Located in `functions/index.js` (shared with the admin app). The full list with one-line purposes is in [ARCHITECTURE.md](ARCHITECTURE.md); the complete reference for the main callables and triggers:

- `onNewOrder` (trigger) — authoritative `createdAt`/`cancellationDeadline`, food ID/pricing normalization, cafe derivation, NEW_ORDER notifications
- `onOrderStatusChanged` (trigger) — READY deadline creation, terminal timestamps, reliability events
- `onNewNotification` (trigger) — post-commit FCM delivery (eventId-deduped)
- `processExpiredPickups` (scheduled — every 1 minute) — grace-period expiry, PICKUP_REMINDER/ORDER_NO_SHOW, deferred reliability reconciliation
- `placeOrder` (callable) — server-authoritative order creation with active-order limit and one-cafe constraint
- `cancelOrder` (callable) — 2-minute cancellation window
- `extendPickupDeadline` (callable) — one-tap +10 min extension
- `excuseNoShow` (callable — Phase G admin intervention)
- `setFoodDisposition` (callable — Phase H food waste management)
- `reactivateStudent` (callable — admin account action)
- `createAdminAccount` (callable — admin provisioning)
- `deleteCloudinaryImage` (callable — server-side Cloudinary deletion)
- `onReviewChanged` (trigger) — rating aggregation/moderation
- `cleanupDeletedNotifications` / `cleanupInactiveTokens` (scheduled) — retention & token hygiene
- `migrateLegacyOrderFoodIds` / `migrateLegacyOrderCafes` (scheduled) — backward-compatible backfills
- `auditReviewCreationRate` (scheduled) — review-rate abuse monitoring

### Deploying Functions

Write your firebase.rules and deploy them. It is added in .gitignore by default so consider that.

```bash
npx firebase-tools deploy --only functions
```

Cloudinary api:

Get the api keys on your cloudinary account or any other storage providers.

---

## Firestore Data Schema

## Seed Required Collections

Create these collections manually in the Firestore Console (or through the admin app):

| Collection | Required Documents |
|---|---|
| `categories` | `{ name: "Breakfast", order: 1 }`, `{ name: "Lunch", order: 2 }`, etc. |
| `cafes` | `{ name: "Main Cafeteria", location: "Building A" }` |
| `section` | `{ name: "campus_favourite" }` |

## Collections

- **`categories`** — `{ name, order }`
- **`food_items`** — `{ title, subtitle, description, image, price, rating, category, availableCafes, section, time, available, featured, quantity, dietaryTags, keywords, searchPrefixes, createdAt, updatedAt }`
- **`orders`** — `{ orderId, userId, userName, items, totalPrice, status, cafe, cafeId, cafes, cafeLocation, distanceMeters, distanceCalculated, pickupWindowMinutes, readyAt, pickupDeadline, deadlineStatus, noShowProcessed, noShowAt, noShowExcused, excusedAt, excusedBy, excuseReason, excuseNote, expiredAt, deadlineExtended, extensionAt, foodDisposition, foodDispositionAt, foodDispositionBy, foodDispositionNote, createdAt, updatedAt }`
- **`users`** — `{ fullName, email, role, accountStatus, createdAt, updatedAt, pickupReliability, favouriteFoodIds }` — reliability/restriction fields (`pickupReliability.*`) and `accountStatus` are server-owned; the legacy strike fields (`strikeCount`, `strikePercentage`) are no longer written
- **`users/{userId}/cart`** — `{ foodItemId, quantity, cafe }`
- **`users/{userId}/plans`** — `{ title, note, totalAmount, plannedDate, createdAt, items }`
- **`notifications`** — `{ recipientId, recipientRole, type, title, message, orderId, eventId, deepLink, metadata, read, readAt, deleted, deletedAt, createdAt, createdBy }`
- **`audit_logs`** — backend-only (no client create/update/delete). Records carry `{action, orderId, studentId, cafeId, adminId, timestamp}` plus action-specific fields: `NO_SHOW_EXCUSED` adds `{reason, note}`; `FOOD_DISPOSITION` adds `{previousDisposition, newDisposition, note}`; `REACTIVATE` and `CREATE_ADMIN` add student/actor fields; `cloudinary_image_deleted` records the public ID. Admin reads are scoped to the caller's cafe
- **`cafes`** — `{ name, location, geopoint }`
- **`section`** — `{ name }`
- **`reviews`** — `{ userId, text, rating, ... }`
