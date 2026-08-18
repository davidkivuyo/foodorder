# CampusBite — Security Model

## Authentication

- Firebase Authentication (email/password) with email verification required
  before ordering.
- Firebase App Check (`enforceAppCheck: true`) on all callable functions.
- Role enforcement (`student` vs `admin`) verified in rules and in every
  admin callable.

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
