# CampusBite — Architecture Overview

> Phase I (final production-hardening) reference. Deep dives live in
> [`DOCUMENTATION.md`](DOCUMENTATION.md); this file is the system map.

## System at a glance

CampusBite is a two-app food-ordering platform for university campuses with a
shared Firebase backend.

```
┌──────────────────┐      ┌──────────────────┐
│  Student app     │      │  Admin app       │
│  (customerview)  │      │  (adminview)     │
│  Flutter + FCM   │      │  Flutter + FCM   │
└────────┬─────────┘      └────────┬─────────┘
         │                         │
         ▼                         ▼
┌───────────────────────────────────────────────┐
│                 Firebase (foodorder-8ffcf)     │
│  • Authentication (email/password, App Check) │
│  • Cloud Firestore (rules + indexes)          │
│  • Cloud Functions (Node 22)                  │
│  • Cloud Messaging (FCM)                      │
│  • Crashlytics / Analytics / Performance      │
└───────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────┐   ┌──────────────────────┐
│ Cloudinary (food images)│   │ Cloudflare Worker    │
└─────────────────────────┘   │ dl.larason.space     │
                              │ (update proxy)       │
                              └──────────────────────┘
```

- **Student app** — browse menu, search, cart, order placement, 2-minute
  cancellation, pickup countdown + grace period, collection, no-show display,
  pickup reliability, graduated restrictions, recovery, reviews, favourites,
  notifications, in-app updates.
- **Admin app** — menu/Cloudinary management, order management (accept →
  preparing → ready → collected), student reliability visibility, no-show
  excusal, food disposition, notifications, audit logs. Not published to stores.
- **Backend** — server-authoritative order lifecycle. Deadlines, cancellation
  windows, no-show transitions, reliability, restrictions, excusal and
  disposition are all computed and enforced in Cloud Functions and Firestore
  rules, never trusted from the client.

## Key architectural principles

1. **Server-authoritative state.** The client never writes `status`,
   `pickupDeadline`, `noShowAt`, `collectedAt`, `expiredAt`, reliability
   summaries, restriction levels, or audit records. Rules reject these
   client-side; Cloud Functions own them.
2. **One cafe per order.** Orders are created through the `placeOrder` callable,
   which enforces the active-order limit and the single-cafe constraint; the
   derived `cafes` array scopes admin visibility and notifications per cafe.
3. **Transactional boundaries.** Multi-document invariants (excuse, disposition,
   reactivation, reliability events) commit in single Firestore transactions;
   FCM delivery is post-commit and idempotent via `eventId`-keyed outbox
   records.
4. **Idempotent processing.** Triggers and scheduled jobs guard on persisted
   markers (`readyAt`, `reliabilityProcessed`, `noShowProcessed`, `eventId`) so
   retries and duplicate events never double-count.
5. **Privacy-first logging.** All log output passes through
   `LoggerService.sanitize` (emails, UIDs, tokens, phones, coordinates, and
   `users/<id>` paths are redacted); audit records are the only place admin UIDs
   are permitted, and they are backend-only.

## Code layout

```
lib/
├── data/          # static menu data, seeds
├── models/        # FoodOrder, FoodItem, PickupReliabilitySummary, UpdateInfo…
├── repositories/  # Firestore repositories (orders, reviews, favourites…)
├── screens/       # Home, Categories, Search, Orders, Account, FoodDetails…
├── services/      # cart, order placement/cancellation, pickup window,
│                  # reliability, update, auth, connectivity, sync queue…
├── viewmodels/    # OrdersViewModel and friends
├── widgets/       # countdown, restriction notice, reliability card…
└── navigation/    # go_router routes + bottom navigation (Home, Categories,
                   # Search, Orders, Account)
functions/index.js # all Cloud Functions (single deployment unit)
firestore.rules    # security rules
firestore.indexes.json  # 16 composite indexes
cloudflare-worker/ # update proxy (dl.larason.space)
```

## Cloud Functions

| Export | Type | Purpose |
|---|---|---|
| `onNewOrder` | trigger | Authoritative `createdAt`/`cancellationDeadline`, food ID/pricing normalization, cafe derivation, admin notifications |
| `onOrderStatusChanged` | trigger | READY → `readyAt` + `pickupDeadline`; terminal-state timestamps; reliability event processing |
| `onNewNotification` | trigger | Post-commit FCM delivery (eventId-deduped) |
| `processExpiredPickups` | scheduled (1 min) | READY → NO_SHOW after deadline + grace; reminders; reconciliation of deferred reliability events |
| `placeOrder` | callable | Server-authoritative order creation: auth, active-order limit, one-cafe constraint, availability |
| `cancelOrder` | callable | 2-minute-window cancellation with `cancellationDeadline` fallback |
| `extendPickupDeadline` | callable | One-tap +10 min extension, once per order |
| `excuseNoShow` | callable | Admin no-show excusal + reliability correction (transactional) |
| `setFoodDisposition` | callable | Admin food-outcome recording for NO_SHOW orders (transactional) |
| `reactivateStudent` | callable | Admin reactivation of suspended accounts |
| `createAdminAccount` | callable | Admin provisioning (auth + profile + audit) |
| `deleteCloudinaryImage` | callable | Server-side Cloudinary deletion (secrets in Secret Manager) |
| `onReviewChanged` | trigger | Rating aggregation / moderation |
| `cleanupDeletedNotifications` / `cleanupInactiveTokens` | scheduled | Retention & token hygiene |
| `migrateLegacyOrderFoodIds` / `migrateLegacyOrderCafes` | scheduled | Backward-compatible backfills |
| `auditReviewCreationRate` | scheduled | Review-rate abuse monitoring |

## Update system

GitHub Actions builds signed APKs (universal + per-ABI) on `v*` tags, emits
`release.json` + SHA-256 checksums, publishes a GitHub Release, and deploys the
Cloudflare Worker. The app checks `https://dl.larason.space/latest`, validates
semver, verifies the APK SHA-256 before install, and supports resumable
downloads. See [`DEPLOYMENT.md`](DEPLOYMENT.md) and
[`DOCUMENTATION.md`](DOCUMENTATION.md) § In-App Update System.
