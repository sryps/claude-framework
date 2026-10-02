#!/usr/bin/env bash
# PostToolUse hook (Edit|Write|MultiEdit|NotebookEdit): flag Yellow-tier edits.
#
# The edit stays. Claude gets a reminder of the extra duties for that kind of
# change, once per category per session, and the path is logged so pr-gate.sh
# can require a Security-Review section in the PR body.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
. "$(dirname "$0")/lib/policy.sh"

fw_read_input
fw_enter_project
path=$(fw_get '.tool_input.file_path // .tool_input.notebook_path')
[ -z "$path" ] && exit 0

tier=$(fw_path_tier "$path")
case "$tier" in yellow*) ;; *) exit 0 ;; esac
reason=${tier#yellow }
rel=$(fw_project_rel "$path")

state=$(fw_state_dir)
printf '%s\t%s\n' "$reason" "$rel" >>"$state/yellow.log"

key=$(printf '%s' "$reason" | tr -c 'a-z' '_')
[ -f "$state/yellow.$key" ] && exit 0
touch "$state/yellow.$key"

case "$reason" in
  auth*) duty="Run the auth-change skill before you finish. Add tests for the deny path: wrong user, expired token, missing role." ;;
  database*) duty="Follow the db-migration skill: reversible migration, no destructive change in one step, RLS or policy on every new table." ;;
  CI*) duty="Pin every third-party action to a full commit SHA. Give the workflow the least permissions it needs. Never expose secrets to pull_request_target or fork PRs." ;;
  infrastructure*) duty="Keep least privilege, no public exposure by default, no secrets in the file. Record the change in the PR." ;;
  agent*) duty="These files steer every future agent run. Keep each rule enforceable and specific. Never weaken a security rule or remove a required step." ;;
  framework*) duty="Maintainer mode. Run .claude/framework/verify.sh before you finish. Every guard change needs a test in .claude/framework/tests/hooks-test.sh." ;;
  dependency*) duty="Follow the add-dependency skill for each new package. Regenerate the lockfile with the package manager." ;;
  *) duty="Describe the change and its risk in the PR." ;;
esac

fw_context PostToolUse "Yellow-tier edit: $rel ($reason).
$duty
The PR body must contain a 'Security-Review:' section that names each yellow file and the risk you checked. A human reviews yellow changes before merge." "! yellow-tier edit: $reason"
