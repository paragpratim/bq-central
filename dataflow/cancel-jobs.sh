#!/usr/bin/env bash
set -euo pipefail

if (( $# != 0 )); then
  echo "This script takes no arguments and targets dataflow-test-290e." >&2
  exit 2
fi

project="dataflow-test-290e"
echo "Listing active Dataflow jobs in all available regions of $project..."
jobs="$(gcloud --quiet --billing-project="$project" dataflow jobs list \
  --project="$project" --status=active --limit=unlimited \
  --format='value(id,location,name,state)')"

if [[ -z "$jobs" ]]; then
  echo "No active jobs found. Regional outages may hide jobs."
  exit 0
fi

printf 'Job ID\tRegion\tName\tState\n%s\n' "$jobs"
echo "WARNING: This will cancel ALL listed jobs immediately, including unrelated jobs."
echo "In-flight data may be lost. Regional outages may hide jobs."
printf 'Type %s to confirm: ' "$project"
if ! IFS= read -r confirmation || [[ "$confirmation" != "$project" ]]; then
  echo "Cancelled; no jobs were stopped."
  exit 1
fi

failed=0
while IFS=$'\t' read -r id region name state; do
  if [[ -z "$id" || -z "$region" ]]; then
    echo "Missing job ID or region in list output; refusing to cancel: $id $region" >&2
    failed=1
    continue
  fi
  echo "Requesting cancellation of $id ($name) in $region..."
  if ! gcloud --quiet --billing-project="$project" dataflow jobs cancel "$id" \
      --project="$project" --region="$region"; then
    echo "Failed to request cancellation of $id in $region." >&2
    failed=1
  fi
done <<< "$jobs"

if (( failed )); then
  echo "Some cancellation requests failed; check the errors above." >&2
  exit 1
fi
echo "Cancellation requested for all listed jobs. Check Dataflow for final states."
