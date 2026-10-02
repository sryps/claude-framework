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

# fw_sha256 <file>. GNU coreutils or macOS shasum.
fw_sha256() {
  if fw_have sha256sum; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# fw_block <message>. Exit 2 blocks the tool call or the stop and sends
# stderr back to Claude.
fw_block() {
  printf '%s\n' "$1" >&2
  exit 2
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
