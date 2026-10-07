#!/usr/bin/env bash
# Queries Log Analytics for the SRE watchdog's four signals: two hard-
# threshold checks (mirror the native scheduled query alerts in
# main.monitor.tf, so the same conditions get an AI-narrated GitHub issue,
# not just an email) and two trend/anomaly checks (a leading indicator ahead
# of either threshold actually breaching).
#
# Env in:  SRE_RESOURCE_GROUP
# Out:     $BUILD_ARTIFACTSTAGINGDIRECTORY/watchdog-signals.json
#
# Runs inside an AzureCLI@2 task (already authenticated via the azure-cloud
# service connection). Read-only: only ever calls `az monitor log-analytics
# query`, nothing that can change a resource.
set -euo pipefail

# The real root cause of the 2026-09-29 hang: az CLI forks a detached
# telemetry-upload subprocess after each command that can inherit this
# script's stdout pipe. Every az call below runs inside a `$(...)` command
# substitution, and bash won't return from that until ALL holders of the
# pipe's write end close it -- including that background child. The `az`
# command itself was finishing fine; the substitution was left waiting on a
# telemetry uploader nobody was watching for. Disabling telemetry stops the
# fork happening in the first place. Confirmed by reproducing locally: the
# workspace-list call left two zombied `bash query.sh` processes at 0% CPU
# with no az/python process anywhere in the tree -- not a slow call, a stuck
# pipe. `timeout`/`-k` below stay in as a second line of defense, not the
# fix itself.
export AZURE_CORE_COLLECT_TELEMETRY=0

OUT="$BUILD_ARTIFACTSTAGINGDIRECTORY"
RG="${SRE_RESOURCE_GROUP:?SRE_RESOURCE_GROUP not set}"

# `timeout N` sends SIGTERM at N; `-k 10` escalates to SIGKILL 10s later if
# the child (az's underlying pip/subprocess tree) doesn't honor it -- a plain
# `timeout 30` was observed NOT bounding a stuck call in practice (2026-09-29
# run: the step's own 3-minute hard timeout had to kill an orphaned `timeout`
# process at cleanup).
run_with_timeout() { timeout -k 10 "$@"; }

# `az monitor log-analytics query` dynamic-installs its `log-analytics`
# extension on first use -- on a fresh hosted agent (every run) that's a
# ~20-25s network + pip install, observed locally, eating most of a 30s
# per-query budget on the FIRST of the four calls below and nothing on the
# rest. Install it explicitly, once, up front, outside that budget, so the
# per-query timeouts only ever have to cover the query itself. The extension
# has no stable release (preview only), hence allow_preview.
echo "Pre-installing the log-analytics CLI extension..."
az config set extension.use_dynamic_install=yes_without_prompt extension.dynamic_install_allow_preview=yes_without_prompt --only-show-errors > /dev/null
run_with_timeout 60 az extension add --name log-analytics --only-show-errors -y > /dev/null 2>&1 || true

echo "Looking up the Log Analytics workspace in $RG..."
WORKSPACE_ID=$(run_with_timeout 20 az monitor log-analytics workspace list -g "$RG" --query "[0].customerId" -o tsv) || WORKSPACE_ID=""
if [ -z "$WORKSPACE_ID" ]; then
  echo "##vso[task.logissue type=warning]No Log Analytics workspace found in $RG (or the call timed out) -- skipping watchdog run."
  echo '{"signals": []}' > "$OUT/watchdog-signals.json"
  exit 0
fi

run_query() {
  local name="$1" kql="$2" rows
  echo "Querying $name..." >&2   # stderr -- this function's stdout is captured by $(...), a stray line here corrupts the JSON
  # 15s cap: with the extension already installed above, a normal query
  # answers in a few seconds -- this only guards against one call stalling
  # and eating the other three signals' share of the step's time budget.
  rows=$(run_with_timeout 15 az monitor log-analytics query --workspace "$WORKSPACE_ID" --analytics-query "$kql" -o json 2>/dev/null) || rows="[]"
  # -n (null input): this filter doesn't read stdin -- without -n, jq waits
  # for an input value to iterate over and, given none, silently produces
  # zero output (exit 0, no error) instead of running the filter once. Pre-
  # existing since #58; never surfaced because the telemetry hang above
  # always killed the script before reaching this code path in a real run.
  jq -n -c --arg name "$name" --argjson rows "${rows:-[]}" '{name: $name, rows: $rows}'
}

FAILED_BURST=$(run_query "failed_request_burst" '
  AppRequests
  | where TimeGenerated > ago(15m) and Success == false
  | summarize Count = count(), Since = min(TimeGenerated) by AppRoleName')

EXCEPTION_BURST=$(run_query "unhandled_exceptions" '
  AppExceptions
  | where TimeGenerated > ago(15m)
  | summarize Count = count(), Since = min(TimeGenerated) by AppRoleName')

FAILURE_TREND=$(run_query "failure_rate_trend" '
  AppRequests
  | where TimeGenerated > ago(3h)
  | make-series FailedPct = 100.0 * countif(Success == false) / count() default=0 on TimeGenerated step 15m by AppRoleName
  | extend (anomalies, score, baseline) = series_decompose_anomalies(FailedPct, 1.5)
  | mv-expand TimeGenerated to typeof(datetime), FailedPct to typeof(double), anomalies to typeof(double), score to typeof(double)
  | where anomalies != 0
  // series_decompose_anomalies needs real history to build a baseline against
  // -- with only a few hours of telemetry (fresh workspace), it flags
  // degenerate points with a 0% failure rate and no real score (isnotnull
  // catches these -- az CLI stringifies the Kusto null as "None", not JSON
  // null, so this check happens before that serialization, not after).
  // Neither is an actual signal worth an AI-narrated GitHub issue.
  | where isnotnull(score) and FailedPct > 0
  | project AppRoleName, TimeGenerated, FailedPct, score')

EXCEPTION_TREND=$(run_query "exception_count_trend" '
  AppExceptions
  | where TimeGenerated > ago(3h)
  | make-series ExceptionCount = count() on TimeGenerated step 15m by AppRoleName
  | extend (anomalies, score, baseline) = series_decompose_anomalies(ExceptionCount, 1.5)
  | mv-expand TimeGenerated to typeof(datetime), ExceptionCount to typeof(long), anomalies to typeof(double), score to typeof(double)
  | where anomalies != 0
  | where isnotnull(score) and ExceptionCount > 0
  | project AppRoleName, TimeGenerated, ExceptionCount, score')

jq -n --argjson a "$FAILED_BURST" --argjson b "$EXCEPTION_BURST" --argjson c "$FAILURE_TREND" --argjson d "$EXCEPTION_TREND" \
  '{signals: [$a, $b, $c, $d]}' > "$OUT/watchdog-signals.json"

echo "Watchdog signals collected:"
cat "$OUT/watchdog-signals.json"
