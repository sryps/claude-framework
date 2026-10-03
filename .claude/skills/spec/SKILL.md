---
name: spec
description: Guide the user through writing the spec for a feature, then get their approval. Explains what a spec is, walks through each section with questions, drafts docs/specs/<feature>.md, and ends with the approval command. Code and tests should wait until the user approves. Use at the start of any feature or behavior change, when spec-gate warns about an edit, or when the user asks to write or change a spec.
allowed-tools: Read, Write, Edit, Grep, Glob, AskUserQuestion
---

# /spec: write the spec with the user

**Arguments:** `$ARGUMENTS` (the task, an issue, or a path to an existing spec)

The `spec-gate` hook warns on every code and test edit until the user approves a spec for the branch. Your job here is to help the user write a spec good enough to approve. You draft. The user decides.

## 0. Tell the user what this is

Say this in your own words, once, in 3 or 4 short lines:
- A spec says what the feature must do, in terms a test can check.
- Tests only prove the code matches the spec. Anything the spec leaves out, I have to guess, and a guess can differ from what you meant.
- I will ask about each part, draft the file, and you approve it with one command. Code waits until then.
- If you change the spec later, you approve again.

Skip this when the user has written specs with you before.

## 1. Find or start the file

1. Look for an existing spec: `docs/specs/`, an issue or ticket in the task.
2. If none exists, copy `.claude/framework/templates/SPEC.md` to `docs/specs/<feature>.md`. Use a short kebab-case name.
3. Pre-fill what the task already says. Do not ask the user what they already told you.

## 2. Walk the sections

Ask about one section at a time, in this order. Use AskUserQuestion with 2 to 4 concrete options and your recommendation first. Batch the small questions of one section into one call. Explain a section in one line before you ask about it.

| Section | What to settle | Example question |
|---|---|---|
| Goal | The problem, for whom, and how we know it is solved | "Who uses this, and what do they do today instead?" |
| Users and permissions | Each role, what it may do, what it may not | "Can a viewer export, or only an admin?" |
| Acceptance criteria | Each behavior as Given, When, Then, with an observable result | "When the link has expired, what does the user see?" |
| Edge cases | Empty, max, invalid input, wrong user, failure, double submit, existing data | "Two people edit at once: last write wins, or a conflict error?" |
| Limits | Size, rate, time, performance | "Largest upload you expect: 10 MB, 100 MB, or 1 GB?" |
| Out of scope | What this change does not do | "Is bulk import part of this, or later?" |
| Open questions | What the user wants to decide later, with an interim choice | "I'll use 30 days until you decide. OK?" |

Rules for criteria:
- One behavior each, with an ID: `AC-1`, `AC-2`. Keep IDs stable.
- The Then must be checkable: a response code, a screen, a stored value, an exit code.
- Replace "fast", "secure", "user-friendly", "handle errors" with a number or an outcome.

When the user says "you decide", choose the smallest, most reversible option that matches the code around it, write it into the spec, and tell them in one line.

## 3. Check the draft

Before you show it, confirm:
- [ ] Every criterion has an ID and an observable result.
- [ ] Every edge case line is decided or marked out of scope.
- [ ] Every role has a may and a may-not.
- [ ] Every open question has an interim choice.
- [ ] No `{{placeholders}}` remain. The approval script refuses them.
- [ ] Someone who never saw the conversation could write the tests from it.

## 4. Ask for approval

Show the user the spec file path and a 5-line summary: the criteria count, the main decisions, and the open questions. Then give the exact command:

```
! scripts/approve-spec.sh docs/specs/<feature>.md
```

Do not run it yourself, and do not write `.claude/approvals/`: the approval is the user's. Hooks warn if you try. Wait for the user.

For a change too small for a spec (a typo, a version bump), the user may run instead:

```
! scripts/approve-spec.sh --no-spec "<reason>"
```

Suggest it only when the change has no behavior to specify.

## 5. After approval

- Commit the spec and the approval file with the first commit: `git add docs/specs/<feature>.md .claude/approvals/`.
- Name each test after its criterion: `it("AC-2: ...")`.
- When you find a gap while coding: stop, add it to the spec under Open questions with your proposed choice, and ask the user to approve again. Never code around a gap.

## Autonomous runs

Nobody can approve during the run. When the branch has no approved spec:
1. Draft the spec from the task. Put every guess under Open questions with an interim choice.
2. Commit the draft. Do not touch code or tests.
3. Open a draft PR with the spec and run `blocked-report`. Under Blocked, write: "Waiting for spec approval: scripts/approve-spec.sh docs/specs/<feature>.md".
