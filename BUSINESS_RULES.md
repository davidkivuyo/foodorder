# CampusBite — Business Rules

The authoritative behavior of the order lifecycle, pickup reliability,
graduated restrictions, excusal and food disposition. Deep dives:
[`DOCUMENTATION.md`](DOCUMENTATION.md) § Order Lifecycle / Pickup Reliability
Engine.

## Order lifecycle

```
PLACED ──(≤2 min, student)──▶ CANCELLED
   │
   ▼
ACCEPTED → PREPARING → READY ──▶ COLLECTED
                          │
                          ▼
              pickupDeadline + 10 min grace
                          │
                          ▼
                       NO_SHOW ──▶ (admin) EXCUSED / disposition recorded
```

- **Order placement** (`placeOrder` callable): authenticated student, verified
  email, ACTIVE account, one cafe per order, availability, and the active-order
  limit (below) are enforced server-side.
- **Cancellation** (`cancelOrder` callable): only within the 2-minute window
  ending at the authoritative `cancellationDeadline` (= `createdAt` + 2 min,
  set by `onNewOrder`). If the trigger's deadline has not landed yet, the
  callable falls back to `createdAt` + 2 min so a brand-new order is still
  cancellable. Once the window passes, cancellation is permanently denied —
  never trust the device clock.
- **READY** (`onOrderStatusChanged`): sets `readyAt`, `pickupWindowMinutes`
  (20), `pickupDeadline` = `readyAt` + 20 min, `deadlineStatus = ACTIVE`.
- **Grace period**: the order remains READY and collectable for 10 minutes
  past `pickupDeadline`; the cutoff (`noShowEligibleAt`) is a hard boundary —
  a delayed scheduler run never extends collection eligibility.
- **NO_SHOW** (`processExpiredPickups`, every 1 min): READY + deadline + grace
  passed → NO_SHOW with `noShowAt`, `deadlineStatus = EXPIRED`. Idempotent:
  re-runs make no further writes. A collection racing the cutoff wins only
  before the cutoff; COLLECTED + NO_SHOW is impossible.
- **One cafe per order**: every line item resolves to a single cafe; orders
  carry the derived `cafes` array which scopes admin access and notifications.

## Pickup reliability

Computed by the reliability engine (event-driven on terminal status) and
persisted in `users/{uid}.pickupReliability`:

- **Eligible** = terminal pickup outcomes (COLLECTED or NO_SHOW, non-cancelled,
  non-excused-from-failure). **Lifetime** counts cover all history; **recent**
  counts cover the latest 10 eligible terminal events.
- **Score** = 70% lifetime collection rate + 30% recent collection rate,
  rounded for storage/display. New users (0 eligible) get `NEW`; 1–2 eligible
  orders get `INSUFFICIENT_HISTORY`; otherwise a 0–100 score.
- **Restrictions** (Phase E): score 50–100 → `NORMAL` (no limit), 25–49 →
  `LIMITED` (max 2 active orders), 0–24 → `HIGHLY_LIMITED` (max 1 active
  order). The minimum-history rule is respected — no restriction before 3
  eligible orders.
- **Recovery** (Phase F): only the existing engine moves a student back up —
  on-time collections raise the score and relax the limit; there are no bonus
  recovery points.
- **Excused no-shows** (Phase G) are excluded from failure counts; the summary
  and restriction recompute atomically with the excuse. If the student's user
  document is absent at excuse time, a `reliabilityExcusePending`
  reconciliation marker is committed in the same transaction and the scheduled
  processor applies the correction once the user document exists (giving up
  explicitly and audibly after the retry window) — an excuse is never committed
  with a silently skipped reliability update.
- **Food disposition** (Phase H) never affects reliability — it is an
  operational record only.

## Admin intervention

- **Excuse no-show**: any ACTIVE admin whose cafe serves the order may excuse a
  NO_SHOW order with `noShowAt`, once. Reason is a predefined enum (free-text
  only via Other), note ≤ 200 chars, no URLs/HTML. Commits order state +
  reliability correction + audit record + notification outbox event in one
  transaction. The reliability correction is guaranteed: if the student's user
  document is absent, the transaction persists a `reliabilityExcusePending`
  marker and the scheduled processor applies the correction once the document
  exists.
- **Food disposition**: ACTIVE, cafe-scoped admin records the outcome of a
  NO_SHOW order's prepared food — `UNRESOLVED | RESOLD | DISCOUNTED | DONATED |
  STAFF_USE | DISPOSED | OTHER`. The order stays NO_SHOW; corrections append a
  second audit record (no duplicate current-state record); re-submitting the
  same disposition is a no-op (`alreadyRecorded`).
- **Cross-cafe denial**: admins may only manage orders their cafe serves;
  suspended or non-admin callers are rejected everywhere.

## Notifications

Student: `ORDER_ACCEPTED`, `ORDER_PREPARING`, `ORDER_READY`,
`PICKUP_REMINDER`, `ORDER_NO_SHOW`, `ACCOUNT_REACTIVATED`. Admin: `NEW_ORDER`
(ACTIVE admins of the serving cafe only). No strike notifications exist. FCM is
delivered post-commit by `onNewNotification`, deduplicated by `eventId`.

## Reviews & favourites

- One live review per (student, food): a second review for the same meal is
  refused; the UI always offers "Edit Review" once reviewed. Eligibility
  requires a collected order containing the food. The (student, food)
  uniqueness is enforced transactionally at create via a
  `review_guards/{userId}:{foodId}` guard committed atomically with the
  review (the deterministic review doc ID remains per
  `(userId, orderId, foodId)`).
- Favourites are derived from collected order history (top 5 food IDs cached in
  the user document).

## Anti-fraud invariants

- No client-written statuses, timestamps, reliability, restrictions,
  dispositions or audit records (rules deny them).
- Active-order limits are enforced by the backend callable, not the UI.
- Review creation is rate-monitored (`auditReviewCreationRate`).
