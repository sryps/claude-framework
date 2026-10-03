#!/usr/bin/env bash
# Stop hook: scan every file changed on this branch before Claude may stop.
#
#   1. Secret files (.env, keys) added to the tree     -> block
#   2. Credentials in changed files                    -> block
#      gitleaks when installed, else the built-in patterns in lib/policy.sh.
#   3. SAST with semgrep (autonomous profile, or FW_SAST=always)
#      Findings at ERROR severity block. No semgrep or no network -> note only.
#
# Retry cap: 3 blocks per session, then Claude must report and may stop.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
. "$(dirname "$0")/lib/policy.sh"

fw_read_input
fw_enter_project
cd "$FW_ROOT" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

state=$(fw_state_dir)
count_file="$state/diff-scan.count"
[ -f "$state/diff-scan.capped" ] && exit 0

files=$(fw_changed_files)
[ -z "$files" ] && exit 0

report=""
add() { report="$report$1
"; }

# 1. Secret files.
while IFS= read -r f; do
  fw_is_secret_path "$f" && add "- secret file in the working tree and not ignored: $f. Add it to .gitignore and remove it from git."
done <<EOF2
$files
EOF2

# 2. Credentials.
if fw_have gitleaks; then
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    out=$(gitleaks dir --no-banner --redact --exit-code 1 "$f" 2>&1 || gitleaks detect --no-git --no-banner --redact --exit-code 1 -s "$f" 2>&1)
    rc=$?
    [ "$rc" -eq 1 ] && add "- gitleaks: $f
$(printf '%s\n' "$out" | grep -E 'RuleID|Line|Secret' | head -6)"
  done <<EOF2
$files
EOF2
else
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    # Skip binaries and big generated files.
    [ "$(wc -c <"$f" | tr -d ' ')" -gt 1048576 ] && continue
    grep -Iq . "$f" 2>/dev/null || continue
    if hits=$(fw_scan_secrets <"$f"); then
      add "- possible credential in $f:
$hits"
    fi
  done <<EOF2
$files
EOF2
fi

# 3. SAST.
note=""
if fw_autonomous || [ "${FW_SAST:-}" = always ]; then
  if fw_have semgrep; then
    list=$(printf '%s\n' "$files" | grep -E '\.(js|jsx|ts|tsx|mjs|cjs|py|go|rb|java|kt|swift|rs|php|cs|c|cc|cpp|h|scala|sh|tf|ya?ml|json|html|vue|svelte)$' || true)
    if [ -n "$list" ]; then
      # shellcheck disable=SC2086
      out=$(printf '%s\n' "$list" | tr '\n' '\0' | xargs -0 semgrep scan --config "${FW_SEMGREP_CONFIG:-p/default}" --severity ERROR --error --quiet --metrics off 2>&1)
      rc=$?
      if [ "$rc" -eq 1 ]; then
        add "- semgrep ERROR findings:
$(printf '%s\n' "$out" | head -40)"
      elif [ "$rc" -ne 0 ]; then
        note="semgrep did not run (exit $rc). Likely no network for the rule registry. Set FW_SEMGREP_CONFIG to a local rules file."
      fi
    fi
  else
    note="semgrep is not installed. SAST skipped. Install it: pipx install semgrep, or brew install semgrep."
  fi
fi

if [ -z "$report" ]; then
  rm -f "$count_file"
  [ -n "$note" ] && printf '%s\n' "$note" >&2
  exit 0
fi

count=$(( $(cat "$count_file" 2>/dev/null || echo 0) + 1 ))
echo "$count" >"$count_file"
msg=$({
  echo "Blocked by diff-scan (attempt $count of 3). Fix these before you stop:"
  printf '%s' "$report"
  [ -n "$note" ] && echo "Note: $note"
  if [ "$count" -ge 3 ]; then
    touch "$state/diff-scan.capped"
    echo "Retry limit reached. Write the final report with these findings under Blocked."
  else
    echo "A false positive on a test fixture: use an obvious placeholder, or add fw:allow-secret on that line."
  fi
})
fw_block "$msg"
