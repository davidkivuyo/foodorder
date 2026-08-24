# CampusBite — Troubleshooting

## Student app

### "Cannot place order" / orders rejected after deployment
- **Rules blocking `orders` create** — since Phase E, client-side order
  creation is revoked; orders must go through the `placeOrder` callable. If
  deployments are split (functions before rules), students get
  `permission-denied`. Deploy rules **and** indexes first, then functions.
- **Active-order limit** — `LIMITED` students max 2 active orders,
  `HIGHLY_LIMITED` max 1. The limit is server-enforced; check the user's
  `pickupReliability.restrictionLevel` and active order count.
- **One cafe per order** — a cart mixing two cafes is rejected. Clear the cart
  and order per cafe.

### "Please sign in to extend your pickup"
- The extend action appears on READY orders with an ACTIVE deadline. If the
  countdown shows a grace-period state, the deadline has passed and the button
  should no longer render; a stale UI build (or a second device) can briefly
  show it. Pull the order list to refresh.

### Update not offered despite a new release
- The in-app updater is semver-aware: if the installed version is *newer* than
  the release metadata (e.g. `v1.8.0-dev` installed, `v1.0.0` tagged), no
  update is offered. Tag releases semver-greater than every previously shipped
  `-dev` tag (see DEPLOYMENT.md).
- Check `https://dl.larason.space/latest` returns `release.json` for the tag
  and that the worker cache TTL (12 h) has not masked a fresh tag.

### Download fails or stalls
- Downloads are resumable (HTTP Range via the worker). Retry; if a checksum
  mismatch is reported, the artifact is rejected for safety — re-download from
  the GitHub Release.

### Offline behavior
- Menu/orders/notifications come from cache; writes queue and sync on
  reconnect. Server-side invariants (limits, deadlines, auth) are not bypassed
  offline.

## Admin app

### Cannot see an order
- Admin visibility is **cafe-scoped**: the caller's `cafeName` (in
  `users/{uid}`) must be present in the order's `cafes` array. Verify the
  profile's `cafeName` matches the order. Cafeless/legacy orders without a
  `cafes` array are denied until backfilled (`migrateLegacyOrderCafes`).
- Only `accountStatus == "ACTIVE"` admins receive `NEW_ORDER` notifications.

### "Only authorized cafe administrators…" on excuse/disposition
- The caller is re-read inside the transaction: role must be `admin`,
  `accountStatus` exactly `ACTIVE`, and the cafe scope must match. Suspended or
  cross-cafe admins are rejected atomically.

## Backend

### Emulator integration tests fail to start
The Firestore emulator requires **Java 21+** — the project's declared JDK for
the integration suites (CI uses Temurin 21; see `.github/workflows/deploy.yml`
and the `// Run (requires Java 21+...)` header in each `functions/test/*.js`).
Point `JAVA_HOME` at any JDK 21+ install; the exact path is distro-specific
(e.g. `/usr/lib/jvm/java-21-openjdk` on Debian/Ubuntu, or
the `JAVA_HOME` of your JDK manager).
```bash
export JAVA_HOME=/path/to/a/jdk-21-or-newer
export PATH=$JAVA_HOME/bin:$PATH

# Validate BEFORE running the suites:
"$JAVA_HOME/bin/java" -version \
  || { echo "JAVA_HOME does not point to a valid JDK: $JAVA_HOME"; exit 1; }

cd functions
npm run test:<suite>:integration
```
Suites: `no-show`, `cancellation`, `reliability`, `phase-e`, `cafe-scoping`,
`excuse`, `disposition`.

### Function deploy fails with `adminSdkConfig` / `cloudresourcemanager` errors
- A transient Google API/network failure — retry after confirming
  `firebase login` and that the CLI can reach `firebase.googleapis.com`
  (proxy/firewall check: `curl -sS -o /dev/null -w '%{http_code}'
  https://firebase.googleapis.com/v1beta1/projects/foodorder-8ffcf/adminSdkConfig`).

### Composite index required in production
- The emulator does not enforce indexes, so a query that passes locally can
  fail in production with "requires an index". Add the index to
  `firestore.indexes.json` and deploy (`firebase deploy --only firestore:indexes`).
  Current audit_logs/orders/cafes/reviews composite queries are already covered.

## Monitoring

- **Crashlytics missing events** — confirm the debugger is not attached in
  release builds and Crashlytics was enabled at startup.
- **Log redaction too aggressive?** — `LoggerService.sanitize` redacts emails,
  UIDs, tokens, phones, coordinates and `users/<id>` paths; expected technical
  labels (single character class) are preserved. See `app_log_test.dart` for
  the exact contract.
