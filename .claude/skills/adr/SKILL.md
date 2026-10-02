---
name: adr
description: Record an architecture decision as docs/adr/NNNN-title.md in MADR form. Use when a change picks a framework, datastore, auth provider, protocol, or pattern that later work depends on, or when the user asks to record a decision.
allowed-tools: Bash, Read, Write, Edit, Glob
---

# /adr: architecture decision record

**Arguments:** `$ARGUMENTS` (the decision)

## 1. Number

```bash
mkdir -p docs/adr
last=$(ls docs/adr 2>/dev/null | grep -E '^[0-9]{4}-' | sort | tail -1 | cut -c1-4)
next=$(printf '%04d' $(( 10#${last:-0} + 1 )))
echo "$next"
```

File name: `docs/adr/<next>-<kebab-case-title>.md`. Keep the title short, as the decision, not the problem: `0007-use-postgres-rls-for-tenancy.md`.

If the repo keeps ADRs somewhere else (`adr/`, `doc/architecture/decisions/`), use that folder.

## 2. Write

```markdown
# <NNNN>. <Decision title>

- Status: proposed | accepted | superseded by [<NNNN>](<file>)
- Date: <YYYY-MM-DD>
- Deciders: <names or "agent, pending review">

## Context and problem
<2 to 5 sentences. The force that makes a decision necessary.>

## Decision drivers
- <security, cost, team skill, latency, compliance>

## Options considered
1. <option>
2. <option>
3. <option>

## Decision
<The chosen option, and the main reason in one or two sentences.>

## Consequences
- Good: <...>
- Bad: <...>
- Security: <new trust boundaries, data exposure, auth impact>

## Pros and cons of the options
### <option 1>
- Good: <...>
- Bad: <...>
### <option 2>
- Good: <...>
- Bad: <...>
```

## 3. Rules

- An agent writes ADRs with `Status: proposed`. A human changes it to accepted.
- Never edit the decision in an accepted ADR. Write a new ADR that supersedes it, and update the old one's status line only.
- Link the ADR in the PR body.
