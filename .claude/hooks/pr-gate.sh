#!/usr/bin/env bash
# PreToolUse hook (Bash): gate PR and MR creation on GitHub (gh), GitLab
# (glab), and Gitea or Forgejo (tea).
#
# When the branch touches a Yellow-tier path, the PR body must contain a
# `Security-Review:` section. The hook reads the body from the command line,
# from --body-file/-F, or from a `$(cat FILE)` substitution.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
. "$(dirname "$0")/lib/policy.sh"
set -f

fw_read_input
cmd=$(fw_get '.tool_input.command')
[ -z "$cmd" ] && exit 0
printf '%s' "$cmd" | grep -qE "(^|[;&|[:space:]])(gh[[:space:]]+pr[[:space:]]+(create|new|edit)|glab[[:space:]]+mr[[:space:]]+(create|new|update)|tea[[:space:]]+(pr|pulls)[[:space:]]+create)([[:space:]]|$)" || exit 0
fw_enter_project
cd "$FW_ROOT" 2>/dev/null || exit 0

yellow=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  t=$(fw_path_tier "$FW_ROOT/$f")
  case "$t" in yellow*) yellow="$yellow
- $f (${t#yellow })" ;; esac
done <<EOF2
$(fw_changed_files)
EOF2
[ -z "$yellow" ] && exit 0

body=$cmd
bf=$(printf '%s' "$cmd" | sed -nE 's/.*(--body-file|-F)[[:space:]=]+("([^"]+)"|'"'"'([^'"'"']+)'"'"'|([^[:space:]]+)).*/\3\4\5/p' | head -1)
if [ -z "$bf" ]; then
  # glab and tea take the body inline: -d "$(cat FILE)" or --description "$(< FILE)".
  bf=$(printf '%s' "$cmd" | sed -nE 's/.*\$\((cat[[:space:]]+|<[[:space:]]*)["'"'"']?([^"'"'"' )]+)["'"'"']?[[:space:]]*\).*/\2/p' | head -1)
fi
# Expand the variables a skill may leave in the path. The hook sees the raw command.
case "$bf" in
  '${TMPDIR:-/tmp}'/*) bf="${TMPDIR:-/tmp}/${bf#*\}/}" ;;
  '$TMPDIR'/*|'${TMPDIR}'/*) bf="${TMPDIR:-/tmp}/${bf#*/}" ;;
  '$HOME'/*|'${HOME}'/*|'~'/*) bf="$HOME/${bf#*/}" ;;
esac
if [ -n "$bf" ] && [ "$bf" != "-" ] && [ -f "$bf" ]; then
  body=$(cat "$bf")
fi

how_to="Add a section like this to the body, then run the command again:

Security-Review:
- <file or directory/>: <risk you checked> -> <how the change handles it, with the test name>

Name each Yellow file, or a directory that holds it (for example .claude/skills/).
Write the body to a file and pass --body-file, so the section survives shell quoting."

if ! printf '%s' "$body" | grep -q 'Security-Review:'; then
  fw_block "Blocked by pr-gate: this branch changes Yellow-tier files, and the PR body has no 'Security-Review:' section.
Yellow files on this branch:$yellow
$how_to"
fi

# The section runs from the marker to the next markdown heading. HTML
# comments (the template's instructions) do not count.
section=$(printf '%s\n' "$body" | awk '
  {
    line = $0
    if (incomment) {
      e = index(line, "-->")
      if (!e) next
      line = substr(line, e + 3); incomment = 0
    }
    while ((s = index(line, "<!--")) > 0) {
      e = index(substr(line, s), "-->")
      if (e > 0) line = substr(line, 1, s - 1) substr(line, s + e + 2)
      else { line = substr(line, 1, s - 1); incomment = 1; break }
    }
  }
  insec && line ~ /^#+[ \t]/ { exit }
  insec { print line; next }
  (p = index(line, "Security-Review:")) > 0 {
    insec = 1
    rest = substr(line, p + 16)
    if (rest ~ /[^ \t]/) print rest
  }')
# Placeholders and "none" are not a review.
content=$(printf '%s\n' "$section" | grep -vE '<[A-Za-z][^>]*>|\{\{' | grep -viE '^[[:space:]]*([-*][[:space:]]*)?(none|n/a|tbd|todo)?[[:space:]]*\.?[[:space:]]*$' || true)
if [ -z "$content" ]; then
  fw_block "Blocked by pr-gate: the 'Security-Review:' section is empty, says none, or still holds the template placeholders, but this branch changes Yellow-tier files.
Yellow files on this branch:$yellow
$how_to"
fi

missing=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # The file itself, or any parent directory written with a trailing slash.
  covered=0
  printf '%s' "$content" | grep -qF -- "$f" && covered=1
  d=$f
  while [ "$covered" = 0 ]; do
    case "$d" in */*) d=${d%/*} ;; *) break ;; esac
    printf '%s' "$content" | grep -qF -- "$d/" && covered=1
  done
  [ "$covered" = 1 ] || missing="$missing
- $f"
done <<EOF2
$(printf '%s\n' "$yellow" | sed -nE 's/^- (.*) \([^)]*\)$/\1/p')
EOF2
if [ -n "$missing" ]; then
  fw_block "Blocked by pr-gate: the 'Security-Review:' section does not name these Yellow files:$missing
$how_to"
fi
exit 0
