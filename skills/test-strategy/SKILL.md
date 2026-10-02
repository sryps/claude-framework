---
name: test-strategy
description: Plan and write tests for a change across levels (unit, integration, contract, regression, e2e). Picks the levels that apply, sets up test infrastructure for the stack, runs the regression-first flow for bug fixes, and handles flaky tests. Use before writing code for a feature or fix, or when a project lacks a test level it needs.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# /test-strategy: pick the test levels and write the tests

**Arguments:** `$ARGUMENTS` (the change, or a bug report)

Read `.claude/rules/testing.md` first. It holds the MUST rules this skill applies.

## 1. Classify the change

| Change | Levels |
|---|---|
| Pure logic, parsing, validation | Unit |
| Data access, queries, RLS, migrations | Unit + integration (real local DB) |
| New or changed endpoint | Unit + integration + contract |
| Bug fix | Regression test first, at the lowest level that reproduces it |
| UI flow, screen, critical journey | Unit for logic + e2e for the journey |
| Auth, access control | Integration for every deny path + e2e for sign-in if touched |
| CLI command | Unit + golden-file tests on the built binary |

Write the plan as a short list: each acceptance criterion, its level, and the test name.

## 2. Find or set up the infrastructure

Detect what exists before you add anything:

```bash
ls package.json pyproject.toml go.mod Cargo.toml Package.swift build.gradle* playwright.config.* vitest.config.* jest.config.* .maestro 2>/dev/null
```

Use the runner the project already has. Add a new one only for a missing level, and follow the `add-dependency` skill for it.

| Stack | Unit | Integration | E2E |
|---|---|---|---|
| TS, Node | `npx vitest run` or `npx jest` | vitest or jest + `docker compose up -d db` or testcontainers | `npx playwright test` |
| Python | `pytest -q` | pytest + testcontainers-python or compose | Playwright for Python |
| Go | `go test ./...` | `go test -tags=integration ./...` + testcontainers-go | Playwright or chromedp |
| Rust | `cargo test` | `cargo test --features integration` + testcontainers | Playwright against the server |
| Supabase | n/a | `supabase start`, then `supabase test db` (pgTAP) | Playwright against the local stack |
| Expo, React Native | jest | jest against local Supabase or a mock server | `maestro test .maestro/` or Detox |
| iOS, Android native | XCTest, JUnit | same, with local services | XCUITest, Espresso |

Keep integration tests in a separate target (`npm run test:integration`, a build tag, or a pytest marker) when they need containers. The project `verify` target runs all of them.

## 3. Bug fix: regression first

1. Reproduce the bug in a test. Name it after the bug: `test_issue_412_double_charge`.
2. Run it. Confirm it fails, and that the failure matches the bug report:
   ```bash
   npx vitest run path/to/file.test.ts -t "issue 412"
   ```
3. Commit the failing test only if the project allows a red commit on a branch. Otherwise keep it staged with the fix.
4. Fix the code. Run the test again. It passes.
5. Run the full suite.
6. Put the failure output from step 2 in the PR under Tests.

## 4. Write the tests

- One behavior per test. The name states the behavior and the expected result.
- Arrange seeded data in the test or a fixture. Never depend on another test's data.
- Integration tests isolate data: a rolled-back transaction, a unique schema, or unique IDs.
- E2E selectors: `getByRole` and accessible names first, `data-testid` second.
- Wait for conditions, never for time.
- Add the deny paths for any auth or access change: 401, 403 or 404, wrong role, bad token.
- Delegate a large batch to the `test-writer` subagent with the plan from step 1.

## 5. Run and check

```bash
make verify            # or the project's test command
```

- Each new test failed before the change and passes after it.
- No `.only`, `.skip`, or retries were needed.

## 6. Flaky tests

1. Run the test 20 times to confirm: `for i in $(seq 20); do npx vitest run file -t name || break; done`, `pytest --count 20` (needs pytest-repeat), `go test -count 20 -run Name`.
2. Find the cause: shared state, ordering, timers, real network, real clock, animation.
3. Fix it. Run 20 times again.
4. If you cannot fix it now, quarantine only with an issue link and a fix-by date next to the marker, and a `Test-Change-Reason:` trailer on the commit. Never quarantine a security or regression test.
5. Report the retry count. A pass after a retry is not a pass.

## Output

- The plan from step 1.
- The tests written, with file paths.
- The command and the result.
- Any level you could not set up, with the reason, under Blocked.
