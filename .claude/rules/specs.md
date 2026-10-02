# Specs and drift

Tests prove the code does what the spec says. They cannot prove the spec says what the user meant. Where the spec is silent, the agent guesses, and every guess is a place where intent and code can drift apart.

## Before code

- MUST have a spec the user approved before any code or test edit. The `spec-gate` hook blocks those edits until the branch has an approval.
- Write the spec with the user: run the `spec` skill. It drafts `docs/specs/<feature>.md` and asks the user about each section.
- The user approves with `scripts/approve-spec.sh docs/specs/<feature>.md`. Agents cannot run it. The approval holds the spec's hash, so any later change to the spec needs a new approval.
- A change with no behavior to specify (a typo, a version bump) needs the user's `scripts/approve-spec.sh --no-spec "<reason>"`.
- The spec MUST give each acceptance criterion an ID (`AC-1`, `AC-2`) and state it so a test can pass or fail: Given, When, Then.
- The spec MUST cover, or say "out of scope" for: error cases, empty and boundary values, permissions (who may and may not), limits (size, rate, time), and what happens to existing data.
- Read the spec for gaps before you write a test. A gap is any behavior the code must have that the spec does not decide.

## Gaps

- Attended: ask the user about each gap that changes what the user sees, what data is kept, or who can do what. Take the obvious default for the rest and state it.
- A gap found while coding goes into the spec under Open questions, with your proposed choice. The spec changed, so the gate blocks code until the user approves again. Never code around a gap.
- Autonomous: never ask. Draft the spec with every guess under Open questions, commit it, and stop with a draft PR. Code waits for the approval.
- MUST NOT fill a gap silently. Every gap goes in the PR under `## Spec gaps and assumptions`, and into the spec as an open question when the user should decide it.

## Traceability

- Each test names the criterion it proves: `it("AC-2: rejects an expired link")`, `test_ac2_rejects_expired_link`.
- Each criterion has at least one test, or a row under Verification that says why not.
- A test with no criterion means the spec is missing something. Add the criterion to the spec, or remove the test.
- The PR has a `Spec:` line that points at the spec, and a Verification row per criterion.

## Change

- When the code must differ from the spec, change the spec in the same PR and say why. MUST NOT let code and spec disagree.
- A bug report that the spec did not cover becomes a new criterion and a regression test.

## Done means

- [ ] The spec exists and every criterion has an ID.
- [ ] Every criterion has a test or a Verification row.
- [ ] Every gap is listed in the PR, with the choice made.
- [ ] Code and spec agree.
