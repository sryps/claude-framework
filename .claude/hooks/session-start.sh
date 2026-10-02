#!/usr/bin/env bash
# SessionStart hook: inject the framework context.
#
#   - profile reminder (attended or autonomous) and the tier rules
#   - git state (branch, protected-branch warning, recent commits, changes)
#   - detected stack, so Claude knows which rules files apply
#   - missing tools the guards depend on
#
# Plain stdout is not reliably picked up as context. The JSON
# hookSpecificOutput.additionalContext form is used instead.
# Turn sections off with FW_SESSION_GIT=0 or FW_SESSION_TOOLS=0, for example
# when a user-level hook already reports git state.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"

fw_read_input
fw_enter_project
cd "$FW_ROOT" 2>/dev/null || true

out=""
add() { out="$out$1
"; }

if fw_autonomous; then
  add "## Framework: autonomous profile
Nobody is watching this run.
1. Never ask the user a question. Decide, record the decision, continue.
2. Loop build and test until green. A Stop hook reruns the tests and a secret and SAST scan.
3. Never skip or weaken a test. After 3 failed approaches, record it under Blocked.
4. Red tier is blocked by hooks: merge, push to a protected branch, force push, deploy, publish, secrets, prod data. Do not look for another spelling.
5. Yellow tier (auth, crypto, migrations, CI, infra, dependencies) is allowed on a branch. The PR needs a Security-Review: section.
6. End on a branch with a PR. Never merge it.
7. End with the full final report."
else
  add "## Framework: attended profile
Tiers: Green = do it. Yellow (auth, crypto, migrations, CI, infra, dependencies) = do it on a branch and add a Security-Review: section to the PR. Red (merge, protected-branch push, force push, deploy, publish, secrets, prod data) = hooks block it; ask the user instead."
fi

if [ "${FW_SESSION_GIT:-1}" != 0 ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch="(detached at $(git rev-parse --short HEAD 2>/dev/null))"
  add ""
  add "## Git state"
  add "Branch: $branch (default: $(fw_default_branch))"
  if fw_is_protected_branch "$branch"; then
    add "You are on a protected branch. Create a feature branch before the first commit: git switch -c <type>/<short-name>."
  fi
  upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
  if [ -n "$upstream" ]; then
    counts=$(git rev-list --left-right --count "$upstream"...HEAD 2>/dev/null)
    behind=$(printf '%s' "$counts" | awk '{print $1}')
    ahead=$(printf '%s' "$counts" | awk '{print $2}')
    if [ "${ahead:-0}" != 0 ] || [ "${behind:-0}" != 0 ]; then
      add "Vs $upstream: ${ahead:-0} ahead, ${behind:-0} behind"
    fi
  fi
  log=$(git log --oneline -5 2>/dev/null)
  [ -n "$log" ] && add "Recent commits:
$log"
  changes=$(git status --short 2>/dev/null)
  if [ -n "$changes" ]; then
    total=$(printf '%s\n' "$changes" | wc -l | tr -d ' ')
    add "Uncommitted ($total):
$(printf '%s\n' "$changes" | head -15)"
  else
    add "Working tree clean"
  fi
fi

stack=""
has() { [ -e "$1" ]; }
has package.json && stack="$stack node"
{ has tsconfig.json || ls tsconfig*.json >/dev/null 2>&1; } && stack="$stack typescript"
{ has next.config.js || has next.config.mjs || has next.config.ts; } && stack="$stack nextjs"
{ has app.json || has app.config.ts || has app.config.js; } && grep -qs '"expo"' package.json && stack="$stack expo"
has supabase/config.toml && stack="$stack supabase"
has Cargo.toml && stack="$stack rust"
has go.mod && stack="$stack go"
{ has pyproject.toml || has requirements.txt; } && stack="$stack python"
{ has Package.swift || ls ./*.xcodeproj >/dev/null 2>&1; } && stack="$stack swift"
{ has build.gradle || has build.gradle.kts; } && stack="$stack gradle"
{ has Dockerfile || has compose.yaml || has docker-compose.yml; } && stack="$stack docker"
ls ./*.tf >/dev/null 2>&1 && stack="$stack terraform"
if [ -n "$stack" ]; then
  add ""
  add "## Stack:$stack"
fi
if [ -d .claude/rules ]; then
  add "Rules live in .claude/rules/. Read the file for the area you change before you change it (security.md always)."
fi

if [ "${FW_SESSION_TOOLS:-1}" != 0 ]; then
  missing=""
  for t in jq git gitleaks; do fw_have "$t" || missing="$missing $t"; done
  if fw_autonomous; then fw_have semgrep || missing="$missing semgrep"; fi
  # The Linux sandbox needs bubblewrap and socat. Without them Claude Code
  # runs commands unsandboxed unless sandbox.failIfUnavailable is set.
  if [ "$(uname -s)" = Linux ] && [ "$FW_HAS_JQ" = 1 ] && \
     jq -e '.sandbox.enabled == true' "$FW_ROOT/.claude/settings.json" >/dev/null 2>&1; then
    sbx=""
    fw_have bwrap || sbx="$sbx bubblewrap"
    fw_have socat || sbx="$sbx socat"
    if [ -n "$sbx" ]; then
      missing="$missing$sbx"
      add ""
      add "## Sandbox is enabled but$sbx is missing
Commands run without the sandbox unless sandbox.failIfUnavailable is true. Tell the user to install it: sudo apt install$sbx."
    fi
  fi
  if [ -n "$missing" ]; then
    add ""
    add "## Missing tools:$missing"
    case "$missing" in *jq*) add "Without jq the guards fall back to raw matching and the test gates are off. Tell the user to install jq." ;; esac
  fi
fi

msg="framework: $(fw_autonomous && echo autonomous || echo attended)"
[ -n "${branch:-}" ] && msg="$msg · $branch"
[ -n "${missing:-}" ] && msg="$msg · missing:$missing"
fw_context SessionStart "$out" "$msg"
