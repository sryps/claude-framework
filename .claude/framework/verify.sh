#!/usr/bin/env bash
# Verify the framework locally. No CI service needed.
#
#   .claude/framework/verify.sh            # all checks this machine can run
#   .claude/framework/verify.sh --quick    # skip the bash 3.2 container
#
# Checks: JSON parses, the project settings still carry every framework deny
# rule and hook, shellcheck, hook tests (also through a symlinked TMPDIR),
# installer tests, and the tests again under bash 3.2 (native /bin/bash on
# macOS, a docker container elsewhere).
# A missing optional tool is reported as SKIP, not as a pass.
set -u
cd "$(dirname "$0")/../.." || exit 1
FWD=.claude/framework
quick=0
[ "${1:-}" = --quick ] && quick=1

fails=0
skips=""
step() { printf '\n== %s\n' "$1"; }
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
skip() { printf 'SKIP %s (%s)\n' "$1" "$2"; skips="$skips
  - $1: $2"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git is required." >&2; exit 1; }

step "JSON"
bad=0
for f in $FWD/settings/*.json $FWD/settings/overlays/*.json .claude/settings.json .claude/settings.autonomous.json; do
  [ -f "$f" ] || continue
  jq empty "$f" 2>/dev/null || { echo "invalid: $f"; bad=1; }
done
[ "$bad" = 0 ] && pass "JSON files parse" || fail "JSON files parse"

step "settings carry the framework guards"
# Every base deny rule and every hook command must be in the project
# settings. Projects may add more, never fewer.
check_settings() {
  local f=$1 missing
  missing=$(jq -n --slurpfile base $FWD/settings/base.json --slurpfile hooks $FWD/settings/hooks.json --slurpfile cur "$f" '
    ($base[0].permissions.deny - ($cur[0].permissions.deny // []))
    + ([$hooks[0].hooks[][].hooks[].command] - [($cur[0].hooks // {})[][]?.hooks[]?.command])
    | .[]' -r)
  if [ -z "$missing" ]; then pass "$f"; else fail "$f is missing:"; printf '  %s\n' "$missing"; fi
}
if [ -f .claude/settings.json ]; then check_settings .claude/settings.json; else fail ".claude/settings.json is missing. Run $FWD/install.sh"; fi
[ -f .claude/settings.autonomous.json ] && check_settings .claude/settings.autonomous.json

step "framework docs"
# Upstream keeps the root README and the framework README identical. A fork
# replaces the root README, and this check then stops applying.
if [ "$(head -1 README.md 2>/dev/null)" = "$(head -1 $FWD/README.md)" ]; then
  cmp -s README.md $FWD/README.md && pass "README.md matches $FWD/README.md" || fail "README.md and $FWD/README.md differ. Copy one onto the other."
else
  skip "framework docs" "root README is the project's own"
fi

SH_FILES=".claude/hooks/*.sh .claude/hooks/lib/*.sh $FWD/*.sh $FWD/tests/*.sh scripts/*.sh .githooks/*"
step "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  shellcheck -S warning -x $SH_FILES && pass shellcheck || fail shellcheck
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  docker run --rm -v "$PWD":/w -w /w koalaman/shellcheck:stable -S warning -x $SH_FILES && pass "shellcheck (docker)" || fail shellcheck
else
  skip shellcheck "install shellcheck: brew install shellcheck, or apt install shellcheck"
fi

step "hook tests ($(bash --version | head -1 | sed 's/.*version \([0-9.]*\).*/bash \1/'))"
bash $FWD/tests/hooks-test.sh && pass "hook tests" || fail "hook tests"

step "hook tests through a symlinked TMPDIR (emulates macOS /var -> /private/var)"
lt=$(mktemp -d "${TMPDIR:-/tmp}/fw-verify.XXXXXX")
mkdir -p "$lt/real" && ln -s "$lt/real" "$lt/link"
TMPDIR="$lt/link" bash $FWD/tests/hooks-test.sh && pass "hook tests, symlinked TMPDIR" || fail "hook tests, symlinked TMPDIR"
rm -rf "$lt"

step "installer tests"
bash $FWD/tests/install-test.sh && pass "installer tests" || fail "installer tests"

step "bash 3.2"
if [ "$quick" = 1 ]; then
  skip "bash 3.2" "--quick"
elif [ "$(uname -s)" = Darwin ] && /bin/bash --version | head -1 | grep -q 'version 3\.2'; then
  /bin/bash $FWD/tests/hooks-test.sh && /bin/bash $FWD/tests/install-test.sh && pass "bash 3.2 (macOS /bin/bash, BSD tools)" || fail "bash 3.2"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker run --rm -v "$PWD":/w -w /w bash:3.2 sh -c \
    "apk add -q --no-cache jq git make diffutils >/dev/null 2>&1 && bash $FWD/tests/hooks-test.sh && bash $FWD/tests/install-test.sh" \
    && pass "bash 3.2 (docker, busybox tools)" || fail "bash 3.2"
else
  skip "bash 3.2" "no docker and not macOS"
fi

printf '\n'
[ -n "$skips" ] && printf 'Skipped:%s\n' "$skips"
if [ "$fails" -gt 0 ]; then echo "verify: $fails check(s) failed"; exit 1; fi
echo "verify: all checks that ran passed"
