# CampusBite — Roadmap

## Completed phases

| Phase | Scope | Status |
|---|---|---|
| Foundation | Flutter app shell, navigation (Home/Categories/Search/Orders/Account), menu data | ✔ |
| Ordering System | Menu browse, cart, order placement, order history | ✔ |
| Student Discipline & Account | Account management, authentication hardening | ✔ |
| Pickup Deadline Engine | READY → `pickupDeadline`, countdown, collection | ✔ |
| Distance-Based Pickup Windows | Location-aware pickup windows (`pickup_window_service`) | ✔ |
| Automatic No-Show Engine | Grace period, hard cutoff, automatic NO_SHOW | ✔ |
| Notifications | FCM, Firestore notification records, eventId dedup | ✔ |
| Search & Personalization | Search, favourites engine | ✔ |
| Reviews & Feedback | Eligibility-gated reviews, one review per meal | ✔ |
| Business Analytics | Admin reporting surfaces | ✔ |
| Production Hardening & Release | Crashlytics, analytics, monitoring, in-app updates, Cloudflare proxy | ✔ |
| (Security Hardening) | App Check, rules lockdown, audit logs | ✔ |
| A — Cancellation Foundation | 2-minute cancellation window, `cancelOrder` callable, rules | ✔ |
| B — Reliability Engine | `pickupReliability` data model, event-driven engine, idempotent transactions | ✔ |
| B.2 — Reliability Scores | Lifetime/recent rates, score, status tiers | ✔ |
| D — Reliability Experience | Reliability card, encouragement, recovery framing | ✔ |
| E — Graduated Restrictions | `NORMAL/LIMITED/HIGHLY_LIMITED`, backend-enforced active-order limits | ✔ |
| F — Reliability Recovery | Score-driven restriction relaxation | ✔ |
| G — Admin Excusal | `excuseNoShow` callable, transactional correction + audit + outbox | ✔ |
| H — Food Disposition | `setFoodDisposition` callable, disposition sheet, admin reports | ✔ |
| I — Testing & Production Hardening | validation, security/cost audits, documentation, release gate — see [PHASE_I_REPORT.md](PHASE_I_REPORT.md) | x |

## Legacy strike engine

Removed from the student app (phases B/D). No strike notifications, strike
percentage UI, or automatic suspension flow exists in the customer experience;

## Phase I gates

Phase I completes when the release gates in
[`PRODUCTION_CHECKLIST.md`](PRODUCTION_CHECKLIST.md) are satisfied and the
final report is issued. No new product features are added during this phase.
