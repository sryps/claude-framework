#!/usr/bin/env bash
# Start an unattended Claude Code run with the autonomous profile.
#
#   scripts/claude-autonomous.sh "Add rate limiting to POST /login"
#   scripts/claude-autonomous.sh -f task.md
#
# The run works on a branch, loops build and test, and ends with a PR. Hooks
# block merge, deploy, publish, secrets, and protected-branch pushes.
# CLI only: the Claude Desktop app has no --settings flag, so Desktop
# sessions use the attended profile.
#
# Extra arguments after the task go straight to `claude`.
set -euo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
settings="$root/.claude/settings.autonomous.json"
[ -f "$settings" ] || { echo "Missing $settings. Run the framework install.sh first." >&2; exit 1; }
command -v claude >/dev/null 2>&1 || { echo "claude CLI not found on PATH." >&2; exit 1; }

if [ "${1:-}" = "-f" ]; then
  [ -f "${2:-}" ] || { echo "Task file not found: ${2:-}" >&2; exit 1; }
  task=$(cat "$2"); shift 2
else
  task=${1:?Usage: $0 \"<task>\" | -f task.md}; shift
fi

logdir="$root/.claude/runs"
mkdir -p "$logdir"
log="$logdir/$(date +%Y%m%d-%H%M%S).log"

cd "$root"
echo "Autonomous run. Log: $log"
claude -p "Use the feature skill for this task. $task" \
  --settings "$settings" \
  --permission-mode "${CLAUDE_PERMISSION_MODE:-auto}" \
  "$@" 2>&1 | tee "$log"
