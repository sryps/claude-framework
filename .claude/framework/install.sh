#!/usr/bin/env bash
# Configure the framework in a project. Everything lives in the project's
# .claude/ directory, so it travels with the repo and every clone gets it.
#
# Two ways to use it:
#   Fork or template: the framework is already in the repo. Run with no target
#     to pick stack overlays and write settings:   .claude/framework/install.sh
#   Existing project: run from a framework checkout with the project as target.
#     It copies the framework into the project:     .claude/framework/install.sh ~/code/app
#
# It writes:
#   .claude/settings.json             base + hook wiring + overlays, merged into any existing file
#   .claude/settings.autonomous.json  autonomous profile + cloud overlay, used on top of settings.json
#   .claude/{hooks,skills,agents,rules,output-styles,framework}/   (existing project only)
#   scripts/security-check.sh, scripts/claude-autonomous.sh, .githooks/
#   CLAUDE.md, SECURITY.md, .claude/pull_request_template.md   only when absent
#   .github/                          PR template, workflows, Dependabot (--ci github, or auto on a GitHub remote)
#   .gitignore                        secret patterns, when missing
#
# Updates: re-run from a newer framework checkout. A framework file you edited
# is kept and reported (the manifest .claude/framework/manifest.tsv records
# what was installed). --force replaces it and keeps a .bak copy.
#
# Usage: install.sh [options] [TARGET_DIR]
#   --overlay LIST     comma list: node,python,rust,go,docker,terraform,supabase,expo-eas,cloud,sandbox
#                      default: auto-detect from the target
#   --sandbox          add the sandbox overlay (needs bubblewrap on Linux/WSL2, built in on macOS)
#   --no-autonomous    skip .claude/settings.autonomous.json
#   --ci MODE          auto (default): GitHub files only when origin is on github.com
#                      github: always write them. none: never write them
#   --git-hooks        set core.hooksPath to .githooks when it is unset
#   --force            replace edited framework files and templates (a .bak copy is kept)
#   --dry-run          print what would change, write nothing
#   --check            like --dry-run, but exit 1 when anything would change
#   -h, --help
#
# Runs on bash 3.2+ (macOS), Linux, and WSL. Needs jq and git.
set -euo pipefail

SRC=$(cd "$(dirname "$0")/../.." && pwd)
FWD="$SRC/.claude/framework"
VERSION=$(cat "$FWD/VERSION" 2>/dev/null || echo unknown)

overlays="auto"
sandbox=0
autonomous=1
ci=auto
git_hooks=0
force=0
dry=0
check=0
target=""

usage() { sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

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
    --force) force=1 ;;
    --dry-run) dry=1 ;;
    --check) dry=1; check=1 ;;
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

target=${target:-$SRC}
[ -d "$target" ] || { echo "Target directory not found: $target" >&2; exit 1; }
target=$(cd "$target" && pwd)
inplace=0
[ "$(cd "$target" && pwd -P)" = "$(cd "$SRC" && pwd -P)" ] && inplace=1

changes=0
say() { printf '  %s\n' "$1"; }
changed() { changes=$((changes + 1)); say "$1"; }
rel() { printf '%s' "${1#"$target"/}"; }

sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# --- manifest of framework-owned files (existing-project installs) ---
manifest="$target/.claude/framework/manifest.tsv"
old_manifest=""
[ -f "$manifest" ] && old_manifest=$(cat "$manifest")
new_manifest=""
recorded_sha() { printf '%s\n' "$old_manifest" | awk -F '\t' -v p="$1" '$1 == p {print $2}'; }

# sync_file <src> <dest>. Framework-owned file: replace when unchanged since
# the last install, keep and report when the user edited it.
sync_file() {
  local src=$1 dest=$2 r new cur rec
  r=$(rel "$dest")
  new=$(sha "$src")
  new_manifest="$new_manifest$r	$new
"
  if [ -f "$dest" ]; then
    cur=$(sha "$dest")
    [ "$cur" = "$new" ] && return 0
    rec=$(recorded_sha "$r")
    if [ "$cur" != "$rec" ] && [ "$force" = 0 ]; then
      say "keep     $r (edited locally; --force to replace)"
      return 0
    fi
  fi
  if [ "$dry" = 1 ]; then changed "[dry-run] write $r"; return 0; fi
  mkdir -p "$(dirname "$dest")"
  [ -f "$dest" ] && [ "$force" = 1 ] && cp -p "$dest" "$dest.bak"
  cp -p "$src" "$dest"
  changed "write    $r"
}

# write_once <src> <dest>. Template the project owns after the first copy.
write_once() {
  local src=$1 dest=$2
  if [ -e "$dest" ] && [ "$force" = 0 ]; then return 0; fi
  [ -e "$dest" ] && cmp -s "$src" "$dest" && return 0
  if [ "$dry" = 1 ]; then changed "[dry-run] write $(rel "$dest")"; return 0; fi
  mkdir -p "$(dirname "$dest")"
  [ -e "$dest" ] && cp -p "$dest" "$dest.bak"
  cp -p "$src" "$dest"
  changed "write    $(rel "$dest")"
}

# install_json <dest> <generated>
install_json() {
  local dest=$1 src=$2
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then return 0; fi
  if [ "$dry" = 1 ]; then
    changed "[dry-run] write $(rel "$dest")"
    if [ -f "$dest" ]; then diff -u "$dest" "$src" | sed 's/^/      /' | head -40 || true; fi
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  changed "write    $(rel "$dest")"
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
  { ls "$target"/*.tf >/dev/null 2>&1 || [ -d "$target/terraform" ]; } && o="$o,terraform"
  printf '%s' "${o#,}"
}
if [ "$overlays" = auto ]; then
  overlays=$(detect_overlays)
  # Keep overlays chosen on an earlier run.
  if [ -f "$target/.claude/framework/installed.json" ]; then
    prev=$(jq -r '.overlays | join(",")' "$target/.claude/framework/installed.json" 2>/dev/null || true)
    overlays="$prev,$overlays"
  fi
fi
[ "$sandbox" = 1 ] && overlays="$overlays,sandbox"
overlays=$(printf '%s' "$overlays" | tr ',' '\n' | awk 'NF && !seen[$0]++' | paste -sd, - || true)
for o in $(printf '%s' "$overlays" | tr ',' ' '); do
  [ -f "$FWD/settings/overlays/$o.json" ] || { echo "Unknown overlay: $o" >&2; exit 1; }
done

echo "framework $VERSION -> $target ($([ "$inplace" = 1 ] && echo "configure in place" || echo "install into project"))"
say "overlays: ${overlays:-none}"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/fw-install.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# --- copy the framework (existing project only) ---
if [ "$inplace" = 0 ]; then
  for dir in hooks skills agents rules output-styles framework; do
    [ -d "$SRC/.claude/$dir" ] || continue
    ( cd "$SRC/.claude/$dir" && find . -type f ! -name '*.bak' ! -name 'manifest.tsv' ! -name 'installed.json' | sed 's|^\./||' | sort ) >"$tmp/files"
    while IFS= read -r f; do
      sync_file "$SRC/.claude/$dir/$f" "$target/.claude/$dir/$f"
    done <"$tmp/files"
  done
  for f in scripts/security-check.sh scripts/claude-autonomous.sh scripts/approve-spec.sh .githooks/pre-commit .githooks/pre-push; do
    sync_file "$SRC/$f" "$target/$f"
  done
fi

# --- settings ---
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

layers="$FWD/settings/base.json $FWD/settings/hooks.json"
for o in $(printf '%s' "$overlays" | tr ',' ' '); do
  layers="$layers $FWD/settings/overlays/$o.json"
done
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
install_json "$existing" "$tmp/settings.json"

if [ "$autonomous" = 1 ]; then
  # Passed with --settings on top of the project settings. Claude Code
  # combines permission lists across settings files, so this file holds only
  # the autonomous additions. It is generated: re-running replaces it.
  auto_layers="$FWD/settings/autonomous.json"
  case ",$overlays," in *,cloud,*) ;; *) auto_layers="$auto_layers $FWD/settings/overlays/cloud.json" ;; esac
  # shellcheck disable=SC2086
  merge_json $auto_layers >"$tmp/autonomous.json"
  install_json "$target/.claude/settings.autonomous.json" "$tmp/autonomous.json"
fi

# --- templates the project owns ---
write_once "$FWD/templates/CLAUDE.md" "$target/CLAUDE.md"
write_once "$FWD/templates/SECURITY.md" "$target/SECURITY.md"
write_once "$FWD/templates/pull_request_template.md" "$target/.claude/pull_request_template.md"

if [ "$ci" = auto ]; then
  ci=none
  git -C "$target" remote get-url origin 2>/dev/null | grep -q 'github\.com' && ci=github
fi
say "ci: $ci"
if [ "$ci" = github ]; then
  write_once "$FWD/templates/pull_request_template.md" "$target/.github/pull_request_template.md"
  write_once "$FWD/templates/ci/github/security.yml" "$target/.github/workflows/security.yml"
  write_once "$FWD/templates/ci/github/dependabot.yml" "$target/.github/dependabot.yml"
fi

if [ "$git_hooks" = 1 ]; then
  if git -C "$target" rev-parse --git-dir >/dev/null 2>&1; then
    current=$(git -C "$target" config --get core.hooksPath || true)
    if [ -z "$current" ]; then
      if [ "$dry" = 1 ]; then changed "[dry-run] set core.hooksPath=.githooks"
      else git -C "$target" config core.hooksPath .githooks; changed "set      core.hooksPath=.githooks"; fi
    elif [ "$current" != .githooks ]; then
      say "keep     core.hooksPath=$current (call scripts/security-check.sh from your hooks)"
    fi
  else
    say "skip     core.hooksPath (target is not a git repo)"
  fi
fi

# --- .gitignore ---
gi="$target/.gitignore"
missing=""
for line in ".env" ".env.*" "!.env.example" "*.pem" "*.key" ".claude/settings.local.json" ".claude/runs/" ".vuln-scan/" "*.bak"; do
  grep -qxF -- "$line" "$gi" 2>/dev/null || missing="$missing$line
"
done
if [ -n "$missing" ]; then
  if [ "$dry" = 1 ]; then
    changed "[dry-run] append to .gitignore: $(printf '%s' "$missing" | tr '\n' ' ')"
  else
    { [ -s "$gi" ] && [ -n "$(tail -c1 "$gi")" ] && echo; echo "# framework: secrets and local agent state"; printf '%s' "$missing"; } >>"$gi"
    changed "append   .gitignore"
  fi
fi

# --- record ---
if [ "$dry" = 0 ]; then
  rec="$target/.claude/framework/installed.json"
  jq -n --arg v "$VERSION" --arg o "$overlays" \
    '{version: $v, overlays: ($o | split(",") | map(select(. != "")))}' >"$tmp/installed.json"
  cmp -s "$tmp/installed.json" "$rec" 2>/dev/null || { mkdir -p "$(dirname "$rec")"; cp "$tmp/installed.json" "$rec"; }
  if [ "$inplace" = 0 ]; then
    printf '%s' "$new_manifest" | sort >"$tmp/manifest.tsv"
    cmp -s "$tmp/manifest.tsv" "$manifest" 2>/dev/null || cp "$tmp/manifest.tsv" "$manifest"
  fi
fi

if [ "$check" = 1 ]; then
  if [ "$changes" -gt 0 ]; then echo "check: $changes change(s) pending"; exit 1; fi
  echo "check: up to date"
  exit 0
fi

[ "$dry" = 1 ] && exit 0
cat <<EOF

Done ($changes change(s)). Next steps:
  1. Fill in the placeholders in CLAUDE.md (purpose, stack, commands).
  2. Install the guard tools: jq (required), gitleaks, semgrep. See .claude/framework/README.md.
  3. Run the local checks: scripts/security-check.sh
  4. Review and commit: git -C "$target" status --short
  5. Start Claude Code in the project. It loads .claude/ on its own.
  6. Unattended run: scripts/claude-autonomous.sh "<task>"
EOF
