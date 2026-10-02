#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit|NotebookEdit): when the caller is the
# test-writer subagent, block any edit outside test files and fixtures, so the
# agent that writes the failing tests cannot also change the code under test.
#
# Claude Code puts agent_type in the hook input for a subagent's tool calls.
# The hook is wired in the project settings, because hooks in an agent's
# frontmatter did not run in testing (Claude Code 2.1.287).
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
. "$(dirname "$0")/lib/policy.sh"

fw_read_input
[ "$(fw_get '.agent_type')" = test-writer ] || exit 0
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
