#!/usr/bin/env bash
# Stop hook: run the project tests before Claude may stop.
# Exit 2 blocks the stop and feeds stderr back to Claude as the next thing to fix.
#
# Test command: $CLAUDE_TEST_CMD if set, else detected from the project root:
# a Makefile `verify` target, then package.json test script, Cargo.toml,
# go.mod, pyproject/pytest, Gradle, Swift package, Makefile `test` target.
# No command found -> allow the stop.
#
# Retry cap: $CLAUDE_TEST_MAX_ATTEMPTS failed runs per session (default 8). At
# the cap Claude gets one last block telling it to write the Blocked report.
#
# Runs in the autonomous profile. Set FW_TEST_GATE=always for attended sessions.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"

fw_autonomous || [ "${FW_TEST_GATE:-}" = always ] || exit 0
[ "$FW_HAS_JQ" = 1 ] || exit 0

fw_read_input
fw_enter_project
cd "$FW_ROOT" || exit 0

detect() {
  # A project's own `verify` target wins: it is the project saying what "done"
  # means, and it usually covers more than the test runner (types, lint, DB).
  if [ -f Makefile ] && grep -qE '^verify:' Makefile; then echo "make verify"; return; fi
  if [ -f package.json ]; then
    script=$(jq -r '.scripts.test // empty' package.json 2>/dev/null)
    if [ -n "$script" ] && ! printf '%s' "$script" | grep -q 'no test specified'; then
      if [ -f pnpm-lock.yaml ]; then echo "pnpm test"
      elif [ -f yarn.lock ]; then echo "yarn test"
      elif [ -f bun.lockb ] || [ -f bun.lock ]; then echo "bun run test"
      else echo "npm test"; fi
      return
    fi
  fi
  [ -f Cargo.toml ] && { echo "cargo test"; return; }
  [ -f go.mod ] && { echo "go test ./..."; return; }
  if [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ]; then
    if [ -f uv.lock ]; then echo "uv run pytest"; return; fi
    if [ -f poetry.lock ]; then echo "poetry run pytest"; return; fi
    fw_have pytest && { echo "pytest"; return; }
  fi
  [ -x gradlew ] && { echo "./gradlew test"; return; }
  [ -f Package.swift ] && { echo "swift test"; return; }
  if [ -f Makefile ] && grep -qE '^test:' Makefile; then echo "make test"; return; fi
}

cmd=${CLAUDE_TEST_CMD:-$(detect)}
[ -z "$cmd" ] && exit 0

state=$(fw_state_dir)
count_file="$state/test-gate.count"
done_file="$state/test-gate.capped"
max=${CLAUDE_TEST_MAX_ATTEMPTS:-8}
limit=${CLAUDE_TEST_TIMEOUT:-600}

# Cap already reached and Claude was told to report: let it stop.
[ -f "$done_file" ] && exit 0

log=$(mktemp "${TMPDIR:-/tmp}/fw-test.XXXXXX")
CI=1 fw_timeout "$limit" "$cmd" >"$log" 2>&1
rc=$?

if [ "$rc" -eq 0 ]; then
  rm -f "$count_file" "$log"
  exit 0
fi

count=$(( $(cat "$count_file" 2>/dev/null || echo 0) + 1 ))
echo "$count" >"$count_file"

{
  if [ "$rc" -eq 124 ]; then
    echo "Test gate: \`$cmd\` timed out after ${limit}s (attempt $count of $max)."
  else
    echo "Test gate: \`$cmd\` failed with exit code $rc (attempt $count of $max)."
  fi
  echo "Last 80 lines of output:"
  tail -n 80 "$log"
  echo
  if [ "$count" -ge "$max" ]; then
    touch "$done_file"
    echo "Retry limit reached. Stop fixing. Leave the build in its best state, then write the final report with this failure under Blocked."
  else
    echo "Fix the cause, then stop again to rerun the tests."
  fi
} >&2
rm -f "$log"
exit 2
