# claude-framework

Rules, guards, and skills for writing production software with Claude Code agents, attended or unattended. It works for web apps, mobile apps, services, and binaries.

The framework has two parts:

- A Claude Code plugin named `agent-guardrails`, with hooks, skills, and subagents. The hooks run on every tool call. They block what an agent must never do and check what it did before it may stop.
- `install.sh`, which writes the project files a plugin cannot set: permissions, the autonomous profile, domain rules, output styles, and templates.

## Principles

1. Hooks and settings enforce the rules. CLAUDE.md explains them. Any rule that must hold is a hook, a permission, or the sandbox. Prose covers judgment calls only.
2. Deny by default. Every route needs auth, every query takes parameters, and every input gets validation at the boundary.
3. Agents never ship. They branch, commit, open a PR, and stop. Merge, deploy, release, and secrets stay with a human.
4. One base and many overlays. The base works for any stack. Stack-specific rules live in overlays.

## Tiers

| Tier | Agent may | Examples | Enforced by |
|---|---|---|---|
| Green | Do it | Feature code, tests, refactors, docs, local builds | - |
| Yellow | Do it on a branch. The PR needs a `Security-Review:` section and a human review | Auth, crypto, sessions, migrations, CI, infra, dependency manifests | `yellow-notice`, `pr-gate` |
| Red | Never | Merge, push to a protected branch, force push, deploy, publish, secrets, prod data, edit agent settings | `bash-guard`, `protected-paths`, `secret-write-guard`, permission denies |

## Install

Requirements: `git`, `jq`. Recommended: `gitleaks`, `semgrep`, `gh`.

```sh
# macOS
brew install jq gitleaks semgrep gh
# Debian, Ubuntu, WSL2
sudo apt install jq gh && pipx install semgrep   # gitleaks: see github.com/gitleaks/gitleaks/releases
```

Then, from a clone of this repo:

```sh
./install.sh ~/code/my-app                 # detect stack overlays
./install.sh --overlay node,supabase ~/code/my-app
./install.sh --dry-run ~/code/my-app       # show what changes
./install.sh --git-hooks ~/code/my-app     # also run security-check.sh on commit and push
```

GitHub files (PR template, workflows, Dependabot) are written only when the project's `origin` is on github.com. Use `--ci github` or `--ci none` to choose. Every check also runs locally with no CI service, through `scripts/security-check.sh` and the git hooks.

Install the plugin, from the terminal or inside Claude Code:

```sh
claude plugin marketplace add <owner>/<repo>   # the GitHub repo you cloned, or a git URL, or a local path
claude plugin install agent-guardrails@agent-guardrails
```

The installed `.claude/settings.json` also lists the marketplace and enables the plugin, so a teammate who opens the project gets a prompt to install it.

Re-running `install.sh` is safe. It merges settings again, keeps files you edited, and reports each one it kept. Pass `--force` to replace templates; it keeps a `.bak` copy.

## Unattended runs

```sh
scripts/claude-autonomous.sh "Add rate limiting to POST /login"
scripts/claude-autonomous.sh -f task.md
```

This starts `claude -p` with `.claude/settings.autonomous.json`. That profile turns on the Autonomous output style, the test gate, the test guard, SAST on stop, and a stricter deny list (global installs, cloud CLIs). The agent works on a branch, loops build and test until green, and verifies the change against the spec in a real browser, emulator, or binary run. It ends with a PR on GitHub (`gh`), a merge request on GitLab (`glab`), or a PR on Gitea and Forgejo (`tea`). With no forge CLI or no remote, it leaves the branch and the PR body in `.claude/runs/pr-body.md`. A run it cannot finish ends with a draft and a Blocked report.

## What is in the box

### Hooks (plugin)

| Event | Hook | What it does |
|---|---|---|
| SessionStart | `session-start` | Profile rules, git state, protected-branch warning, detected stack, missing tools |
| PreToolUse Bash | `bash-guard` | Blocks Red commands in any spelling: `git -C . push origin main`, `bash -c "..."`, `head .env`, `curl \| sh`, deploys, publishes, destructive SQL, `rm -rf` outside the project |
| PreToolUse Bash | `pr-gate` | `gh pr create`, `glab mr create`, and `tea pr create` need a `Security-Review:` section when the branch touches Yellow paths |
| PreToolUse Bash | `test-guard` | Blocks a commit that skips tests or removes assertions (autonomous) |
| PreToolUse Edit/Write | `protected-paths` | Blocks secrets, lockfiles, agent settings, git internals, files outside the project |
| PreToolUse Edit/Write | `secret-write-guard` | Blocks content that contains a credential |
| PostToolUse Edit/Write | `yellow-notice` | Flags a Yellow edit and states the extra duties |
| PostToolUse Edit/Write | `format-lint` | Runs the project formatter and linter on the file |
| Stop | `diff-scan` | Secret scan (gitleaks or built-in patterns) on changed files; semgrep in autonomous runs |
| Stop | `test-gate` | Runs the tests before the agent may stop (autonomous) |

### Skills (plugin)

| Skill | Use |
|---|---|
| `feature` | The main loop: spec, threat notes, tests, code, self-review, verification, PR |
| `test-strategy` | Pick test levels (unit, integration, contract, regression, e2e) and set up test tools |
| `verify-spec` | Drive the running app (headless browser, Android emulator, iOS simulator, CLI, API) and check each acceptance criterion, with evidence |
| `threat-model` | STRIDE pass, writes `docs/THREAT_MODEL.md` |
| `api-design` | Contract first, then handlers and contract tests |
| `auth-change` | Checklist for any auth, session, or crypto edit |
| `add-dependency` | Vet a package before you add it |
| `db-migration` | Reversible, expand and contract, local DB only |
| `release-prep` | Changelog, version, SBOM, human checklist (user-only) |
| `blocked-report` | Final report and draft PR when a run cannot finish |
| `adr` | Architecture decision record |
| `pr-review` | Peer review of a branch or PR |
| `review-security` | Adversarial security review |
| `vulnscan` | Random-file vulnerability sweep with parallel scouts |
| `unslop` | Remove AI tells from prose that ships |

### Subagents (plugin)

`security-reviewer` (read-only), `test-writer` (test files only), `architect` (read-only).

### Project files (`install.sh`)

| File | Content |
|---|---|
| `.claude/settings.json` | Base permissions and stack overlays, merged into your file |
| `.claude/settings.autonomous.json` | The same, plus the autonomous profile and cloud CLI denies |
| `.claude/rules/*.md` | Security, auth, API, backend, frontend, data, mobile, CLI, testing, agentic verification, dependencies, CI/CD, logging |
| `.claude/output-styles/` | Terse (attended) and Autonomous (unattended) |
| `CLAUDE.md` | Project template under 100 lines |
| `SECURITY.md`, `.claude/pull_request_template.md` | Disclosure policy and a PR template with `Security-Review:` and `Verification` |
| `scripts/security-check.sh` | Local scans: secret files, gitleaks, semgrep, osv-scanner, trivy. `--staged` and `--changed` modes |
| `scripts/claude-autonomous.sh` | Starts an unattended run |
| `.githooks/` (`--git-hooks`) | pre-commit and pre-push run `security-check.sh` |
| `.github/` (GitHub remotes only) | PR template, security workflow, Dependabot |

### Overlays

`node`, `python`, `rust`, `go`, `docker`, `terraform`, `supabase`, `expo-eas`, `cloud`, `sandbox`.

## Configuration

Set these in the `env` block of the project `.claude/settings.json`.

| Variable | Effect |
|---|---|
| `FW_GUARD_ALLOW` | ERE. A matching command skips `bash-guard`. For a human-approved exception, such as `^make deploy-staging$` |
| `FW_RED_PATHS_EXTRA`, `FW_YELLOW_PATHS_EXTRA` | ERE. Extra Red or Yellow paths |
| `FW_SECRET_ALLOW` | ERE. Lines that never count as secrets |
| `FW_TEST_GATE=always`, `FW_TEST_GUARD=always`, `FW_SAST=always` | Run those checks in attended sessions too |
| `CLAUDE_TEST_CMD` | The test command for `test-gate`. The default is detected |
| `CLAUDE_TEST_TIMEOUT`, `CLAUDE_TEST_MAX_ATTEMPTS` | Test gate limits |
| `FW_SEMGREP_CONFIG` | semgrep rules. The default is `p/default` |
| `FW_FORMAT_LINT=off` | Turn off `format-lint` |
| `FW_SESSION_GIT=0`, `FW_SESSION_TOOLS=0` | Hide those sections of the session context |

## Platforms

| Platform | Hooks, skills, settings | Sandbox overlay |
|---|---|---|
| Linux | Yes | Yes, needs bubblewrap |
| WSL2 | Yes. Keep repos on the Linux filesystem | Yes, needs bubblewrap |
| WSL1 | Yes | No |
| macOS | Yes | Yes |
| Claude Desktop, Code tab | Yes, same `~/.claude` and `.claude/` | Same as the host |
| Claude Desktop, chat | Skills only, uploaded as a zip | No |
| Native Windows | Hooks run under Git Bash. Not tested | No |

Hooks are bash scripts that run through `bash` explicitly, so a zsh login shell does not matter. They target bash 3.2, which macOS ships, and work with both BSD and GNU tools. `scripts/verify.sh` runs the tests under bash 3.2: `/bin/bash` on macOS, or a container elsewhere.

`scripts/claude-autonomous.sh` needs the CLI. The Desktop app has no `--settings` flag, so Desktop sessions run the attended profile.

## Limits

- Hooks do not isolate the agent. A process can still write a script file and run it, and no hook reads that file. Turn on the `sandbox` overlay where it is available, and keep production credentials off the machine.
- `bash-guard` matches patterns and does not fully parse shell. `hooks/tests/run.sh` lists each spelling it blocks.
- Path-scoped rules in `.claude/rules/` may not load on their own in every Claude Code version. `CLAUDE.md` tells the agent to read the matching file before it changes an area.

## Development

Everything is verified locally. No CI service is needed.

```sh
make verify          # JSON, shellcheck, hook tests, installer tests, plugin manifest, bash 3.2
make verify-quick    # the same without the bash 3.2 container
make test            # hook and installer tests only
```

`verify.sh` prints SKIP, not PASS, for any check whose tool is missing (shellcheck, the claude CLI, docker). Run it on macOS and on Linux before a release. `.github/workflows/test.yml` is an optional wrapper that runs the same script.

Test a local checkout as a plugin: `./install.sh --plugin-local <project>`, then `claude plugin marketplace add "$PWD"`.
