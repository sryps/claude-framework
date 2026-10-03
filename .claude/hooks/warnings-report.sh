#!/usr/bin/env bash
# Stop hook: make sure the user hears about every warning the hooks let
# through in this session.
#
# Advisory hooks log each finding to .claude/runs/warnings.log. At stop:
#   - Autonomous: when there are warnings Claude has not reported yet, send
#     Claude back once to put them in the final report and the PR body, and
#     to post them as a PR comment when the PR already exists.
#   - Attended: show the user a short summary.
# Nothing is blocked. The autonomous run only gets one extra turn to report.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"

[ "$FW_HAS_JQ" = 1 ] || exit 0
fw_read_input
fw_enter_project
log="$FW_ROOT/.claude/runs/warnings.log"
[ -f "$log" ] || exit 0

session=$(fw_get '.session_id'); [ -z "$session" ] && session=unknown
state=$(fw_state_dir)
seen_file="$state/warnings.reported"
seen=$(cat "$seen_file" 2>/dev/null || echo 0)

# This session's warnings, numbered, with the ones already reported dropped.
mine=$(awk -F'\t' -v s="$session" '$2 == s' "$log")
total=$(printf '%s' "$mine" | grep -c . || true)
[ "${total:-0}" -gt "$seen" ] || exit 0
new=$(printf '%s\n' "$mine" | tail -n "$((total - seen))" | awk -F'\t' '{
  detail = $4; if (length(detail) > 80) detail = substr(detail, 1, 77) "..."
  printf "- %s: %s (%s)\n", $3, $5, detail
}')
echo "$total" >"$seen_file"

if fw_autonomous; then
  jq -n --arg r "The framework hooks raised $((total - seen)) warning(s) in this run and let each action go ahead. Before you stop, tell the user about every one:
1. Add a 'Framework warnings' section to the final report, one bullet per warning: what happened, why you went ahead, and what the user should check.
2. Add the same list under '## Framework warnings' in the PR body (.claude/runs/pr-body.md).
3. If the PR already exists, post the list as a PR comment: gh pr comment <number> --body-file <file> (glab mr note or tea comment on other forges).

Warnings:
$new" '{decision: "block", reason: $r}'
else
  jq -n --arg m "Framework warnings this session ($((total - seen)) new, the actions went ahead):
$new
Full log: .claude/runs/warnings.log" '{systemMessage: $m}'
fi
exit 0
