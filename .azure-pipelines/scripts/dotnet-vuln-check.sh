#!/usr/bin/env bash
# Fail if any given project has a vulnerable NuGet package (direct or transitive).
# `dotnet list package --vulnerable` exits 0 even when it finds some, so grep for
# its report line. Needs a prior restore/build (the assets file).
# Usage: dotnet-vuln-check.sh <project.csproj>...
set -uo pipefail

FAILED=0
for PROJECT in "$@"; do
  OUTPUT=$(dotnet list "$PROJECT" package --vulnerable --include-transitive 2>&1) || { echo "$OUTPUT"; FAILED=1; continue; }
  echo "$OUTPUT"
  if grep -q 'has the following vulnerable packages' <<< "$OUTPUT"; then FAILED=1; fi
done
[ "$FAILED" -eq 0 ] || { echo "##vso[task.logissue type=error]NuGet vulnerability check found vulnerable packages or could not run -- see above."; exit 1; }
