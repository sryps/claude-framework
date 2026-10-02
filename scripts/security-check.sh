#!/usr/bin/env bash
# Local security checks. No CI service or forge needed.
#
#   scripts/security-check.sh             # whole working tree
#   scripts/security-check.sh --changed   # files changed vs the default branch
#   scripts/security-check.sh --staged    # staged changes (git pre-commit)
#
# Required: gitleaks (secrets). A missing gitleaks is a failure, because a
# skipped secret scan must not look like a pass.
# Optional: semgrep (SAST), osv-scanner (dependency CVEs), trivy (IaC and
# container config). Each missing optional tool prints SKIP.
#
# Env: FW_SEMGREP_CONFIG (default p/default, needs network; point it at a
# local rules file for offline use).
# Runs on bash 3.2+ (macOS), Linux, and WSL.
set -u
PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/go/bin:$PATH"
mode=all
case "${1:-}" in
  --changed) mode=changed ;;
  --staged) mode=staged ;;
  ""|--all) ;;
  -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Unknown option: $1" >&2; exit 2 ;;
esac

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$root" || exit 2
fails=0
skips=0
have() { command -v "$1" >/dev/null 2>&1; }
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
skip() { printf 'SKIP %s (%s)\n' "$1" "$2"; skips=$((skips + 1)); }

default_branch() {
  local ref
  ref=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) && { printf '%s' "${ref#refs/remotes/origin/}"; return; }
  for ref in main master; do git show-ref --verify --quiet "refs/heads/$ref" && { printf '%s' "$ref"; return; }; done
  printf 'main'
}

# File list for the scanners that take paths.
list=$(mktemp "${TMPDIR:-/tmp}/fw-sec.XXXXXX")
trap 'rm -f "$list"' EXIT
case "$mode" in
  all) git ls-files -co --exclude-standard >"$list" 2>/dev/null || find . -type f -not -path './.git/*' >"$list" ;;
  changed)
    mb=$(git merge-base HEAD "$(default_branch)" 2>/dev/null || true)
    { [ -n "$mb" ] && git diff --name-only "$mb" HEAD; git diff --name-only HEAD; git ls-files -o --exclude-standard; } 2>/dev/null | sort -u >"$list" ;;
  staged) git diff --cached --name-only --diff-filter=ACMR >"$list" 2>/dev/null ;;
esac
# Keep files that still exist.
tmp=$(mktemp "${TMPDIR:-/tmp}/fw-sec.XXXXXX")
while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done <"$list" >"$tmp"
mv "$tmp" "$list"
count=$(wc -l <"$list" | tr -d ' ')
echo "security-check: mode=$mode files=$count"

# 1. Secret files that git would track.
secret_re='(^|/)\.env($|\.)|\.(pem|key|p8|p12|pfx|keystore|jks)$|(^|/)id_(rsa|ed25519|ecdsa|dsa)$'
leaked=$(grep -E "$secret_re" "$list" | grep -vE '\.(example|sample|template)(\.[A-Za-z0-9]+)?$' || true)
if [ -n "$leaked" ]; then
  fail "secret files not ignored by git:"
  printf '  %s\n' $leaked
else
  pass "no secret files in the tree"
fi

# 2. gitleaks (required).
if have gitleaks; then
  case "$mode" in
    staged) out=$(gitleaks git --staged --redact --no-banner . 2>&1 || gitleaks protect --staged --redact --no-banner 2>&1); rc=$? ;;
    *)
      rc=0; out=""
      if [ "$count" -gt 0 ]; then
        d=$(mktemp -d "${TMPDIR:-/tmp}/fw-sec-dir.XXXXXX")
        # Copy the listed files so gitleaks scans exactly this set.
        while IFS= read -r f; do mkdir -p "$d/$(dirname "$f")"; cp "$f" "$d/$f"; done <"$list"
        out=$(gitleaks dir --redact --no-banner "$d" 2>&1 || gitleaks detect --no-git --redact --no-banner -s "$d" 2>&1); rc=$?
        rm -rf "$d"
      fi ;;
  esac
  if [ "$rc" -eq 0 ]; then pass gitleaks; else fail gitleaks; printf '%s\n' "$out" | grep -E 'Finding|RuleID|File|Line' | head -30; fi
else
  fail "gitleaks is not installed. Install it: brew install gitleaks, or see https://github.com/gitleaks/gitleaks/releases"
fi

# 3. semgrep (optional).
if [ "$mode" = staged ]; then
  : # Keep pre-commit fast. --changed and the full run cover SAST.
elif have semgrep; then
  if [ "$count" -gt 0 ]; then
    out=$(tr '\n' '\0' <"$list" | xargs -0 semgrep scan --config "${FW_SEMGREP_CONFIG:-p/default}" --severity ERROR --error --quiet --metrics off 2>&1); rc=$?
    case "$rc" in
      0) pass semgrep ;;
      1) fail semgrep; printf '%s\n' "$out" | head -40 ;;
      *) skip semgrep "exit $rc; likely no network for the rule registry. Set FW_SEMGREP_CONFIG to a local rules file" ;;
    esac
  fi
else
  skip semgrep "not installed: pipx install semgrep, or brew install semgrep"
fi

# 4. osv-scanner (optional).
if [ "$mode" = staged ]; then
  :
elif have osv-scanner; then
  out=$(osv-scanner scan source -r . 2>&1 || osv-scanner -r . 2>&1); rc=$?
  case "$rc" in
    0) pass osv-scanner ;;
    1) fail "osv-scanner: vulnerable dependencies"; printf '%s\n' "$out" | tail -30 ;;
    128) pass "osv-scanner (no lockfiles found)" ;;
    *) skip osv-scanner "exit $rc" ;;
  esac
else
  skip osv-scanner "not installed: brew install osv-scanner, or go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest"
fi

# 5. trivy config scan (optional, only with IaC or container files).
if [ "$mode" != staged ] && grep -qE '(^|/)(Dockerfile|docker-compose|compose\.ya?ml)|\.tf$|(^|/)(k8s|kubernetes|helm|charts)/' "$list"; then
  if have trivy; then
    out=$(trivy fs --quiet --scanners misconfig --severity HIGH,CRITICAL --exit-code 1 . 2>&1); rc=$?
    [ "$rc" -eq 0 ] && pass "trivy misconfig" || { fail "trivy misconfig"; printf '%s\n' "$out" | tail -30; }
  else
    skip trivy "not installed: brew install trivy"
  fi
fi

echo
if [ "$fails" -gt 0 ]; then echo "security-check: $fails failed, $skips skipped"; exit 1; fi
echo "security-check: passed ($skips skipped)"
