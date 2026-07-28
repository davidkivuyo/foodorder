# instruction for release production builds

Here's the standard industry practice for naming releases and git tags: **Semantic Versioning (SemVer)**.

SemVer uses a strict `MAJOR.MINOR.PATCH` format (e.g., `v1.4.2`) to clearly communicate the scope and impact of changes to users and automated systems.

---

### 1. Tag & Release Version Structure

A standard version string consists of three core numbers:

$$\mathbf{v X . Y . Z}$$

```
  v  1  .  4  .  2
  │  │     │     └─ PATCH: Bug fixes, security patches, minor non-breaking tweaks
  │  │     └─────── MINOR: New features added in a backward-compatible manner
  │  └───────────── MAJOR: Breaking changes, architectural overhauls, major redesigns
  └──────────────── Prefix (Standard convention for Git tags)

```

#### When to Increment Each Digit

* **`PATCH` (Bug Fixes & Security Updates):**
* **When:** Resolving security vulnerabilities, fixing minor bugs, performance patches, or non-functional structural maintenance.
* **Rule:** Must be backward-compatible (no broken user flows or API changes).
* **Example:** Moving from `v1.2.0` $\rightarrow$ `v1.2.1`.


* **`MINOR` (New Features & Non-Breaking Enhancements):**
* **When:** Adding new user-facing features, new screens, or extending existing capabilities.
* **Rule:** Must remain backward-compatible with existing app data/APIs.
* **Example:** Moving from `v1.2.1` $\rightarrow$ `v1.3.0` (Note: The `PATCH` resets to `0`).


* **`MAJOR` (Incompatible / Breaking Changes):**
* **When:** Major UI/UX overhauls, dropping support for older database schemas, breaking API integration changes, or replacing core architecture.
* **Rule:** Existing users or systems may require explicit migration steps.
* **Example:** Moving from `v1.3.5` $\rightarrow$ `v2.0.0` (Both `MINOR` and `PATCH` reset to `0`).



---

### 2. Pre-Releases & Release Candidates (Optional)

If you want to publish internal testing or beta builds via GitHub Releases before a full release, append a hyphen `-` followed by pre-release identifiers:

* **Alpha (Early testing):** `v2.0.0-alpha.1`
* **Beta (Feature complete, testing stability):** `v2.0.0-beta.1`
* **Release Candidate (Staging before production):** `v2.0.0-rc.1`

---

### 3. Git Tagging vs. GitHub Release Naming Conventions

While git tags and GitHub release titles represent the same milestone, they are typically formatted slightly differently:

| Concept | Naming Standard | Example | Purpose |
| --- | --- | --- | --- |
| **Git Tag** | Lowercase `v` prefix + SemVer | `v1.4.2` | Immutable pointer in git history (triggers CI/CD). |
| **Release Title** | Descriptive title + Version | `v1.4.2 - Payment Gateways & Bug Fixes` | Human-readable title in the GitHub UI. |

---

### Summary Checklist for Tagging Workflow

1. Start your project at `v1.0.0` when releasing the first stable production build.
2. For small security or bug fixes, increment the last digit: `v1.0.1`.
3. For new features, increment the middle digit and reset the last: `v1.1.0`.
4. Always prefix Git tags with `v` (e.g., `v1.1.0`), as automated workflows (like the GitHub Actions `on: push: tags: ['v*.*.*']` trigger) rely on this standard pattern.

# Create a local tag
git tag v1.0.0

# Push the tag to GitHub
git push origin v1.0.0
