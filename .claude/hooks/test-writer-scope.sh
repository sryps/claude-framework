#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit|NotebookEdit) for the test-writer
# subagent only. It is wired in .claude/agents/test-writer.md, not in the
# project settings. Blocks any edit outside test files and test fixtures, so
# the agent that writes the failing tests cannot also change the code under
# test.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
. "$(dirname "$0")/lib/policy.sh"

fw_read_input
fw_enter_project
path=$(fw_get '.tool_input.file_path // .tool_input.notebook_path')
[ -z "$path" ] && exit 0
rel=$(fw_project_rel "$path")

if printf '%s' "$rel" | grep -qE "$FW_TEST_PATH_RE"; then
  exit 0
fi
fw_block "Blocked by test-writer-scope: $rel is not a test file. The test-writer agent edits test files and fixtures only.
Test paths: *.test.* and *.spec.* files, __tests__/, test/, tests/, spec/, e2e/, .maestro/, *_test.go, test_*.py, *Test(s).{swift,kt,java,cs}, and fixtures or snapshots under those.
Report the code change the tests need, and let the main agent make it."
