---
name: feature
description: The main build loop for a feature, fix, or change. Branch, spec, threat notes, tests first, small green commits, self-review, then a PR that a human merges. Use when the user asks to build, add, implement, or fix something in a codebase, attended or in an autonomous run.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, Skill
---

# /feature: build a change from task to PR

**Arguments:** `$ARGUMENTS` (the task)

The loop ends in an open PR. You never merge it. Hooks block merge, push to a protected branch, deploy, and secrets.

## Mode

- Check `CLAUDE_PROFILE`. If it is `autonomous`, nobody is watching. Never ask a question. Take the smallest reversible option, record it as a decision, and continue.
- Otherwise ask the user only when the choice changes what you build. Take obvious defaults and state them in one line.

## 1. Read before you write

1. Read the task. Write it again as 1 to 3 acceptance criteria you can test.
2. Read `CLAUDE.md` and `.claude/rules/security.md`.
3. Find the area you change. Read the matching rules file in `.claude/rules/`: `frontend.md`, `backend.md`, `api.md`, `auth.md`, `data-migrations.md`, `mobile.md`, `binaries-cli.md`, `testing.md`, `dependencies.md`.
4. Read the code around the change. Match its naming, structure, and test style.

## 2. Branch

```bash
git switch -c <type>/<short-name>   # feat/, fix/, chore/, refactor/, docs/
```

Never commit on `main`, `master`, or a release branch. A hook blocks it.

## 3. Spec and threat notes

Tests only prove the code matches the spec. Run the `spec` skill first: it finds or writes `docs/specs/<feature>.md`, gives each criterion an ID (`AC-1`), and lists the gaps. Attended, ask the user about gaps that change what they see, what data is kept, or who can do what. Autonomous, record each gap and your choice. See `.claude/rules/specs.md`.

Then note:
- The inputs that cross a trust boundary (user input, network, files, other services).
- The data that the change reads or writes, and who may see it.

Classify the tier of each file you plan to touch:
- Yellow: auth, session, crypto, permissions, migrations, CI, infra, dependency manifests.
- Red: secrets, settings, lockfiles by hand, deploy. Do not plan Red work. Record it under Blocked.

For Yellow work, run the `threat-model` skill before you write code. For a new or changed endpoint, run `api-design`. For auth, run `auth-change`. For a schema change, run `db-migration`. For a new package, run `add-dependency`.

## 4. Tests first

1. Run the `test-strategy` skill to pick the levels: unit, integration, contract, regression, e2e. For a bug fix, write the regression test first and confirm it reproduces the bug.
2. Write tests for each acceptance criterion and name the criterion in the test (`it("AC-2: ...")`). Run them. Confirm they fail for the right reason.
3. Add negative tests: bad input, missing auth, wrong user, empty and boundary values.
4. For a large or unfamiliar area, delegate to the `test-writer` subagent with the criteria.

## 5. Build in small green steps

Repeat:
1. Make the smallest change that moves one test toward green.
2. Run the tests that cover it.
3. When they pass, commit:
   ```bash
   git add -A && git commit -m "<type>: <what changed>"
   ```

Rules:
- Never skip, delete, or weaken a test. A hook blocks commits that do.
- After 3 failed approaches to one failure, stop on that failure. Record it under Blocked. Continue with other parts.
- Run the full test suite before step 6.

## 6. Self-review

1. Run `/pr-review` against the default branch. Fix every BLOCK finding.
2. If the branch touches a Yellow path, run `/review-security`, or delegate to the `security-reviewer` subagent. Fix every CRITICAL and HIGH finding.
3. Check the diff yourself:
   ```bash
   git diff "$(git merge-base HEAD origin/HEAD 2>/dev/null || git merge-base HEAD main)"...HEAD --stat
   ```
   Remove debug code, dead code, and unrelated edits.

## 7. Verify against the spec

For any user-visible change (UI, screen, route, API response, CLI output), run the `verify-spec` skill. It drives the running app locally and saves evidence. Mark each criterion PASS, FAIL, or NOT VERIFIED. Fix each FAIL before the PR. A pure refactor needs the test suite only.

## 8. Open the PR

1. Push the branch:
   ```bash
   git push -u origin HEAD
   ```
2. Write the body to `.claude/runs/pr-body.md` (gitignored; create the directory). Use the structure of `.claude/pull_request_template.md` or `.github/pull_request_template.md` if the repo has one, else this:
   ```markdown
   ## Summary
   - <what and why>

   Spec: docs/specs/<feature>.md

   ## Changes
   - <file>: <change>

   ## Tests
   - <command>: <pass/fail counts>

   ## Verification
   | Criterion | Result | Evidence |
   |---|---|---|
   | AC-1 <short text> | PASS | .claude/runs/<id>/evidence/<file> |

   ## Spec gaps and assumptions
   - <what the spec did not decide>: <what you chose, and why>

   ## Decisions
   - <choice>: <reason>

   Security-Review:
   - <yellow file>: <risk checked> -> <how the change handles it, with test name>

   ## Dependencies
   - <package@version>: <reason> (only when you added one)
   ```
   `pr-gate` blocks the PR when the branch changes code and the body lacks any of: test changes (or a `No-Test-Reason:` line), a filled Verification row, a `Spec:` line, or the Spec gaps section ("none" is allowed there). It also requires `Security-Review:` to name each Yellow file.
3. Create the PR, or the merge request on GitLab. Pick the row that matches the remote:

   | Remote | Command |
   |---|---|
   | GitHub, `gh` installed | `gh pr create --title "<type>: <summary>" --body-file .claude/runs/pr-body.md` |
   | GitLab, `glab` installed | `glab mr create --title "<type>: <summary>" --description "$(cat .claude/runs/pr-body.md)"` |
   | Gitea or Forgejo, `tea` installed | `tea pr create --title "<type>: <summary>" --description "$(cat .claude/runs/pr-body.md)"` |
   | Other remote, or no forge CLI | Push the branch. Keep the body in `.claude/runs/pr-body.md`. Give the branch name and the file path in the report |
   | No remote | Keep the branch local. Give the branch name and the file path in the report |

   Find the remote with `git remote get-url origin`.

   Mark it as a draft (`--draft`) when something is under Blocked.
4. On later pushes, update the same PR. Never open a second PR for the same task.

## 9. Report

- Autonomous: end with the Final report from the Autonomous output style. Use the `blocked-report` skill when you could not finish.
- Attended: give the PR link and any open decisions.

Never merge: no `gh pr merge`, `glab mr merge`, `tea pr merge`, or local merge into the default branch. A green build or an approval is not permission.
