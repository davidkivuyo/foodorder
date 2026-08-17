# CampusBite — Security Model

## Authentication

- Firebase Authentication (email/password) with email verification required
  before ordering.
- Firebase App Check (`enforceAppCheck: true`) on all callable functions.
- Role enforcement (`student` vs `admin`) verified in rules and in every
  admin callable.

## Firestore rules model

All collections default to deny. Rules enforce:

- **Students**: may read/write their own `users/{uid}` profile (excluding
  server-owned fields), their own cart, their own orders, public menu/reference
  data, and non-deleted public reviews. They can never modify reliability,
  restrictions, order status/timestamps, dispositions, audit logs, or another
  user's data.
- **Admins**: per-cafe scope — the caller's immutable `cafeName` in
  `users/{uid}` must match the order's `cafes` (or `UNASSIGNED` sentinel for
  cafeless orders) before any order write; admins can never rewrite reliability
  or edit audit logs.
- **Server-only collections**: `audit_logs` has no client create/update/delete;
  `delivery_records` is fully locked.
- **Client-created orders**: direct `allow create` on `/orders` is revoked —
  orders are created exclusively through the `placeOrder` callable.
- No `allow read, write: if true` exists anywhere (verified by
  `no_show_foundation_test.dart` and the security-rule audits).

## Cloud Functions security

- Every admin callable re-reads the caller document inside its transaction and
  validates existence, `role == "admin"`, `accountStatus == "ACTIVE"`, and cafe
  scope atomically with the write (no TOCTOU window).
- Student callables validate ownership (e.g. `cancelOrder`, `extendPickupDeadline`
  only touch the caller's own order).
- Inputs are validated server-side: enums, length limits (notes ≤ 200),
  trimming, and rejection of URLs/HTML — client controls are never trusted.
- Idempotency markers (`reliabilityProcessed`, `eventId`, `readyAt`,
  `noShowProcessed`) prevent duplicate writes and double-counting on retries.
- Errors return safe codes (`permission-denied`, `invalid-argument`, …) — never
  stack traces or internal details.

## Secrets

- No secrets in source or git history. Firebase API keys in
  `firebase_options.dart` are public client identifiers (safe to ship).
- Cloudinary credentials (`CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`,
  `CLOUDINARY_API_SECRET`) live in Firebase Secret Manager and are read only
  inside the `deleteCloudinaryImage` function; the Flutter client never sees
  them.
- CI secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, Cloudflare tokens) live
  in GitHub Secrets and are never logged.

## Monitoring & privacy

- Crashlytics/Analytics/Performance carry no UIDs, emails, phones, tokens,
  review text or locations. Logs pass through `LoggerService.sanitize` before
  emission (verified by `app_log_test.dart` in both apps).
- The only permitted identifier in monitoring data is the admin UID inside
  immutable `audit_logs` records, which are backend-only and cafe-scoped for
  reads.

## Reporting a vulnerability

Report any vulnerability to [lembotor6@gmail.com](mailto:lembotor6@gmail.com). Do not open vulnerabilities in public issues.

Public issues can be opened publicly and should only be used for sanitized follow-up, Do not use issues to disclose live credentials or production data.
