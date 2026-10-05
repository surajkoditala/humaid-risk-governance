#!/usr/bin/env bash
# Open/update/close one pinned GitHub issue per watchdog condition. Issue
# state IS the dedupe store: an already-open issue for a still-active
# condition gets no repeat notification; a condition that clears gets its
# issue closed with a "recovered" comment.
#
# Env in: GITHUB_PAT (repo scope)
# Kept separate from summarize.sh on purpose: the step that reads log/
# exception content (which could contain injected text) never sees this token.
set -euo pipefail

VERDICT="$BUILD_ARTIFACTSTAGINGDIRECTORY/watchdog-verdict.json"
if [ ! -f "$VERDICT" ]; then
  echo "No watchdog verdict -- nothing to post."
  exit 0
fi

REPO="$BUILD_REPOSITORY_NAME"
API="https://api.github.com/repos/$REPO"
RUN_URL="$SYSTEM_COLLECTIONURI$SYSTEM_TEAMPROJECTID/_build/results?buildId=$BUILD_BUILDID"
gh_api() { curl -sS -H "Authorization: token $GITHUB_PAT" -H "Accept: application/vnd.github+json" "$@"; }

title_for() {
  case "$1" in
    failed_request_burst)  echo "[SRE Watchdog] Failed-request burst" ;;
    unhandled_exceptions)  echo "[SRE Watchdog] Unhandled exceptions" ;;
    failure_rate_trend)    echo "[SRE Watchdog] Trending toward a failure-rate breach" ;;
    exception_count_trend) echo "[SRE Watchdog] Trending toward an exception spike" ;;
    *)                      echo "[SRE Watchdog] $1" ;;
  esac
}

OPEN_ISSUES=$(gh_api "$API/issues?state=open&per_page=100")

jq -c '.conditions[]' "$VERDICT" | while read -r COND; do
  NAME=$(jq -r '.name' <<< "$COND")
  STATUS=$(jq -r '.status' <<< "$COND")
  SUMMARY=$(jq -r '.summary' <<< "$COND")
  APP=$(jq -r '.app // "n/a"' <<< "$COND")
  SINCE=$(jq -r '.since // "n/a"' <<< "$COND")
  TITLE=$(title_for "$NAME")

  EXISTING=$(jq -c --arg t "$TITLE" '[.[] | select(.title == $t)][0] // empty' <<< "$OPEN_ISSUES")

  if [ "$STATUS" = "ok" ]; then
    if [ -n "$EXISTING" ]; then
      NUM=$(jq -r '.number' <<< "$EXISTING")
      gh_api -X POST "$API/issues/$NUM/comments" -d "$(jq -n --arg b "Recovered: $SUMMARY" '{body:$b}')" > /dev/null
      gh_api -X PATCH "$API/issues/$NUM" -d '{"state":"closed"}' > /dev/null
      echo "Closed #$NUM ($TITLE) -- recovered."
    fi
    continue
  fi

  if [ -n "$EXISTING" ]; then
    echo "Skipping $TITLE -- already open (no repeat notification)."
    continue
  fi

  BODY=$(jq -n --arg t "$TITLE" --arg app "$APP" --arg since "$SINCE" --arg summary "$SUMMARY" --arg run "$RUN_URL" --arg status "$STATUS" \
    '{title: $t, body: "**Status:** \($status)\n**App:** \($app)\n**Since:** \($since)\n\n\($summary)\n\n[Pipeline run](\($run))", labels: ["sre-watchdog"]}')

  CODE=$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
    -H "Authorization: token $GITHUB_PAT" -H "Accept: application/vnd.github+json" \
    "$API/issues" --data "$BODY" || true)
  if [ "$CODE" = "201" ]; then
    echo "Opened $TITLE."
  else
    echo "##vso[task.logissue type=warning]Could not open $TITLE (HTTP $CODE)."
  fi
done

exit 0
