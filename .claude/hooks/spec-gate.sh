#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit|NotebookEdit): no code or test edits
# until a human has approved the spec for this branch.
#
# A human approves with scripts/approve-spec.sh, which writes
# .claude/approvals/<branch>.json with the spec's SHA-256. The edit passes
# when that file exists and the spec is unchanged since approval, or when the
# human approved the branch with --no-spec. Specs, docs, and config stay
# editable, so the agent can write the spec with the user first.
#
# A human can turn the gate off with FW_SPEC_GATE=off in the settings env.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
. "$(dirname "$0")/lib/policy.sh"

[ "${FW_SPEC_GATE:-}" = off ] && exit 0
fw_read_input
fw_enter_project
path=$(fw_get '.tool_input.file_path // .tool_input.notebook_path')
[ -z "$path" ] && exit 0
git -C "$FW_ROOT" rev-parse --git-dir >/dev/null 2>&1 || exit 0
rel=$(fw_project_rel "$path")
case "$rel" in /*) exit 0 ;; esac

# Only code and tests wait for the spec.
fw_is_test_change "$rel" || printf '%s' "$rel" | grep -qE "$FW_CODE_RE" || exit 0

if reason=$(fw_spec_approval); then
  exit 0
fi
# Advisory mode: say it once per branch per session, not on every edit.
if ! fw_enforcing; then
  marker="$(fw_state_dir)/spec-gate.$(git -C "$FW_ROOT" branch --show-current 2>/dev/null | tr -c 'A-Za-z0-9._-' '_')"
  [ -f "$marker" ] && exit 0
  touch "$marker"
fi
fw_block "Blocked by spec-gate: $reason
Code and tests wait for a spec the user has approved, so the tests check what the user meant.
1. Run the spec skill. Write docs/specs/<feature>.md with the user.
2. Ask the user to read it and run: scripts/approve-spec.sh docs/specs/<feature>.md
   (or, for a change too small for a spec: scripts/approve-spec.sh --no-spec \"<reason>\")
Autonomous run: write the spec, stop, and report it under Blocked so the user can approve it."
