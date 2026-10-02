#!/usr/bin/env bash
# PreToolUse hook (Bash): refuse a `git commit` whose staged diff weakens tests.
#
# Blocks when staged changes to test files
#   - add a skip or focus marker (.skip, .only, xit, xdescribe, it.todo,
#     Deno ignore/only, pgTAP skip/todo, #[ignore], t.Skip, pytest skip), or
#   - remove more assertions than they add.
#
# Escape hatch: a `Test-Change-Reason:` trailer in the commit message, so a
# deliberate change (a test that was wrong) goes through with its reason on
# record for the reviewer.
#
# Runs in the autonomous profile. Set FW_TEST_GUARD=always to run it in
# attended sessions too.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"

fw_autonomous || [ "${FW_TEST_GUARD:-}" = always ] || exit 0
[ "$FW_HAS_JQ" = 1 ] || exit 0

fw_read_input
cmd=$(fw_get '.tool_input.command')
printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit([[:space:]]|$)' || exit 0
printf '%s' "$cmd" | grep -q 'Test-Change-Reason:' && exit 0

fw_enter_project
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# `git commit -a` / `--all` stages tracked changes as part of the commit.
if printf '%s' "$cmd" | grep -qE 'git[^;&|]*commit[^;&|]*[[:space:]](-a|--all|-[a-zA-Z]*a[a-zA-Z]*)([[:space:]]|$)'; then
  diff=$(git diff HEAD -U0 2>/dev/null)
else
  diff=$(git diff --cached -U0 2>/dev/null)
fi
[ -z "$diff" ] && exit 0

# Keep only hunks from test files.
tests=$(printf '%s\n' "$diff" | awk '
  /^diff --git/ {
    f = $3
    keep = (f ~ /\.(test|spec)\.[cm]?[jt]sx?$/ || f ~ /(^|\/)(__tests__|tests?|spec)\// || f ~ /_test\.(go|py|ts|exs?)$/ || f ~ /(^|\/)test_[^\/]*\.py$/ || f ~ /Tests?\.(swift|kt|java|cs)$/ || f ~ /\.maestro\//)
  }
  keep { print }
')
[ -z "$tests" ] && exit 0

added=$(printf '%s\n' "$tests" | grep -E '^\+[^+]' || true)
removed=$(printf '%s\n' "$tests" | grep -E '^-[^-]' || true)

B='(^|[^A-Za-z0-9_])'
skip_re="${B}(it|test|describe|context|suite)\.(skip|only|todo)${FW_E}|${B}x(it|describe|test)\(|${B}f(it|describe)\(|Deno\.test\.(ignore|only)${FW_E}|${B}(ignore|only)[[:space:]]*:[[:space:]]*true${FW_E}|${B}select[[:space:]]+(skip|todo)\(|#\[ignore\]|${B}t\.Skip(Now|f)?\(|@pytest\.mark\.(skip|xfail)|${B}pytest\.skip\(|@(Disabled|Ignore)${FW_E}|XCTSkip"
assert_re="${B}expect\(|${B}assert[A-Za-z_]*[(!]|${B}select[[:space:]]+(is|isnt|ok|results_eq|set_eq|bag_eq|throws_ok|throws_like|lives_ok|has_[a-z_]+|policies_are|row_eq)\(|^[+-]?[[:space:]]*-[[:space:]]*assert[A-Za-z]+:|${B}t\.(Error|Fatal)f?\(|${B}XCTAssert|${B}should[.(]|${B}require\.[A-Z]"

new_skips=$(printf '%s\n' "$added" | grep -cE "$skip_re" || true)
plus=$(printf '%s\n' "$added" | grep -cE "$assert_re" || true)
minus=$(printf '%s\n' "$removed" | grep -cE "$assert_re" || true)

problems=""
[ "${new_skips:-0}" -gt 0 ] && problems="adds $new_skips skip or focus marker(s)"
if [ "${minus:-0}" -gt "${plus:-0}" ]; then
  [ -n "$problems" ] && problems="$problems, and "
  problems="${problems}removes $minus assertion(s) and adds only $plus"
fi
[ -z "$problems" ] && exit 0

{
  echo "Blocked by test-guard: this commit weakens the tests. It $problems."
  echo "Staged lines that tripped it:"
  printf '%s\n' "$added" | grep -E "$skip_re" | head -10
  printf '%s\n' "$removed" | grep -E "$assert_re" | head -10
  echo
  echo "Fix the code, not the test. If the test itself was wrong and the task makes the right behavior clear,"
  echo "commit again with a trailer that says why, for example:"
  echo "  git commit -m \"...\" -m \"Test-Change-Reason: the old assertion expected the pre-fix rounding\""
  echo "and record the change under Decisions in the final report."
} >&2
exit 2
