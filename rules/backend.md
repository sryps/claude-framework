---
paths:
  - "**/server/**"
  - "**/backend/**"
  - "**/services/**"
  - "**/src/lib/**"
  - "**/internal/**"
  - "**/pkg/**"
  - "**/app/**/*.py"
  - "**/cmd/**"
  - "**/workers/**"
  - "**/jobs/**"
  - "**/supabase/functions/**"
---

# Backend services

## Input and data access

- Validate at every entry point: HTTP, queue consumer, cron input, CLI flag, webhook. Use zod/valibot (TS), pydantic (Python), `go-playground/validator` or explicit checks (Go), serde with `deny_unknown_fields` (Rust).
- Use parameterized queries or a query builder. MUST NOT build SQL with string concatenation or template strings.
- Raw SQL is allowed only with bound parameters. Identifiers (table, column, sort field) come from an allowlist.
- Scope every query by tenant or owner.
- Use transactions for multi-step changes. Pick the isolation level on purpose for money and counters.

## Process safety

- Never pass user input to a shell. Use an argv array (`execFile`, `subprocess.run([...], shell=False)`, `exec.Command`, `std::process::Command`).
- Never `eval`, `new Function`, `pickle.loads`, `yaml.load` (use `safe_load`), or deserialize untrusted data into code objects.
- File paths from users: resolve, then check the result stays under the allowed base directory.
- File uploads: check size, check content type by magic bytes, rename to a random name, store outside the web root or in object storage, and scan when the risk needs it.

## Resilience

- Set timeouts on all network calls, DB queries, and locks.
- Retry only idempotent operations, with backoff and jitter and a cap.
- Bound every queue, buffer, and in-memory cache.
- Graceful shutdown: stop accepting work, finish in-flight work, then exit.
- Health check endpoints reveal no versions or secrets.

## Config and secrets

- Load config from the environment once, at start. Validate it with a schema. Fail at start when a required value is missing.
- Separate config per environment. Never point a dev or test run at a production database.
- Service accounts get only the permissions they need.

## Error handling

- Catch errors at the boundary. Map them to the API error shape.
- Never swallow an error silently. Log it with context and a request ID.
- Panics and unhandled rejections crash the process and the supervisor restarts it. Do not keep running in a bad state.

## Per-stack notes

- Node/TS: `strict: true` in tsconfig. No `any` in new code. Use `helmet` (Express) or set headers in the framework.
- Python: type hints and `mypy` or `pyright`. Use `secrets`, not `random`, for tokens.
- Go: check every error. Use `context.Context` with deadlines. Run `go vet` and `govulncheck`.
- Rust: no `unwrap()` or `expect()` on input-driven paths. `unsafe` needs a comment that proves the invariant.
- Supabase Edge Functions: verify the JWT, create the client with the caller's token, use `service_role` only for server-only tasks, and never return it.

## Done means

- [ ] Every entry point validates input.
- [ ] No string-built SQL or shell.
- [ ] Timeouts on every outbound call.
- [ ] Errors are logged with a request ID and mapped to a safe client error.
