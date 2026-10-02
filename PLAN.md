# Claude framework plan

Status: v0.1 is built. README.md describes what shipped. The plugin is named `agent-guardrails`, because Claude Code reserves the `claude-` prefix.

A reusable set of rules, settings, hooks, skills, and agents for building production software with autonomous Claude Code agents. Works for web apps, mobile apps, services, and binaries.

## Principles

1. The harness enforces, CLAUDE.md informs. Any rule that must hold goes into a hook, a permission, or the sandbox. Prose rules are for judgment calls only.
2. Deny by default. Every route needs auth, every query is parameterized, and every input gets validation at the boundary.
3. Agents never ship. They branch, commit, open a PR, and stop. Merge, deploy, release, and secrets stay with a human.
4. A base layer plus stack overlays. The base is stack-agnostic. Supabase, Expo/EAS, Rust, and similar live in overlays.

## Repo layout

```
claude-framework/
  README.md
  install.sh                  # installs into a target repo: copy or symlink, merge settings
  templates/
    CLAUDE.md                 # project root template, short, links to rules
    SECURITY.md, THREAT_MODEL.md, ADR.md
    ci/github/                # gitleaks, semgrep, osv-scanner, trivy, codeql, tests
  rules/                      # -> .claude/rules/*.md, loaded by path frontmatter
    security.md  auth.md  api.md  backend.md  frontend.md
    data-migrations.md  mobile.md  binaries-cli.md  testing.md  dependencies.md
  settings/
    base.json                 # project .claude/settings.json
    autonomous.json           # unattended profile (generalized from yours)
    overlays/                 # supabase, expo-eas, node, rust, go, python, docker, terraform
  hooks/
    session-start/            # git-state, stack-detect, toolchain-check, rules digest
    pre-tool/                 # bash-guard, secret-write-guard, protected-paths, test-guard
    post-tool/                # format + lint the edited file
    stop/                     # test-gate, diff secret scan, diff SAST
  skills/
    pr-review/ vulnscan/ unslop/ review-security/   # copied from ~/.claude/skills
    feature/ threat-model/ api-design/ auth-change/
    add-dependency/ db-migration/ release-prep/ blocked-report/ adr/
  agents/                     # subagents
    security-reviewer.md  test-writer.md  architect.md (read-only)
  output-styles/
    terse.md  autonomous.md
```

## Autonomy tiers

| Tier | Agent may | Examples |
|---|---|---|
| Green | Do it, no flag | Feature code, tests, refactors, docs, local builds |
| Yellow | Do it on a branch, flag it in the PR, and require a human review label | Auth, crypto, session handling, migrations, CI files, new dependencies, permission or RLS changes, infra |
| Red | Never | Merge, push to main, force push, deploy, release, store submit, read or write secrets, touch prod data |

Hooks enforce Red. The `protected-paths` hook enforces Yellow: an edit to a Yellow path adds a required `Security-Review:` note to the PR body.

## Domain rules (rules/*.md)

- Frontend: no secrets in the bundle, server-side authz only, CSP, no raw HTML injection, sanitize URLs, env vars with a public prefix are public.
- Backend: schema validation at every entry point (zod, pydantic, serde), parameterized queries, least-privilege service accounts, structured logs with no PII or tokens, errors without stack traces.
- Auth: use a vetted provider or library. Never write your own crypto. Argon2id for passwords. Cookies are HttpOnly, Secure, SameSite. Short-lived access tokens with rotating refresh tokens. Deny-by-default RLS or policy layer. Tests cover IDOR and privilege escalation.
- API: authn on by default with an explicit public allowlist, OpenAPI or schema contract first, rate limits, idempotency keys on writes, pagination limits, versioning, one error shape.
- Security: secrets from env or a secret manager only, lockfiles committed, pinned CI actions by SHA, SBOM on release, dependency add needs the `add-dependency` skill.
- Mobile: secure storage for tokens, cert pinning decision recorded, no secrets in the app binary, deep link validation.
- Binaries and CLIs: reproducible builds, signed releases, no shell interpolation of user input, safe temp files.
- Testing: tests come before or with the code, no skipped tests, coverage on auth and authz paths is mandatory.

## Settings

- `base.json`: allowlist read-only and build commands, deny secret reads, enable the sandbox with filesystem `denyRead` on `.env*`, keys, and `~/.ssh`, `~/.aws`, `~/.config/gh`.
- `autonomous.json`: your current file, split. Generic denies (git push main, force push, reset --hard, gh pr merge, env dumps) stay in it. Supabase and EAS denies move to overlays.
- Fake credentials in `env` (like your Supabase token) stay. They make an accidental prod call fail closed.

Gap in the current profile: `Bash(...)` deny patterns are prefix matches and are easy to route around (`git -C . push origin main`, `bash -c "..."`, `head .env`). Back them with a `bash-guard` PreToolUse hook that parses the command, and with the sandbox for file reads.

## Hooks

| Event | Hook | Action |
|---|---|---|
| SessionStart | git-state, stack-detect, toolchain-check | Inject branch, detected stack, missing tools, active tier rules |
| PreToolUse Bash | bash-guard | Block Red commands in any form, exit 2 with the reason |
| PreToolUse Bash | test-guard (yours) | Block commits that weaken tests |
| PreToolUse Edit/Write | secret-write-guard | Block writes that contain key patterns (gitleaks rules) |
| PreToolUse Edit/Write | protected-paths | Flag Yellow paths, block lockfile hand edits |
| PostToolUse Edit/Write | format-lint | Run the formatter and linter on the changed file, feed errors back |
| Stop | test-gate (yours) | Run tests before the agent may stop |
| Stop | diff-scan | gitleaks plus semgrep on the branch diff |

## Skills

Copy as is: `pr-review`, `vulnscan`, `unslop`, `review-security`.

New:
- `feature`: spec, threat notes, tests, code, self-review, PR. The main autonomous loop.
- `threat-model`: STRIDE pass on a feature or service, writes `THREAT_MODEL.md`.
- `api-design`: contract first, then handlers and tests.
- `auth-change`: checklist for any Yellow auth edit, runs `review-security` at the end.
- `add-dependency`: checks license, maintenance, advisories, size. Records the reason in the PR.
- `db-migration`: reversible migrations, backfill plan, no destructive change without a two-step plan.
- `release-prep`: changelog, version bump, SBOM, checklist for the human. Never runs the release.
- `blocked-report`: the stop report an autonomous agent writes when it cannot finish.
- `adr`: records an architecture decision.

## CLAUDE.md

The template stays under 100 lines: the project purpose, stack, commands (build, test, lint), the tier table, and links to `rules/`. Long guidance goes into rules or skills so it only loads when relevant.

## Platform support

| Platform | Settings, skills, hooks | Sandbox |
|---|---|---|
| Linux | Yes | Yes (bubblewrap) |
| WSL2 | Yes, keep repos on the Linux filesystem | Yes (bubblewrap) |
| WSL1 | Yes | No, so hooks are the only guard |
| macOS | Yes | Yes (Seatbelt) |
| Desktop app, Code tab | Yes, reads the same `~/.claude` and `.claude/` | Same as the host OS |
| Desktop app, chat | Skills only, uploaded as a zip. No hooks or settings | No |
| Native Windows | Hooks run in Git Bash | No |

Portability rules for hooks:
- Use `#!/usr/bin/env bash` and write for bash 3.2, which macOS ships. No `mapfile`, `${var,,}`, or associative arrays.
- No GNU-only flags: `sed -i`, `grep -P`, `date -d`, `readlink -f`. Use a `lib/portable.sh` with helpers instead.
- GUI apps on macOS do not load your shell PATH. Each hook prepends `/opt/homebrew/bin:/usr/local/bin`.
- `jq`, `gitleaks`, and `semgrep` are dependencies. `toolchain-check` reports what is missing. Each hook fails closed for Red checks and fails open for lint.
- Hook paths use `$CLAUDE_PROJECT_DIR` or `${CLAUDE_PLUGIN_ROOT}`, never `$HOME/...` hard-coded.
- CI runs the hook test suite on `ubuntu-latest` and `macos-latest`.

The autonomous profile starts with `claude --settings settings/autonomous.json`. That flag only exists in the CLI. Desktop sessions get the attended base profile.

## Phases

1. Copy the four skills, the two output styles, and your hooks. Split `settings.autonomous.json` into base, autonomous, and overlays.
2. Write `bash-guard`, `secret-write-guard`, `protected-paths`, and `format-lint`. Add tests for each hook.
3. Write the rules files and the CLAUDE.md template.
4. Write the new skills and the three subagents.
5. Write the CI templates and `install.sh`.
6. Dogfood on one web app and one mobile app. Run `vulnscan` against the output.

## Open decisions

- Distribution: a Claude Code plugin for skills, hooks, and agents, plus `install.sh` for settings and CLAUDE.md. Plugins cannot set permissions. (Recommended)
- Or copy only, through `install.sh`. Simpler, but updates do not propagate.
