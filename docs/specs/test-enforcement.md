# Test enforcement and spec drift

Status: agreed
Owner: repo owner

Since 0.6.0 every hook is advisory by default: where a criterion says "blocks", the hook warns and the action goes ahead. `FW_ENFORCE=1`, set by a human, restores the blocking behavior these criteria describe.

## Goal

Agents building a project with the framework must write regression, integration, and e2e tests, and the user must see where the spec left room for the agent to guess.

## Acceptance criteria

- AC-1: Given a staged commit with subject `fix:` or `fix(scope):` and no test file, when the agent commits, then test-guard blocks it, unless the message has a `No-Test-Reason:` trailer.
- AC-2: Given a branch that changes code and no test file, when the agent opens a PR, then pr-gate blocks it, unless the body has a `No-Test-Reason:` line.
- AC-3: Given a branch that changes code, when the PR body has no Verification row with a result (PASS, FAIL, or NOT VERIFIED) and its evidence or reason, then pr-gate blocks it.
- AC-4: Given a branch that changes code, when the PR body has no `Spec:` line, or it points at a repo file that does not exist, then pr-gate blocks it. A URL or an issue reference passes.
- AC-5: Given a branch that changes code, when the PR body has no `## Spec gaps and assumptions` section, or the section is empty, then pr-gate blocks it. An explicit "none" passes.
- AC-6: Given any session, the always-loaded rules tell the agent that tests only prove the code matches the spec, and to record every spec gap and its choice.
- AC-7: Given a new feature, the `spec` skill explains what a spec is, asks the user about each section, and produces a spec with criterion IDs, decided edge cases, and open questions with interim choices.
- AC-8: Given a branch with no approval, when the agent edits a code or test file, then spec-gate blocks it. Specs, docs, and config stay editable.
- AC-9: Given the user runs `scripts/approve-spec.sh <spec>`, then `.claude/approvals/<branch>.json` records the spec path and its SHA-256, and code edits pass. The script refuses a spec with no `AC-n` criteria or with `{{placeholders}}`, and refuses the default branch.
- AC-10: Given an approved spec that changes afterwards, when the agent edits code, then spec-gate blocks it until the user approves again.
- AC-11: Given any agent, including maintainer mode, when it runs the approval script or writes `.claude/approvals/`, then the hooks block it.
- AC-12: Given a code PR, pr-gate requires a valid approval and a `Spec:` line that names the approved file, or `Spec: none` for a `--no-spec` approval.
- AC-13: Given `FW_SPEC_GATE=off` set by a human, spec-gate and the pr-gate approval check are off. pr-gate still requires a `Spec:` line.

## Edge cases

- Documentation under a `specs/` or `tests/` directory does not count as a test change.
- The untouched PR template does not pass pr-gate.
- test-guard runs in every session. A human can turn it off with `FW_TEST_GUARD=off`.
- Detached HEAD: spec-gate blocks, because there is no branch to hold an approval.
- Autonomous runs cannot be approved mid-run. They draft the spec and stop with a draft PR.
- Edits through Bash (sed, redirects) are not covered by spec-gate. pr-gate checks the approval at PR time as the backstop.

## Open questions

- Should spec-gate also cover Bash writes to code files? Interim choice: no. Command parsing cannot see every write, and pr-gate catches the PR.

## Out of scope

- Repository settings (branch rules, required checks). Projects keep their own.
- Judging test quality. The hooks check that tests exist, not that they are good.
