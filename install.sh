#!/usr/bin/env bash
# Install the claude-framework project files into a target repository.
#
# The plugin ships hooks, skills, and agents. Plugins cannot set permissions,
# env, or output styles reliably, so this script writes those into the target:
#
#   .claude/settings.json             base + stack overlays, merged into any existing file
#   .claude/settings.autonomous.json  the above + autonomous profile + cloud overlay
#   .claude/rules/*.md                domain rules
#   .claude/output-styles/*.md        Terse and Autonomous styles
#   .claude/framework.json            what was installed, for re-runs
#   scripts/security-check.sh         local secret, SAST, CVE, and IaC checks
#   CLAUDE.md, SECURITY.md            templates, only when absent (or --force)
#   .github/                          PR template and workflows (--ci github, or auto on a GitHub remote)
#   .githooks/                        pre-commit and pre-push checks (--git-hooks)
#   .gitignore                        secret patterns appended when missing
#
# Usage: ./install.sh [options] [TARGET_DIR]
#   --overlay LIST     comma list: node,python,rust,go,docker,terraform,supabase,expo-eas,cloud,sandbox
#                      default: auto-detect from the target
#   --sandbox          add the sandbox overlay (needs bubblewrap on Linux/WSL2, built in on macOS)
#   --no-autonomous    skip .claude/settings.autonomous.json
#   --ci MODE          auto (default): GitHub files only when origin is on github.com
#                      github: always write them. none: never write them
#   --git-hooks        install .githooks/ and set core.hooksPath when it is unset
#   --plugin-local     point the marketplace at this checkout instead of its git remote
#   --force            overwrite template files (a .bak copy is kept)
#   --dry-run          print what would change, write nothing
#   -h, --help
#
# Runs on bash 3.2+ (macOS), Linux, and WSL. Needs jq.
set -euo pipefail

FW_DIR=$(cd "$(dirname "$0")" && pwd)
VERSION=$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$FW_DIR/.claude-plugin/plugin.json" | head -1)

overlays="auto"
sandbox=0
autonomous=1
ci=auto
git_hooks=0
plugin_local=0
force=0
dry=0
target=""

usage() { sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --overlay) overlays=${2:?--overlay needs a value}; shift ;;
    --overlay=*) overlays=${1#*=} ;;
    --sandbox) sandbox=1 ;;
    --no-autonomous) autonomous=0 ;;
    --ci) ci=${2:?--ci needs auto, github, or none}; shift ;;
    --ci=*) ci=${1#*=} ;;
    --no-ci) ci=none ;;
    --git-hooks) git_hooks=1 ;;
    --plugin-local) plugin_local=1 ;;
    --force) force=1 ;;
    --dry-run) dry=1 ;;
    -h|--help) usage 0 ;;
    -*) echo "Unknown option: $1" >&2; usage 1 ;;
    *) target=$1 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || {
  echo "jq is required. Install it: brew install jq (macOS), sudo apt install jq (Debian, Ubuntu, WSL)." >&2
  exit 1
}

case "$ci" in auto|github|none) ;; *) echo "--ci must be auto, github, or none" >&2; exit 1 ;; esac
target=${target:-$PWD}
[ -d "$target" ] || { echo "Target directory not found: $target" >&2; exit 1; }
target=$(cd "$target" && pwd)
if [ "$target" = "$FW_DIR" ]; then
  echo "Target is the framework checkout itself. Pass the project directory." >&2
  exit 1
fi

say() { printf '  %s\n' "$1"; }
run() { if [ "$dry" = 1 ]; then say "[dry-run] $*"; else "$@"; fi; }

# write_file <dest> <src>. Skips an existing file unless --force.
write_file() {
  local dest=$1 src=$2
  if [ -e "$dest" ] && [ "$force" = 0 ]; then
    if cmp -s "$src" "$dest"; then return; fi
    say "keep     ${dest#"$target"/} (exists; --force to replace)"
    return
  fi
  if [ "$dry" = 1 ]; then say "[dry-run] write ${dest#"$target"/}"; return; fi
  mkdir -p "$(dirname "$dest")"
  [ -e "$dest" ] && cp "$dest" "$dest.bak"
  cp "$src" "$dest"
  say "write    ${dest#"$target"/}"
}

# --- detect overlays ---
detect_overlays() {
  local o=""
  [ -f "$target/package.json" ] && o="$o,node"
  [ -f "$target/package.json" ] && grep -q '"expo"' "$target/package.json" && o="$o,expo-eas"
  [ -f "$target/supabase/config.toml" ] && o="$o,supabase"
  [ -f "$target/Cargo.toml" ] && o="$o,rust"
  [ -f "$target/go.mod" ] && o="$o,go"
  { [ -f "$target/pyproject.toml" ] || [ -f "$target/requirements.txt" ]; } && o="$o,python"
  { [ -f "$target/Dockerfile" ] || [ -f "$target/compose.yaml" ] || [ -f "$target/docker-compose.yml" ]; } && o="$o,docker"
  ls "$target"/*.tf >/dev/null 2>&1 && o="$o,terraform"
  [ -d "$target/terraform" ] && o="$o,terraform"
  printf '%s' "${o#,}"
}
[ "$overlays" = auto ] && overlays=$(detect_overlays)
[ "$sandbox" = 1 ] && overlays="${overlays:+$overlays,}sandbox"
overlays=$(printf '%s' "$overlays" | tr ',' '\n' | awk 'NF && !seen[$0]++' | paste -sd, -)

for o in $(printf '%s' "$overlays" | tr ',' ' '); do
  [ -f "$FW_DIR/settings/overlays/$o.json" ] || { echo "Unknown overlay: $o" >&2; exit 1; }
done

echo "claude-framework $VERSION -> $target"
say "overlays: ${overlays:-none}"

# --- merge settings ---
# Objects merge deeply. Arrays union in order. A scalar from a later file wins.
JQ_MERGE='
def uniq: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
def merge($a; $b):
  if ($a|type) == "object" and ($b|type) == "object" then
    reduce ($b|keys_unsorted[]) as $k ($a; .[$k] = merge($a[$k]; $b[$k]))
  elif ($a|type) == "array" and ($b|type) == "array" then ($a + $b) | uniq
  elif $b == null then $a
  else $b end;
reduce .[] as $x ({}; merge(.; $x))
'
merge_json() { jq -s "$JQ_MERGE" "$@"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/fw-install.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

layers="$FW_DIR/settings/base.json"
for o in $(printf '%s' "$overlays" | tr ',' ' '); do
  layers="$layers $FW_DIR/settings/overlays/$o.json"
done

# Marketplace source: the remote this checkout was cloned from, so forks and
# mirrors point at themselves. --plugin-local, or no remote, uses this directory.
origin=$(git -C "$FW_DIR" remote get-url origin 2>/dev/null || true)
gh_slug=$(printf '%s' "$origin" | sed -nE 's#^(https://|git@|ssh://git@)github\.com[:/]([^/]+/[^/.]+)(\.git)?/?$#\2#p')
if [ "$plugin_local" = 1 ] || [ -z "$origin" ]; then
  market_add=$FW_DIR
  jq -n --arg p "$FW_DIR" '{source: "directory", path: $p}' >"$tmp/src.json"
elif [ -n "$gh_slug" ]; then
  market_add=$gh_slug
  jq -n --arg r "$gh_slug" '{source: "github", repo: $r}' >"$tmp/src.json"
else
  market_add=$origin
  jq -n --arg u "$origin" '{source: "git", url: $u}' >"$tmp/src.json"
fi
jq -n --slurpfile s "$tmp/src.json" '{extraKnownMarketplaces: {"agent-guardrails": {source: $s[0]}}}' >"$tmp/market.json"
layers="$layers $tmp/market.json"

existing="$target/.claude/settings.json"
if [ -f "$existing" ]; then
  jq empty "$existing" 2>/dev/null || { echo "Existing $existing is not valid JSON. Fix it first." >&2; exit 1; }
  # Existing values win for scalars; arrays union.
  # shellcheck disable=SC2086
  merge_json $layers "$existing" >"$tmp/settings.json"
else
  # shellcheck disable=SC2086
  merge_json $layers >"$tmp/settings.json"
fi

install_json() {
  local dest=$1 src=$2
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then return; fi
  if [ "$dry" = 1 ]; then
    say "[dry-run] write ${dest#"$target"/}"
    [ -f "$dest" ] && diff -u "$dest" "$src" | sed 's/^/      /' | head -40 || true
    return
  fi
  mkdir -p "$(dirname "$dest")"
  [ -f "$dest" ] && cp "$dest" "$dest.bak"
  cp "$src" "$dest"
  say "write    ${dest#"$target"/}"
}
install_json "$existing" "$tmp/settings.json"

if [ "$autonomous" = 1 ]; then
  # The autonomous file is passed with --settings. It repeats the full deny
  # list, so it is safe whether or not Claude Code merges arrays across files.
  auto_layers="$tmp/settings.json $FW_DIR/settings/autonomous.json"
  case ",$overlays," in *,cloud,*) ;; *) auto_layers="$auto_layers $FW_DIR/settings/overlays/cloud.json" ;; esac
  # shellcheck disable=SC2086
  merge_json $auto_layers >"$tmp/autonomous.json"
  install_json "$target/.claude/settings.autonomous.json" "$tmp/autonomous.json"
fi

# --- rules, styles, templates ---
for f in "$FW_DIR"/rules/*.md; do
  [ -f "$f" ] && write_file "$target/.claude/rules/$(basename "$f")" "$f"
done
for f in "$FW_DIR"/templates/output-styles/*.md; do
  write_file "$target/.claude/output-styles/$(basename "$f")" "$f"
done
write_file "$target/CLAUDE.md" "$FW_DIR/templates/CLAUDE.md"
write_file "$target/SECURITY.md" "$FW_DIR/templates/SECURITY.md"
write_file "$target/scripts/security-check.sh" "$FW_DIR/templates/scripts/security-check.sh"
[ "$dry" = 0 ] && [ -f "$target/scripts/security-check.sh" ] && chmod +x "$target/scripts/security-check.sh"

if [ "$ci" = auto ]; then
  ci=none
  git -C "$target" remote get-url origin 2>/dev/null | grep -q 'github\.com' && ci=github
fi
say "ci: $ci"
if [ "$ci" = github ]; then
  write_file "$target/.github/pull_request_template.md" "$FW_DIR/templates/pull_request_template.md"
  write_file "$target/.github/workflows/security.yml" "$FW_DIR/templates/ci/github/security.yml"
  write_file "$target/.github/dependabot.yml" "$FW_DIR/templates/ci/github/dependabot.yml"
fi
# The PR template also lives in .claude/ so the feature skill finds it on any forge.
write_file "$target/.claude/pull_request_template.md" "$FW_DIR/templates/pull_request_template.md"

if [ "$git_hooks" = 1 ]; then
  for f in "$FW_DIR"/templates/githooks/*; do
    write_file "$target/.githooks/$(basename "$f")" "$f"
    [ "$dry" = 0 ] && chmod +x "$target/.githooks/$(basename "$f")"
  done
  if git -C "$target" rev-parse --git-dir >/dev/null 2>&1; then
    current=$(git -C "$target" config --get core.hooksPath || true)
    if [ -z "$current" ]; then
      run git -C "$target" config core.hooksPath .githooks
      say "set      core.hooksPath=.githooks"
    elif [ "$current" != .githooks ]; then
      say "keep     core.hooksPath=$current (call scripts/security-check.sh from your hooks)"
    fi
  else
    say "skip     core.hooksPath (target is not a git repo)"
  fi
fi
write_file "$target/scripts/claude-autonomous.sh" "$FW_DIR/scripts/run-autonomous.sh"
[ "$dry" = 0 ] && [ -f "$target/scripts/claude-autonomous.sh" ] && chmod +x "$target/scripts/claude-autonomous.sh"

# --- .gitignore ---
gi="$target/.gitignore"
missing=""
for line in ".env" ".env.*" "!.env.example" "*.pem" "*.key" ".claude/settings.local.json" ".claude/runs/" ".vuln-scan/"; do
  grep -qxF -- "$line" "$gi" 2>/dev/null || missing="$missing$line
"
done
if [ -n "$missing" ]; then
  if [ "$dry" = 1 ]; then
    say "[dry-run] append to .gitignore: $(printf '%s' "$missing" | tr '\n' ' ')"
  else
    { [ -s "$gi" ] && [ -n "$(tail -c1 "$gi")" ] && echo; echo "# claude-framework: secrets and local agent state"; printf '%s' "$missing"; } >>"$gi"
    say "append   .gitignore"
  fi
fi

# --- record ---
if [ "$dry" = 0 ]; then
  jq -n --arg v "$VERSION" --arg o "$overlays" --arg src "$FW_DIR" --arg d "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{version: $v, overlays: ($o | split(",") | map(select(. != ""))), source: $src, installedAt: $d}' \
    >"$target/.claude/framework.json"
fi

cat <<EOF

Done. Next steps:
  1. Install the plugin (hooks, skills, agents):
       claude plugin marketplace add $market_add
       claude plugin install agent-guardrails@agent-guardrails
     Or open Claude Code in the project and accept the plugin prompt.
  2. Fill in the placeholders in CLAUDE.md (purpose, stack, commands).
  3. Install the guard tools: jq, gitleaks, semgrep (see README).
  4. Run the local checks: scripts/security-check.sh
  5. Review and commit: git -C "$target" status --short
  6. Unattended run: scripts/claude-autonomous.sh "<task>"
EOF
