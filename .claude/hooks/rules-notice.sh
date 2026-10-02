#!/usr/bin/env bash
# PostToolUse hook (Edit|Write|MultiEdit|NotebookEdit): name the rules file
# that applies to the file Claude just wrote.
#
# Claude Code loads a path-scoped rule (`paths:` frontmatter in
# .claude/rules/*.md) only when Claude reads a matching file. Creating a new
# file never loads it. This hook closes that gap: on each write it matches the
# path against every rule's globs and, once per rule per session, tells Claude
# to read the rule and check the change against it.
set -uo pipefail
. "$(dirname "$0")/lib/common.sh"
. "$(dirname "$0")/lib/policy.sh"

fw_read_input
fw_enter_project
path=$(fw_get '.tool_input.file_path // .tool_input.notebook_path')
[ -z "$path" ] && exit 0
rules_dir="$FW_ROOT/.claude/rules"
[ -d "$rules_dir" ] || exit 0
rel=$(fw_project_rel "$path")
case "$rel" in /*) exit 0 ;; esac

# rule_globs <file>. Prints each glob from the `paths:` frontmatter, one per
# line. Handles the YAML list form and the inline [a, b] form.
rule_globs() {
  awk '
    NR == 1 && $0 != "---" { exit }
    NR == 1 { infm = 1; next }
    infm && $0 == "---" { exit }
    infm && /^paths:[ \t]*\[/ {
      line = $0; sub(/^paths:[ \t]*\[/, "", line); sub(/\][ \t]*$/, "", line)
      # Split on commas outside {braces}, so "src/**/*.{ts,tsx}" stays whole.
      depth = 0; g = ""
      for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == "{") depth++
        if (c == "}") depth--
        if (c == "," && depth == 0) { gsub(/^[ \t]*["\047]?|["\047]?[ \t]*$/, "", g); if (g != "") print g; g = ""; continue }
        g = g c
      }
      gsub(/^[ \t]*["\047]?|["\047]?[ \t]*$/, "", g); if (g != "") print g
      next
    }
    infm && /^paths:/ { inpaths = 1; next }
    infm && inpaths && /^[ \t]*-[ \t]*/ {
      g = $0; sub(/^[ \t]*-[ \t]*/, "", g); gsub(/^["\047]|["\047][ \t]*$/, "", g); print g; next
    }
    infm && inpaths && /^[^ \t]/ { inpaths = 0 }
  ' "$1"
}

# glob_to_ere <glob>. ** spans directories, * and ? stay inside one, {a,b}
# picks one, and a leading **/ also matches at the repo root.
glob_to_ere() {
  printf '%s' "$1" | awk '{
    g = $0; out = ""; n = length(g); i = 1; inbrace = 0
    while (i <= n) {
      c = substr(g, i, 1)
      if (c == "*" && substr(g, i + 1, 1) == "*") {
        if (substr(g, i + 2, 1) == "/") { out = out "(.*/)?"; i += 3 } else { out = out ".*"; i += 2 }
        continue
      }
      if (c == "*") out = out "[^/]*"
      else if (c == "?") out = out "[^/]"
      else if (c == "{") { out = out "("; inbrace = 1 }
      else if (c == "}" && inbrace) { out = out ")"; inbrace = 0 }
      else if (c == "," && inbrace) out = out "|"
      else if (index(".+()|^$[]\\", c)) out = out "\\" c
      else out = out c
      i++
    }
    print "^" out "$"
  }'
}

state=$(fw_state_dir)
hits=""
for rule in "$rules_dir"/*.md; do
  [ -f "$rule" ] || continue
  name=$(basename "$rule")
  [ -f "$state/rule.$name" ] && continue
  matched=0
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    if printf '%s\n' "$rel" | grep -qE "$(glob_to_ere "$g")"; then matched=1; break; fi
  done <<EOF
$(rule_globs "$rule")
EOF
  if [ "$matched" = 1 ]; then
    touch "$state/rule.$name"
    hits="$hits .claude/rules/$name"
  fi
done
[ -z "$hits" ] && exit 0

fw_context PostToolUse "Path-scoped rules apply to $rel:$hits
Read each of these files now if you have not read it in this session, and check this change against it. Fix any rule you broke before you continue." "rules:$hits"
