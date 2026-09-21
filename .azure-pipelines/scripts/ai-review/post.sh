#!/usr/bin/env bash
# Post the AI review to the GitHub PR as one comment, then fail the build if the
# verdict is BLOCKING_ISSUES. A failed post only warns; the gate still applies.
#
# Env in: GITHUB_PAT (repo scope), REVIEW_TITLE (comment heading)
# Kept separate from review.sh on purpose: the step that runs the (prompt-
# injectable) model never sees the GitHub token.
set -euo pipefail

REVIEW="$BUILD_ARTIFACTSTAGINGDIRECTORY/ai-review.json"
if [ ! -f "$REVIEW" ]; then
  echo "No AI review was produced (nothing to review, or AI unavailable) -- nothing to post."
  exit 0
fi

# One markdown comment: verdict, summary, then findings (blockers first, max 20).
BODY=$(jq -n --slurpfile r "$REVIEW" --arg title "$REVIEW_TITLE" '
  $r[0] as $r
  | def tag: {"blocker": "🔴 Blocker", "major": "🟠 Major", "minor": "🟡 Minor"}[.severity];
    "### 🤖 AI Code Review — \($title)\n\n**Verdict: `\($r.verdict)`**\n\n\($r.summary)"
  + ($r.findings | sort_by({"blocker": 0, "major": 1, "minor": 2}[.severity]) | .[:20]
     | map("\n\n#### \(tag) — \(.title)\n`\(.file):\(.line)`\n\n\(.body)") | join(""))
  + (if ($r.findings | length) == 0 then "\n\nNo issues found in this diff." else "" end)
  + "\n\n<sub>Automated review of the PR diff only; a human reviewer still decides.</sub>"
  | {body: .}')

CODE=$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
  -H "Authorization: token $GITHUB_PAT" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$BUILD_REPOSITORY_NAME/issues/$SYSTEM_PULLREQUEST_PULLREQUESTNUMBER/comments" \
  --data "$BODY" || true)
if [ "$CODE" = "201" ]; then
  echo "Posted AI review to PR #$SYSTEM_PULLREQUEST_PULLREQUESTNUMBER."
else
  echo "##vso[task.logissue type=warning]Could not post the AI review (HTTP $CODE) -- see ai-review.json in the build artifacts."
fi

VERDICT=$(jq -r '.verdict' "$REVIEW")
echo "AI review verdict: $VERDICT"
if [ "$VERDICT" = "BLOCKING_ISSUES" ]; then
  echo "##vso[task.logissue type=error]AI review found blocking issues -- see the PR comment or the ai-review.json artifact."
  exit 1
fi
