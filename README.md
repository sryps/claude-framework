# claude-framework

Rules, guards, and skills for writing production software with Claude Code agents, attended or unattended. It works for web apps, mobile apps, services, and binaries.

Everything lives in the project's `.claude/` directory: settings, hooks, skills, subagents, rules, and output styles. It travels with the repo, so every clone, every teammate, and every agent run gets the same guards. Nothing is installed globally.

The hooks run on every tool call. They recommend best practices: when an agent does something risky or skips a step, the hook tells the agent and shows you a one-line warning. Nothing is blocked unless you turn enforcement on.

## Recommendations, not enforcement

By default every hook is advisory:
- The action goes ahead.
- Claude gets the finding and the recommended fix as context.
- You see a one-line warning that starts with `!`.
- Framework permission rules are `ask` rules, so Claude Code asks you before, for example, reading `.env` or force-pushing. Nothing is a `deny` rule.
- The git hooks (`--git-hooks`) print `security-check.sh` findings and let the commit or push go through.

To make the hooks and git hooks block instead, set `FW_ENFORCE=1` in the `env` block of `.claude/settings.local.json` (just you) or `.claude/settings.json` (the whole team). Then a finding stops the tool call, the commit, or the stop, as earlier versions did.

## Principles

1. Recommend, explain, and let the human decide. The hooks point out risks and missing steps. `FW_ENFORCE=1` turns the same checks into blocks for teams that want that.
2. Deny by default. Every route needs auth, every query takes parameters, and every input gets validation at the boundary.
3. Agents never ship. They branch, commit, open a PR, and stop. Merge, deploy, release, and secrets stay with a human.
4. One base and many overlays. The base works for any stack. Stack-specific rules live in overlays.

## Specs and drift

Tests prove the code matches the spec. They cannot prove the spec matches what you meant. Where the spec is silent, the agent guesses, and each guess is a place where your intent and the code can drift apart.

So the recommended flow writes the spec first, with you:

1. The agent runs the `spec` skill. It explains what a spec is, asks you about each section (goal, permissions, criteria, edge cases, limits, scope), and drafts `docs/specs/<feature>.md`.
2. You read it and approve it: `scripts/approve-spec.sh docs/specs/<feature>.md`. The script refuses a spec with no criteria or with unfilled placeholders. The approval is yours; agents are told never to run it.
3. `spec-gate` warns on code and test edits until the branch has your approval. The approval holds the spec's hash, so if the spec changes, the warning comes back until you approve again.
4. For a change with no behavior to specify: `scripts/approve-spec.sh --no-spec "<reason>"`.

Then the agent builds against it:
- Each test names the criterion it proves (`AC-2`). Each criterion gets a Verification row in the PR.
- A gap found while coding goes into the spec, which sends it back to you for approval.
- Every code PR has a `## Spec gaps and assumptions` section listing what the agent decided for you.
- `pr-gate` warns when a code PR lacks your approval, tests (or a `No-Test-Reason:`), a filled Verification row, or the Spec gaps section.
- `test-guard` warns on a `fix:` commit with no test change.

`scripts/approve-spec.sh --status` shows the approval for the current branch. Commit `.claude/approvals/` with the branch, so reviewers see what you approved.

Autonomous runs cannot get an approval mid-run. Without one, the agent drafts the spec, commits it, and stops with a draft PR for you to approve.

## Tiers

| Tier | Recommendation | Examples | Flagged by |
|---|---|---|---|
| Green | Do it | Feature code, tests, refactors, docs, local builds | - |
| Yellow | Do it on a branch. The PR gets a `Security-Review:` section and a human review | Auth, crypto, sessions, migrations, CI, infra, dependency manifests | `yellow-notice`, `pr-gate` |
| Red | Don't. Ask the human | Merge, push to a protected branch, force push, deploy, publish, secrets, prod data, edit agent settings | `bash-guard`, `protected-paths`, `secret-write-guard`, permission `ask` rules |

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

Each hook warns by default and blocks with `FW_ENFORCE=1`.

| Event | Hook | What it flags |
|---|---|---|
| SessionStart | `session-start` | Profile rules, git state, protected-branch warning, detected stack, missing tools |
| PreToolUse Bash | `bash-guard` | Red commands in any spelling: `git -C . push origin main`, `bash -c "..."`, `head .env`, `curl \| sh`, deploys, publishes, destructive SQL, `rm -rf` outside the project |
| PreToolUse Bash | `pr-gate` | Gates `gh pr create`, `glab mr create`, and `tea pr create`. A branch that changes code needs test changes (or `No-Test-Reason:`), a filled Verification row, a `Spec:` line, and a Spec gaps section. A branch that touches Yellow paths needs a `Security-Review:` section naming each Yellow file (or a parent directory with a trailing slash). Empty sections and template placeholders do not count |
| PreToolUse Bash | `test-guard` | A `fix:` commit with no test change (escape: `No-Test-Reason:`), and a commit that skips tests or removes assertions (escape: `Test-Change-Reason:`). Every session |
| PreToolUse Edit/Write | `protected-paths` | Edits to secrets, lockfiles, agent settings, git internals, files outside the project |
| PreToolUse Edit/Write | `secret-write-guard` | Content that contains a credential |
| PreToolUse Edit/Write | `test-writer-scope` | The `test-writer` subagent editing anything but tests and fixtures |
| PreToolUse Edit/Write | `spec-gate` | Code and test edits before the user has approved the branch's spec and the spec is unchanged since |
| PostToolUse Edit/Write | `yellow-notice` | Flags a Yellow edit and states the extra duties |
| PostToolUse Edit/Write | `rules-notice` | Names the `.claude/rules/` file whose `paths:` match the file just written, once per rule per session. Claude Code loads a path-scoped rule only when Claude reads a matching file, never when it creates one |
| PostToolUse Edit/Write | `format-lint` | Runs the project formatter and linter on the file |
| Stop | `diff-scan` | Secret scan (gitleaks or built-in patterns) on changed files; semgrep in autonomous runs |
| Stop | `test-gate` | Runs the tests before the agent may stop (autonomous) |

### Skills (`.claude/skills/`)

| Skill | Use |
|---|---|
| `feature` | The main loop: spec, threat notes, tests, code, self-review, verification, PR |
| `spec` | Guides the user through writing the spec, section by section, then hands over the approval command |
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

The `test-writer-scope` hook flags any edit outside test files and fixtures when the caller is `test-writer`. Claude Code names the subagent (`agent_type`) in the hook input. The hook is wired in the project settings, because hooks in an agent's frontmatter did not run in testing. The read-only limits of the other two come from their tool lists and prompts.

### Settings and other files

| File | Content |
|---|---|
| `.claude/settings.json` | Base permissions, hook wiring, and stack overlays |
| `.claude/settings.autonomous.json` | The autonomous profile and cloud CLI denies, passed with `--settings` on top of `settings.json`. Claude Code combines permission lists across settings files. Generated: a re-run replaces it |
| `.claude/rules/*.md` | Security, specs, auth, API, backend, frontend, data, mobile, CLI, testing, agentic verification, dependencies, CI/CD, logging |
| `.claude/output-styles/` | Terse (attended) and Autonomous (unattended) |
| `CLAUDE.md` | Project template under 100 lines |
| `SECURITY.md`, `.claude/pull_request_template.md` | Disclosure policy and a PR template with `Security-Review:` and `Verification` |
| `scripts/security-check.sh` | Local scans: secret files, gitleaks, semgrep, osv-scanner, trivy. `--staged` and `--changed` modes |
| `scripts/claude-autonomous.sh` | Starts an unattended run |
| `scripts/approve-spec.sh` | The user approves the branch's spec. Writes `.claude/approvals/<branch>.json` with the spec's hash. Agents cannot run it |
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
| `FW_TEST_GATE=always`, `FW_SAST=always` | Run those checks in attended sessions too |
| `FW_ENFORCE=1` | Hook findings block instead of warn. Also makes the git hooks stop a failing commit or push |
| `FW_TEST_GUARD=off` | Turn off `test-guard` |
| `FW_SPEC_GATE=off` | Turn off `spec-gate` and the approval check in `pr-gate` |
| `CLAUDE_TEST_CMD` | The test command for `test-gate`. The default is detected |
| `CLAUDE_TEST_TIMEOUT`, `CLAUDE_TEST_MAX_ATTEMPTS` | Test gate limits |
| `FW_SEMGREP_CONFIG` | semgrep rules. The default is `p/default` |
| `FW_FORMAT_LINT=off` | Turn off `format-lint` |
| `FW_SESSION_GIT=0`, `FW_SESSION_TOOLS=0` | Hide those sections of the session context |
| `FW_MAINTAINER=1` | Framework development only. Hooks, `.claude/framework/`, and git hooks become Yellow. Set it by hand in `.claude/settings.local.json`. The hooks read that file, not the environment, so the flag does not leak into a `claude` run in another project. The autonomous profile ignores it |

### What an agent may change in `.claude/`

| Path | Tier |
|---|---|
| `.claude/settings*.json`, `.mcp.json`, `.git/` | Red, always |
| `.claude/hooks/`, `.claude/framework/`, `.githooks/`, `scripts/security-check.sh`, `scripts/claude-autonomous.sh` | Red. Yellow with `FW_MAINTAINER=1` |
| `.claude/skills/`, `.claude/agents/`, `.claude/rules/`, `.claude/output-styles/` | Yellow. A project may tune them, with review |

## Platforms

| Platform | Hooks, skills, settings | Sandbox overlay |
|---|---|---|
| Linux | Yes | Yes, needs bubblewrap and socat |
| WSL2 | Yes. Keep repos on the Linux filesystem | Yes, needs bubblewrap and socat |
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
- Without bubblewrap or socat, Claude Code runs commands unsandboxed. The `sandbox` overlay sets `sandbox.failIfUnavailable`, so Claude Code refuses to start instead, and `session-start` names the missing tool.
- Claude Code loads a path-scoped rule only when Claude reads a matching file. `rules-notice` names the rule on each write, and `CLAUDE.md` tells the agent to read the matching file first. Rules that must always apply belong in a file without `paths:`, like `security.md`.

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
