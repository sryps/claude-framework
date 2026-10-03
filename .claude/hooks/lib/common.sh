#!/usr/bin/env bash
# Shared helpers for framework hooks. Source it, do not run it.
#
# Portability contract: bash 3.2 (macOS default), BSD and GNU userland.
# No mapfile, no associative arrays, no ${var,,}, no `grep -P`, no `sed -i`,
# no `\b` in regexes (BSD grep does not promise it), no `readlink -f`.

# GUI apps on macOS do not inherit the login shell PATH. Add the usual
# Homebrew and user locations so jq, gitleaks, and semgrep resolve.
PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/go/bin:$HOME/.cargo/bin:$PATH"
export PATH

# Word boundary stand-ins for ERE. Use as "${FW_B}word${FW_E}".
FW_B='(^|[^A-Za-z0-9_])'
FW_E='($|[^A-Za-z0-9_])'

FW_INPUT=""
FW_HAS_JQ=0
command -v jq >/dev/null 2>&1 && FW_HAS_JQ=1

fw_read_input() {
  FW_INPUT=$(cat)
}

# fw_get <jq filter>. Prints "" when jq is missing or the field is absent.
fw_get() {
  [ "$FW_HAS_JQ" = 1 ] || return 0
  printf '%s' "$FW_INPUT" | jq -r "$1 // empty" 2>/dev/null
}

fw_autonomous() {
  [ "${CLAUDE_PROFILE:-}" = autonomous ]
}

fw_have() {
  command -v "$1" >/dev/null 2>&1
}

# Move into the session cwd, then the repo root. Sets FW_ROOT.
fw_enter_project() {
  local cwd
  cwd=$(fw_get '.cwd')
  [ -n "$cwd" ] && { cd "$cwd" 2>/dev/null || true; }
  FW_ROOT=${CLAUDE_PROJECT_DIR:-}
  if [ -z "$FW_ROOT" ]; then
    FW_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  fi
}

fw_state_dir() {
  local session dir
  session=$(fw_get '.session_id')
  [ -z "$session" ] && session=unknown
  dir="${TMPDIR:-/tmp}/claude-framework/$session"
  mkdir -p "$dir" 2>/dev/null
  printf '%s' "$dir"
}

# fw_timeout <seconds> <command string>. Uses timeout, gtimeout, or perl.
# Exit 124 means the command timed out.
fw_timeout() {
  local secs=$1; shift
  if fw_have timeout; then
    timeout "$secs" bash -c "$1"
  elif fw_have gtimeout; then
    gtimeout "$secs" bash -c "$1"
  elif fw_have perl; then
    perl -e '
      my $s = shift; my $pid = fork();
      if ($pid == 0) { setpgrp(0, 0); exec("bash", "-c", shift) or exit 127 }
      local $SIG{ALRM} = sub { kill("TERM", -$pid); sleep 2; kill("KILL", -$pid); exit 124 };
      alarm $s; waitpid($pid, 0); exit($? >> 8);
    ' "$secs" "$1"
  else
    bash -c "$1"
  fi
}

# fw_redact <text>. Masks values that may be secrets: the value after a
# key-like name (token=, password:, Authorization: Bearer ...), and any run of
# 20 or more token characters (keys, JWTs, hashes). Keeps the first 4 chars.
fw_redact() {
  # Case-insensitive key match in awk (BSD sed has no I flag), then the
  # long-token and URL-password rules in portable sed.
  printf '%s\n' "$1" | awk '{
    s = $0; l = tolower(s); out = ""
    re = "(pass(word)?|passwd|pwd|secret|token|api[_-]?key|apikey|access[_-]?key|authorization|auth|bearer|basic|cookie|session|private[_-]?key|client[_-]?secret)[\"\047]?[ \t]*[:= ][ \t]*[\"\047]?"
    while (match(l, re)) {
      cut = RSTART + RLENGTH - 1
      out = out substr(s, 1, cut); s = substr(s, cut + 1); l = substr(l, cut + 1)
      if (match(l, /^[^"\047 \t&]+/)) {
        word = substr(l, 1, RLENGTH)
        out = out "[REDACTED]"; s = substr(s, RLENGTH + 1); l = substr(l, RLENGTH + 1)
        # "Authorization: Bearer <token>": the scheme is not the secret, the
        # next word is.
        if (word == "bearer" || word == "basic" || word == "token" || word == "digest") {
          if (match(l, /^[ \t]+[^"\047 \t&]+/)) {
            out = out " [REDACTED]"; s = substr(s, RLENGTH + 1); l = substr(l, RLENGTH + 1)
          }
        }
      }
    }
    s = out s
    # Long tokens: 20+ chars from [A-Za-z0-9_+=-] that contain a digit.
    # Paths and hyphenated names stay readable ("/" and "." end a token).
    out = ""; tok = ""
    for (i = 1; i <= length(s) + 1; i++) {
      c = (i <= length(s)) ? substr(s, i, 1) : ""
      if (c != "" && c ~ /[A-Za-z0-9_+=-]/) { tok = tok c; continue }
      if (length(tok) >= 20 && tok ~ /[0-9]/) tok = substr(tok, 1, 4) "[REDACTED]"
      out = out tok c; tok = ""
    }
    print out
  }' | sed -E 's#(://[^:/@[:space:]]+:)[^@/[:space:]]+@#\1[REDACTED]@#g'
}

# fw_log_warning <one line>. Appends an advisory finding to
# .claude/runs/warnings.log (gitignored), so nothing a hook let through gets
# lost: warnings-report.sh puts the session's warnings in front of the user
# at the end of a run, in the final report and the PR.
# Format: time<TAB>session<TAB>hook<TAB>tool detail<TAB>finding
fw_log_warning() {
  local root dir session hook detail line
  root=${FW_ROOT:-${CLAUDE_PROJECT_DIR:-}}
  [ -z "$root" ] && root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  dir="$root/.claude/runs"
  mkdir -p "$dir" 2>/dev/null || return 0
  session=$(fw_get '.session_id'); [ -z "$session" ] && session=unknown
  hook=$(basename "$0" .sh)
  detail=$(fw_get '.tool_input.command // .tool_input.file_path // .tool_input.notebook_path' | head -1 | cut -c1-200)
  # The log ends up in the final report, the PR body, and PR comments, so
  # redact anything that may be a secret before it is written.
  line=$(printf '%s\t%s\t%s\t%s\t%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$session" "$hook" "$(fw_redact "$detail")" "$(fw_redact "$1")" | tr '\n' ' ')
  printf '%s\n' "$line" >>"$dir/warnings.log" 2>/dev/null || true
}

# fw_sha256 <file>. GNU coreutils or macOS shasum.
fw_sha256() {
  if fw_have sha256sum; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# fw_block <message>. Exit 2 blocks the tool call or the stop and sends
# stderr back to Claude.
#
# Advisory by default: the action goes ahead, Claude gets the finding as
# context, and the user sees a one-line warning. A human sets FW_ENFORCE=1
# in the settings env block to make the finding block instead (exit 2).
fw_enforcing() {
  [ "${FW_ENFORCE:-}" = 1 ]
}
fw_block() {
  local msg=$1 ev first
  if fw_enforcing; then
    printf '%s\n' "$msg" >&2
    exit 2
  fi
  # Reword for advisory mode: a recommendation, not a block.
  msg=$(printf '%s\n' "$msg" | sed -E '1s/^Blocked by ([A-Za-z-]+)/Recommendation from \1 (not blocked)/')
  first=$(printf '%s\n' "$msg" | head -1 | cut -c1-160)
  ev=$(fw_get '.hook_event_name')
  fw_log_warning "$first"
  if [ "$FW_HAS_JQ" = 1 ]; then
    case "$ev" in
      PreToolUse|PostToolUse|UserPromptSubmit)
        jq -n --arg ev "$ev" --arg ctx "$msg" --arg m "$first" \
          '{systemMessage: ("! " + $m), hookSpecificOutput: {hookEventName: $ev, additionalContext: $ctx}}' ;;
      *)
        jq -n --arg m "$msg" '{systemMessage: $m}' ;;
    esac
  else
    printf '%s\n' "$msg"
  fi
  exit 0
}

# fw_context <event> <context> [visible message]
fw_context() {
  if [ "$FW_HAS_JQ" = 1 ]; then
    jq -n --arg ev "$1" --arg ctx "$2" --arg msg "${3:-}" '
      {suppressOutput: true,
       hookSpecificOutput: {hookEventName: $ev, additionalContext: $ctx}}
      + (if $msg == "" then {} else {systemMessage: $msg} end)'
  else
    printf '%s\n' "$2"
  fi
}

# fw_default_branch. origin/HEAD if known, else main or master if present.
fw_default_branch() {
  local ref
  ref=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$ref" ]; then
    printf '%s' "${ref#refs/remotes/origin/}"
    return
  fi
  for ref in main master; do
    if git show-ref --verify --quiet "refs/heads/$ref"; then
      printf '%s' "$ref"
      return
    fi
  done
  printf 'main'
}

# fw_is_protected_branch <name>
fw_is_protected_branch() {
  case "$1" in
    main|master|trunk|production|prod|release|release/*) return 0 ;;
  esac
  [ "$1" = "$(fw_default_branch)" ]
}

# fw_changed_files. Files changed on this branch vs the default branch,
# plus staged, unstaged, and untracked files. One per line, existing only.
fw_changed_files() {
  local base mb
  base=$(fw_default_branch)
  mb=$(git merge-base HEAD "$base" 2>/dev/null || true)
  {
    [ -n "$mb" ] && git diff --name-only "$mb" HEAD 2>/dev/null
    git diff --name-only HEAD 2>/dev/null
    git diff --name-only --cached 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | sort -u | while IFS= read -r f; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}
