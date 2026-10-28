#!/usr/bin/env bash
# Post the dev harness report to the GitHub PR as one comment, updated in place on every push
# (found by a hidden marker) so a PR with many pushes still has a single harness comment.
# Informational only: a failed post warns and never fails the build.
#
# Env in: GITHUB_PAT (repo scope)
# Kept separate from the step that runs the (prompt-injectable) model on purpose: that step
# never sees the GitHub token.
set -uo pipefail

REPORT="$BUILD_ARTIFACTSTAGINGDIRECTORY/dev-harness-report.md"
if [ ! -f "$REPORT" ]; then
  echo "No dev harness report was produced (skipped, or the harness did not get as far as writing one) -- nothing to post."
  exit 0
fi

MARKER='<!-- dev-harness-report -->'
API="https://api.github.com/repos/$BUILD_REPOSITORY_NAME"
PR="$SYSTEM_PULLREQUEST_PULLREQUESTNUMBER"

# The report is model output about an untrusted diff: defuse @mentions so it cannot ping anyone,
# and stay under GitHub's 65,536-character comment limit.
BODY=$(jq -n --rawfile r "$REPORT" --arg marker "$MARKER" '
  ($r | gsub("@"; "@​") | .[:60000]) as $report
  | {body: "\($marker)\n### 🧭 Dev harness review\n\n\($report)\n\n<sub>Automated review of the PR diff only; a human reviewer still decides.</sub>"}')

# Update the existing harness comment if there is one, otherwise create it.
EXISTING=$(curl -sS -H "Authorization: token $GITHUB_PAT" -H "Accept: application/vnd.github+json" \
  "$API/issues/$PR/comments?per_page=100" \
  | jq -r --arg marker "$MARKER" '[.[]? | select(.body | contains($marker))] | first | .id // empty' || true)

if [ -n "$EXISTING" ]; then
  METHOD=PATCH; URL="$API/issues/comments/$EXISTING"; OK=200
else
  METHOD=POST; URL="$API/issues/$PR/comments"; OK=201
fi

CODE=$(curl -sS -o /dev/null -w '%{http_code}' -X "$METHOD" \
  -H "Authorization: token $GITHUB_PAT" -H "Accept: application/vnd.github+json" \
  "$URL" --data "$BODY" || true)
if [ "$CODE" = "$OK" ]; then
  echo "Posted the dev harness report to PR #$PR ($METHOD)."
else
  echo "##vso[task.logissue type=warning]Could not post the dev harness report (HTTP $CODE) -- see the dev-harness-report artifact."
fi
