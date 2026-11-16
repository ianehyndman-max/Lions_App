# Testing the Lions App

This repo has two test suites: one for the Flutter app and one for the
`lions_api` backend. Both run automatically in CI
([.github/workflows/ci.yml](.github/workflows/ci.yml)) on every push to
`main`/`test-suite` and on pull requests to `main`.

The overall strategy, phased roadmap, and known gaps are documented in
[regression_suite_plan.md](regression_suite_plan.md).

## Flutter app

```bash
# All unit + widget tests (fast — run on every change)
flutter test

# Static analysis, scoped to the app's own code (CI gates on errors only)
flutter analyze --no-fatal-infos --no-fatal-warnings lib test
```

Tests live in `test/`:

- `test/widget_test.dart` — app boot smoke tests (onboarding vs main screen)
- `test/conference_section_tree_test.dart` — section tree building
- `test/conference_page_attachment_utils_test.dart` — attachment URL helpers

Notes for writing widget tests:

- Seed auth state with `SharedPreferences.setMockInitialValues({...})`
  (keys: `member_id`, `club_id`, `is_admin`, `is_super`,
  `is_conference_member`).
- Flutter's test harness replaces the real HTTP client with one that always
  returns HTTP 400, so pages that fetch in `initState` deterministically take
  their error/empty path. Proper response mocking arrives with the
  injectable-client refactor in Phase 4 of the plan.

## Backend (`lions_api`)

```bash
cd lions_api

# Unit tests (no database needed)
dart test test/unit

# Static analysis
dart analyze
```

### Integration tests (requires Docker)

A disposable MySQL 8 database is defined in
`lions_api/docker-compose.test.yml`. Schema and migrations are applied
automatically on first start; it listens on **port 3307** to avoid clashing
with any local MySQL.

```bash
cd lions_api
docker compose -f docker-compose.test.yml up -d --wait

# Harness defaults match the compose file (127.0.0.1:3307, root/lions_test);
# override with TEST_DB_* / TEST_API_PORT env vars if needed.
dart test test/integration

# Set TEST_SERVER_LOGS=1 to stream API server output while debugging.

docker compose -f docker-compose.test.yml down -v   # -v wipes all data
```

Directory layout under `lions_api/test/`:

- `unit/` — pure logic tests (currently: email template contracts)
- `integration/` — HTTP tests against the real server + test DB
  (members/clubs, events lifecycle, event types/templates/meal options;
  conference and reports arriving next)
- `helpers/` — `test_harness.dart`: server subprocess bootstrap, authenticated
  HTTP client, DB reset/seed fixtures; `api_builders.dart`: create
  types/templates/events through the API for use as fixtures
- `db/` — test-database-only SQL (e.g. the MySQL 8–compatible version of the
  `parent_id` migration; the shipped one uses MariaDB-only syntax)

## CI

Two independent jobs:

1. **Flutter app** — `flutter analyze` (errors only) + `flutter test
   --coverage`; coverage uploaded as a build artifact.
2. **Backend API** — `dart analyze` + schema/migration verification against a
   MySQL 8 service container + `dart test test/unit`.

The analyzer gates are intentionally lenient (errors only) because the
codebase has pre-existing warnings/infos. Tighten to `--fatal-warnings` once
those are cleared.
