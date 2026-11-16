# Lions App — Regression Test Suite Plan

**Date:** 16 November 2026
**Scope:** Flutter client (`lib/`, ~10,000 lines) and Dart shelf API (`lions_api/bin/lions_api.dart`, ~5,000 lines)
**Status of this document:** Plan only — no code changes have been made.

---

## 1. Goals

- Provide a **repeatable regression suite** that can be run before every release and on every change.
- Catch breakage in the areas that matter most: **API contracts, permissions, event/role lifecycle, conference content, reports, and email**.
- Keep the suite **fast enough to run constantly** (unit/widget layers in seconds) while providing deeper confidence via API integration tests against a disposable database.
- Require **minimal refactoring** in early phases; defer riskier test-enabling refactors until the suite is in place to protect them.

## 2. Current State Assessment

| Item | Status |
|---|---|
| Frontend unit tests | 2 files, 3 passing tests (`conference_section_tree_test.dart`, `conference_page_attachment_utils_test.dart`) |
| `test/widget_test.dart` | **Broken** — stale Flutter counter template referencing `MyApp`, which doesn't exist (app class is `LionsApp`). Fails compilation; `flutter test` reports "Some tests failed" today. |
| Backend (`lions_api`) tests | **None.** No `test/` directory, no `test` dev dependency. |
| CI | **None.** No `.github/workflows`, so nothing runs tests automatically. |
| Test seams | Poor. HTTP access is via static methods (`ApiClient`) or direct `http.*` calls inside widgets; backend logic lives in one 5,000-line file of top-level functions with a private `_router()`. |

**Verified baseline (16 Nov 2026):** `flutter test` → 3 passed, 1 failed to compile (`widget_test.dart`).

## 3. Test Architecture (Test Pyramid)

```
        ┌────────────────────────┐
        │  E2E smoke (few)       │  integration_test on device/desktop vs staging API
        ├────────────────────────┤
        │  API integration tests │  shelf server + disposable MySQL (Docker)
        │  (the regression core) │
        ├────────────────────────┤
        │  Widget tests          │  flutter_test + mocked HTTP + mocked prefs
        ├────────────────────────┤
        │  Unit tests (many)     │  pure Dart logic, frontend + backend
        └────────────────────────┘
```

**The API integration layer is the highest-value investment.** The backend is where the business rules, permissions, and data integrity live, and it can be tested without any refactoring — the server starts via `PORT`/`DB_*` environment variables (`lions_api.dart:46–51, 4973–4991`) and can be exercised over real HTTP.

### Directory layout

```
test/                           # Flutter: unit + widget tests (exists)
  unit/
  widget/
integration_test/               # Flutter: E2E smoke tests (new)
lions_api/
  test/
    unit/                       # pure logic tests
    integration/                # HTTP tests against live server + test DB
    helpers/                    # test server bootstrap, DB seed/reset utilities
  docker-compose.test.yml       # MySQL 8 for tests
```

---

## 4. Phase 1 — Foundation (do first, ~1 day)

1. **Fix or delete `test/widget_test.dart`.** Replace with a real smoke test: pump `LionsApp(showOnboarding: true)` with `SharedPreferences.setMockInitialValues({})` and assert the onboarding page renders. This makes `flutter test` green and establishes the baseline.
2. **Add backend test scaffolding:** add `test: ^1.25.0` and `http` to `lions_api/pubspec.yaml` dev dependencies; create `lions_api/test/`.
3. **Add `docker-compose.test.yml`** running MySQL 8 with `lions_test` database; apply `lions_api/migrations/create_schema.sql` plus the incremental migration files on startup.
4. **Add CI (GitHub Actions):**
   - Job 1: `flutter analyze` + `flutter test --coverage`.
   - Job 2: `dart analyze` in `lions_api` + spin up MySQL service container, run `dart test` in `lions_api`.
5. **Document how to run everything** in a short `TESTING.md` (or a section in `README.md`).

**Exit criteria:** one command (`flutter test` and `dart test`) runs green locally and in CI on every push.

## 5. Phase 2 — Unit Tests for Pure Logic (no refactoring required, ~2–3 days)

These run in milliseconds and need no network, DB, or mocks.

### 5.1 Frontend (`test/unit/`)

| Target | Source | Cases |
|---|---|---|
| `buildConferenceSectionTree` | `lib/conference_section_tree.dart` | Extend existing test: archived include/exclude, `includeChildren: false`, missing/invalid `parent_id`/`sort_order`, orphan children, input not mutated |
| `buildConferenceAttachmentUrl` + MIME/byte helpers | `lib/conference_page.dart:55–95, 165–181` | Extend existing: URL encoding of keys, region handling, unknown MIME types, byte-size formatting boundaries |
| `AuthStore._isTruthy` / profile normalization | `lib/auth_store.dart:8–13`, `lib/onboarding_page.dart:83–100` | `1`, `true`, `'1'`, `[1]` (MySQL BIT blob), `0`, `false`, `null`, empty list — verify both copies behave identically |
| `getApiBase` | `lib/config.dart` | Env-override behavior per platform flag combination |

### 5.2 Backend (`lions_api/test/unit/`)

Several helpers are top-level functions in `bin/lions_api.dart` and are testable once the file is importable (either via a `part`/library split later, or short-term by testing through HTTP in Phase 3). Where directly testable now:

| Target | Source (approx.) | Cases |
|---|---|---|
| `_renderTemplate` | `lions_api.dart:219–268` | Variable substitution, missing variables, missing template file fallback, cache behavior, **HTML in variable values (documents the injection gap)** |
| `_normalizeConferenceStatus` | `lions_api.dart:383–394` | All aliases, unknown values, null |
| `_isTruthy` / flag conversion | `lions_api.dart:374–376` | Same matrix as frontend |
| ICS generation | `lions_api.dart:1783–1846` | Date formatting, escaping of summary/location, all-day vs timed events |
| Attachment token/presign helpers | `lions_api.dart:398–596` | MIME allowlist, key encoding, token expiry/validation |

> Note: because everything is private in one `bin/` file, some of these may only be reachable via the HTTP layer until the Phase 6 refactor. Prioritise the ones reachable now; cover the rest through integration tests.

## 6. Phase 3 — API Integration Tests (the regression core, ~1–2 weeks)

**Harness:** a test helper that (a) starts MySQL via Docker, (b) applies schema + migrations, (c) launches `dart run bin/lions_api.dart` with `DB_*`, `PORT`, and attachment env vars pointing at the test environment (`ATTACHMENT_PRESIGN_MODE=mock`), (d) seeds fixture data (clubs, members with each permission combination, event types, role templates), and (e) truncates tables between test groups for isolation. SMTP stays unconfigured so email sends fail fast — assert on the API response/audit behavior, not delivery (see §6.7).

Auth in tests: pass `x-member-id` headers for fixture members (super, admin, conference member, plain member, absent) — the current identity scheme (`lions_api.dart:330–338`) makes role simulation trivial.

### Coverage matrix (every endpoint gets: happy path, auth/permission denial, invalid input, not-found)

#### 6.1 Members & Clubs
- CRUD `/members`, `/clubs` — field round-tripping, `club_id` filter, delete cascades/constraints.
- Permission matrix: who can create/update/delete members and clubs (club writes enforce auth at `lions_api.dart:1508–1517`).
- **Regression guard:** `GET /members` currently requires no auth (`:270–322`) — write a test documenting current behavior so any future fix is deliberate and visible.

#### 6.2 Events lifecycle (highest business value)
- `POST /events`: with explicit roles; with event-type role templates copied; invalid dates; missing required fields; malformed JSON (handler at `:795–908`).
- `GET /events` filtering: by club, by date range, super vs non-super visibility (`:617–690`).
- `PUT /events/<id>` permission checks (`:995–1003`); `DELETE` removes roles/volunteers transactionally (`:947–964`).
- Volunteers: assign (`POST /events/<id>/volunteers`), double-assignment to the same role, unassign, assignment to a non-existent role.
- `GET /events/<id>/calendar.ics` returns valid ICS content.
- `POST /events/<id>/roles` adds roles to existing events.

#### 6.3 Event types & role templates
- CRUD `/event_types`, templates per type, template copy-on-event-create, delete template in use.
- Dinner meal options CRUD and permission checks (`:1380–1390`).

#### 6.4 Conference
- Content get/save; section CRUD, nesting (`parent_id`), reorder, archive/restore round trip.
- Attachments in mock presign mode: presign → mock upload → register → list → reorder → archive/restore → content fetch.
- Permission matrix via `_canEditConference` (`:2298–2321`).
- Conference ideas: submit, status transitions, delete.

#### 6.5 Reports
- `/reports/events`, `/reports/volunteers`, `/reports/fill_rates`, `/reports/club_comparison` against seeded fixtures with known expected aggregates; date-range edge cases; club-comparison super-only enforcement (`:4471`).

#### 6.6 Audit logs
- Mutations create audit rows; `GET /audit_logs` filters; verify behavior when audit insert fails (currently swallowed, `:141–168` — document).

#### 6.7 Email endpoints
- `POST /events/<id>/notify` with SMTP unconfigured: assert graceful failure response (not a 500 with a stack trace) and that no partial state is left behind. Template rendering itself is covered in Phase 2 unit tests.

**Exit criteria:** every registered route in `_router()` (`:4546–4674`) appears in at least one test; permission matrix covered for all mutating endpoints.

## 7. Phase 4 — Flutter Widget Tests (~1 week, after small refactors)

**Enabling refactor (small, mechanical — defer until Phase 3 is protecting the backend):**
1. Give `ApiClient` an injectable `http.Client` (default to a real one): `static http.Client client = http.Client();` is the minimal seam, or convert to an instance passed down.
2. Route the remaining direct `http.*` calls through `ApiClient` (see Gaps §A3) — this also fixes the missing `x-member-id` header on those calls.
3. Use `SharedPreferences.setMockInitialValues` for auth flags in tests (already supported, no refactor needed).

**Priority widget tests:**

| Flow | Tests |
|---|---|
| Onboarding (`onboarding_page.dart`) | Club list loads; selecting club loads members; club change clears member; save persists profile and navigates; non-200 and malformed JSON responses |
| Main navigation (`main.dart`) | Rail vs bottom bar at the 800px breakpoint; Reports action visible only for admin/super; tab switching |
| Events list (`events_page.dart`) | Render from mocked payload; filters alter the request; admin-only controls hidden for plain members |
| Create event dialog (`create_event_dialog.dart`) | Templates load on type selection; "Other" clears roles; club locked for non-super; role add/remove; submit payload shape; create failure shows error |
| Event detail (`event_detail_page.dart`) | Volunteer assignment UI; admin actions gated; email preview opens and cancel sends nothing |
| Conference (`conference_page.dart`) | Read-only vs editable mode per flags; tree rendering from fixture |
| Reports (`reports_page.dart`) | Date presets produce correct query params; partial endpoint failure handling; CSV export content (extract `_exportToCSV` body into a pure function first — `:192–280`) |

## 8. Phase 5 — E2E Smoke Tests (~2–3 days, optional but recommended)

A handful of `integration_test` scenarios run against a locally launched API + test DB (reusing the Phase 3 harness):

1. Onboard → land on home.
2. Create event with roles → appears in list and calendar.
3. Assign volunteer → fill rate updates in reports.
4. Conference: add section, reorder, archive.

Run on desktop (`flutter test integration_test -d macos`) in CI nightly rather than per-push — these are slower and flakier by nature.

## 9. Phase 6 — Test-Enabling Backend Refactor (after the suite exists)

Once integration tests protect behavior, split `bin/lions_api.dart` into `lib/` libraries (handlers, db, email, auth helpers) so unit tests can import them directly, add a connection-pool/transaction wrapper, and centralize auth middleware. **The integration suite from Phase 3 is precisely what makes this refactor safe.**

## 10. Running the Suite

```bash
# Frontend unit + widget tests (fast, run on every change)
flutter test

# Backend unit tests
cd lions_api && dart test test/unit

# Backend integration tests (needs Docker)
docker compose -f lions_api/docker-compose.test.yml up -d
cd lions_api && dart test test/integration
docker compose -f lions_api/docker-compose.test.yml down -v

# E2E smoke (nightly / pre-release)
flutter test integration_test -d macos
```

## 11. Prioritised Roadmap

| Phase | Effort | Value | Prerequisite |
|---|---|---|---|
| 1. Foundation (fix broken test, CI, DB harness) | ~1 day | Unblocks everything | — |
| 2. Pure-logic unit tests | 2–3 days | Fast feedback on helpers | Phase 1 |
| 3. API integration tests | 1–2 weeks | **Core regression protection** | Phase 1 |
| 4. Widget tests (+ HTTP seam refactor) | ~1 week | UI regression protection | Phase 3 (so refactor is safe) |
| 5. E2E smoke | 2–3 days | Release confidence | Phases 3–4 |
| 6. Backend refactor for unit testability | 1–2 weeks | Long-term maintainability | Phase 3 |

---

## 12. Gaps and Issues Found During Review

These were found while assessing testability. **No changes have been made.** Severity: 🔴 should address soon · 🟡 should address · 🔵 cleanup/hygiene.

### A. Flutter client

| # | Severity | Issue | Location |
|---|---|---|---|
| A1 | 🔴 | ~~**Broken test file**: `widget_test.dart` references non-existent `MyApp`~~ **Resolved in Phase 1** — replaced with real smoke tests | `test/widget_test.dart` |
| A2 | 🔴 | **Hardcoded `http://localhost:8080`** for lookups and notifications — wrong on every real device and bypasses the configured base URL and auth header | `lib/calendar_page.dart:103–127` |
| A3 | 🟡 | **Direct `http.*` calls bypass `ApiClient`**, omitting the `x-member-id` auth header and preventing central mocking | `create_event_dialog.dart:28–29, 453–457`; `onboarding_page.dart:31, 61`; `members_page.dart:47–61`; `events_page.dart:205, 244, 394`; `event_detail_page.dart:121, 550` |
| A4 | 🟡 | **Duplicated API module** — `lib/lions_api.dart` and `lib/services/lions_api.dart` are near-identical; consolidate | both files, entire contents |
| A5 | 🟡 | **Authorization is UI-only in places** — role gating reads possibly-stale `SharedPreferences` flags; server-side enforcement must be the real guard (see B1/B2) | e.g. `main.dart:298–303`; `members_page.dart:36`; `conference_page.dart:124–128` |
| A6 | 🟡 | **Inconsistent error handling** — some fetches have no `try/catch`, some swallow errors, some leave a permanent loading state on non-200 | `calendar_page.dart:103–106`; `onboarding_page.dart:57–71` |
| A7 | 🟡 | **Verbose `debugPrint`/`print` of API bodies and member data** in production code paths — personal-data leak risk in logs | `onboarding_page.dart:79–113`; `create_event_dialog.dart:435–458`; `members_page.dart:179–182`; `event_detail_page.dart:775–812` |
| A8 | 🔵 | **Duplicated role-flag normalization** (`_isTruthy`-style logic) in `AuthStore` and onboarding — risk of divergence | `auth_store.dart:8–13`; `onboarding_page.dart:83–100` |
| A9 | 🔵 | **Dead/disabled code**: `email_html_editor.dart` always exports the stub; the web implementation is parked as `email_html_editor_web.disabled.dart` | `lib/widgets/` |
| A10 | 🔵 | Private LAN IP (`192.168.4.39`) baked into default config; harmless but confusing | `lib/config.dart:15–17` |

### B. Backend API (`lions_api`)

| # | Severity | Issue | Location (`bin/lions_api.dart`) |
|---|---|---|---|
| B1 | 🔴 | **Authentication is spoofable** — identity is whatever the caller puts in `x-member-id` header or `_auth_member_id` query param; no token/session/password verification exists anywhere (code comments acknowledge this placeholder) | `:330–338` |
| B2 | 🔴 | **Unauthenticated data exposure** — `GET /members` returns names, emails, phone numbers, and privilege flags with no auth check; several other reads behave similarly | `:270–322` |
| B3 | 🔴 | **SMTP TLS verification disabled** (`allowInsecure: true`, `ignoreBadCertificate: true`) — credentials and member emails exposed to MITM | `:187–192` |
| B4 | 🟡 | **HTML injection in email templates** — `{{variable}}` values are substituted into HTML without escaping; user-supplied event names/notes become markup in outgoing email | `:239–259` |
| B5 | 🟡 | **Raw exception details returned to clients** (`Error: $e`), leaking DB/internal information | e.g. `:321–322`, `:4537–4538` |
| B6 | 🟡 | **No transaction around multi-step event creation** — event + roles inserts can partially succeed | `:844–908` (contrast with deletion at `:947–964`, which is transactional) |
| B7 | 🟡 | **Audit-log failures silently swallowed** — mutations can succeed with no audit trail | `:141–168` |
| B8 | 🟡 | **Permissive CORS** (any origin) combined with the header-based identity model | `:4980–4988` |
| B9 | 🟡 | **Runtime schema mutation on every connection** — `_connect()` may run `ALTER TABLE` and suppress errors; surprising in production, problematic for concurrent startup and test isolation | `:88–135` |
| B10 | 🟡 | **Request bodies logged**, including raw body on malformed JSON — personal data in server logs | `:815–836` |
| B11 | 🔵 | **No connection pooling** — a fresh MySQL connection (plus TCP diagnostics written to stderr) per request | `:14–43, 117–135` |
| B12 | 🔵 | **Monolithic structure** — all ~5,000 lines in one `bin/` file of private functions; blocks direct unit testing (addressed by Phase 6) | whole file |
| B13 | 🔵 | **Input validation inconsistent across handlers** — some validate thoroughly, others don't; no central validation | throughout |
| B14 | 🟡 | **`add_conference_section_parent_id.sql` uses MariaDB-only syntax** (`ADD COLUMN IF NOT EXISTS`) and fails on MySQL 8; masked in production because the API re-adds the column at startup. A MySQL 8–compatible version for the test DB lives at `lions_api/test/db/` | `migrations/add_conference_section_parent_id.sql` |
| B15 | 🔵 | **Dead comparisons in permission helpers** — `mysql_client` returns column values as strings, so the `== 1` / `== true` branches in `_isSuper`/`_isAdmin`/`_isConferenceMember` are unreachable (only `== '1'` matches); harmless but flagged by the analyzer | `:340–376` |
| B16 | 🔴 | **Unauthenticated member writes** — `POST /members` and `DELETE /members/<id>` perform **no identity or permission check at all**: anyone who can reach the API can create members or delete any member. Pinned by regression guards in `test/integration/members_clubs_test.dart` so the fix is a visible, deliberate change | `:4679–4741`, `:4844–4880` |

### C. Project-level

| # | Severity | Issue |
|---|---|---|
| C1 | 🔴 | ~~**No CI**~~ **Resolved in Phase 1** — `.github/workflows/ci.yml` runs analyze + tests for both projects (analyzer gates on errors only until pre-existing warnings are cleared) |
| C2 | 🟡 | `lions-app-key.pem` sits in the repository root — verify it contains no private key material that should be removed from version control and rotated |
| C3 | 🔵 | Build artifacts and installers (`build/`, `installer/*.exe`, `release_artifacts/`) tracked alongside source; consider pruning from version control |

### Suggested remediation order (separate from the test plan)

1. C1 (CI) and A1 (broken test) — covered by Phase 1.
2. B1/B2 (real authentication + auth on reads) — the single biggest risk; the integration suite's permission matrix (Phase 3 §6.1) should be written first so the fix is verifiable.
3. A2/A3 (hardcoded localhost, bypassed `ApiClient`) — quick wins that also unblock widget testing.
4. B3–B7, A6/A7 — hardening, best done once integration tests exist.
