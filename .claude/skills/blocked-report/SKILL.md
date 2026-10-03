---
name: blocked-report
description: Write the final report and open a draft PR when an autonomous run cannot finish. Use when a test gate retry cap is hit, a hard limit stops a step, the task is unclear at its core, or 3 approaches to one failure have failed.
allowed-tools: Bash, Read, Write, Grep, Glob
---

# /blocked-report: stop cleanly when blocked

**Arguments:** `$ARGUMENTS` (optional: what blocked the run)

A blocked run still ends in a PR. The report is the only thing the user reads, so it must let them act without reading the transcript.

## 1. Leave the tree in its best green state

1. Run the full test suite.
2. If the last change breaks the build and you cannot fix it, revert only your own partial change:
   ```bash
   git stash push -m "blocked: <short reason>"   # keep it, do not discard it
   ```
   Never use `git reset --hard` or `git clean -f`. Hooks warn on them.
3. Commit what is green:
   ```bash
   git add -A && git commit -m "wip: <what works>"
   ```

## 2. Push and open a draft PR

```bash
git push -u origin HEAD
```

Then open a draft. Pick the row that matches the remote:

| Remote | Command |
|---|---|
| GitHub, `gh` installed | `gh pr create --draft --title "<type>: <summary>" --body-file .claude/runs/pr-body.md` |
| GitLab, `glab` installed | `glab mr create --draft --title "<type>: <summary>" --description "$(cat .claude/runs/pr-body.md)"` |
| Gitea or Forgejo, `tea` installed | `tea pr create --title "<type>: <summary>" --description "$(cat .claude/runs/pr-body.md)"` |
| Other remote, or no forge CLI | Push the branch. Keep the body in `.claude/runs/pr-body.md`. Give the branch name and the file path in the report |
| No remote | Keep the branch local. Give the branch name and the file path in the report |

Find the remote with `git remote get-url origin`.

If a PR for this task exists, update it instead (`gh pr edit <number> --body-file ...` or `glab mr update <number> --description ...`).

If the push or the forge CLI fails (no remote, no auth), record that under Blocked and keep the branch local.

## 3. The report

Write the same text to the PR body and as your last message. Use these sections, in this order. Omit a section with no items, except Result and Tests.

```markdown
**Result**
- Blocked: <one line>. Or: Partly done: <what works>.

**Changes**
- <file path>: <change>

**Tests**
- `<command>`: <passed> passed, <failed> failed. <test names that fail>

**Decisions**
- <choice made without the user>: <reason>

**Framework warnings**
- <hook>: <what it flagged>. Went ahead because <reason>. Check: <what the user should look at>.

**Blocked**
- <failure>: exact error:
  ```
  <last 10 to 20 relevant lines>
  ```
  Tried: 1) <approach> 2) <approach> 3) <approach>
- <step a hard limit stopped>: <the hook or rule>, and the command a human must run.

**Todo (you)**
- <action>: `<exact command>`
```

Add a `Security-Review:` section to the PR body when the branch touches a Yellow path. A hook checks for it.

## Rules

- Quote errors exactly. Never summarize an error into vaguer words.
- Never claim a test passes that you did not run.
- Never paste secrets, tokens, or `.env` values into the report.
- One draft PR per task.
