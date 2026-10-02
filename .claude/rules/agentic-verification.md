---
paths:
  - "**/e2e/**"
  - "**/*.spec.*"
  - "**/app/**"
  - "**/pages/**"
  - "**/routes/**"
  - "**/screens/**"
  - "**/components/**"
  - "**/views/**"
  - "**/cmd/**"
  - "**/bin/**"
  - "**/main.*"
  - "**/.maestro/**"
  - "**/api/**"
---

# Agentic verification

Tests prove that the code does what the tests say. This file covers the next step: the agent drives the real app and checks it against the spec. Run the `verify-spec` skill for the steps.

## When it applies

- MUST verify every user-visible change: UI, screens, routes, API responses, CLI output, exit codes.
- A pure refactor with no behavior change needs the test suite only. Say so in the PR.

## The checklist

- MUST turn each acceptance criterion into one checklist line with an observable result. "User can reset a password" becomes "Submitting a valid email on /reset shows 'Check your inbox' and creates one reset token row".
- Criteria come from the task, the issue, the PR, or `docs/specs/`. If none exist, write them first and put them in the PR.
- Each line ends as PASS, FAIL, or NOT VERIFIED. Each PASS or FAIL has an evidence path.

## Environment

- MUST run the app locally: local server, local database, seeded data.
- MUST NOT point at production, shared staging with real users, or real user accounts.
- MUST use seeded test accounts only. Create them in the seed script.
- Third-party services run in test mode or through a local fake (Stripe test keys from the environment, a local SMTP catcher such as Mailpit).

## Tools by app type

| App type | Drive it with |
|---|---|
| Web | Playwright CLI or Playwright MCP, headless. Claude in Chrome in attended sessions only |
| React Native, Expo | Maestro flows or Detox, on an Android emulator or iOS Simulator |
| Android native | Android emulator with `adb`, Espresso |
| iOS native | iOS Simulator with `xcrun simctl`, XCUITest. macOS only |
| CLI, binary | Run the built binary against fixture inputs. Compare output to golden files. Check exit codes |
| API | `curl` or `httpie` against the local server. Validate responses against the schema |
| Library | Run the examples or a small consumer script against the built package |

## Evidence

- MUST save evidence under `.claude/runs/<run-id>/evidence/`. Use the timestamp as the run id: `date +%Y%m%d-%H%M%S`.
- Web: a screenshot per criterion, a Playwright trace on failure, console errors, failed network requests.
- Mobile: a screenshot per criterion, the device log (`adb logcat -d`, `xcrun simctl spawn booted log show`).
- CLI and API: the exact command, its output, and its exit code.
- MUST look at each screenshot with the Read tool before marking a UI criterion PASS. A screenshot nobody looked at is not evidence.
- Evidence MUST NOT contain secrets or real personal data. Seeded data only.

## Quality checks during verification

- Web: no console errors and no failed requests on the pages you touched. Run axe (`@axe-core/playwright`) on those pages. Fix serious and critical violations.
- Mobile: no crash or red box in the device log. Labels exist for touch targets.
- CLI: `--help` works. Errors go to stderr with a non-zero exit code.
- API: errors use the documented error shape and leak no stack traces.

## From manual to automated

- Turn each manual check that passed into an automated e2e or contract test when practical. Commit it with the change.
- If automation is not practical, say why in the PR.

## When the environment cannot run

- Examples: no browsers installed, no KVM for the Android emulator, no macOS for the iOS Simulator, a service that needs real credentials.
- MUST mark the affected criteria NOT VERIFIED. MUST NOT claim them as verified.
- Record the cause and the exact command that failed under Blocked.
- MUST NOT install system packages with sudo in an autonomous run. Record the missing package under Blocked.

## PR section

Add this to the PR body after Tests:

```markdown
## Verification

| Criterion | Result | Evidence |
|---|---|---|
| Valid email on /reset shows confirmation | PASS | .claude/runs/20261001-1412/evidence/reset-ok.png |
| Unknown email shows the same message | PASS | .claude/runs/20261001-1412/evidence/reset-unknown.png |
| Reset link expires after 30 min | NOT VERIFIED | Needs clock control; covered by unit test `reset_token_expiry` |
```

`.claude/runs/` is gitignored. Name the evidence files in the PR. Attach the key screenshots to the PR by hand if reviewers need them.

## Done means

- [ ] Each acceptance criterion has a checklist line and a result.
- [ ] Each PASS has evidence you looked at.
- [ ] No console errors, crashes, or serious accessibility violations on the touched screens.
- [ ] Manual checks became automated tests where practical.
- [ ] NOT VERIFIED lines have a reason, and Blocked has the failed command.
- [ ] Nothing ran against production or a real account.
