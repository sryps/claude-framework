---
name: spec
description: Write or tighten the spec for a feature before any code, so tests check what the user meant. Gives each acceptance criterion an ID, forces decisions on edge cases and permissions, and lists the gaps the user must decide. Use at the start of any feature or behavior change, when a task arrives with no spec, or when the spec is too thin to test.
allowed-tools: Read, Write, Edit, Grep, Glob, AskUserQuestion
---

# /spec: make the spec testable

**Arguments:** `$ARGUMENTS` (the task, an issue, or a path to an existing spec)

Tests only prove the code matches the spec. A thin spec lets the agent guess, and each guess can drift from what the user meant. This skill turns a task into a spec with no silent gaps.

## 1. Find or start the spec

1. Look for an existing spec: `docs/specs/`, the issue or ticket in the task, or a spec section in the PR.
2. If none exists, copy `.claude/framework/templates/SPEC.md` to `docs/specs/<feature>.md`.
3. Write the goal in one or two sentences, in the user's words.

## 2. Write the criteria

- One behavior per criterion. Give each an ID: `AC-1`, `AC-2`.
- Use Given, When, Then. The Then must be observable: a response, a screen, a stored value, an exit code.
- No "should work", "fast", "user-friendly", or "handle errors". Replace each with a value or an outcome.

## 3. Hunt the gaps

Go through each line of the template's Edge cases, Users and permissions, and Limits. For each one the task does not decide, you have a gap.

Also check:
- Every input: its type, range, and what happens when it is wrong.
- Every state change: what happens to existing data, and what happens if it runs twice.
- Every external call: what happens when it fails or is slow.
- Every role: what each one may and may not do.

## 4. Close the gaps

Sort each gap:

| Kind | Examples | Action |
|---|---|---|
| User decides | What the user sees, what data is kept or deleted, who may do what, money, legal, anything hard to reverse | Attended: ask, with options and a recommendation. Autonomous: take the smallest reversible choice and put it under Open questions |
| Obvious default | Matches the code around it, an existing pattern, a standard | Decide, and write the choice into the spec |

Ask attended questions in one batch, not one at a time. Use AskUserQuestion with 2 to 4 options each, the recommended option first.

## 5. Check the spec

The spec is ready when:
- [ ] Every criterion has an ID and an observable result.
- [ ] Every edge case line is decided or marked out of scope.
- [ ] Every role has a may and a may-not.
- [ ] Every open question has an interim choice and a reason.
- [ ] A tester who never saw the task could write the tests from it.

## 6. Hand off

- Commit the spec with the first commit of the feature: `docs: spec for <feature>`.
- Tests name the criterion they prove: `it("AC-2: ...")`.
- The PR body has `Spec: docs/specs/<feature>.md`, a Verification row per criterion, and `## Spec gaps and assumptions` with every open question and interim choice.
- When the code must differ from the spec, change the spec in the same PR and add a line under Changes.
