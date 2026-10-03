#!/usr/bin/env bash
# PreToolUse hook (Bash): gate PR and MR creation on GitHub (gh), GitLab
# (glab), and Gitea or Forgejo (tea).
#
# When the branch changes code:
#   - it must also change tests, or the body has a `No-Test-Reason:` line
#   - the body has a `## Verification` table with at least one result
#     (PASS, FAIL, or NOT VERIFIED) and its evidence or reason
#   - the body has a `Spec:` line that points at the spec (a repo file that
#     exists, a URL, or an issue reference)
#   - the body has a `## Spec gaps and assumptions` section, even if it says
#     none, so the reader sees where the agent filled in for the spec
# When the branch touches a Yellow-tier path:
#   - the `Security-Review:` section names each Yellow file, or a parent
#     directory with a trailing slash
#
# The hook reads the body from the command line, from --body-file/-F, or from
# a `$(cat FILE)` substitution. HTML comments in the body do not count.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
. "$(dirname "$0")/lib/policy.sh"
set -f

fw_read_input
cmd=$(fw_get '.tool_input.command')
[ -z "$cmd" ] && exit 0
printf '%s' "$cmd" | grep -qE "(^|[;&|[:space:]])(gh[[:space:]]+pr[[:space:]]+(create|new|edit)|glab[[:space:]]+mr[[:space:]]+(create|new|update)|tea[[:space:]]+(pr|pulls)[[:space:]]+create)([[:space:]]|$)" || exit 0
# An edit that does not replace the body (a new base branch, a label) passes.
# Only the flags of the gh or glab command itself count, not those of a
# chained `git commit -F msg && gh pr edit --base main`.
edit_seg=$(printf '%s\n' "$cmd" | grep -oE "(gh[[:space:]]+pr[[:space:]]+edit|glab[[:space:]]+mr[[:space:]]+update)[^;&|]*" | head -1)
if [ -n "$edit_seg" ] && \
   ! printf '%s' "$edit_seg" | grep -qE "[[:space:]](--body|--body-file|-b|-F|--description|-d)([[:space:]=]|$)"; then
  exit 0
fi
fw_enter_project
cd "$FW_ROOT" 2>/dev/null || exit 0

# --- what the branch changes ---
yellow=""
code=""
tests=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  t=$(fw_path_tier "$FW_ROOT/$f")
  case "$t" in yellow*) yellow="$yellow
- $f (${t#yellow })" ;; esac
  if fw_is_test_change "$f"; then
    tests="$tests $f"
  elif printf '%s' "$f" | grep -qE "$FW_CODE_RE"; then
    code="$code
- $f"
  fi
done <<EOF2
$(fw_changed_files)
EOF2
[ -z "$yellow" ] && [ -z "$code" ] && exit 0

# --- the body ---
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

# The body without HTML comments (the template's instructions).
clean=$(printf '%s\n' "$body" | awk '
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
    print line
  }')

# section <marker>. Text after the marker, up to the next markdown heading.
section() {
  printf '%s\n' "$clean" | awk -v m="$1" '
    insec && /^#+[ \t]/ { exit }
    insec { print; next }
    (p = index($0, m)) > 0 {
      insec = 1
      # Text after an inline marker ("Security-Review: x") counts. The rest
      # of a heading line ("## Spec gaps and assumptions") does not.
      rest = substr($0, p + length(m))
      if (m !~ /^#/ && rest ~ /[^ \t]/) print rest
    }'
}
# Lines that say something: no placeholders, not empty, not a bare "none".
real_lines() {
  grep -vE '<[A-Za-z][^>]*>|\{\{' | grep -viE '^[[:space:]]*([-*][[:space:]]*)?(none|n/a|tbd|todo)?[[:space:]]*\.?[[:space:]]*$' || true
}

problems=""
problem() { problems="$problems

- $1"; }

# --- code changes ---
if [ -n "$code" ]; then
  if [ -z "$tests" ] && ! printf '%s' "$clean" | grep -q 'No-Test-Reason:'; then
    problem "The branch changes code and no test file. Add the tests (regression test for a fix, integration or e2e test for new behavior). If no test can cover it, add a line: No-Test-Reason: <why>."
  fi

  if ! printf '%s' "$clean" | grep -q '## Verification'; then
    problem "No '## Verification' section. Run the verify-spec skill and add one row per acceptance criterion: | Criterion | Result | Evidence |."
  else
    rows=$(section '## Verification' | awk -F'|' '
      /^[ \t]*\|/ {
        result = $3; evidence = $4
        gsub(/^[ \t]+|[ \t]+$/, "", result); gsub(/^[ \t]+|[ \t]+$/, "", evidence)
        if (result ~ /^(PASS|FAIL|NOT VERIFIED)/ && evidence != "" && evidence !~ /^<.*>$/) print
      }')
    if [ -z "$rows" ]; then
      problem "The '## Verification' table has no filled row. Each row needs a criterion, a result (PASS, FAIL, or NOT VERIFIED), and the evidence path or the reason it was not verified."
    fi
  fi

  # The branch needs the user's approval of the spec (scripts/approve-spec.sh),
  # and the Spec: line must name the approved file.
  spec=$(printf '%s\n' "$clean" | grep -E '^[[:space:]]*[-*]?[[:space:]]*(\*\*)?Spec:' | head -1 | sed -E 's/.*Spec:(\*\*)?[[:space:]]*//; s/[[:space:]]+$//; s/^`//; s/`$//')
  if [ "${FW_SPEC_GATE:-}" = off ]; then
    [ -n "$spec" ] || problem "No 'Spec:' line. Point it at the spec the change implements."
  elif ! approved=$(fw_spec_approval); then
    problem "Spec approval: $approved Write the spec with the user (spec skill), then the user runs: scripts/approve-spec.sh docs/specs/<feature>.md"
  elif [ "$approved" = none ]; then
    [ -n "$spec" ] || problem "No 'Spec:' line. The user approved this branch without a spec, so write: Spec: none (approved without a spec)."
  elif [ -z "$spec" ] || ! printf '%s' "$spec" | grep -qF -- "$approved"; then
    problem "The 'Spec:' line must name the approved spec: Spec: $approved"
  fi

  if ! printf '%s' "$clean" | grep -qi '## Spec gaps'; then
    problem "No '## Spec gaps and assumptions' section. List each place the spec was silent or unclear and what you chose, or write none. This is where intent and code can drift apart."
  elif [ -z "$(section '## Spec gaps' | grep -vE '^[[:space:]]*([-*][[:space:]]*)?$' | grep -vE '<[A-Za-z][^>]*>|\{\{')" ]; then
    problem "The '## Spec gaps and assumptions' section is empty. List each gap and the choice you made, or write none."
  fi
fi

# --- Yellow paths ---
if [ -n "$yellow" ]; then
  before=$problems
  content=$(section 'Security-Review:' | real_lines)
  if ! printf '%s' "$clean" | grep -q 'Security-Review:'; then
    problem "No 'Security-Review:' section, and the branch changes Yellow-tier files."
  elif [ -z "$content" ]; then
    problem "The 'Security-Review:' section is empty, says none, or holds the template placeholders, and the branch changes Yellow-tier files."
  else
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
      [ "$covered" = 1 ] || missing="$missing $f"
    done <<EOF2
$(printf '%s\n' "$yellow" | sed -nE 's/^- (.*) \([^)]*\)$/\1/p')
EOF2
    [ -n "$missing" ] && problem "The 'Security-Review:' section does not name:$missing"
  fi
  [ "$problems" != "$before" ] && problems="$problems

Security-Review format, one line per Yellow file or directory:
- <file or directory/>: <risk you checked> -> <how the change handles it, with the test name>
Yellow files on this branch:$yellow"
fi

[ -z "$problems" ] && exit 0
fw_block "Blocked by pr-gate. Fix the PR body, then run the command again:$problems

Write the body to a file and pass --body-file, so it survives shell quoting. The template is .claude/pull_request_template.md."
