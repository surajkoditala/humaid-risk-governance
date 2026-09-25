#!/usr/bin/env bash
# Turn the raw KQL signal rows into a classified, plain-language verdict per
# condition using Claude. No tool access -- it only ever sees the JSON
# query.sh already collected, never live repo or infra access.
#
# Env in:  CLAUDE_CODE_OAUTH_TOKEN
# Out:     $BUILD_ARTIFACTSTAGINGDIRECTORY/watchdog-verdict.json
#
# Never fails the build: no signals or an AI outage just means no verdict.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$BUILD_ARTIFACTSTAGINGDIRECTORY"
SIGNALS="$OUT/watchdog-signals.json"
warn() { echo "##vso[task.logissue type=warning]$*"; }

if [ ! -s "$SIGNALS" ]; then
  echo "No signals collected -- nothing to summarize."
  exit 0
fi

PROMPT=$(mktemp)
{
  cat "$HERE/rules.md"
  printf '\n--- RAW SIGNALS (Log Analytics query results) ---\n'
  cat "$SIGNALS"
} > "$PROMPT"

if ! npm install -g --silent @anthropic-ai/claude-code; then
  warn "Could not install the Claude Code CLI -- skipping watchdog summary."
  exit 0
fi

set +e
timeout 300 claude -p --output-format json --max-turns 1 \
  --json-schema "$(jq -c . "$HERE/schema.json")" \
  --allowedTools "" \
  < "$PROMPT" > "$OUT/claude-output.json" 2> "$OUT/claude-stderr.log"
STATUS=$?
set -e
rm -f "$PROMPT"

VERDICT=$(jq -c '.structured_output // empty' "$OUT/claude-output.json" 2> /dev/null || true)
if [ "$STATUS" -ne 0 ] || [ -z "$VERDICT" ]; then
  warn "Watchdog summary returned no result (exit $STATUS) -- not notifying this run."
  tail -n 20 "$OUT/claude-stderr.log" || true
  exit 0
fi

echo "$VERDICT" > "$OUT/watchdog-verdict.json"
jq -r '.conditions[] | "[\(.status | ascii_upcase)] \(.name) (\(.app // "n/a")) -- \(.summary)"' "$OUT/watchdog-verdict.json"
