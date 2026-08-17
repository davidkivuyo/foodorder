# CampusBite — Deployment & Release

## Environment

| Component | Version / value |
|---|---|
| Flutter | 3.44.6 (stable) |
| Dart | 3.12.2 |
| Gradle | 9.1.0 |
| Android Gradle Plugin | 9.0.1 |
| Kotlin | 2.3.20 |
| Java (build) | 17 (JDK 25 available for the emulator) |
| Node.js (local) | 24 (functions runtime: Node 22 / `nodejs22`) |
| Firebase project | `foodorder-8ffcf` |
| Cloudinary | configured via Secret Manager |
| Update proxy | `https://dl.larason.space` |

## Backend deployment

```bash
# Firestore rules + indexes
firebase deploy --only firestore:rules,firestore:indexes

# Cloud Functions (reads secrets from Secret Manager)
firebase deploy --only functions

# Everything (rules, indexes, functions)
firebase deploy
```

Before deploying functions, ensure secrets exist:

```bash
firebase functions:secrets:set CLOUDINARY_CLOUD_NAME
firebase functions:secrets:set CLOUDINARY_API_KEY
firebase functions:secrets:set CLOUDINARY_API_SECRET
```

Ordering guidance: deploy **rules** and **indexes** before functions so the new
callables are not blocked by stale permissions; deploy **readers before
writers** for schema changes (see rollback below).

## Release process (student app APK)

1. On the `main` branch, tag the release:
   - `git tag vX.Y.Z` (final) — e.g. `v1.9.0`
   - `git tag vX.Y.Z-rc.1` (pre-release) — publishes as a GitHub pre-release
   - **Versioning rule:** a production tag must be semver-greater than every
     `-dev` tag ever shipped, or existing installs will never see the update
     (e.g. shipping `v1.0.0` after `v1.8.0-dev` strands testers). Enforced
     automatically: the workflow's release-ordering gate rejects any tag that
     is not semver-greater than every previously published tag.
2. `git push origin vX.Y.Z` triggers `.github/workflows/release-apk.yml`:
   - Validates the tag as semver; derives `VERSION` and `IS_PRERELEASE`.
   - Builds `CampusBite-universal.apk` + per-ABI splits (`arm64-v8a`,
     `armeabi-v7a`, `x86_64`) with obfuscation, signed with
     `KEYSTORE_BASE64`/`KEYSTORE_PASSWORD` secrets.
   - Generates `release.json` from the template, validates all asset URLs
     against the `dl.larason.space` proxy allow-list, emits SHA-256 checksums.
   - Creates/updates the GitHub Release and deploys the Cloudflare Worker
     (`cloudflare-worker/`) via Wrangler.
3. Verify the release: checksums, signature, `release.json` on
   `https://dl.larason.space/release/<tag>` and `/latest`.

The admin app (`adminview/`) is not published to stores; it has its own
`release-apk.yml` and `sonar-analysis.yml` workflows. The student app also has
`deploy.yml`, which gates a Cloudflare Pages deployment on the
`no-show-integration` emulator suite (`needs:` dependency) so the web build is
never published ahead of the backend tests.

## Rollback plan

| Artifact | Procedure |
|---|---|
| Flutter release | Tag the previous version and push; in-app updater serves it (never lower than installed per semver — use a higher patch, e.g. revert with `vX.Y.(Z+1)`). |
| Cloud Functions | Redeploy the previous commit — `git checkout <last-good-tag>` then `firebase deploy --only functions` (for gen-2, redeploy the previous container image). |
| Firestore rules | Deploy the previous `firestore.rules` (rules are versioned in git). |
| Firestore indexes | Remove new index entries from `firestore.indexes.json` and deploy; queries using them fail closed rather than corrupting data. |
| Cloudflare Worker | `wrangler rollback` or redeploy the previous worker version. |
| Reliability / disposition changes | Backward-compatible fields only; no destructive migrations run automatically. |

## Smoke test after deploy

Run the final user journeys in [`PRODUCTION_CHECKLIST.md`](PRODUCTION_CHECKLIST.md):
place → cancel-window → accept → preparing → ready → countdown → collect; and
the no-show path → excuse → disposition → audit trail.
