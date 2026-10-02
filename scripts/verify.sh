#!/usr/bin/env bash
# Verify the framework locally. No CI service needed.
#
#   scripts/verify.sh            # all checks this machine can run
#   scripts/verify.sh --quick    # skip the bash 3.2 container
#
# Checks: JSON parses, shellcheck, hook tests, installer tests, plugin
# manifest (when the claude CLI is present), and the tests again under
# bash 3.2 (native /bin/bash on macOS, a docker container elsewhere).
# A missing optional tool is reported as SKIP, not as a pass.
set -u
cd "$(dirname "$0")/.." || exit 1
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
for f in settings/*.json settings/overlays/*.json hooks/hooks.json .claude-plugin/*.json; do
  jq empty "$f" 2>/dev/null || { echo "invalid: $f"; bad=1; }
done
[ "$bad" = 0 ] && pass "JSON files parse" || fail "JSON files parse"

SH_FILES="hooks/*.sh hooks/lib/*.sh hooks/tests/run.sh install.sh scripts/*.sh tests/*.sh templates/scripts/*.sh templates/githooks/*"
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
bash hooks/tests/run.sh && pass "hook tests" || fail "hook tests"

step "hook tests through a symlinked TMPDIR (emulates macOS /var -> /private/var)"
lt=$(mktemp -d "${TMPDIR:-/tmp}/fw-verify.XXXXXX")
mkdir -p "$lt/real" && ln -s "$lt/real" "$lt/link"
TMPDIR="$lt/link" bash hooks/tests/run.sh && pass "hook tests, symlinked TMPDIR" || fail "hook tests, symlinked TMPDIR"
rm -rf "$lt"

step "installer tests"
bash tests/install-test.sh && pass "installer tests" || fail "installer tests"

step "plugin manifest"
if command -v claude >/dev/null 2>&1; then
  out=$(claude plugin validate . 2>&1)
  if printf '%s' "$out" | grep -q 'Validation passed'; then pass "claude plugin validate"; else printf '%s\n' "$out" | tail -8; fail "claude plugin validate"; fi
else
  skip "plugin manifest" "claude CLI not on PATH"
fi

step "bash 3.2"
if [ "$quick" = 1 ]; then
  skip "bash 3.2" "--quick"
elif [ "$(uname -s)" = Darwin ] && /bin/bash --version | head -1 | grep -q 'version 3\.2'; then
  /bin/bash hooks/tests/run.sh && /bin/bash tests/install-test.sh && pass "bash 3.2 (macOS /bin/bash, BSD tools)" || fail "bash 3.2"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker run --rm -v "$PWD":/w -w /w bash:3.2 sh -c \
    'apk add -q --no-cache jq git make diffutils >/dev/null 2>&1 && bash hooks/tests/run.sh && bash tests/install-test.sh' \
    && pass "bash 3.2 (docker, busybox tools)" || fail "bash 3.2"
else
  skip "bash 3.2" "no docker and not macOS"
fi

printf '\n'
[ -n "$skips" ] && printf 'Skipped:%s\n' "$skips"
if [ "$fails" -gt 0 ]; then echo "verify: $fails check(s) failed"; exit 1; fi
echo "verify: all checks that ran passed"
