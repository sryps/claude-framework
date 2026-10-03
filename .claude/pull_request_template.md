## Summary

<!-- One or two sentences: what changes and why. Link the issue. -->

<!-- Required when the branch changes code: the spec this implements. A repo file, a URL, or an issue. -->
Spec:

## Changes

<!-- One bullet per change, with the file path. -->
-

## Tests

<!--
The command you ran and the result. Name new tests and the criterion each proves (AC-1).
When the branch changes code and no test file, pr-gate needs a line:
No-Test-Reason: <why no test can cover it>
-->
- Command:
- Result:
- New tests:

## Verification

<!--
Required when the branch changes code. Run the verify-spec skill.
One row per acceptance criterion. Result is PASS, FAIL, or NOT VERIFIED.
Evidence is a path under .claude/runs/<id>/evidence/, or for NOT VERIFIED, the reason.
-->
| Criterion | Result | Evidence |
|---|---|---|
| | | |

## Spec gaps and assumptions

<!--
Required when the branch changes code. Tests prove the code matches the spec,
not what the user meant. List each behavior the spec did not decide and the
choice you made, so a human can confirm it. Write "none" only when the spec
decided everything.
-->
-

## Security-Review:

<!--
Required when the branch touches a Yellow-tier path: auth, sessions, crypto,
access control, migrations, CI, infra, dependency manifests, or agent
instructions. Name each Yellow file, or a parent directory with a trailing slash:
- <file>: <risk you checked> -> <how the change handles it, with the test name>
-->
- none

## Framework warnings

<!--
The framework hooks warn instead of block. List every warning from this run
(.claude/runs/warnings.log, this session's lines): what the hook flagged, why
you went ahead, and what the reviewer should check. Write "none" when the hooks
raised nothing.
-->
- none

## Decisions

<!-- Each choice made without a human: what, and why. -->
-

## Checklist

- [ ] Every acceptance criterion has a test or a Verification row.
- [ ] Each fixed bug has a regression test that failed before the fix.
- [ ] No secrets, keys, or real `.env` values in the diff.
- [ ] Input is validated at the boundary. Access checks run on the server.
- [ ] New dependencies went through `add-dependency`.
- [ ] Migrations are reversible or the recovery plan is above.
- [ ] The spec, docs, and `CLAUDE.md` match the code.
