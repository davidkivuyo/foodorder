# CampusBite — Firestore Database

> Firestore project: `foodorder-8ffcf`. Rules: `firestore.rules`. Indexes:
> `firestore.indexes.json` (16 composite indexes). Client-visible schema is
> documented in [`DOCUMENTATION.md`](DOCUMENTATION.md) § Firestore Data Schema;
> this file describes the security model and server-owned fields.

## Collections

### `users/{uid}`
- Public identity: `fullName`, `email`, `role` (`student` | `admin`),
  `accountStatus` (`ACTIVE` | `SUSPENDED`), `createdAt`, `updatedAt`.
- Student favourites: `favouriteFoodIds` (≤ 5, server-validated list).
- **Server-owned** (client writes denied by rules):
  - `pickupReliability` — `{ eligibleOrders, collectedOrders, noShowOrders,
    collectionRate, recentEligibleOrders, recentCollectedOrders,
    recentNoShowOrders, recentCollectionRate, reliabilityScore,
    status (NEW | INSUFFICIENT_HISTORY | EXCELLENT | GOOD |
    NEEDS_IMPROVEMENT | POOR | CRITICAL), restrictionLevel (NORMAL | LIMITED |
    HIGHLY_LIMITED), recentPickupHistory[], reliabilityProcessed,
    reliabilityOutcome, updatedAt }`.
  - `accountStatus` — only admin callables (`reactivateStudent`) flip it.
- Legacy strike fields (`strikeCount`, `strikePercentage`) are no longer
  written; the reliability summary replaced them.

### `orders/{orderId}`
- Client-created via the `placeOrder` callable only — rules deny direct client
  `create`.
- **Server-owned fields** (client updates rejected): `status` transitions,
  `createdAt`, `cancellationDeadline` (createdAt + exactly 2 min),
  `readyAt`, `pickupDeadline`, `deadlineStatus`, `expiredAt`, `noShowAt`,
  `noShowProcessed`, `noShowExcused`, `excusedAt/By`, `excuseReason/Note`,
  `collectedAt`, `foodDisposition*`, `cafes` (derived from items),
  `foodIds`, normalized pricing.
- Admin updates are scoped per cafe: the caller's immutable `cafeName`
  (in `users/{uid}`) must match `cafes` membership (or the `UNASSIGNED`
  sentinel for cafeless orders).

### `users/{userId}/cart` (subcollection)
- One item per `(foodItemId, selectedCafe)`; the one-cafe-per-order constraint
  is enforced in the client sync layer and by `placeOrder` server-side. Lock
  marker `__cart_lock__` documents are validated by a dedicated rules path.

### Other collections
- `food_items` — public menu; availability/price changes by admins of the
  owning cafe.
- `categories`, `cafes`, `section` — public reference data.
- `notifications` — `{ recipientId, recipientRole, type, title, message,
  orderId, eventId, deepLink, metadata, read, readAt, deleted, deletedAt,
  createdAt, createdBy }`. `eventId` is the idempotency key; FCM push happens
  in the `onNewNotification` trigger.
- `reviews` — deterministic doc ID per `(userId, orderId, foodId)`; **one
  live review per `(userId, foodId)`** is enforced transactionally at create
  via the `review_guards` guard below — never a racy client-side query.
  Public reads for non-deleted reviews; author/admin access to deleted ones.
- `review_guards` — deterministic doc ID per `(userId, foodId)`; claimed
  atomically with the review (create/revive) and released on soft-delete, so
  a second live review for the same meal via a different order is impossible
  even under concurrency. Owner read/create/delete only; no client updates.
- `audit_logs` — **backend-only** (no client create/update/delete). Automatic
  engine writes are **system** actions with no admin identity:
  `automatic_no_show` `{ action, orderId, studentId, performedBy: "system",
  reason: "pickup_deadline_expired", timestamp }` (no `cafeId`/`adminId`).
  Admin-performed records carry the actor identity and cafe:
  `NO_SHOW_EXCUSED` `{ action, orderId, studentId, cafeId, adminId, reason,
  note, timestamp }`; `FOOD_DISPOSITION` `{ action, orderId, studentId,
  cafeId, adminId, previousDisposition, newDisposition, note, timestamp }`;
  `REACTIVATE`, `CREATE_ADMIN`, `cloudinary_image_deleted`. Admin reads are
  scoped to the caller's cafe (or an explicitly authorized role).
- `delivery_records` — legacy; deliberately locked `allow read, write: if
  false`.

## Server-owned write matrix (client → denied)

| Field | Student | Admin |
|---|---|---|
| `orders.status` transitions | denied | allowed only per cafe + valid transition |
| `orders` timestamps (ready/pickup/no-show/collected/expired) | denied | denied |
| `orders.cancellationDeadline` on create | denied (callable sets it) | n/a |
| `users.pickupReliability` | denied | denied |
| `users.accountStatus` | denied | denied (callable only) |
| `orders.foodDisposition*` | denied | denied (callable only) |
| `audit_logs` | denied | denied (callable only) |
| `reviews` | own only, valid rating, post-collection | moderation only |

## Composite indexes (firestore.indexes.json)

16 indexes cover: notifications per recipient/role/deleted with createdAt or
read ordering; menu availability; orders per student with status/updatedAt;
no-show processor query (status + deadlineStatus + pickupDeadline); cart
(foodItemId + selectedCafe); reviews (foodId + deleted + rating/createdAt,
foodId + userId); cafe-scoped orders (`cafes` CONTAINS + createdAt DESC);
audit_logs (action + orderId + timestamp, action + studentId).

## Offline behavior

The app uses Firestore default persistence with a local sync queue:
- Menu, orders, notifications and account data read from cache offline.
- Writes (cart ops) queue locally and replay on reconnect with conflict
  validation.
- Server-authoritative invariants (order limits, cancellation window, no-show
  cutoff, authorization) are never bypassed by offline state — the callables
  and rules re-validate on the server.
