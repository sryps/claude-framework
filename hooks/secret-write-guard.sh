#!/usr/bin/env bash
# PreToolUse hook (Edit|Write|MultiEdit|NotebookEdit): block writes that
# contain a credential.
#
# Placeholders (example, dummy, 0000..., ${VAR}, process.env) pass. A real
# test fixture that must look like a key can carry the marker
# `fw:allow-secret` on the same line. A reviewer sees that marker in the diff.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
. "$(dirname "$0")/lib/policy.sh"

fw_read_input
if [ "$FW_HAS_JQ" = 1 ]; then
  text=$(printf '%s' "$FW_INPUT" | jq -r '
    .tool_input as $t
    | [ $t.content, $t.new_string, $t.new_source, ($t.edits // [] | .[]? | .new_string) ]
    | map(select(. != null)) | join("\n")' 2>/dev/null)
else
  text=$FW_INPUT
fi
[ -z "$text" ] && exit 0

if findings=$(printf '%s\n' "$text" | fw_scan_secrets); then
  fw_block "Blocked by secret-write-guard: the new content looks like it contains a credential.
$findings
Read secrets from the environment or a secret manager at runtime. Commit only a placeholder in .env.example.
If this is a fake value for a test, use an obvious placeholder, or add the marker fw:allow-secret on that line."
fi
exit 0
