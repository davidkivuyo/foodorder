# AGENTS.md

## Project Overview

Build a Flutter mobile application for university students to order food from the campus cafeteria.

The purpose of the application is to:

* Reduce cafeteria queues.
* Allow students to see available meals before arriving.
* Allow students to place food orders in advance.
* Help cafeteria staff manage orders efficiently.
* Minimize food waste caused by abandoned orders.

This application will eventually use Firebase for authentication and data storage, but Firebase must not be implemented until its phase is activated.

---

# Product Vision

The completed system may include:

Student Features

* Registration
* Login
* Browse daily menu
* Categories
* Place orders
* View order history
* Account management
* Reviews

Cafe Admin Features

* Registration
* Login
* Add food items
* Edit food items
* Remove food items
* Manage orders
* Mark orders as collected

Order Management

* Order status tracking
* Collection confirmation
* Prevention of abandoned orders

Backend

* Firebase Authentication
* Cloud Firestore
* Firebase Storage
* firebase notifications

These features are future phases and must not be implemented unless activated.

---

# Application Navigation

Bottom Navigation Bar must contain:

1. Home
2. Categories
3. Search
3. Orders
4. Account

This navigation structure should remain consistent throughout development.

---

# Agent Development Rules

## Rule 1

Implement only the active phase.

Do not implement future phases.

All changes made are must be **production ready** hence solve any security and performance issues arise during development.

---

## Rule 2

Before writing code, answer:

1. Current phase?
2. Requirement being implemented?
3. Files being modified?
4. Possible regressions?

Then proceed.

---

## Rule 3

Use simple Flutter architecture.

Preferred structure:

lib/
├── data/
├── screens/
├── widgets/
├── models/
├── services/
├── navigation/
├── repositories/

Avoid unnecessary complexity.

Do not introduce advanced architecture unless requested.

---

## Rule 4

Preserve working functionality.

Never rewrite entire screens when small modifications are sufficient.

---

## Rule 5

After completing a feature:

* Verify build succeeds.
* Verify navigation works.
* Verify all features still work.

---

# Rule 6

Limit the amount of comments you put in the code to a strict minimum. You should almost never add comments, except sometimes on non-trivial code, function definitions if the arguments aren't self-explanatory, and class definitions and their members.
Do not remove existing comments unless they are directly related to what you are changing.

---

# Current Phase

# PHASE 16

# TASK

Implement semver-aware version comparison in the CampusBite update system, replacing any implicit/string-based comparison, without regressing the update path that has already been manually verified to work (`v1.0.0-dev → v1.1.0-dev`).

This is a **refactor of comparison logic only**. It must not change the Worker's routing, caching, metadata contract, or the download/verify/install pipeline.

---

# CONTEXT — READ BEFORE STARTING

The update system currently in place:

- Worker (`cloudflare-worker/src/index.js`) resolves `/latest`, `/release/{tag}`, and asset routes, rewrites GitHub URLs to `dl.larason.space`, and validates no disallowed host leaks through.
- Flutter client fetches metadata, selects ABI, downloads, verifies SHA-256, and installs.
- `release.json` (built from `.github/release-template.json`) contains `version` and `minimumVersion` as **plain strings**, e.g. `"1.0.0-dev"`.
- A manual test has already confirmed `v1.0.0-dev → v1.1.0-dev` correctly triggers an update prompt. **Do not assume this means comparison logic is already correct** — MAJOR/MINOR differing (`1.0.0` vs `1.1.0`) is the case where naive string comparison and semver comparison happen to agree. This is exactly the kind of case that hides bugs; do not use it as evidence the current logic is safe for other inputs (e.g. `1.0.9-dev` vs `1.0.10-dev`, or same-version different-channel comparisons).

## Known gap this task closes

There is currently no dedicated version-comparison module. Comparison logic (if present at all) is either inline and string-based, or does not exist yet and must be added. Locate whatever currently decides "is this an update" before writing anything new — do not assume a blank slate without checking.

---

# OBJECTIVE

Introduce a single, tested `VersionComparator` module that:

1. Correctly implements semver precedence rules (numeric core comparison, pre-release identifier comparison, numeric-vs-alphanumeric identifier rules, bare-release-beats-prerelease rule).
2. Is a **drop-in replacement** for whatever currently decides update eligibility — same inputs available (`localVersion`, `remoteVersion`, `minimumVersion`), same decision outputs (`upToDate` / `optional` / `mandatory`).
3. Does not change `release.json`'s schema, the Worker, the download flow, or the verification flow.

---

# NON-GOALS — DO NOT DO THESE

- Do not modify `cloudflare-worker/src/index.js`.
- Do not modify `.github/workflows/release-apk.yml`.
- Do not change the `release.json` / `release-template.json` schema (no new required fields). If you believe a `channel` field is needed for a *future* task, note it in your deliverables as a recommendation — do not implement it now.
- Do not change tagging conventions currently in use in CI.
- Do not touch download, ABI-selection, checksum verification, or install code paths except where they call into the comparison logic.
- Do not remove or rewrite the existing manual test that passed (`v1.0.0-dev → v1.1.0-dev`) — it must remain part of the suite and must still pass after your change.

---

# IMPLEMENTATION REQUIREMENTS

## 1. Dependency

Add `pub_semver` to `pubspec.yaml`. Do not hand-roll a semver parser — use the maintained package.

## 2. New file: `lib/services/version_comparator.dart`

Must expose, at minimum:

```dart
class VersionComparator {
  static bool isNewer({required String local, required String remote});
  static bool isBelowMinimum({required String local, required String minimum});
}
```

Requirements:
- Strip a leading `v` from any input before parsing (tags are `v1.0.0-dev`; semver parsing expects `1.0.0-dev`).
- Throw a clear, typed exception (e.g. `VersionParseException`) on malformed input — do not silently fall back to string comparison or treat unparseable input as "no update." A parse failure must be treated as **fail-safe-neutral**: the calling code should treat it the same as an update-check network failure (continue on current version, log in debug only, do not crash, do not block the user).
- No other behavior. This module does semver comparison only — it must not know about channels, force-update flags, or UI state.

## 3. Locate and refactor the existing decision point

Before writing new decision logic:
- Search the codebase for wherever `minimumVersion`, `forceUpdate`, or version strings are currently compared (likely in `lib/services/update_service.dart` or equivalent).
- Replace only the comparison calls with `VersionComparator`. Do not restructure surrounding logic (state emission, UI triggers, download triggering) unless the comparison change requires it.
- If comparison logic does not exist yet (i.e. the update-eligibility decision was never actually implemented and the "working" test passed only on other grounds — e.g. a hardcoded flag, or `version != remote.version`), stop and report this in your deliverables rather than guessing at what was intended. Do not paper over an undiscovered gap.

## 4. Backward compatibility check

Before finalizing, verify with actual parsed comparisons (not assumptions) that these all still produce the same *decision* as before your change:
- `1.0.0-dev` (local) vs `1.1.0-dev` (remote) → still "update available" (the already-verified case)
- Any other version pairs currently covered by existing tests

If any previously-passing case would now produce a different result, stop and flag it — do not silently "fix" it as part of this task without calling it out explicitly in deliverables, since it may indicate the old behavior was relied upon elsewhere.

---

# EDGE CASES TO HANDLE EXPLICITLY

Write a test for each of these (see Testing section):

| Local | Remote | Expected | Reason |
|---|---|---|---|
| `1.0.0-dev` | `1.1.0-dev` | update | MINOR differs (the known-working case) |
| `1.0.9-dev` | `1.0.10-dev` | update | numeric identifier comparison, not string comparison |
| `1.0.10-dev` | `1.0.9-dev` | no update | same as above, reversed |
| `1.0.0-dev` | `1.0.0` | update | bare release beats pre-release at same core version |
| `1.0.0` | `1.0.0-dev` | no update | remote pre-release is not newer than local release |
| `1.0.0-dev` | `1.0.0-dev` | no update | identical |
| `1.0.0-dev.1` | `1.0.0-dev.2` | update | numeric sub-identifier |
| `1.0.0-alpha` | `1.0.0-beta` | update | alphabetic identifier comparison |
| `v1.0.0-dev` | `v1.1.0-dev` | update | leading "v" must be stripped correctly |
| `not-a-version` | `1.0.0` | no crash | malformed local input must fail safe, not throw uncaught |
| `1.0.0` | `garbage` | no crash | malformed remote input must fail safe, not throw uncaught |

---

# TESTING

## Required
- Unit tests for `VersionComparator` covering every row in the edge-case table above, plus `isBelowMinimum` equivalents.
- Re-run (or confirm still passing) the existing manual/integration check for `v1.0.0-dev → v1.1.0-dev` end to end through the actual update flow, not just the comparator in isolation.
- Confirm no other file in `lib/` does its own ad-hoc version string comparison (`grep -rn "compareTo\|split('.')\|split(\".\")" lib/` as a starting point) — if found, flag it, don't silently leave a second, inconsistent comparison path in the app.

## Regression guard
- Do not mark this task complete if the previously-working `1.0.0-dev → 1.1.0-dev` case is not re-verified after the change.

---

# DELIVERABLES

1. Files created / modified (full list, with the specific diff for the comparison call site — not just "updated update_service.dart").
2. Confirmation of where the previous comparison logic lived (or explicit statement that none existed, if that's what's found).
3. Full table of edge-case test results (pass/fail) from the table above.
4. Explicit confirmation that `v1.0.0-dev → v1.1.0-dev` still passes after the change.
5. Any case where new behavior differs from old behavior, called out separately and not silently folded in.
6. A short note (not implemented, just noted) on whether a `channel` field would still be worth adding later for force-migrating between channels — this task does not implement that, only flags it as a known follow-up.

---

# SCOPE — FILES YOU MAY TOUCH

- `pubspec.yaml` (add dependency only)
- `lib/services/version_comparator.dart` (new)
- `lib/services/version_comparator_test.dart` or equivalent test file (new)
- The single existing file where update-eligibility decisions are made (identify it first; modify only the comparison calls)

Do not touch: Worker code, CI workflow, `release-template.json`, download/verify/install code, UI widgets, unrelated services.

---

# Phase Completion Criteria

Phase 16 is complete when:

* The new features works well with past features.
* App runs successfully.
* No runtime errors occur.
