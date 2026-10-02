#!/usr/bin/env bash
# Installer tests: install into an existing project, merge settings, update
# with local edits, configure a fork in place, CI modes, git hooks, and the
# security-check script. bash 3.2+, GNU or BSD userland. Needs jq and git.
set -u
FW=$(cd "$(dirname "$0")/../../.." && pwd)
INSTALL="$FW/.claude/framework/install.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fw-install-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { if eval "$2"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $1"; fi; }
inst() { bash "$INSTALL" "$@" >"$TMP/out" 2>&1; }

# --- existing project ---
P="$TMP/proj"
mkdir -p "$P/.claude" "$P/supabase"
echo '{"name":"x","dependencies":{"expo":"1"}}' >"$P/package.json"
touch "$P/supabase/config.toml"
echo '{"model":"opus","permissions":{"deny":["Bash(rm -rf /*)"]}}' >"$P/.claude/settings.json"
printf 'node_modules\n' >"$P/.gitignore"

inst --dry-run "$P"
ok "dry run exit 0" '[ $? -eq 0 ]'
ok "dry run leaves settings alone" '[ "$(jq -c . "$P/.claude/settings.json")" = "{\"model\":\"opus\",\"permissions\":{\"deny\":[\"Bash(rm -rf /*)\"]}}" ]'
ok "dry run copies nothing" '[ ! -d "$P/.claude/hooks" ]'
ok "check reports pending" '! inst --check "$P"'

inst "$P"
ok "install exit 0" '[ $? -eq 0 ]'
S="$P/.claude/settings.json"
A="$P/.claude/settings.autonomous.json"
ok "hooks copied" '[ -f "$P/.claude/hooks/bash-guard.sh" ] && [ -f "$P/.claude/hooks/lib/policy.sh" ]'
ok "skills copied" '[ -f "$P/.claude/skills/feature/SKILL.md" ] && [ -f "$P/.claude/skills/vulnscan/pick-files.py" ]'
ok "agents copied" '[ -f "$P/.claude/agents/security-reviewer.md" ]'
ok "rules copied" '[ -f "$P/.claude/rules/security.md" ]'
ok "styles copied" '[ -f "$P/.claude/output-styles/autonomous.md" ]'
ok "framework copied" '[ -f "$P/.claude/framework/install.sh" ] && [ -f "$P/.claude/framework/settings/base.json" ]'
ok "manifest written" '[ -s "$P/.claude/framework/manifest.tsv" ] && grep -q "^.claude/hooks/bash-guard.sh	" "$P/.claude/framework/manifest.tsv"'
ok "scripts copied" '[ -x "$P/scripts/security-check.sh" ] && [ -x "$P/scripts/claude-autonomous.sh" ] && [ -f "$P/scripts/approve-spec.sh" ]'
ok "spec-gate wired" 'jq -e "[.hooks.PreToolUse[].hooks[].command] | any(test(\"spec-gate.sh\"))" "$S" >/dev/null'
ok "githooks copied" '[ -x "$P/.githooks/pre-commit" ]'
ok "hook wiring in settings" 'jq -e "[.hooks.PreToolUse[].hooks[].command] | any(test(\"CLAUDE_PROJECT_DIR/.claude/hooks/bash-guard.sh\"))" "$S" >/dev/null'
ok "stop hooks wired" 'jq -e ".hooks.Stop | length > 0" "$S" >/dev/null'
ok "existing scalar kept" '[ "$(jq -r .model "$S")" = opus ]'
ok "existing deny kept" 'jq -e ".permissions.deny | index(\"Bash(rm -rf /*)\")" "$S" >/dev/null'
ok "base deny added" 'jq -e ".permissions.deny | index(\"Read(**/.env)\")" "$S" >/dev/null'
ok "supabase overlay detected" 'jq -e ".permissions.deny | index(\"Bash(supabase db push*)\")" "$S" >/dev/null'
ok "expo overlay detected" 'jq -e ".permissions.deny | index(\"Bash(eas *)\")" "$S" >/dev/null'
ok "node overlay detected" 'jq -e ".permissions.deny | index(\"Bash(npm publish*)\")" "$S" >/dev/null'
ok "no duplicate denies" '[ "$(jq "[.permissions.deny[]] | length" "$S")" = "$(jq "[.permissions.deny[]] | unique | length" "$S")" ]'
ok "no plugin keys" '! jq -e "has(\"enabledPlugins\") or has(\"extraKnownMarketplaces\")" "$S" >/dev/null'
ok "attended has no cloud deny" '! jq -e ".permissions.deny | index(\"Bash(aws *)\")" "$S" >/dev/null'
ok "autonomous profile env" '[ "$(jq -r .env.CLAUDE_PROFILE "$A")" = autonomous ]'
ok "autonomous style" '[ "$(jq -r .outputStyle "$A")" = Autonomous ]'
ok "autonomous has cloud deny" 'jq -e ".permissions.deny | index(\"Bash(aws *)\")" "$A" >/dev/null'
ok "autonomous holds only additions" '! jq -e "has(\"hooks\") or (.permissions.deny | index(\"Read(**/.env)\"))" "$A" >/dev/null'
ok "CLAUDE.md written" '[ -f "$P/CLAUDE.md" ]'
ok "PR template in .claude" '[ -f "$P/.claude/pull_request_template.md" ]'
ok "no GitHub files without a GitHub remote" '[ ! -d "$P/.github" ]'
ok "gitignore has .env" 'grep -qxF ".env" "$P/.gitignore"'
ok "gitignore kept old line" 'grep -qxF "node_modules" "$P/.gitignore"'
ok "record written" '[ "$(jq -r ".overlays | join(\",\")" "$P/.claude/framework/installed.json")" = "node,expo-eas,supabase" ]'
ok "check is clean after install" 'inst --check "$P"'

# Re-run is idempotent.
cp "$S" "$TMP/s1"; cp "$P/.gitignore" "$TMP/g1"
echo "# my notes" >>"$P/CLAUDE.md"
inst "$P"
ok "rerun exit 0" '[ $? -eq 0 ]'
ok "rerun settings unchanged" 'cmp -s "$S" "$TMP/s1"'
ok "rerun gitignore unchanged" 'cmp -s "$P/.gitignore" "$TMP/g1"'
ok "rerun keeps edited CLAUDE.md" 'grep -q "my notes" "$P/CLAUDE.md"'
ok "rerun reports no changes" 'grep -q "Done (0 change" "$TMP/out"'

# Update: an unedited framework file is replaced, an edited one is kept.
NEWFW="$TMP/newfw"
mkdir -p "$NEWFW"
(cd "$FW" && tar cf - .claude scripts .githooks) | (cd "$NEWFW" && tar xf -)
rm -f "$NEWFW/.claude/framework/manifest.tsv" "$NEWFW/.claude/framework/installed.json" "$NEWFW/.claude/settings.json" "$NEWFW/.claude/settings.autonomous.json"
echo "# upstream change" >>"$NEWFW/.claude/rules/api.md"
echo "# upstream change" >>"$NEWFW/.claude/rules/auth.md"
echo "# my project rule" >>"$P/.claude/rules/auth.md"
bash "$NEWFW/.claude/framework/install.sh" "$P" >"$TMP/out" 2>&1
ok "update replaces unedited file" 'grep -q "upstream change" "$P/.claude/rules/api.md"'
ok "update keeps edited file" 'grep -q "my project rule" "$P/.claude/rules/auth.md" && ! grep -q "upstream change" "$P/.claude/rules/auth.md"'
ok "update reports kept file" 'grep -q "keep     .claude/rules/auth.md" "$TMP/out"'
bash "$NEWFW/.claude/framework/install.sh" --force "$P" >/dev/null 2>&1
ok "force replaces edited file" 'grep -q "upstream change" "$P/.claude/rules/auth.md" && [ -f "$P/.claude/rules/auth.md.bak" ]'

# --- fork: configure in place ---
F="$TMP/fork"
mkdir -p "$F"
(cd "$FW" && tar cf - .claude scripts .githooks CLAUDE.md SECURITY.md .gitignore) | (cd "$F" && tar xf -)
echo '{"name":"app"}' >"$F/package.json"
before=$(cd "$F/.claude/hooks" && ls | wc -l | tr -d ' ')
bash "$F/.claude/framework/install.sh" >"$TMP/out" 2>&1
ok "in-place exit 0" '[ $? -eq 0 ]'
ok "in-place mode reported" 'grep -q "configure in place" "$TMP/out"'
ok "in-place adds overlay" 'jq -e ".permissions.deny | index(\"Bash(npm publish*)\")" "$F/.claude/settings.json" >/dev/null'
ok "in-place keeps hooks" '[ "$(cd "$F/.claude/hooks" && ls | wc -l | tr -d " ")" = "$before" ]'
ok "in-place writes no manifest" '[ ! -f "$F/.claude/framework/manifest.tsv" ]'
ok "in-place remembers overlays" '(cd "$F" && rm package.json && bash .claude/framework/install.sh --check >/dev/null 2>&1)'

# --- options ---
P2="$TMP/proj2"; mkdir -p "$P2"
inst --overlay rust --sandbox --no-autonomous --ci none "$P2"
ok "explicit overlay" 'jq -e ".permissions.deny | index(\"Bash(cargo publish*)\")" "$P2/.claude/settings.json" >/dev/null'
ok "sandbox overlay" 'jq -e ".sandbox.enabled == true" "$P2/.claude/settings.json" >/dev/null'
ok "no autonomous file" '[ ! -f "$P2/.claude/settings.autonomous.json" ]'
ok "bad overlay fails" '! inst --overlay nope "$P2"'
ok "bad --ci fails" '! inst --ci jenkins "$P2"'

P4="$TMP/proj4"; mkdir -p "$P4"; git -C "$P4" init -q; git -C "$P4" remote add origin https://github.com/example/app.git
inst "$P4"
ok "auto ci on GitHub remote" '[ -f "$P4/.github/workflows/security.yml" ] && [ -f "$P4/.github/pull_request_template.md" ]'
P5="$TMP/proj5"; mkdir -p "$P5"; git -C "$P5" init -q; git -C "$P5" remote add origin https://gitlab.com/example/app.git
inst "$P5"
ok "auto ci skips GitLab remote" '[ ! -d "$P5/.github" ]'
inst --ci github "$P5"
ok "explicit --ci github" '[ -f "$P5/.github/workflows/security.yml" ]'

inst --git-hooks "$P5"
ok "hooksPath set" '[ "$(git -C "$P5" config core.hooksPath)" = .githooks ]'
P6="$TMP/proj6"; mkdir -p "$P6"; git -C "$P6" init -q; git -C "$P6" config core.hooksPath .husky
inst --git-hooks "$P6"
ok "existing hooksPath kept" '[ "$(git -C "$P6" config core.hooksPath)" = .husky ]'

P3="$TMP/proj3"; mkdir -p "$P3/.claude"; echo '{bad' >"$P3/.claude/settings.json"
ok "invalid json fails" '! inst "$P3"'

# --- security-check.sh ---
SC="$TMP/sc"; mkdir -p "$SC"; git -C "$SC" init -q
cp "$FW/scripts/security-check.sh" "$SC/check.sh"
echo "x" >"$SC/app.txt"
mkdir -p "$TMP/bin"; printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/gitleaks"; chmod +x "$TMP/bin/gitleaks"
ok "security-check passes clean tree" '(cd "$SC" && PATH="$TMP/bin:$PATH" bash check.sh >/dev/null 2>&1)'
echo "A=1" >"$SC/.env"
ok "security-check fails on .env" '! (cd "$SC" && PATH="$TMP/bin:$PATH" bash check.sh >/dev/null 2>&1)'
rm "$SC/.env"
ok "security-check fails without gitleaks" '! (cd "$SC" && PATH="/usr/bin:/bin" HOME=/nonexistent bash check.sh >/dev/null 2>&1) || command -v gitleaks >/dev/null'

echo "pass: $PASS  fail: $FAIL"
[ "$FAIL" -eq 0 ]
