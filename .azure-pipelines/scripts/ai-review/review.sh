#!/usr/bin/env bash
# AI code review of a PR diff with Claude Code (read-only tools).
#
# Env in:  REVIEW_SCOPE   space-separated repo paths this pipeline reviews
#          REVIEW_PROMPT  repo-relative path of the component prompt (project context/rules)
#          CLAUDE_CODE_OAUTH_TOKEN
# Out:     $BUILD_ARTIFACTSTAGINGDIRECTORY/ai-review.json  {summary, findings[], verdict}
#
# Never fails the build: no diff or an AI outage just means no review. The gate
# lives in post.sh, and the verdict is derived here from the findings (not taken
# from the model) so it is deterministic.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$BUILD_ARTIFACTSTAGINGDIRECTORY"
cd "$SYSTEM_DEFAULTWORKINGDIRECTORY"
warn() { echo "##vso[task.logissue type=warning]$*"; }

# ---- 1. The diff ---------------------------------------------------------------
# PR build: HEAD is GitHub's merge commit, its first parent is the target branch.
BASE=$(git rev-parse 'HEAD^1')
read -ra SCOPE <<< "$REVIEW_SCOPE"
# Lockfiles, generated/bulk SQL and minified assets are noise.
EXCLUDES=(':(exclude)*package-lock.json' ':(exclude)*.min.js' ':(exclude)*.svg'
          ':(exclude)*/db/seed.sql' ':(exclude)*/db/deploy_all.sql')
git diff --no-color --unified=5 "$BASE" HEAD -- "${SCOPE[@]}" "${EXCLUDES[@]}" > "$OUT/pr.diff"

if [ ! -s "$OUT/pr.diff" ]; then
  echo "No reviewable changes in this pipeline's paths -- skipping AI review."
  exit 0
fi
DIFF_LIMIT=200000
NOTE=""
if [ "$(wc -c < "$OUT/pr.diff")" -gt "$DIFF_LIMIT" ]; then
  NOTE="NOTE: the diff was truncated to ${DIFF_LIMIT} bytes; files after the cut-off were NOT reviewed. Say so in your summary."
  warn "PR diff exceeds ${DIFF_LIMIT} bytes -- AI review covers only the first part."
fi

# ---- 2. The prompt: shared rules + component context + diff ---------------------
PROMPT=$(mktemp)
{
  cat "$HERE/rules.md"
  printf '\n'
  cat "$REVIEW_PROMPT"
  printf '\n%s\n\n--- PR DIFF (unified) ---\n' "$NOTE"
  head -c "$DIFF_LIMIT" "$OUT/pr.diff"
} > "$PROMPT"

# ---- 3. Run Claude ----------------------------------------------------------------
if ! npm install -g --silent @anthropic-ai/claude-code; then
  warn "Could not install the Claude Code CLI -- skipping AI review."
  exit 0
fi

# Read/Grep/Glob, all limited to the checkout. Anything outside it (~/.claude,
# ~/.ssh, /proc/self/environ = the OAuth token, ...) is unreadable, so a
# prompt-injected diff cannot leak it. Scope ALL THREE: a bare Grep/Glob is not
# limited to the workspace.
ROOT="/$PWD/**"   # "//abs/path" is Claude's syntax for an absolute path
TOOLS="Read($ROOT),Grep($ROOT),Glob($ROOT)"

set +e
timeout 900 claude -p --output-format json --max-turns 25 \
  --json-schema "$(jq -c . "$HERE/schema.json")" \
  --allowedTools "$TOOLS" \
  < "$PROMPT" > "$OUT/claude-output.json" 2> "$OUT/claude-stderr.log"
STATUS=$?
set -e
rm -f "$PROMPT"

REVIEW=$(jq -c '.structured_output // empty' "$OUT/claude-output.json" 2> /dev/null || true)
if [ "$STATUS" -ne 0 ] || [ -z "$REVIEW" ]; then
  warn "AI review returned no result (exit $STATUS) -- not blocking."
  tail -n 20 "$OUT/claude-stderr.log" || true
  exit 0
fi

# ---- 4. Verdict ----------------------------------------------------------------------
#   BLOCKING_ISSUES = any blocker    NEEDS_ATTENTION = any major    else LOOKS_GOOD
echo "$REVIEW" | jq '
  { summary, findings: [ .findings[] | select(.severity | IN("blocker","major","minor")) ] }
  | .verdict = (if   any(.findings[]; .severity == "blocker") then "BLOCKING_ISSUES"
                elif any(.findings[]; .severity == "major")   then "NEEDS_ATTENTION"
                else "LOOKS_GOOD" end)
' > "$OUT/ai-review.json"

jq -r '.summary, "", (.findings[] | "[\(.severity | ascii_upcase)] \(.file):\(.line) -- \(.title)\n    \(.body)"), "", "Verdict: \(.verdict)"' "$OUT/ai-review.json"
