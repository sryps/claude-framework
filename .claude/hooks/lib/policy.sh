#!/usr/bin/env bash
# Path tiers and secret patterns. Source after common.sh.
#
# Projects extend the lists with environment variables (set them in the
# project .claude/settings.json "env" block):
#   FW_RED_PATHS_EXTRA     ERE, matched against the repo-relative path
#   FW_YELLOW_PATHS_EXTRA  ERE, matched against the repo-relative path
#   FW_SECRET_ALLOW        ERE, a matching line is never reported as a secret
#
# Maintainer mode (framework development only) makes hooks, framework, and
# git hook files Yellow instead of Red. Set "FW_MAINTAINER": "1" in the env
# block of .claude/settings.local.json by hand. The hooks read that file, not
# the environment, so the flag never leaks into a claude process started in
# another project. The autonomous profile ignores it.

fw_maintainer() {
  local f="$FW_ROOT/.claude/settings.local.json"
  fw_autonomous && return 1
  [ -f "$f" ] || return 1
  if [ "$FW_HAS_JQ" = 1 ]; then
    jq -e '.env.FW_MAINTAINER == "1" or .env.FW_MAINTAINER == 1' "$f" >/dev/null 2>&1
  else
    grep -qE '"FW_MAINTAINER"[[:space:]]*:[[:space:]]*"?1"?' "$f"
  fi
}

# Secret files. Templates (.env.example and similar) stay editable.
FW_SECRET_FILE_RE='(^|/)\.env($|\.)|(^|/)\.envrc$|\.(pem|key|p8|p12|pfx|keystore|jks|mobileprovision)$|(^|/)id_(rsa|dsa|ecdsa|ed25519)$|(^|/)\.netrc$|(^|/)\.npmrc$|(^|/)\.pypirc$|(^|/)credentials(\.json)?$|(^|/)service-account[^/]*\.json$|(^|/)google-services[^/]*\.json$|(^|/)GoogleService-Info[^/]*\.plist$|(^|/)\.ssh/|(^|/)\.aws/|(^|/)\.config/gh/|(^|/)\.kube/config$|(^|/)\.docker/config\.json$|(^|/)\.git-credentials$'
FW_SECRET_TEMPLATE_RE='\.(example|sample|template|dist|defaults)(\.[A-Za-z0-9]+)?$'

# Test files, fixtures, and test setup. Used by test-writer-scope.sh.
FW_TEST_PATH_RE='(^|/)(__tests__|__mocks__|__snapshots__|__fixtures__|tests?|specs?|e2e|cypress|playwright|\.maestro|testdata|fixtures)/|\.(test|spec)\.[A-Za-z0-9]+$|_test\.(go|py|ts|js|rb|exs?)$|(^|/)test_[^/]*\.py$|[A-Za-z0-9](Test|Tests|Spec)\.(swift|kt|java|cs|scala)$|(^|/)(conftest\.py|(jest|vitest)\.setup\.[cm]?[jt]s|playwright\.config\.[cm]?[jt]s)$'

# fw_spec_approval. Checks the human approval for the current branch
# (.claude/approvals/<branch>.json, written by scripts/approve-spec.sh).
# Valid: prints the approved spec path, or "none" for a --no-spec approval,
# and returns 0. Not valid: prints the reason and returns 1.
fw_spec_approval() {
  local branch file spec want have
  branch=$(git -C "$FW_ROOT" branch --show-current 2>/dev/null)
  if [ -z "$branch" ]; then echo "detached HEAD, so there is no branch to hold a spec approval."; return 1; fi
  file="$FW_ROOT/.claude/approvals/$(printf '%s' "$branch" | tr '/' '_' | tr -c 'A-Za-z0-9._-' '_').json"
  if [ ! -f "$file" ]; then echo "no approved spec for branch $branch."; return 1; fi
  if [ "$FW_HAS_JQ" = 1 ]; then
    spec=$(jq -r '.spec // empty' "$file" 2>/dev/null)
    want=$(jq -r '.sha256 // empty' "$file" 2>/dev/null)
  else
    spec=$(sed -nE 's/.*"spec"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$file" | head -1)
    want=$(sed -nE 's/.*"sha256"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$file" | head -1)
  fi
  if [ "$spec" = none ]; then echo none; return 0; fi
  if [ -z "$spec" ] || [ ! -f "$FW_ROOT/$spec" ]; then echo "the approved spec ${spec:-?} does not exist."; return 1; fi
  have=$(fw_sha256 "$FW_ROOT/$spec")
  if [ "$have" != "$want" ]; then
    echo "$spec changed since the user approved it. The user must read the change and approve again."
    return 1
  fi
  echo "$spec"
}

# fw_is_test_change <path>. A test file that is not documentation, so a spec
# in docs/specs/ or a README under tests/ never counts as a test.
fw_is_test_change() {
  printf '%s' "$1" | grep -qE "$FW_TEST_PATH_RE" || return 1
  printf '%s' "$1" | grep -qiE '\.(md|markdown|txt|rst|adoc)$' && return 1
  return 0
}

# Source code. A branch that changes these needs tests, verification, and a
# spec reference in the PR (pr-gate.sh). Test files match FW_TEST_PATH_RE
# first and do not count as code.
FW_CODE_RE='\.(js|jsx|ts|tsx|mjs|cjs|vue|svelte|astro|py|go|rs|rb|java|kt|kts|swift|m|mm|cs|fs|php|c|cc|cpp|h|hpp|scala|dart|ex|exs|erl|clj|lua|zig|sh|bash|sql)$'

FW_LOCKFILE_RE='(^|/)(package-lock\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb?|Cargo\.lock|go\.sum|poetry\.lock|uv\.lock|Pipfile\.lock|Gemfile\.lock|composer\.lock|Podfile\.lock|pubspec\.lock|flake\.lock)$'

# Files that control the agent itself. An agent that edits these can turn off
# its own guards. Settings and git internals stay Red even for maintainers.
FW_CONTROL_RE='(^|/)\.claude/settings[^/]*\.json$|(^|/)\.git/|(^|/)\.mcp\.json$|(^|/)\.claude/approvals/|(^|/)scripts/approve-spec\.sh$'
FW_GUARD_RE='(^|/)\.claude/hooks/|(^|/)\.claude/framework/|(^|/)\.githooks/|(^|/)scripts/(security-check|claude-autonomous)\.sh$|(^|/)\.husky/|(^|/)\.pre-commit-config\.yaml$|(^|/)lefthook\.ya?ml$'
# Instructions the agent follows. A project may tune them, with review.
FW_YELLOW_AGENT_RE='(^|/)\.claude/(skills|agents|rules|output-styles|commands)/|(^|/)\.claude/pull_request_template\.md$'

FW_YELLOW_AUTH_RE='(^|/|[-_.])(auth|authn|authz|oauth|oidc|saml|sso|login|logout|signin|signup|session|sessions|jwt|token|tokens|password|passwd|credential|credentials|crypto|cipher|encrypt|decrypt|hash|permission|permissions|rbac|acl|policy|policies|middleware|guard|guards|csrf|cors|mfa|totp|2fa)([-_./]|$)'
FW_YELLOW_DATA_RE='(^|/)(migrations?|migrate|db/schema|schema\.(sql|rb|prisma)|prisma/schema\.prisma|supabase/migrations|alembic|flyway|liquibase)(/|$|\.)|\.sql$'
FW_YELLOW_CI_RE='(^|/)(\.github/workflows/|\.github/actions/|\.gitlab-ci\.yml|\.circleci/|Jenkinsfile|azure-pipelines\.yml|bitbucket-pipelines\.yml|\.buildkite/|codemagic\.yaml|eas\.json|fastlane/)'
FW_YELLOW_INFRA_RE='\.(tf|tfvars|hcl)$|(^|/)(Dockerfile[^/]*|docker-compose[^/]*\.ya?ml|compose\.ya?ml|k8s/|kubernetes/|helm/|charts/|terraform/|pulumi/|cdk/|serverless\.ya?ml|fly\.toml|vercel\.json|netlify\.toml|wrangler\.toml|firebase\.json|supabase/config\.toml|app\.json|app\.config\.[jt]s|AndroidManifest\.xml|Info\.plist|entitlements[^/]*)$|\.entitlements$|(^|/)nginx[^/]*\.conf$'
FW_YELLOW_DEPS_RE='(^|/)(package\.json|Cargo\.toml|go\.mod|pyproject\.toml|requirements[^/]*\.txt|Pipfile|Gemfile|composer\.json|Podfile|pubspec\.yaml|build\.gradle(\.kts)?|pom\.xml|Package\.swift|deno\.json)$'

# fw_relpath <path>. Repo-relative when inside FW_ROOT, else unchanged.
fw_relpath() {
  local p=$1
  case "$p" in
    "$FW_ROOT"/*) printf '%s' "${p#"$FW_ROOT"/}" ;;
    *) printf '%s' "$p" ;;
  esac
}

# fw_abspath <path>. Lexical absolute path, no symlink resolution.
fw_abspath() {
  local p=$1
  case "$p" in
    "~"|"~/"*) p="$HOME${p#\~}" ;;
    /*) ;;
    *) p="$PWD/$p" ;;
  esac
  # Collapse /./ and /../ lexically.
  printf '%s' "$p" | awk -F/ '{
    n = 0
    for (i = 2; i <= NF; i++) {
      if ($i == "" || $i == ".") continue
      if ($i == "..") { if (n > 0) n--; continue }
      s[++n] = $i
    }
    out = ""
    for (i = 1; i <= n; i++) out = out "/" s[i]
    print (out == "" ? "/" : out)
  }'
}

# fw_physpath <abs path>. Resolves symlinks in the nearest existing ancestor
# and keeps the rest. macOS /var -> /private/var, symlinked checkouts.
fw_physpath() {
  local abs=$1 dir rest=""
  dir=$abs
  while [ -n "$dir" ] && [ ! -d "$dir" ]; do
    rest="/${dir##*/}$rest"
    dir=${dir%/*}
  done
  [ -z "$dir" ] && dir=/
  dir=$(cd "$dir" 2>/dev/null && pwd -P) || { printf '%s' "$abs"; return; }
  [ "$dir" = / ] && dir=""
  printf '%s' "$dir$rest"
}

# fw_project_rel <path>. Repo-relative path, also when the path and FW_ROOT
# reach the same place through different symlinks. Absolute when outside.
fw_project_rel() {
  local abs p r
  abs=$(fw_abspath "$1")
  case "$abs" in "$FW_ROOT"/*) printf '%s' "${abs#"$FW_ROOT"/}"; return ;; esac
  p=$(fw_physpath "$abs")
  r=$(fw_physpath "$FW_ROOT")
  case "$p" in "$r"/*) printf '%s' "${p#"$r"/}" ;; *) printf '%s' "$abs" ;; esac
}

# fw_same_path <a> <b>. True when both name the same path, lexically or
# after resolving symlinks.
fw_same_path() {
  [ "$1" = "$2" ] && return 0
  [ "$(fw_physpath "$1")" = "$(fw_physpath "$2")" ]
}

# fw_inside_root <abs path>. True when the path is in FW_ROOT, lexically or
# after resolving symlinks (macOS /var -> /private/var, symlinked checkouts).
fw_inside_root() {
  local abs=$1 dir rootp
  case "$abs" in "$FW_ROOT"|"$FW_ROOT"/*) return 0 ;; esac
  rootp=$(cd "$FW_ROOT" 2>/dev/null && pwd -P) || return 1
  dir=$abs
  # Walk up to the nearest existing directory, then resolve it.
  while [ -n "$dir" ] && [ ! -d "$dir" ]; do dir=${dir%/*}; done
  [ -z "$dir" ] && dir=/
  dir=$(cd "$dir" 2>/dev/null && pwd -P) || return 1
  case "$dir/" in "$rootp"/*) return 0 ;; esac
  return 1
}

# fw_is_secret_path <path>
fw_is_secret_path() {
  printf '%s' "$1" | grep -qE "$FW_SECRET_FILE_RE" || return 1
  printf '%s' "$1" | grep -qE "$FW_SECRET_TEMPLATE_RE" && return 1
  return 0
}

# fw_path_tier <abs path>. Prints "red <reason>", "yellow <reason>", or "green".
fw_path_tier() {
  local abs rel
  abs=$(fw_abspath "$1")
  rel=$(fw_relpath "$abs")

  if fw_is_secret_path "$rel"; then echo "red secret or credential file"; return; fi
  if printf '%s' "$rel" | grep -qE "$FW_CONTROL_RE"; then echo "red agent control file (settings, git internals, MCP config)"; return; fi
  if printf '%s' "$rel" | grep -qE "$FW_GUARD_RE"; then
    if fw_maintainer; then echo "yellow framework guard file (maintainer mode)"; return; fi
    echo "red framework guard file (hooks, framework scripts, git hooks)"; return
  fi
  if printf '%s' "$rel" | grep -qE "$FW_LOCKFILE_RE"; then echo "red lockfile; regenerate it with the package manager instead of editing it"; return; fi
  if [ -n "${FW_RED_PATHS_EXTRA:-}" ] && printf '%s' "$rel" | grep -qE "$FW_RED_PATHS_EXTRA"; then echo "red project policy (FW_RED_PATHS_EXTRA)"; return; fi
  if ! fw_inside_root "$abs"; then
    case "$abs" in
      "${TMPDIR:-/tmp}"/*|/tmp/*|/private/tmp/*|/private/var/folders/*|/var/folders/*) echo "green"; return ;;
      *) echo "red outside the project directory"; return ;;
    esac
  fi

  if printf '%s' "$rel" | grep -qE "$FW_YELLOW_AGENT_RE"; then echo "yellow agent instructions (skills, agents, rules, styles)"; return; fi
  if printf '%s' "$rel" | grep -qiE "$FW_YELLOW_AUTH_RE"; then echo "yellow auth, session, or crypto code"; return; fi
  if printf '%s' "$rel" | grep -qE "$FW_YELLOW_DATA_RE"; then echo "yellow database schema or migration"; return; fi
  if printf '%s' "$rel" | grep -qE "$FW_YELLOW_CI_RE"; then echo "yellow CI or release pipeline"; return; fi
  if printf '%s' "$rel" | grep -qE "$FW_YELLOW_INFRA_RE"; then echo "yellow infrastructure or platform config"; return; fi
  if printf '%s' "$rel" | grep -qE "$FW_YELLOW_DEPS_RE"; then echo "yellow dependency manifest"; return; fi
  if [ -n "${FW_YELLOW_PATHS_EXTRA:-}" ] && printf '%s' "$rel" | grep -qE "$FW_YELLOW_PATHS_EXTRA"; then echo "yellow project policy (FW_YELLOW_PATHS_EXTRA)"; return; fi
  echo "green"
}

# Secret value patterns, one ERE per line: name<TAB>regex.
fw_secret_patterns() {
  cat <<'EOF'
private key	-----BEGIN ([A-Z]+ )?PRIVATE KEY( BLOCK)?-----
AWS access key id	(AKIA|ASIA|ABIA|ACCA)[0-9A-Z]{16}
GitHub token	(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}
GitHub fine-grained token	github_pat_[A-Za-z0-9_]{60,}
GitLab token	glpat-[A-Za-z0-9_-]{20,}
Slack token	xox[abposr]-[A-Za-z0-9-]{10,}
Slack webhook	hooks\.slack\.com/services/T[A-Za-z0-9_]+/B[A-Za-z0-9_]+/[A-Za-z0-9_]+
Stripe live key	(sk|rk)_live_[0-9A-Za-z]{20,}
Google API key	AIza[0-9A-Za-z_-]{35}
Anthropic API key	sk-ant-[A-Za-z0-9_-]{20,}
OpenAI API key	sk-(proj-|svcacct-)?[A-Za-z0-9_-]{32,}
Supabase access token	sbp_[a-f0-9]{40}
npm token	npm_[A-Za-z0-9]{36}
PyPI token	pypi-AgEIcHlwaS5vcmc[A-Za-z0-9_-]{50,}
SendGrid key	SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}
Twilio key	SK[0-9a-fA-F]{32}
JSON web token	eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}
URL with password	[A-Za-z][A-Za-z0-9+.-]*://[^:/@[:space:]"']+:[^@/[:space:]"'$<{]{6,}@
assigned secret	(password|passwd|pwd|secret|api[_-]?key|apikey|access[_-]?key|auth[_-]?token|client[_-]?secret|private[_-]?key)["']?[[:space:]]*[:=][[:space:]]*["'][^"'[:space:]$<{]{12,}["']
EOF
}

# Lines that look like placeholders, not real secrets.
FW_PLACEHOLDER_RE='(0{12,}|x{8,}|X{8,}|\*{6,}|example|EXAMPLE|Example|dummy|DUMMY|fake|FAKE|placeholder|PLACEHOLDER|changeme|CHANGEME|your[-_]|YOUR[-_]|<[a-zA-Z_-]+>|\$\{|\{\{|process\.env|os\.environ|getenv|env\(|import\.meta\.env|fw:allow-secret)'

# fw_scan_secrets. Reads text on stdin. Prints "name: line" per finding.
# Exit 0 when it found something, 1 when clean.
fw_scan_secrets() {
  local text found=1 name re hits
  text=$(cat)
  [ -z "$text" ] && return 1
  while IFS="$(printf '\t')" read -r name re; do
    [ -z "$re" ] && continue
    hits=$(printf '%s\n' "$text" | grep -iE -- "$re" 2>/dev/null | grep -vE -- "$FW_PLACEHOLDER_RE" | head -3)
    if [ -n "$hits" ] && [ -n "${FW_SECRET_ALLOW:-}" ]; then
      hits=$(printf '%s\n' "$hits" | grep -vE -- "$FW_SECRET_ALLOW")
    fi
    if [ -n "$hits" ]; then
      found=0
      printf '%s\n' "$hits" | while IFS= read -r line; do
        # Never echo the full secret back into the transcript.
        printf '%s: %s\n' "$name" "$(printf '%s' "$line" | cut -c1-60 | sed -E 's/([A-Za-z0-9_+\/=-]{6})[A-Za-z0-9_+\/=-]{6,}/\1[REDACTED]/g')"
      done
    fi
  done <<EOF
$(fw_secret_patterns)
EOF
  return $found
}
