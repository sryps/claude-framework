#!/usr/bin/env bash
# PostToolUse hook (Edit|Write|MultiEdit): format and lint the edited file.
#
# Uses only tools the project already has (node_modules/.bin, a venv, or the
# toolchain on PATH). A missing tool is skipped, never installed. Lint errors
# go back to Claude through exit 2. The edit itself stays.
#
# Opt out per project with FW_FORMAT_LINT=off.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"

[ "${FW_FORMAT_LINT:-}" = off ] && exit 0
fw_read_input
fw_enter_project
path=$(fw_get '.tool_input.file_path')
[ -z "$path" ] || [ ! -f "$path" ] && exit 0
cd "$FW_ROOT" 2>/dev/null || exit 0

bin() {
  # Project-local tool first, then PATH.
  if [ -x "node_modules/.bin/$1" ]; then printf '%s' "node_modules/.bin/$1"; return 0; fi
  if [ -x ".venv/bin/$1" ]; then printf '%s' ".venv/bin/$1"; return 0; fi
  command -v "$1" 2>/dev/null
}

errors=""
run_lint() {
  local out rc
  out=$(fw_timeout 60 "$1" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && errors="$errors
\$ $1
$(printf '%s\n' "$out" | tail -n 30)"
}
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
f=$(q "$path")

case "$path" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.vue|*.svelte|*.css|*.scss|*.json|*.md|*.yaml|*.yml|*.html)
    p=$(bin prettier) && [ -n "$p" ] && fw_timeout 60 "$p --write --log-level warn $f" >/dev/null 2>&1
    case "$path" in
      *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.vue|*.svelte)
        if b=$(bin biome) && [ -n "$b" ] && { [ -f biome.json ] || [ -f biome.jsonc ]; }; then
          run_lint "$b check --write $f"
        elif e=$(bin eslint) && [ -n "$e" ] && [ -x node_modules/.bin/eslint ]; then
          run_lint "$e --fix $f"
        fi ;;
    esac ;;
  *.py)
    if r=$(bin ruff) && [ -n "$r" ]; then
      fw_timeout 60 "$r format $f" >/dev/null 2>&1
      run_lint "$r check --fix $f"
    elif b=$(bin black) && [ -n "$b" ]; then
      fw_timeout 60 "$b -q $f" >/dev/null 2>&1
    fi ;;
  *.rs)
    r=$(bin rustfmt) && [ -n "$r" ] && run_lint "$r --edition 2021 $f" ;;
  *.go)
    g=$(bin gofmt) && [ -n "$g" ] && fw_timeout 60 "$g -w $f" >/dev/null 2>&1
    v=$(bin go) && [ -n "$v" ] && run_lint "$v vet ./$(dirname "$path" | sed "s|^$FW_ROOT/||")/" ;;
  *.sh|*.bash)
    s=$(bin shellcheck) && [ -n "$s" ] && run_lint "$s -S warning $f" ;;
  *.tf|*.tfvars)
    t=$(bin terraform) && [ -n "$t" ] && fw_timeout 60 "$t fmt $f" >/dev/null 2>&1 ;;
  *.swift)
    s=$(bin swiftformat) && [ -n "$s" ] && fw_timeout 60 "$s --quiet $f" >/dev/null 2>&1
    l=$(bin swiftlint) && [ -n "$l" ] && run_lint "$l lint --quiet --strict $f" ;;
  *.kt|*.kts)
    k=$(bin ktlint) && [ -n "$k" ] && run_lint "$k -F $f" ;;
esac

[ -z "$errors" ] && exit 0
printf 'format-lint found problems in %s. Fix them:%s\n' "$path" "$errors" >&2
exit 2
