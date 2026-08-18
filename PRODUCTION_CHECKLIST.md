# CampusBite — Production Release Checklist

Release: **v** 1.9.0 | Build number: 1.9.0 | Date: 18/08/2026

Each gate must be verified before the release candidate is promoted.

## Automated validation

- [x] `flutter analyze` — 0 issues (customerview)
- [x] `flutter analyze` — 0 issues (adminview)
- [x] `flutter test` — 453/453 pass (customerview)
- [x] `flutter test` — 81/81 pass (adminview)
- [x] Emulator suites (functions): no-show 18, cancellation 31, reliability 39,
  ```
  phase-e 21, cafe-scoping 35, excuse 23, disposition 30 — all pass
  ```
- [x] `node --check functions/index.js` clean
- [x] `dart format` applied to changed Dart files
- [x] No secrets in source / git history / CI logs (verified by scan)



## Firestore

- [x] `firestore.rules` reviewed — no `allow read, write: if true`
- [x] Rules deployed to staging (if available) and tested
- [x] Rules diff reviewed and approved
- [x] Rules deployed to production
- [x] All 16 composite indexes deployed
- [x] No collection scans in client queries (indexed + bounded)



## Cloud Functions

- [x] All required secrets exist in Secret Manager (`CLOUDINARY_CLOUD_NAME`,
  ```
  `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`)
  ```
- [x] Runtime (nodejs22) supported; functions compile
- [x] Functions deployed (callables App Check-enforced)
- [x] Scheduled functions deployed: `processExpiredPickups` (1 min),
  ```
  `cleanupDeletedNotifications`, `cleanupInactiveTokens`,
  `migrateLegacyOrderFoodIds`, `migrateLegacyOrderCafes`,
  `auditReviewCreationRate`
  ```
- [x] No test functions remain active
- [x] Retries configured appropriately; idempotency markers verified



## Security

- [x] App Check enabled for all callables
- [x] Admin operations cafe-scoped (cross-cafe denied in emulator tests)
- [x] Client cannot create orders, modify status/timestamps/reliability/
  ```
  restrictions/dispositions/audit logs (emulator-tested)
  ```
- [x] Cloudinary deletion backend-only; client has no secret
- [x] Crashlytics/Analytics/Performance carry no PII (log sanitize tested)



## Release pipeline

- [x] Git tag semver-greater than every previously shipped `-dev` tag
- [x] GitHub Release created: universal APK + arm64-v8a + armeabi-v7a + x86_64
- [x] APKs signed (`apksigner verify` passes)
- [x] `release.json` generated and validated against proxy allow-list
- [x] SHA-256 checksums generated and verified
- [x] Cloudflare Worker (`dl.larason.space`) deployed and serving `/latest`
- [x] In-app update flow verified: check → download → checksum → install
- [x] Rollback plan documented and rehearsed (DEPLOYMENT.md)



## Manual smoke testing

- [x] Student journey: register → verify email → login → browse → search →
  ```
  add to cart → place order → cancellation window → collect
  ```
- [x] Pickup flow: READY → countdown → grace period → collect (or NO_SHOW)
- [x] Reliability: score/status visible; restriction enforced by backend
- [x] Admin journey: login → menu management → receive order → accept →
  ```
  preparing → ready → collected → excuse no-show → food disposition →
  audit trail
  ```
- [x] Notifications: foreground, background, terminated; no duplicates
- [x] Offline: cached menu/orders; queue syncs on reconnect; limits not bypassed
- [x] No layout overflow, dialogs/snackbars work, accessibility basics pass



## Post-release

- [x] Release notes published
- [x] Monitoring dashboards (Crashlytics/Performance) confirm healthy baseline
- [x] Any residual MEDIUM/LOW findings logged as technical debt in the report

Sign-off: The Larason (maintainer)