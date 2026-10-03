# {{PROJECT_NAME}}

{{One or two sentences: what this project does and who uses it.}}

## Stack

- Language and framework: {{e.g. TypeScript, Next.js 15}}
- Data: {{e.g. Postgres via Supabase, RLS on}}
- Auth: {{e.g. Supabase Auth, email and OAuth}}
- Hosting: {{e.g. Vercel, Fly.io, App Store and Play Store}}

## Commands

| Task | Command |
|---|---|
| Install | `{{npm ci}}` |
| Build | `{{npm run build}}` |
| Test | `{{npm test}}` |
| Lint | `{{npm run lint}}` |
| Typecheck | `{{npm run typecheck}}` |
| E2E / verify | `{{npx playwright test, maestro test .maestro/}}` |
| Verify (all of the above) | `{{make verify}}` |

The Stop hook runs `make verify` when that target exists. Keep it complete and fast. Include `scripts/security-check.sh --changed` in it.

## Tiers

| Tier | Scope | Rule |
|---|---|---|
| Green | Feature code, tests, docs, refactors, local builds | Do it. |
| Yellow | Auth, crypto, sessions, access control, migrations, CI, infra, dependency changes | Do it on a branch. Add a `Security-Review:` section to the PR. A human reviews before merge. |
| Red | Merge, push to a protected branch, force push, deploy, publish, secrets, production data | Never. Hooks warn. Record the need under Blocked. |

## Workflow

1. Start on a feature branch: `git switch -c <type>/<short-name>`.
2. Write the spec with the user (`spec` skill). The user approves it with `scripts/approve-spec.sh docs/specs/<feature>.md`. Code and test edits get a warning until then.
3. Read the rules file for each area you will change (list below).
4. Write or update tests first. Name the criterion each test proves (`AC-1`).
5. Make the smallest change that passes. Commit at each green state.
6. Run the verify command.
7. Run `review-security` when a Yellow path changed.
8. Open a PR or MR with the forge CLI (`gh`, `glab`, or `tea`) and a body from `.claude/pull_request_template.md`. With no forge, leave the branch and the body file.
9. Stop. Never merge. A human merges.

## Rules

Rules live in `.claude/rules/`. Claude Code may load them by path, but that is not guaranteed. Read the matching file before you change that area.

| File | Area |
|---|---|
| `security.md` | Always. Tiers, secrets, crypto, common bug classes |
| `specs.md` | Always. Specs, gaps, traceability from criterion to test |
| `auth.md` | Login, sessions, tokens, roles, policies, RLS |
| `api.md` | Routes, handlers, contracts, rate limits, webhooks |
| `backend.md` | Services, workers, data access, process safety |
| `frontend.md` | UI, browser security, CSP, XSS |
| `data-migrations.md` | Schema, migrations, RLS policies |
| `mobile.md` | iOS, Android, Expo, deep links, secure storage |
| `binaries-cli.md` | CLIs, scripts, releases |
| `testing.md` | Test levels, regression, e2e, flaky tests |
| `agentic-verification.md` | Driving the running app to check it against the spec |
| `dependencies.md` | Adding or updating packages |
| `ci-cd.md` | Workflows and pipelines |
| `logging-privacy.md` | Logs, telemetry, PII |

## Skills

| Skill | Use it when |
|---|---|
| `feature` | You build a feature end to end (the main loop) |
| `spec` | You start a feature, or the spec is too thin to test |
| `threat-model` | You add a service, trust boundary, or data store |
| `api-design` | You add or change an endpoint or contract |
| `auth-change` | You touch any auth, session, or access control file |
| `add-dependency` | You add a package |
| `db-migration` | You change the schema |
| `test-strategy` | You plan tests for a change or reproduce a bug |
| `verify-spec` | You check a user-visible change in the running app |
| `release-prep` | You prepare a release for a human to run |
| `blocked-report` | An unattended run cannot finish |
| `adr` | You make a decision that is hard to reverse |
| `pr-review` | You review a PR or branch |
| `review-security` | You review a change for security |
| `vulnscan` | You run a security sweep of the repo |
| `unslop` | You write prose that ships (docs, PR text, commits) |

## Project-specific notes

- {{Anything Claude must know that the code does not show: external systems, quirks, owners.}}
- {{Known traps: "the obvious approach X was tried and reverted because Y".}}
