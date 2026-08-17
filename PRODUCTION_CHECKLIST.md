# CampusBite — Production Release Checklist

Release: **v** ___ | Build number: ___ | Date: ___

Each gate must be verified before the release candidate is promoted.

## Automated validation

- [ ] `flutter analyze` — 0 issues (customerview)
- [ ] `flutter analyze` — 0 issues (adminview)
- [ ] `flutter test` — 453/453 pass (customerview)
- [ ] `flutter test` — 81/81 pass (adminview)
- [ ] Emulator suites (functions): no-show 18, cancellation 31, reliability 39,
      phase-e 21, cafe-scoping 35, excuse 23, disposition 30 — all pass
- [ ] `node --check functions/index.js` clean
- [ ] `dart format` applied to changed Dart files
- [ ] No secrets in source / git history / CI logs (verified by scan)

## Firestore

- [ ] `firestore.rules` reviewed — no `allow read, write: if true`
- [ ] Rules deployed to staging (if available) and tested
- [ ] Rules diff reviewed and approved
- [ ] Rules deployed to production
- [ ] All 16 composite indexes deployed
- [ ] No collection scans in client queries (indexed + bounded)

## Cloud Functions

- [ ] All required secrets exist in Secret Manager (`CLOUDINARY_CLOUD_NAME`,
      `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`)
- [ ] Runtime (nodejs22) supported; functions compile
- [ ] Functions deployed (callables App Check-enforced)
- [ ] Scheduled functions deployed: `processExpiredPickups` (1 min),
      `cleanupDeletedNotifications`, `cleanupInactiveTokens`,
      `migrateLegacyOrderFoodIds`, `migrateLegacyOrderCafes`,
      `auditReviewCreationRate`
- [ ] No test functions remain active
- [ ] Retries configured appropriately; idempotency markers verified

## Security

- [ ] App Check enabled for all callables
- [ ] Admin operations cafe-scoped (cross-cafe denied in emulator tests)
- [ ] Client cannot create orders, modify status/timestamps/reliability/
      restrictions/dispositions/audit logs (emulator-tested)
- [ ] Cloudinary deletion backend-only; client has no secret
- [ ] Crashlytics/Analytics/Performance carry no PII (log sanitize tested)

## Release pipeline

- [ ] Git tag semver-greater than every previously shipped `-dev` tag
- [ ] GitHub Release created: universal APK + arm64-v8a + armeabi-v7a + x86_64
- [ ] APKs signed (`apksigner verify` passes)
- [ ] `release.json` generated and validated against proxy allow-list
- [ ] SHA-256 checksums generated and verified
- [ ] Cloudflare Worker (`dl.larason.space`) deployed and serving `/latest`
- [ ] In-app update flow verified: check → download → checksum → install
- [ ] Rollback plan documented and rehearsed (DEPLOYMENT.md)

## Manual smoke testing

- [ ] Student journey: register → verify email → login → browse → search →
      add to cart → place order → cancellation window → collect
- [ ] Pickup flow: READY → countdown → grace period → collect (or NO_SHOW)
- [ ] Reliability: score/status visible; restriction enforced by backend
- [ ] Admin journey: login → menu management → receive order → accept →
      preparing → ready → collected → excuse no-show → food disposition →
      audit trail
- [ ] Notifications: foreground, background, terminated; no duplicates
- [ ] Offline: cached menu/orders; queue syncs on reconnect; limits not bypassed
- [ ] No layout overflow, dialogs/snackbars work, accessibility basics pass

## Post-release

- [ ] Release notes published
- [ ] Monitoring dashboards (Crashlytics/Performance) confirm healthy baseline
- [ ] Any residual MEDIUM/LOW findings logged as technical debt in the report

Sign-off: ___ (release engineer)
