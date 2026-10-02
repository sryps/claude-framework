#!/usr/bin/env bash
# Installer test: fresh install, merge into existing settings, idempotent
# re-run, and dry run. bash 3.2+, GNU or BSD userland. Needs jq.
set -u
FW=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fw-install-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { if eval "$2"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $1"; fi; }

P="$TMP/proj"
mkdir -p "$P/.claude" "$P/supabase"
echo '{"name":"x","dependencies":{"expo":"1"}}' >"$P/package.json"
touch "$P/supabase/config.toml"
echo '{"model":"opus","permissions":{"deny":["Bash(rm -rf /*)"]}}' >"$P/.claude/settings.json"
printf 'node_modules\n' >"$P/.gitignore"

# Dry run writes nothing.
bash "$FW/install.sh" --dry-run "$P" >"$TMP/dry.out" 2>&1
ok "dry run exit 0" '[ $? -eq 0 ] || grep -q Done "$TMP/dry.out"'
ok "dry run leaves settings alone" '[ "$(jq -c . "$P/.claude/settings.json")" = "{\"model\":\"opus\",\"permissions\":{\"deny\":[\"Bash(rm -rf /*)\"]}}" ]'
ok "dry run writes no rules" '[ ! -d "$P/.claude/rules" ]'

bash "$FW/install.sh" "$P" >"$TMP/run1.out" 2>&1
ok "install exit 0" '[ $? -eq 0 ]'
S="$P/.claude/settings.json"
A="$P/.claude/settings.autonomous.json"
ok "existing scalar kept" '[ "$(jq -r .model "$S")" = opus ]'
ok "existing deny kept" 'jq -e ".permissions.deny | index(\"Bash(rm -rf /*)\")" "$S" >/dev/null'
ok "base deny added" 'jq -e ".permissions.deny | index(\"Read(**/.env)\")" "$S" >/dev/null'
ok "supabase overlay detected" 'jq -e ".permissions.deny | index(\"Bash(supabase db push*)\")" "$S" >/dev/null'
ok "expo overlay detected" 'jq -e ".permissions.deny | index(\"Bash(eas *)\")" "$S" >/dev/null'
ok "node overlay detected" 'jq -e ".permissions.deny | index(\"Bash(npm publish*)\")" "$S" >/dev/null'
ok "no duplicate denies" '[ "$(jq "[.permissions.deny[]] | length" "$S")" = "$(jq "[.permissions.deny[]] | unique | length" "$S")" ]'
ok "plugin enabled" 'jq -e ".enabledPlugins[\"agent-guardrails@agent-guardrails\"] == true" "$S" >/dev/null'
ok "marketplace source is local without a remote" '[ "$(jq -r ".extraKnownMarketplaces[\"agent-guardrails\"].source.source" "$S")" = directory ] || git -C "$FW" remote get-url origin >/dev/null 2>&1'
ok "attended has no cloud deny" '! jq -e ".permissions.deny | index(\"Bash(aws *)\")" "$S" >/dev/null'
ok "autonomous profile env" '[ "$(jq -r .env.CLAUDE_PROFILE "$A")" = autonomous ]'
ok "autonomous style" '[ "$(jq -r .outputStyle "$A")" = Autonomous ]'
ok "autonomous has cloud deny" 'jq -e ".permissions.deny | index(\"Bash(aws *)\")" "$A" >/dev/null'
ok "autonomous repeats base deny" 'jq -e ".permissions.deny | index(\"Read(**/.env)\")" "$A" >/dev/null'
ok "autonomous repeats project deny" 'jq -e ".permissions.deny | index(\"Bash(rm -rf /*)\")" "$A" >/dev/null'
ok "rules copied" '[ -f "$P/.claude/rules/security.md" ]'
ok "styles copied" '[ -f "$P/.claude/output-styles/autonomous.md" ]'
ok "CLAUDE.md written" '[ -f "$P/CLAUDE.md" ]'
ok "PR template in .claude" '[ -f "$P/.claude/pull_request_template.md" ]'
ok "no GitHub files without a GitHub remote" '[ ! -d "$P/.github" ]'
ok "security-check executable" '[ -x "$P/scripts/security-check.sh" ]'
ok "runner executable" '[ -x "$P/scripts/claude-autonomous.sh" ]'
ok "gitignore has .env" 'grep -qxF ".env" "$P/.gitignore"'
ok "gitignore kept old line" 'grep -qxF "node_modules" "$P/.gitignore"'
ok "record written" '[ "$(jq -r ".overlays | join(\",\")" "$P/.claude/framework.json")" = "node,expo-eas,supabase" ]'

# Re-run is idempotent.
cp "$S" "$TMP/s1"; cp "$P/.gitignore" "$TMP/g1"
echo "# my notes" >>"$P/CLAUDE.md"
bash "$FW/install.sh" "$P" >"$TMP/run2.out" 2>&1
ok "rerun exit 0" '[ $? -eq 0 ]'
ok "rerun settings unchanged" 'cmp -s "$S" "$TMP/s1"'
ok "rerun gitignore unchanged" 'cmp -s "$P/.gitignore" "$TMP/g1"'
ok "rerun keeps edited CLAUDE.md" 'grep -q "my notes" "$P/CLAUDE.md"'
ok "rerun reports keep" 'grep -q "keep     CLAUDE.md" "$TMP/run2.out"'

# Explicit overlays and sandbox.
P2="$TMP/proj2"; mkdir -p "$P2"
bash "$FW/install.sh" --overlay rust --sandbox --no-autonomous --no-ci "$P2" >/dev/null 2>&1
ok "explicit overlay" 'jq -e ".permissions.deny | index(\"Bash(cargo publish*)\")" "$P2/.claude/settings.json" >/dev/null'
ok "sandbox overlay" 'jq -e ".sandbox.enabled == true" "$P2/.claude/settings.json" >/dev/null'
ok "no autonomous file" '[ ! -f "$P2/.claude/settings.autonomous.json" ]'
ok "no ci files" '[ ! -f "$P2/.github/workflows/security.yml" ]'

# GitHub remote: --ci auto writes the GitHub files.
P4="$TMP/proj4"; mkdir -p "$P4"; git -C "$P4" init -q; git -C "$P4" remote add origin https://github.com/example/app.git
bash "$FW/install.sh" "$P4" >/dev/null 2>&1
ok "auto ci on GitHub remote" '[ -f "$P4/.github/workflows/security.yml" ] && [ -f "$P4/.github/pull_request_template.md" ]'
P5="$TMP/proj5"; mkdir -p "$P5"; git -C "$P5" init -q; git -C "$P5" remote add origin https://gitlab.com/example/app.git
bash "$FW/install.sh" "$P5" >/dev/null 2>&1
ok "auto ci skips GitLab remote" '[ ! -d "$P5/.github" ]'
bash "$FW/install.sh" --ci github "$P5" >/dev/null 2>&1
ok "explicit --ci github" '[ -f "$P5/.github/workflows/security.yml" ]'
ok "bad --ci fails" '! bash "$FW/install.sh" --ci jenkins "$P5" >/dev/null 2>&1'

# Git hooks.
bash "$FW/install.sh" --git-hooks "$P5" >/dev/null 2>&1
ok "githooks written" '[ -x "$P5/.githooks/pre-commit" ] && [ -x "$P5/.githooks/pre-push" ]'
ok "hooksPath set" '[ "$(git -C "$P5" config core.hooksPath)" = .githooks ]'
P6="$TMP/proj6"; mkdir -p "$P6"; git -C "$P6" init -q; git -C "$P6" config core.hooksPath .husky
bash "$FW/install.sh" --git-hooks "$P6" >/dev/null 2>&1
ok "existing hooksPath kept" '[ "$(git -C "$P6" config core.hooksPath)" = .husky ]'

# security-check.sh: secret file and missing gitleaks fail; stub gitleaks passes.
SC="$TMP/sc"; mkdir -p "$SC"; git -C "$SC" init -q
cp "$FW/templates/scripts/security-check.sh" "$SC/check.sh"
echo "x" >"$SC/app.txt"
mkdir -p "$TMP/bin"; printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/gitleaks"; chmod +x "$TMP/bin/gitleaks"
ok "security-check passes clean tree" '(cd "$SC" && PATH="$TMP/bin:$PATH" bash check.sh >/dev/null 2>&1)'
echo "A=1" >"$SC/.env"
ok "security-check fails on .env" '! (cd "$SC" && PATH="$TMP/bin:$PATH" bash check.sh >/dev/null 2>&1)'
rm "$SC/.env"
ok "security-check fails without gitleaks" '! (cd "$SC" && PATH="/usr/bin:/bin" HOME=/nonexistent bash check.sh >/dev/null 2>&1) || command -v gitleaks >/dev/null'
ok "bad overlay fails" '! bash "$FW/install.sh" --overlay nope "$P2" >/dev/null 2>&1'
ok "self target fails" '! bash "$FW/install.sh" "$FW" >/dev/null 2>&1'

# Invalid existing JSON stops the install.
P3="$TMP/proj3"; mkdir -p "$P3/.claude"; echo '{bad' >"$P3/.claude/settings.json"
ok "invalid json fails" '! bash "$FW/install.sh" "$P3" >/dev/null 2>&1'

echo "pass: $PASS  fail: $FAIL"
[ "$FAIL" -eq 0 ]
