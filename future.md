# future implementation plans

# NOT FULLFILLED
2. prepaire updating code to automatically fetch and update app with ease
Preserves all of your current signing and build logic.
Builds both the universal APK and split-per-ABI APKs.
Renames APKs consistently.
Uploads APKs to Firebase Storage.
Generates release.json automatically.
Publishes only release.json and release notes to GitHub Releases.
Keeps your existing version/tag workflow intact.

3. ADD A Verification email step to disallow other peoples emails and stop email misuse-ready

6. add and search filter to search easily the long list of menu items in the admin app-ready

# 5. Add a review screen with review count dashboard, "campusbite customer" reviews with pre-written templates to avoid review abuse and harsh languages 
Users will be able to delete or edit their reviews.
example
* great deal
* great value for money
* not great as expected
* hot food
* served well

6. Make the student app and admin app choose which university there in and ensure that the FOOD ITEM and CAFE(add a field to specify which university there in) in university A is not shown or mixed into university B, including their orders.
* Also add a university collection to list all available universities in which the app serve

11. order screen should clean 24hrs and its history will be saved under /users/{userId}/history according to date, food item title and the total price.-ready

3. create a new branch to add restaurants other than university ones

5. Performance Analytics: Daily/weekly revenue, top-selling dishes, peak order hours, average prep time, customer rating trends.

2. add products for off_campus food items. the section field will be changed to off_campus, cafe field to offcampus, and the location field will be added to indicate the location of the offcampus cafes.
// Row for deals outside campus cafes on home screnn
* CardRowItems(title: "Deals outside campus cafes",items: offCampus,),
// If cafe is 'offcampus', show 'OFF-CAMPUS', otherwise show 'CAFE(X)'
* item.cafe.toLowerCase() == 'offcampus' ? '${item.rating} • offcampus' : '${item.rating} • CAFE(${item.cafe})',

# Updated CampusBite Roadmap

✔ Phase 0
Foundation

✔ Phase 1
Ordering System

✔ Phase 2
Student Discipline & Account Management

↓

✔ Phase 3
Pickup Deadline Engine

↓

✔Phase 4
Distance-Based Pickup Windows

↓

✔Phase 5
Automatic Strike Engine

↓

✔Phase 6
Notifications
starting to finish with notification, very tired exshausted with freebuff, opencode and antigravity

↓

✔Phase 7
Search & Personalization

↓

Phase 8
Reviews & Feedback

↓

Phase 9
Business Analytics

↓

Phase 10
Production Hardening & Release


# ai instructions for updating the app

# TASK

Implement the CampusBite seamless in-app update system end to end: the
Cloudflare Worker metadata/download service, and the Flutter client that
consumes it.

This implementation must be production-ready.

## Non-negotiable constraints

- The app is NOT distributed through Google Play.
- Release artifacts live on GitHub Releases (build + storage only).
- `https://dl.larason.space` (Cloudflare Worker) is the ONLY endpoint the
  Flutter app is allowed to call for update-related data.
- The Flutter app must contain zero references to `github.com`,
  `api.github.com`, or any GitHub org/repo name, in code or config.
- If you find a direct GitHub reference anywhere in `lib/`, that is a bug —
  fix it, don't leave it.

---

# WORKER RESPONSIBILITIES

The Worker is the only thing allowed to know GitHub exists. It must:

1. Resolve "latest" by calling the GitHub Releases API server-side.
2. Fetch that release's `release.json` asset server-side.
3. Rewrite every URL inside that JSON so it points at
   `dl.larason.space/{tag}/{filename}` instead of `github.com/...`.
4. Cache the rewritten JSON at the edge (do not call GitHub on every request).
5. Proxy-stream the actual APK/checksum bytes from GitHub when a rewritten
   URL is requested, with long-lived immutable caching (tags are immutable).
6. Serve arbitrary past tags via a versioned route, not just "latest," so
   rollback and staged rollout are possible without a redeploy.

## Routes

| Route | Purpose | Cache |
|---|---|---|
| `GET /latest` | Metadata for the current default release | 5 min edge TTL |
| `GET /release/{tag}` | Metadata for a specific past release (rollback, channels) | Immutable |
| `GET /{tag}/{filename}` | Proxies the actual `.apk` / `.sha256` bytes | Immutable |

`/latest` and `/release/{tag}` must return the same JSON *shape* — the
only difference is which tag they resolve.

---

# METADATA ENDPOINT CONTRACT

`GET https://dl.larason.space/latest` returns:

```json
{
  "version": "...",
  "minimumVersion": "...",
  "forceUpdate": false,
  "releaseNotes": "...",
  "downloads": {
    "universal": "https://dl.larason.space/v1.4.2/CampusBite-universal.apk",
    "arm64-v8a": "https://dl.larason.space/v1.4.2/CampusBite-arm64-v8a.apk",
    "armeabi-v7a": "https://dl.larason.space/v1.4.2/CampusBite-armeabi-v7a.apk",
    "x86_64": "https://dl.larason.space/v1.4.2/CampusBite-x86_64.apk"
  },
  "checksums": {
    "universal": "https://dl.larason.space/v1.4.2/CampusBite-universal.apk.sha256",
    ...
  }
}
```

Rules:
- Every URL in the response MUST be a `dl.larason.space` URL. No exceptions.
- Unknown/future top-level fields (e.g. `channel`, `rolloutPercentage`) must
  be passed through untouched, not stripped — the client ignores fields it
  doesn't recognize, so the Worker doesn't need an allowlist.
- If GitHub is unreachable, return the last good cached response with a
  `stale: true` field rather than an error, when a cached copy exists.

---

# FLUTTER CLIENT REQUIREMENTS

## Version check cadence
- On app startup (once), and
- On a 12-hour interval while the app is installed (WorkManager /
  background task — not "every launch").
- Never call the endpoint more than once per cache-validity window;
  respect a locally stored cache with its own TTL independent of the
  Worker's edge cache.

## ABI selection
- Detect device ABI via platform channel, pick the matching download URL.
- Fall back to `universal` if the device ABI isn't in the supported list.
- Never prompt the user to choose an architecture.

## Download
- Stream to app-private storage with progress, size, and ETA shown.
- Support pause/resume if the underlying download plugin does.
- Continue in background where the OS allows; resume gracefully if killed.
- Retry action on failure, capped attempts before surfacing a clear error.

## Integrity
- Fetch the checksum URL for the matching ABI, compute SHA-256 of the
  downloaded file, compare before allowing install.
- On mismatch: delete the file, do not offer install, surface a "couldn't
  verify" retry state.

## Install
- FileProvider + `ACTION_VIEW` with
  `application/vnd.android.package-archive`.
- Handle `REQUEST_INSTALL_PACKAGES` permission flow gracefully if not
  already granted.

## Update types
- `forceUpdate: true` OR local version `< minimumVersion` → mandatory,
  blocking screen, no dismiss, no app usage until updated.
- Otherwise optional → dismissible prompt, "Update now" / "Later".

## UX copy
- User-facing strings only: "New version available", "Downloading
  update…", "Installing update…", "Update completed."
- Never surface ABI names, GitHub, Cloudflare, filenames, or raw JSON.
  Release notes render through a markdown widget, not a raw text dump.

## Resilience
- Any network failure in the update check path is silently swallowed
  (debug-log only) and the app continues normally on the current version.

## Storage hygiene
- Delete a previously downloaded installer once install succeeds or once
  superseded by a newer downloaded version. Never cache APK bytes
  indefinitely.

---

# SECURITY

- Reject any download URL that isn't `https://dl.larason.space/...` —
  hardcode the allowed host, don't just check the scheme.
- Never construct or accept a download URL from anywhere other than the
  `/latest` (or `/release/{tag}`) response body.

---

# LOGGING

- Debug builds only.
- Never log: full download URLs (log tag/filename only if needed), device
  identifiers, or any user/auth data.

---

# SCOPE

Files you are expected to touch:
- `cloudflare-worker/src/index.js`
- `lib/services/update_service.dart` (or equivalent — create if absent)
- `lib/widgets/update_*.dart` (new update UI)
- `.github/workflows/release-apk.yml` only if the metadata contract above
  requires a workflow change

Do not modify unrelated screens, features, or CI jobs.

---

# DELIVERABLES

1. Files created / modified (full list).
2. Architecture diagram (text is fine) showing Flutter → Worker → GitHub.
3. Download flow (sequence of calls).
4. Installation flow.
5. Cache strategy (edge TTL vs local client TTL, explicitly stated).
6. Security measures taken.
7. Manual testing checklist (use the one below, add any you find missing).

---

# MANUAL TESTING CHECKLIST

- [ ] App detects a new release
- [ ] No update prompt when already current
- [ ] Optional update is dismissible and re-prompts later
- [ ] Mandatory update fully blocks app usage until updated
- [ ] Correct ABI APK selected automatically, no user prompt
- [ ] Universal APK used when ABI unsupported
- [ ] Download progress, size, ETA all render
- [ ] Pause/resume works if plugin supports it
- [ ] Install prompt appears after successful verification
- [ ] Checksum mismatch blocks install and offers retry
- [ ] Network failure during check doesn't block app usage
- [ ] Second check within cache TTL makes zero network calls
- [ ] `grep -r "github.com" lib/` returns nothing
- [ ] `/release/{old-tag}` on the Worker still serves an older version
- [ ] Manually corrupt/replace release.json with a non-dl.larason.space URL 
      and confirm the Worker returns 502, not the bad URL
