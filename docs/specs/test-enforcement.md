# Test enforcement and spec drift

Status: agreed
Owner: repo owner

## Goal

Agents building a project with the framework must write regression, integration, and e2e tests, and the user must see where the spec left room for the agent to guess.

## Acceptance criteria

- AC-1: Given a staged commit with subject `fix:` or `fix(scope):` and no test file, when the agent commits, then test-guard blocks it, unless the message has a `No-Test-Reason:` trailer.
- AC-2: Given a branch that changes code and no test file, when the agent opens a PR, then pr-gate blocks it, unless the body has a `No-Test-Reason:` line.
- AC-3: Given a branch that changes code, when the PR body has no Verification row with a result (PASS, FAIL, or NOT VERIFIED) and its evidence or reason, then pr-gate blocks it.
- AC-4: Given a branch that changes code, when the PR body has no `Spec:` line, or it points at a repo file that does not exist, then pr-gate blocks it. A URL or an issue reference passes.
- AC-5: Given a branch that changes code, when the PR body has no `## Spec gaps and assumptions` section, or the section is empty, then pr-gate blocks it. An explicit "none" passes.
- AC-6: Given any session, the always-loaded rules tell the agent that tests only prove the code matches the spec, and to record every spec gap and its choice.
- AC-7: Given a new feature, the `spec` skill produces a spec with criterion IDs, decided edge cases, and open questions with interim choices.

## Edge cases

- Documentation under a `specs/` or `tests/` directory does not count as a test change.
- The untouched PR template does not pass pr-gate.
- test-guard runs in every session. A human can turn it off with `FW_TEST_GUARD=off`.

## Out of scope

- Repository settings (branch rules, required checks). Projects keep their own.
- Judging test quality. The hooks check that tests exist, not that they are good.
