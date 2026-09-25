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

OUT="$BUILD_ARTIFACTSTAGINGDIRECTORY"
RG="${SRE_RESOURCE_GROUP:?SRE_RESOURCE_GROUP not set}"

WORKSPACE_ID=$(az monitor log-analytics workspace list -g "$RG" --query "[0].customerId" -o tsv)
if [ -z "$WORKSPACE_ID" ]; then
  echo "##vso[task.logissue type=warning]No Log Analytics workspace found in $RG -- skipping watchdog run."
  echo '{"signals": []}' > "$OUT/watchdog-signals.json"
  exit 0
fi

run_query() {
  local name="$1" kql="$2" rows
  rows=$(az monitor log-analytics query --workspace "$WORKSPACE_ID" --analytics-query "$kql" -o json 2>/dev/null) || rows="[]"
  jq -c --arg name "$name" --argjson rows "${rows:-[]}" '{name: $name, rows: $rows}'
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
  | project AppRoleName, TimeGenerated, FailedPct, score')

EXCEPTION_TREND=$(run_query "exception_count_trend" '
  AppExceptions
  | where TimeGenerated > ago(3h)
  | make-series ExceptionCount = count() on TimeGenerated step 15m by AppRoleName
  | extend (anomalies, score, baseline) = series_decompose_anomalies(ExceptionCount, 1.5)
  | mv-expand TimeGenerated to typeof(datetime), ExceptionCount to typeof(long), anomalies to typeof(double), score to typeof(double)
  | where anomalies != 0
  | project AppRoleName, TimeGenerated, ExceptionCount, score')

jq -n --argjson a "$FAILED_BURST" --argjson b "$EXCEPTION_BURST" --argjson c "$FAILURE_TREND" --argjson d "$EXCEPTION_TREND" \
  '{signals: [$a, $b, $c, $d]}' > "$OUT/watchdog-signals.json"

echo "Watchdog signals collected:"
cat "$OUT/watchdog-signals.json"
