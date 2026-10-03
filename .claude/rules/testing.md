---
paths:
  - "**/test/**"
  - "**/tests/**"
  - "**/__tests__/**"
  - "**/spec/**"
  - "**/*.test.*"
  - "**/*.spec.*"
  - "**/*_test.go"
  - "**/test_*.py"
  - "**/*Tests.swift"
  - "**/*Test.kt"
  - "**/e2e/**"
  - "**/integration/**"
  - "**/.maestro/**"
  - "**/playwright.config.*"
  - "**/vitest.config.*"
  - "**/jest.config.*"
---

# Testing

Run the `test-strategy` skill to pick the levels for a change. Run `verify-spec` to check a user-visible change in the running app.

## General rules

- MUST write the test before or with the code. A behavior change without a test is not done.
- MUST NOT delete, skip, or weaken a test to make it pass. Hooks warn on `.skip`, `.only`, `xit`, `#[ignore]`, `t.Skip`, and assertion removal.
- If a test is wrong, fix it only when the task makes the right behavior clear. Add a `Test-Change-Reason:` trailer to the commit.
- MUST NOT change an assertion to match wrong output. Fix the code.
- Tests MUST be deterministic. Control time, randomness, and network. MUST NOT sleep to wait for state.
- Tests MUST NOT reach production systems or real third-party accounts.

## Levels

Use the lowest level that proves the behavior. Add a higher level only for the risk the lower one cannot cover.

### Unit

- MUST cover pure logic, parsing, validation, and edge cases.
- MUST run in milliseconds with no network, disk, or clock dependency.
- Mock only at the boundary of the unit, never the unit itself.

### Integration

- MUST run against real local dependencies: a database, queue, cache, or storage in a container or local emulator.
  - Postgres or Supabase: `supabase start`, or `docker compose up -d db`, or testcontainers.
  - Firebase: the emulator suite. AWS: LocalStack. Redis, Kafka: containers.
- MUST NOT mock the thing under test. A data-access test hits the real database. An RLS test runs as a real role.
- MUST isolate data per test: a transaction rolled back after the test, a unique schema, or unique IDs. Tests MUST pass in any order and in parallel.
- MUST cover migrations: apply all from empty, then run the suite.

### Contract

- An API with an OpenAPI spec, JSON schema, protobuf, or zod schema MUST have contract tests.
- The server test validates every response against the schema, including error responses.
- A client in another repo or package tests against the same schema version, not a hand-written mock.
- A breaking schema change MUST fail a test. Version the API instead of editing the old contract.

### Regression

- Every bug fix MUST start with a failing test that reproduces the bug. Commit it with the fix.
- Name the test after the bug: `it("does not double-charge on retry (issue 412)")`, `test_issue_412_double_charge`.
- Confirm the test fails without the fix. Record the failure output in the PR.
- MUST NOT delete a regression test. If the feature is removed, remove the test with it and say why in the PR.

### End-to-end

- Cover the critical user journeys only: sign up, sign in, the main paid or core flow, data export and delete, and each role boundary.
- MUST run against the local stack (local server, local database, seeded data). MUST NOT run against production or shared staging with real users.
- Selectors MUST be stable: ARIA roles and accessible names first (`getByRole`), then `data-testid`. MUST NOT select by CSS class or text that changes with copy edits.
- MUST NOT use fixed sleeps. Wait for a condition: `expect(locator).toBeVisible()`, Maestro `extendedWaitUntil`, Detox `waitFor`.
- Data MUST be seeded and deterministic. Each test creates or resets the data it needs.
- Capture a trace, screenshot, or video on failure.
- Tools: Playwright (web), Maestro or Detox (React Native, Expo), XCUITest (iOS), Espresso (Android), a golden-file runner (CLI).

## Security paths

Mandatory for auth and access control code:

- unauthenticated request -> 401
- other user's object -> 403 or 404, with no data in the body
- lower role on an admin action -> 403
- invalid, expired, or tampered token -> 401
- input that tries injection or path traversal -> rejected
- each deny path tested at the integration level, not only with mocks

## Flaky tests

- A test that fails and then passes on retry is flaky. Treat it as a failure.
- Retries MUST NOT count as a pass in the report. Report the retry count.
- Fix the cause first: shared state, ordering, timing, real network, real clock.
- Quarantine only with a tracking issue and a fix-by date in a comment next to the quarantine marker. The marker goes through a commit with a `Test-Change-Reason:` trailer.
- MUST NOT quarantine a security or regression test.

## Data

- Fixtures use fake data. MUST NOT copy production data.
- Test accounts are seeded and local. Their passwords live in the seed script, never in a real identity provider.
- Fake secrets use obvious placeholders. Add `fw:allow-secret` on a line only when a test needs a value that looks real.

## Coverage

- Coverage is a signal, not a goal. Auth, authz, payment, and data-deletion code needs full branch coverage.
- MUST NOT add tests that assert nothing to raise coverage.

## Done means

- [ ] New behavior has tests at the right level.
- [ ] Each fixed bug has a regression test that failed before the fix.
- [ ] Data access and RLS have integration tests against a real local database.
- [ ] API responses are checked against the contract.
- [ ] Critical journeys touched by the change pass in e2e.
- [ ] Security deny paths are tested.
- [ ] No skipped, focused, or retried-to-green tests.
- [ ] The full suite passes locally with the project verify command.
