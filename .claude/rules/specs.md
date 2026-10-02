# Specs and drift

Tests prove the code does what the spec says. They cannot prove the spec says what the user meant. Where the spec is silent, the agent guesses, and every guess is a place where intent and code can drift apart.

## Before code

- MUST have a spec for each feature or behavior change: a file in `docs/specs/`, an issue, or a ticket. Run the `spec` skill to write or tighten one.
- The spec MUST give each acceptance criterion an ID (`AC-1`, `AC-2`) and state it so a test can pass or fail: Given, When, Then.
- The spec MUST cover, or say "out of scope" for: error cases, empty and boundary values, permissions (who may and may not), limits (size, rate, time), and what happens to existing data.
- Read the spec for gaps before you write a test. A gap is any behavior the code must have that the spec does not decide.

## Gaps

- Attended: ask the user about each gap that changes what the user sees, what data is kept, or who can do what. Take the obvious default for the rest and state it.
- Autonomous: never ask. Take the smallest, most reversible choice. Record each gap and choice.
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
