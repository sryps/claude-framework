# claude-framework

Rules, guards, and skills for writing production software with Claude Code agents, attended or unattended. It works for web apps, mobile apps, services, and binaries.

Everything lives in the project's `.claude/` directory: settings, hooks, skills, subagents, rules, and output styles. It travels with the repo, so every clone, every teammate, and every agent run gets the same guards. Nothing is installed globally.

The hooks run on every tool call. They block what an agent must never do and check what it did before it may stop.

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

## Start a project

Requirements: `git`, `jq`. Recommended: `gitleaks`, `semgrep`, and a forge CLI (`gh`, `glab`, or `tea`).

```sh
# macOS
brew install jq gitleaks semgrep
# Debian, Ubuntu, WSL2
sudo apt install jq && pipx install semgrep   # gitleaks: see github.com/gitleaks/gitleaks/releases
```

### New project: fork or use as a template

1. Fork this repo, or use it as a template, and clone it.
2. Pick the stack overlays and write the settings:
   ```sh
   .claude/framework/install.sh                         # detect overlays from the files present
   .claude/framework/install.sh --overlay node,supabase # or name them
   ```
3. Replace this README with your project's README. The framework docs stay in `.claude/framework/README.md`.
4. Fill in the placeholders in `CLAUDE.md`.
5. Start Claude Code in the repo. It loads `.claude/` on its own.

Pull framework updates from upstream like any other change: `git remote add upstream <framework repo URL>`, then `git fetch upstream && git merge upstream/main`.

### Existing project: copy the framework in

From a clone of this repo:

```sh
.claude/framework/install.sh ~/code/my-app             # detect overlays
.claude/framework/install.sh --dry-run ~/code/my-app   # show what changes
.claude/framework/install.sh --git-hooks ~/code/my-app # also run security-check.sh on commit and push
```

This copies `.claude/{hooks,skills,agents,rules,output-styles,framework}`, `scripts/`, and `.githooks/` into the project. It merges the framework settings into any `.claude/settings.json` already there. To update, run the same command from a newer checkout. A framework file you edited is kept and reported. `--force` replaces it and keeps a `.bak` copy. `.claude/framework/manifest.tsv` records what was installed.

GitHub files (PR template, workflows, Dependabot) are written only when the project's `origin` is on github.com. Use `--ci github` or `--ci none` to choose. Every check also runs locally with no CI service, through `scripts/security-check.sh` and the git hooks.

## Unattended runs

```sh
scripts/claude-autonomous.sh "Add rate limiting to POST /login"
scripts/claude-autonomous.sh -f task.md
```

This starts `claude -p` with `.claude/settings.autonomous.json`. That profile turns on the Autonomous output style, the test gate, the test guard, SAST on stop, and a stricter deny list (global installs, cloud CLIs). The agent works on a branch, loops build and test until green, and verifies the change against the spec in a real browser, emulator, or binary run. It ends with a PR on GitHub (`gh`), a merge request on GitLab (`glab`), or a PR on Gitea and Forgejo (`tea`). With no forge CLI or no remote, it leaves the branch and the PR body in `.claude/runs/pr-body.md`. A run it cannot finish ends with a draft and a Blocked report.

## What is in the box

### Hooks (`.claude/hooks/`)

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

### Skills (`.claude/skills/`)

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

### Subagents (`.claude/agents/`)

`security-reviewer` (read-only), `test-writer` (test files only), `architect` (read-only).

### Settings and other files

| File | Content |
|---|---|
| `.claude/settings.json` | Base permissions, hook wiring, and stack overlays |
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
| `FW_MAINTAINER=1` | Framework development only. Hooks, `.claude/framework/`, and git hooks become Yellow. Set it by hand in `.claude/settings.local.json` |

### What an agent may change in `.claude/`

| Path | Tier |
|---|---|
| `.claude/settings*.json`, `.mcp.json`, `.git/` | Red, always |
| `.claude/hooks/`, `.claude/framework/`, `.githooks/`, `scripts/security-check.sh`, `scripts/claude-autonomous.sh` | Red. Yellow with `FW_MAINTAINER=1` |
| `.claude/skills/`, `.claude/agents/`, `.claude/rules/`, `.claude/output-styles/` | Yellow. A project may tune them, with review |

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

Hooks are bash scripts that run through `bash` explicitly, so a zsh login shell does not matter. They target bash 3.2, which macOS ships, and work with both BSD and GNU tools. `.claude/framework/verify.sh` runs the tests under bash 3.2: `/bin/bash` on macOS, or a container elsewhere.

`scripts/claude-autonomous.sh` needs the CLI. The Desktop app has no `--settings` flag, so Desktop sessions run the attended profile.

## Limits

- Hooks do not isolate the agent. A process can still write a script file and run it, and no hook reads that file. Turn on the `sandbox` overlay where it is available, and keep production credentials off the machine.
- `bash-guard` matches patterns and does not fully parse shell. `.claude/framework/tests/hooks-test.sh` lists each spelling it blocks.
- A skill with the same name in `~/.claude/skills/` may shadow the project's copy. Remove or rename the personal copy if they differ.
- Path-scoped rules in `.claude/rules/` may not load on their own in every Claude Code version. `CLAUDE.md` tells the agent to read the matching file before it changes an area.

## Development

Everything is verified locally. No CI service is needed.

```sh
.claude/framework/verify.sh          # JSON, settings drift, shellcheck, hook tests, installer tests, bash 3.2
.claude/framework/verify.sh --quick  # the same without the bash 3.2 container
```

`verify.sh` prints SKIP, not PASS, for any check whose tool is missing (shellcheck, docker). Run it on macOS and on Linux before a release. `.github/workflows/test.yml` is an optional wrapper that runs the same script.

This repo runs under its own guards. To change hooks or framework files with Claude, a human sets `FW_MAINTAINER=1` in `.claude/settings.local.json`:

```json
{ "env": { "FW_MAINTAINER": "1" } }
```

## License

MIT. See [LICENSE](LICENSE).
