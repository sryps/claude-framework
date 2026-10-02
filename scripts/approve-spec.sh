#!/usr/bin/env bash
# Approve the spec for the current branch. Only a human runs this: agents are
# blocked from running it and from writing .claude/approvals/.
#
#   scripts/approve-spec.sh docs/specs/<feature>.md   approve this spec for the branch
#   scripts/approve-spec.sh --no-spec "<reason>"      approve the branch without a spec
#   scripts/approve-spec.sh --status                  show the approval for the branch
#   scripts/approve-spec.sh --revoke                  remove the approval for the branch
#
# The approval records the spec's SHA-256. When the spec changes, the
# approval no longer matches, and the spec-gate hook blocks code edits until
# you approve again. That keeps the code tied to the spec you read.
#
# The approval lives in .claude/approvals/<branch>.json. Commit it with the
# branch, so reviewers and other machines see what was approved.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Not in a git repository." >&2; exit 1; }
cd "$root"
branch=$(git branch --show-current)
[ -n "$branch" ] || { echo "Detached HEAD. Check out the feature branch first." >&2; exit 1; }
case "$branch" in
  main|master|trunk) echo "You are on $branch. Approve the spec on the feature branch." >&2; exit 1 ;;
esac
dir=.claude/approvals
file="$dir/$(printf '%s' "$branch" | tr '/' '_' | tr -c 'A-Za-z0-9._-' '_').json"

sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

approve() {
  # approve <spec path or none> <sha or ""> <reason>
  mkdir -p "$dir"
  jq -n --arg b "$branch" --arg s "$1" --arg h "$2" --arg r "$3" \
    --arg who "$(git config user.name || echo unknown)" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{branch: $b, spec: $s, sha256: $h, reason: $r, approved_by: $who, approved_at: $at}' >"$file"
  echo "Approved for branch $branch: $file"
  echo "Commit it with the branch: git add $file"
}

case "${1:-}" in
  --status)
    if [ ! -f "$file" ]; then echo "No approval for branch $branch."; exit 1; fi
    jq . "$file"
    spec=$(jq -r .spec "$file")
    if [ "$spec" != none ]; then
      if [ ! -f "$spec" ]; then echo "STALE: $spec no longer exists."; exit 1; fi
      [ "$(sha "$spec")" = "$(jq -r .sha256 "$file")" ] && echo "VALID: $spec is unchanged since approval." || { echo "STALE: $spec changed since approval. Read it and approve again."; exit 1; }
    fi
    ;;
  --revoke)
    rm -f "$file" && echo "Removed the approval for branch $branch."
    ;;
  --no-spec)
    reason=${2:-}
    [ -n "$reason" ] || { echo "Give the reason: scripts/approve-spec.sh --no-spec \"typo fix in a log message\"" >&2; exit 1; }
    approve none "" "$reason"
    ;;
  ""|-h|--help)
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    spec=$1
    [ -f "$spec" ] || { echo "Spec not found: $spec" >&2; exit 1; }
    case "$spec" in /*) spec=${spec#"$root"/} ;; esac
    criteria=$(grep -cE '^[[:space:]]*[-*]?[[:space:]]*(\*\*)?AC-[0-9]+' "$spec" || true)
    placeholders=$(grep -cE '\{\{[^}]*\}\}' "$spec" || true)
    questions=$(awk '/^## Open questions/{f=1; next} /^## /{f=0} f && /^[[:space:]]*[-*][[:space:]]+[^[:space:]{]/' "$spec" | wc -l | tr -d ' ')
    echo "Spec: $spec"
    echo "  acceptance criteria: $criteria"
    echo "  unfilled placeholders: $placeholders"
    echo "  open questions: $questions"
    if [ "$criteria" -eq 0 ]; then echo "Refused: the spec has no acceptance criteria (AC-1, AC-2, ...)." >&2; exit 1; fi
    if [ "$placeholders" -gt 0 ]; then echo "Refused: the spec still has {{placeholders}}. Fill them or delete those lines." >&2; exit 1; fi
    if [ "$questions" -gt 0 ]; then echo "Note: $questions open question(s). The agent will use the interim choices written there."; fi
    approve "$spec" "$(sha "$spec")" ""
    ;;
esac
