---
name: verify-spec
description: Verify a change against its acceptance criteria by driving the real app locally. Web with headless Playwright, mobile with Android emulator, iOS Simulator, or Maestro, CLIs with golden files, APIs with curl and schema checks. Captures evidence and writes the Verification section of the PR. Use after the tests pass and before opening the PR for any user-visible change.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# /verify-spec: check the running app against the spec

**Arguments:** `$ARGUMENTS` (acceptance criteria, an issue, or a spec path)

Read `.claude/rules/agentic-verification.md` first.

Never use production URLs, shared staging with real users, or real user accounts. Use the local stack and seeded test accounts only.

## 1. Build the checklist

1. Collect the criteria from the task, the issue, the PR, or `docs/specs/`.
2. Write one line per criterion with an observable result.
3. Create the evidence folder:
   ```bash
   RUN=".claude/runs/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$RUN/evidence"; echo "$RUN"
   ```

## 2. Detect the app type

```bash
ls package.json app.json app.config.* playwright.config.* .maestro Cargo.toml go.mod pyproject.toml *.xcodeproj android ios compose.yaml docker-compose.yml Makefile 2>/dev/null
grep -E '"(dev|start|serve|preview)"' package.json 2>/dev/null
```

Web, mobile, CLI, API, or library. A project can be more than one.

## 3. Start the local stack

Use the project's own commands. Look in `CLAUDE.md`, `Makefile`, `package.json`, and `compose.yaml`. Typical:

```bash
supabase start                      # if supabase/ exists
docker compose up -d                # if a compose file exists
npm run dev > "$RUN/evidence/server.log" 2>&1 &
npx wait-on http://localhost:3000   # or: until curl -sf localhost:3000 >/dev/null; do sleep 1; done
```

Run the seed script so the test accounts exist. Stop background processes when you finish.

## 4. Drive the app

### Web

- Run the existing e2e suite first: `npx playwright test --reporter=line`.
- For a criterion the suite does not cover, write a throwaway script in `$RUN/check.spec.ts` and run it:
  ```bash
  npx playwright test "$RUN/check.spec.ts" --trace on --output "$RUN/evidence"
  ```
  Save a screenshot per criterion: `await page.screenshot({ path: process.env.RUN + '/evidence/<name>.png', fullPage: true })`.
- A single page: `npx playwright screenshot --full-page http://localhost:3000/path "$RUN/evidence/page.png"`.
- Collect console errors with `page.on('console')` and `page.on('requestfailed')`. Run axe with `@axe-core/playwright` on touched pages.
- Never run `npx playwright codegen` in an autonomous run. It needs a human at the keyboard.
- Playwright MCP is fine when configured. Use Claude in Chrome only in attended sessions.

### Android (emulator)

```bash
emulator -list-avds
emulator -avd <name> -no-window -no-audio -no-boot-anim > "$RUN/evidence/emulator.log" 2>&1 &
adb wait-for-device && until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 2; done
adb install -r path/to/app.apk
adb shell am start -n <package>/<activity>
adb exec-out screencap -p > "$RUN/evidence/<name>.png"
adb logcat -d > "$RUN/evidence/logcat.txt"
maestro test .maestro/            # if flows exist
```

Linux needs KVM (`ls /dev/kvm`). WSL2 needs nested virtualization. Without it, mark the criteria NOT VERIFIED.

### iOS (Simulator, macOS only)

```bash
xcrun simctl list devices available
xcrun simctl boot "<device name>"
xcrun simctl install booted path/to/App.app
xcrun simctl launch booted <bundle id>
xcrun simctl io booted screenshot "$RUN/evidence/<name>.png"
maestro test .maestro/            # if flows exist
```

On Linux or WSL, mark iOS criteria NOT VERIFIED.

### CLI or binary

```bash
make build                                    # or cargo build --release, go build ./cmd/...
./bin/tool < fixtures/input.txt > "$RUN/evidence/out.txt" 2> "$RUN/evidence/err.txt"; echo "exit=$?" >> "$RUN/evidence/out.txt"
diff -u fixtures/expected.txt "$RUN/evidence/out.txt"
```

Check `--help`, a bad argument (non-zero exit, message on stderr), and an empty input.

### API

```bash
TOKEN=$(curl -sf -X POST localhost:3000/auth/login -H 'content-type: application/json' -d '{"email":"seed-user@example.test","password":"<seed password from the seed script>"}' | jq -r .token)
curl -s -w '\n%{http_code}\n' -H "authorization: Bearer $TOKEN" localhost:3000/api/items > "$RUN/evidence/items.txt"
curl -s -w '\n%{http_code}\n' localhost:3000/api/items > "$RUN/evidence/items-noauth.txt"   # expect 401
```

Validate bodies against the OpenAPI or JSON schema when one exists (for example `npx ajv validate`).

## 5. Judge each criterion

- Open every screenshot with the Read tool. Compare it to the criterion: text, state, layout, error messages.
- Read the logs for errors and crashes.
- Mark PASS, FAIL, or NOT VERIFIED, with the evidence path.
- FAIL: fix the code, rerun the tests, then verify again. After 3 failed approaches, record it under Blocked.

## 6. Automate what you checked

Turn each passing manual check into an e2e, Maestro, contract, or golden-file test when practical. Commit it. Delete the throwaway script in `$RUN`.

## 7. Write the Verification section

```markdown
## Verification

| Criterion | Result | Evidence |
|---|---|---|
| <criterion> | PASS | .claude/runs/<id>/evidence/<file> |
| <criterion> | NOT VERIFIED | <reason> |
```

## Platform notes

- Linux and WSL2 need browsers: `npx playwright install chromium`. `--with-deps` installs system packages with sudo. Never run that in an autonomous run. Record the missing packages under Blocked.
- The Android emulator needs KVM on Linux. WSL2 needs nested virtualization enabled on the host.
- The iOS Simulator runs on macOS only.
- Never claim a criterion verified when the environment could not run it.
