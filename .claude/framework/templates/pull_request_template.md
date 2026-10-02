## Summary

<!-- One or two sentences: what changes and why. Link the issue. -->

## Changes

<!-- One bullet per change, with the file path. -->
-

## Tests

<!-- The command you ran and the result. Name new tests. -->
- Command:
- Result:
- New tests:

## Verification

<!--
Required for user-visible changes. Run the verify-spec skill.
One row per acceptance criterion. Result is PASS, FAIL, or NOT VERIFIED.
NOT VERIFIED needs a reason. Evidence lives in .claude/runs/<id>/evidence/.
-->
| Criterion | Result | Evidence |
|---|---|---|
| | | |

## Security-Review:

<!--
Required when the branch touches a Yellow-tier path: auth, sessions, crypto,
access control, migrations, CI, infra, or dependency manifests. The pr-gate hook
blocks `gh pr create` without this section in that case.

One line per Yellow file:
- <file>: <risk you checked> -> <how the change handles it, with the test name>

Write "none" when no Yellow path changed.
-->
- none

## Decisions

<!-- Each choice made without a human: what, and why. -->
-

## Checklist

- [ ] Tests added or updated, and the full suite passes.
- [ ] No secrets, keys, or real `.env` values in the diff.
- [ ] Input is validated at the boundary. Access checks run on the server.
- [ ] New dependencies went through `add-dependency`.
- [ ] Migrations are reversible or the recovery plan is above.
- [ ] Docs and `CLAUDE.md` updated if commands or behavior changed.
