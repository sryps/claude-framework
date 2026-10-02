#!/usr/bin/env bash
# PreToolUse hook (Bash): block Red-tier commands in any spelling.
#
# Permission deny rules match a command prefix, so `git -C . push origin main`,
# `bash -c "git push origin main"`, or `head .env` slip past them. This hook
# reads the whole command string instead, splits it into segments on shell
# operators, and checks each segment and the whole string.
#
# Exit 2 blocks the call and sends the reason to Claude.
# Without jq the hook matches against the raw JSON input, so it still blocks.
#
# Escape hatch for a human: FW_GUARD_ALLOW, an ERE in the settings "env" block.
# A command that matches it skips this hook. Claude cannot set it, because
# protected-paths blocks edits to .claude/settings*.json.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
. "$(dirname "$0")/lib/policy.sh"

# No filename globbing: the hook splits commands on spaces.
set -f

fw_read_input
if [ "$FW_HAS_JQ" = 1 ]; then
  cmd=$(fw_get '.tool_input.command')
else
  cmd=$FW_INPUT
fi
[ -z "$cmd" ] && exit 0
fw_enter_project

if [ -n "${FW_GUARD_ALLOW:-}" ] && printf '%s' "$cmd" | grep -qE -- "$FW_GUARD_ALLOW"; then
  exit 0
fi

deny() {
  fw_block "Blocked by bash-guard: $1
Command: $(printf '%s' "$cmd" | head -c 300)
This is a hard limit of the framework. Do not try another spelling of the same command.
If the task needs it, stop that part and record it under Blocked with the reason, so a human can run it."
}

# Text that never runs gets removed before matching, so docs and messages do
# not trip the guard:
#   - heredoc bodies, unless the heredoc feeds a shell (bash <<EOF runs it)
#   - quoted message arguments to git, gh, glab, and tea (-m, --body, ...),
#     unless the text holds $( or a backtick, which run inside double quotes
strip_heredocs() {
  awk '
    BEGIN { hd = "<<-?[ \t]*[\"\047]?[A-Za-z_][A-Za-z0-9_]*[\"\047]?" }
    inhd {
      line = $0
      if (strip) sub(/^\t+/, "", line)
      if (line == delim) { inhd = 0; print; next }
      if (keep) print
      next
    }
    {
      print
      probe = $0
      gsub(/<<</, "", probe)
      if (match(probe, hd)) {
        m = substr(probe, RSTART, RLENGTH)
        strip = (m ~ /^<<-/)
        sub(/^<<-?[ \t]*/, "", m)
        gsub(/[\"\047]/, "", m)
        delim = m
        inhd = 1
        keep = (probe ~ /(^|[;&|( \t])(sudo[ \t]+)?((ba|z|da|k)?sh|ssh|eval|source|xargs)([ \t]|$)/)
      }
    }'
}
mask_messages() {
  awk '
    BEGIN { RS = "\001"; ORS = "" }
    {
      s = $0; n = length(s); out = ""; i = 1; cmd = ""; atstart = 1
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\"" || c == "\047") {
          q = c; j = i + 1
          while (j <= n) {
            d = substr(s, j, 1)
            if (q == "\"" && d == "\\") { j += 2; continue }
            if (d == q) break
            j++
          }
          body = substr(s, i, j - i + 1)
          runs = (q == "\"" && (index(body, "$(") || index(body, "`")))
          if (!runs && (cmd == "git" || cmd == "gh" || cmd == "glab" || cmd == "tea") &&
              out ~ /(^|[ \t])(-m|--message|-b|--body|-t|--title|-d|--description|--notes)[ \t=]*$/)
            body = q "MSG" q
          out = out body; i = j + 1; atstart = 0
          continue
        }
        if (c == ";" || c == "&" || c == "|" || c == "\n" || c == "(") {
          atstart = 1; cmd = ""; out = out c; i++; continue
        }
        if (atstart && c != " " && c != "\t") {
          j = i
          while (j <= n && substr(s, j, 1) !~ /[ \t;&|\n()]/) j++
          w = substr(s, i, j - i)
          out = out w; i = j
          if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
          sub(/.*\//, "", w); cmd = w; atstart = 0
          continue
        }
        out = out c; i++
      }
      print out
    }'
}
scan=$(printf '%s\n' "$cmd" | strip_heredocs | mask_messages)

# Normalize: newlines, `&&`, `||`, `;`, `|`, `&`, `$(`, and backticks start a new segment.
segments=$(printf '%s\n' "$scan" | sed -E 's/([&][&]|[|][|]|[;]|[|]|[&]|[$][(]|`|[(]|[)])/\
/g')

# Whole-string checks first. These span segments.
if printf '%s' "$scan" | grep -qE "(curl|wget|fetch|iwr|Invoke-WebRequest)${FW_E}[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da|k|fi)?sh${FW_E}"; then
  deny "piping a download into a shell runs unreviewed code (supply chain)."
fi
if printf '%s' "$scan" | grep -qE "(ba|z)?sh[[:space:]]+<\([[:space:]]*(curl|wget)"; then
  deny "running a downloaded script through process substitution."
fi

current_branch=$(git branch --show-current 2>/dev/null || true)
has_commits=0
git rev-parse --verify --quiet HEAD >/dev/null 2>&1 && has_commits=1

check_segment() {
  local s=$1 w
  # Environment dumps, checked before `env` is stripped as a wrapper below.
  if printf '%s' "$s" | grep -qE "^[[:space:]]*(env|printenv|set|export[[:space:]]+-p|declare[[:space:]]+-x)[[:space:]]*$|^[[:space:]]*printenv([[:space:]]|$)|/proc/[^[:space:]]*/environ"; then
    deny "dumping environment variables can expose secrets."
  fi
  # Strip leading env assignments, sudo-like wrappers, and spaces.
  s=$(printf '%s' "$s" | sed -E 's/^[[:space:]]+//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)+//; s/^(command|builtin|exec|nohup|time|nice|env)[[:space:]]+//')
  [ -z "$s" ] && return 0
  w=$(printf '%s' "$s" | awk '{print $1}')
  w=${w##*/}

  # --- privilege and system ---
  case "$w" in
    sudo|doas|su|pkexec|runas) deny "privilege escalation ($w)." ;;
  esac
  if printf '%s' "$s" | grep -qE "^chmod[[:space:]]+(-R[[:space:]]+)?(0?777|a\+rwx)"; then deny "world-writable permissions."; fi

  # --- secrets and environment dumps ---
  local tok
  for tok in $s; do
    tok=${tok#[\"\']}; tok=${tok%[\"\']}
    tok=${tok#*=}
    case "$tok" in -*|"") continue ;; esac
    if fw_is_secret_path "$tok"; then
      printf '%s' "$s" | grep -qE '\.gitignore|\.dockerignore|^git[[:space:]]+(check-ignore|ls-files|status|rm[[:space:]]+--cached)' && continue
      deny "the command touches a secret or credential file ($tok). Agents never read, copy, or write secrets."
    fi
  done

  # --- agent control files ---
  guard_re='\.claude/settings[^[:space:]]*\.json|\.git/hooks/|core\.hooksPath'
  fw_maintainer || guard_re="$guard_re|\.claude/hooks/|\.claude/framework/|\.githooks/"
  if printf '%s' "$s" | grep -qE "$guard_re"; then
    # Reading is fine. So is running the framework's own checks. A write
    # redirect or an in-place flag makes it a write.
    if printf '%s' "$s" | grep -qE '>|[[:space:]](-i|--in-place)([[:space:]=]|$)' || \
       ! printf '%s' "$s" | grep -qE '^(cat|ls|head|tail|less|grep|rg|jq|diff|wc|git[[:space:]]+(diff|log|show|status|ls-files|check-ignore|blame))[[:space:]]|^((ba)?sh[[:space:]]+)?[^[:space:]]*\.claude/framework/(verify\.sh|tests/[^[:space:]]+\.sh)([[:space:]]|$)'; then
      deny "changing agent settings, framework guard files, or git hooks can turn off the guards."
    fi
  fi
  if printf '%s' "$s" | grep -qE "^git([[:space:]]|$).*--no-verify|^git([[:space:]]|$).*[[:space:]]-n([[:space:]]|$).*commit|^git[[:space:]]+commit([[:space:]].*)?[[:space:]]-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)"; then
    deny "--no-verify skips the repository's git hooks."
  fi
  if printf '%s' "$s" | grep -qE "^git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]].*-c[[:space:]]+core\.hooksPath"; then deny "overriding core.hooksPath skips git hooks."; fi

  # --- git: protected branches and history ---
  if [ "$w" = git ]; then
    # Drop global options (-C dir, -c k=v, --git-dir=..., --work-tree=...) to find the subcommand.
    local rest sub
    rest=$(printf '%s' "$s" | sed -E 's/^git//; s/[[:space:]]+-C[[:space:]]+[^[:space:]]+//g; s/[[:space:]]+-c[[:space:]]+[^[:space:]]+//g; s/[[:space:]]+--(git-dir|work-tree|namespace)(=|[[:space:]]+)[^[:space:]]+//g; s/[[:space:]]+--no-pager//g')
    sub=$(printf '%s' "$rest" | awk '{print $1}')
    case "$sub" in
      push)
        if printf '%s' "$rest" | grep -qE "[[:space:]](-f|--force|--force-with-lease|--force-if-includes|--mirror|--delete|-d)([[:space:]=]|$)|[[:space:]]\+[^[:space:]]+|[[:space:]]:[^[:space:]]+"; then
          deny "force push, mirror push, or remote branch delete."
        fi
        if printf '%s' "$rest" | grep -qE "[[:space:]:](refs/heads/)?(main|master|trunk|production|prod|release(/[^[:space:]]*)?)([[:space:]]|$)|[[:space:]]--all([[:space:]]|$)|[[:space:]]--tags([[:space:]]|$)"; then
          deny "pushing to a protected branch or pushing all refs or tags. Push your feature branch and open a PR."
        fi
        if [ -n "$current_branch" ] && fw_is_protected_branch "$current_branch"; then
          # Bare `git push`, `git push origin`, or `git push origin HEAD` while on a protected branch.
          if ! printf '%s' "$rest" | grep -qE "^push([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^-[:space:]][^[:space:]]*[[:space:]]+[^-[:space:]]" || printf '%s' "$rest" | grep -qE "[[:space:]]HEAD([[:space:]]|$)"; then
            deny "pushing while on protected branch '$current_branch'. Create a feature branch first."
          fi
        fi
        ;;
      reset)
        printf '%s' "$rest" | grep -qE -- "--hard|--merge|--keep" && deny "git reset --hard discards work. Use git stash or a new commit."
        ;;
      clean)
        printf '%s' "$rest" | grep -qE -- "[[:space:]]-[a-zA-Z]*f|--force" && deny "git clean -f deletes untracked files."
        ;;
      checkout|restore)
        printf '%s' "$rest" | grep -qE "[[:space:]]--[[:space:]]+\.([[:space:]]|$)|[[:space:]]\.([[:space:]]|$)" && \
          printf '%s' "$rest" | grep -qvE -- "-b[[:space:]]|--staged" && deny "discarding all working tree changes. Use git stash."
        ;;
      branch)
        printf '%s' "$rest" | grep -qE "[[:space:]](-D|-d|--delete|-M|-m|--move|-f|--force)([[:space:]].*)?[[:space:]](main|master|trunk|production|prod)([[:space:]]|$)" && deny "deleting, moving, or forcing a protected branch."
        ;;
      filter-branch|filter-repo|replace|update-ref)
        deny "history rewrite ($sub)."
        ;;
      rebase)
        if [ -n "$current_branch" ] && fw_is_protected_branch "$current_branch"; then deny "rebasing protected branch '$current_branch'."; fi
        ;;
      merge|cherry-pick|commit|am|revert)
        if [ -n "$current_branch" ] && fw_is_protected_branch "$current_branch" && [ "$has_commits" = 1 ]; then
          deny "$sub on protected branch '$current_branch'. Create a feature branch first: git switch -c <type>/<name>."
        fi
        ;;
      config)
        printf '%s' "$rest" | grep -qE "(credential|url\..*insteadOf|core\.hooksPath|core\.sshCommand|http\..*extraheader)" && deny "changing git credential, URL, or hook config."
        ;;
    esac
  fi

  # --- GitHub CLI ---
  if [ "$w" = gh ]; then
    if printf '%s' "$s" | grep -qE "^gh[[:space:]]+pr[[:space:]]+merge|^gh[[:space:]]+api.*(/merge|/merges)([[:space:]\"']|$)|^gh[[:space:]]+api.*-X[[:space:]]*(PUT|DELETE|PATCH)"; then
      deny "merging or mutating through the GitHub API. Only a human merges."
    fi
    if printf '%s' "$s" | grep -qE "^gh[[:space:]]+(release[[:space:]]+(create|upload|edit|delete)|secret|variable|repo[[:space:]]+(delete|edit|archive|rename)|ruleset|workflow[[:space:]]+(run|enable|disable)|run[[:space:]]+(rerun|cancel|delete)|auth|ssh-key|gpg-key|codespace|cache[[:space:]]+delete)"; then
      deny "release, secret, repository, workflow, or auth change through gh."
    fi
    if printf '%s' "$s" | grep -qE "^gh[[:space:]]+pr[[:space:]]+(review[[:space:]].*--approve|ready[[:space:]].*--undo)"; then
      deny "an agent must not approve a pull request."
    fi
  fi

  # --- GitLab and Gitea CLIs ---
  if [ "$w" = glab ] || [ "$w" = tea ]; then
    if printf '%s' "$s" | grep -qE "^(glab[[:space:]]+mr|tea[[:space:]]+(pr|pulls))[[:space:]]+(merge|approve)|^glab[[:space:]]+api.*(/merge|-X[[:space:]]*(PUT|DELETE|PATCH)|--method[[:space:]]*(PUT|DELETE|PATCH))"; then
      deny "merging or approving a merge request. Only a human merges."
    fi
    if printf '%s' "$s" | grep -qE "^glab[[:space:]]+(release[[:space:]]+(create|upload|delete)|variable|repo[[:space:]]+(delete|archive|transfer)|auth|ssh-key|deploy-key|ci[[:space:]]+(run|retry|delete|cancel))|^tea[[:space:]]+(releases?[[:space:]]+(create|delete)|login|repos[[:space:]]+delete)"; then
      deny "release, variable, repository, pipeline, or auth change through $w."
    fi
  fi

  # --- deploy, publish, release ---
  if printf '%s' "$s" | grep -qE "^(npm|pnpm|yarn|bun)[[:space:]]+(.*[[:space:]])?(publish|unpublish|deprecate|dist-tag|owner|token|adduser|login)([[:space:]]|$)|^yarn[[:space:]]+npm[[:space:]]+publish|^(cargo)[[:space:]]+(publish|yank|owner|login)|^(twine)[[:space:]]+upload|^(poetry|uv|hatch|flit|pdm)[[:space:]]+publish|^gem[[:space:]]+(push|yank|signin)|^(dotnet[[:space:]]+nuget|nuget)[[:space:]]+push|^pod[[:space:]]+trunk|^(mvn|gradle|\./gradlew|\./mvnw).*[[:space:]](deploy|publish|publishToMavenCentral)([[:space:]]|$)|^goreleaser([[:space:]]|$)|^(docker|podman)[[:space:]]+(push|login|manifest[[:space:]]+push)|^(docker|podman)[[:space:]]+buildx[[:space:]]+build.*--push"; then
    deny "publishing a package or image."
  fi
  if printf '%s' "$s" | grep -qE "^(terraform|tofu|terragrunt)[[:space:]]+(.*[[:space:]])?(apply|destroy|import|taint|untaint|state[[:space:]]+(rm|mv|push)|force-unlock)([[:space:]]|$)|^pulumi[[:space:]]+(up|destroy|import|refresh|cancel|stack[[:space:]]+rm|state)|^cdk[[:space:]]+(deploy|destroy|bootstrap)|^(sam)[[:space:]]+(deploy|delete)|^(serverless|sls)[[:space:]]+(deploy|remove)|^(kubectl|oc)[[:space:]]+(apply|create|delete|edit|patch|replace|scale|rollout|set|label|annotate|drain|cordon|taint|exec|cp|port-forward)([[:space:]]|$)|^helm[[:space:]]+(install|upgrade|uninstall|delete|rollback)|^(fly|flyctl)[[:space:]]+(deploy|launch|secrets|scale|destroy|apps[[:space:]]+destroy)|^vercel([[:space:]]|$)|^netlify[[:space:]]+(deploy|env)|^firebase[[:space:]]+(deploy|hosting|functions:delete|firestore:delete|auth:import)|^(wrangler)[[:space:]]+(deploy|publish|secret|delete|d1[[:space:]]+execute.*--remote)|^heroku([[:space:]]|$)|^railway[[:space:]]+(up|deploy|variables)|^render([[:space:]]|$)|^(eas|npx[[:space:]]+eas)[[:space:]]+(submit|update|build.*--auto-submit|secret|env:)|^fastlane[[:space:]]+(release|deliver|supply|pilot|upload|beta|appstore|playstore)|^ansible-playbook([[:space:]]|$)"; then
    deny "deploy, infrastructure change, or store release."
  fi
  if printf '%s' "$s" | grep -qE "^make[[:space:]]+(.*[[:space:]])?[^[:space:]]*(deploy|release|publish|submit|prod|production|rollout)[^[:space:]]*([[:space:]]|$)"; then
    deny "a make target that deploys, releases, or touches production."
  fi

  # --- databases ---
  if printf '%s' "$s" | grep -qiE "(drop[[:space:]]+(database|schema|table)|truncate[[:space:]]+table)" && \
     printf '%s' "$s" | grep -qE "^(psql|mysql|mariadb|sqlite3|mongosh|mongo|redis-cli|cqlsh|sqlcmd|clickhouse-client)([[:space:]]|$)"; then
    deny "destructive SQL through a database client. Write a migration instead."
  fi
  if printf '%s' "$s" | grep -qE "^redis-cli.*(flushall|flushdb)|^(prisma|npx[[:space:]]+prisma)[[:space:]]+(migrate[[:space:]]+(reset|deploy)|db[[:space:]]+push.*--accept-data-loss)|^(rails|bin/rails|rake)[[:space:]]+db:(drop|reset|purge)|^(alembic)[[:space:]]+downgrade[[:space:]]+base"; then
    deny "destructive database command."
  fi
  if printf '%s' "$s" | grep -qE "(--db-url|--linked|DATABASE_URL=[^[:space:]]*(amazonaws|supabase\.co|neon\.tech|planetscale|cockroachlabs|azure|render\.com|railway))"; then
    deny "a command aimed at a remote or linked database."
  fi

  # --- rm -r outside the project ---
  if [ "$w" = rm ] && printf '%s' "$s" | grep -qE "[[:space:]]-[a-zA-Z]*[rR]|--recursive"; then
    local a abs
    for a in $(printf '%s' "$s" | cut -d' ' -f2-); do
      case "$a" in -*) continue ;; esac
      a=${a#[\"\']}; a=${a%[\"\']}
      case "$a" in
        "~"|"~/"*|'$HOME'*|'${HOME}'*|"/"|"/*"|"*"|".."|"../"*|"."|"./") deny "recursive delete of '$a'." ;;
      esac
      abs=$(fw_abspath "$a")
      fw_same_path "$abs" "$FW_ROOT" && deny "recursive delete of the project root."
      if ! fw_inside_root "$abs"; then
        case "$abs" in
          "${TMPDIR:-/tmp}"/*|/tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) ;;
          *) deny "recursive delete outside the project directory ($abs)." ;;
        esac
      fi
      fw_same_path "$abs" "$FW_ROOT/.git" && deny "deleting the git directory."
    done
  fi

  # --- autonomous profile only: global installs and cloud CLIs ---
  if fw_autonomous; then
    if printf '%s' "$s" | grep -qE "^(npm|pnpm|yarn|bun)[[:space:]]+(.*[[:space:]])?(-g|--global)([[:space:]]|$)|^yarn[[:space:]]+global|^(brew|port|apt|apt-get|dnf|yum|pacman|apk|snap|choco|winget|scoop)[[:space:]]+(install|upgrade|remove|uninstall|reinstall)|^pip3?[[:space:]]+install.*(--user|--break-system-packages)|^(cargo|go)[[:space:]]+install([[:space:]]|$)|^pipx[[:space:]]+install|^gem[[:space:]]+install"; then
      deny "global or system package install. Add the dependency to the project manifest instead."
    fi
    if printf '%s' "$s" | grep -qE "^(aws|gcloud|gsutil|bq|az|doctl|linode-cli|hcloud|oci|ibmcloud|supabase|stripe|twilio|sentry-cli)([[:space:]]|$)"; then
      printf '%s' "$s" | grep -qE "^[^[:space:]]+[[:space:]]+(--version|version|--help|help)$|^supabase[[:space:]]+(start|stop|status|test|gen|db[[:space:]]+(reset|lint|diff|start)|migration[[:space:]]+(new|list|up)|functions[[:space:]]+(new|serve)|init)([[:space:]]|$)" || \
        deny "cloud or SaaS CLI in an unattended run. These can reach production accounts."
    fi
  fi
  return 0
}

while IFS= read -r seg; do
  check_segment "$seg"
done <<EOF
$segments
EOF

# Nested shells: check the inner command string too.
inner=$(printf '%s' "$cmd" | sed -nE "s/.*(bash|sh|zsh|dash)[[:space:]]+-[a-z]*c[[:space:]]+[\"']([^\"']*)[\"'].*/\2/p" | head -1)
if [ -n "$inner" ] && [ "$inner" != "$cmd" ]; then
  while IFS= read -r seg; do
    check_segment "$seg"
  done <<EOF
$(printf '%s\n' "$inner" | sed -E 's/([&][&]|[|][|]|[;]|[|]|[&])/\
/g')
EOF
fi
exit 0
