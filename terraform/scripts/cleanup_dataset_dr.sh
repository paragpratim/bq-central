#!/usr/bin/env bash
set -euo pipefail

: "${ADMIN_PROJECT:?ADMIN_PROJECT is required}"
if [[ ! "$ADMIN_PROJECT" =~ ^[a-z][a-z0-9-]*$ ]]; then
  echo "Invalid administration project ID" >&2
  exit 1
fi

state="$(terraform show -json)"
datasets="$(jq -er '
  [.values.root_module.resources[]? |
   select(.mode == "managed" and .type == "google_bigquery_dataset" and .name == "dr") |
   [.values.project, .values.dataset_id, .values.location] |
   if all(.[]; type == "string" and length > 0) then @tsv
   else error("Dataset state is missing project, ID, or location") end] | join("\n")
' <<<"$state" || {
  echo "Dataset state is invalid." >&2
  exit 1
})"
if [[ -z "$datasets" ]]; then
  echo "No managed DR datasets in state."
  exit 0
fi
reservation="$(jq -er '
  [.values.root_module.resources[]? |
   select(.mode == "managed" and .type == "google_bigquery_reservation" and .name == "central") |
   .values] |
  if length == 1 and (.[0].name | type == "string" and length > 0)
  then .[0] else error("Expected one managed central reservation") end
' <<<"$state")"
reservation_name="$(jq -r '.name' <<<"$reservation")"
if [[ ! "$reservation_name" =~ ^[a-z0-9-]+$ ]]; then
  echo "Invalid reservation name in state" >&2
  exit 1
fi
locations="$(jq -er '
  [.location, .primary_location, .secondary_location, .original_primary_location] |
  map(select(type == "string" and length > 0)) | unique | .[]
' <<<"$reservation")"

query() {
  local region="$1"
  shift
  bq --project_id="$ADMIN_PROJECT" --location="$region" --format=json \
    query --use_legacy_sql=false "$@"
}

while IFS=$'\t' read -r project dataset original_location; do
  if [[ ! "$project" =~ ^[a-z][a-z0-9-]*$ ||
        ! "$dataset" =~ ^[a-zA-Z0-9_]+$ ||
        ! "$original_location" =~ ^[a-zA-Z0-9-]+$ ]]; then
    echo "Invalid dataset identifier or location in state" >&2
    exit 1
  fi

  replicas='[]'
  while IFS= read -r region; do
    if [[ ! "$region" =~ ^[a-zA-Z0-9-]+$ ]]; then
      echo "Invalid reservation location in state" >&2
      exit 1
    fi
    result="$(query "$region" --parameter="dataset::${dataset}" \
      "SELECT replica_name, location, replica_primary_assigned, replica_primary_assignment_complete
       FROM \`${project}.region-${region}\`.INFORMATION_SCHEMA.SCHEMATA_REPLICAS
       WHERE schema_name = @dataset")"
    replicas="$(jq -ecn --argjson current "$replicas" --argjson result "$result" \
      'if ($result | type) == "array" then $current + $result | unique
       else error("Unexpected replica query result") end')"
  done <<<"$(printf '%s\n%s\n' "$locations" "$original_location" | sort -u)"

  if [[ "$(jq 'length' <<<"$replicas")" -eq 0 ]]; then
    echo "No replicas found for ${project}.${dataset}; Terraform will verify deletion."
    continue
  fi
  if ! jq -e '
    all(.[]; (.replica_name | type == "string") and
      (.location | type == "string") and
      ((.replica_primary_assigned | tostring) == "true" or (.replica_primary_assigned | tostring) == "false") and
      ((.replica_primary_assignment_complete | tostring) == "true" or (.replica_primary_assignment_complete | tostring) == "false")) and
    ([.[] | select((.replica_primary_assigned | tostring) != (.replica_primary_assignment_complete | tostring))] | length == 0) and
    ([.[] | select((.replica_primary_assigned | tostring) == "true")] | length == 1) and
    (group_by(.replica_name) | all(.[]; length == 1))
  ' <<<"$replicas" >/dev/null; then
    echo "Replica state for ${project}.${dataset} is incomplete or inconsistent; refusing cleanup." >&2
    exit 1
  fi
  primary="$(jq -r '.[] | select((.replica_primary_assigned | tostring) == "true") | .location' <<<"$replicas")"
  if [[ ! "$primary" =~ ^[a-zA-Z0-9-]+$ ]]; then
    echo "Invalid primary location for ${project}.${dataset}" >&2
    exit 1
  fi

  secondaries="$(jq -r '.[] | select((.replica_primary_assigned | tostring) == "false") | .replica_name' <<<"$replicas")"
  while IFS= read -r replica; do
    [[ -z "$replica" ]] && continue
    if [[ ! "$replica" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo "Invalid secondary replica name for ${project}.${dataset}" >&2
      exit 1
    fi
  done <<<"$secondaries"

  attachment="$(query "$primary" --parameter="dataset::${dataset}" \
    "SELECT option_value FROM \`${project}.region-${primary}\`.INFORMATION_SCHEMA.SCHEMATA_OPTIONS
     WHERE schema_name = @dataset AND option_name = 'failover_reservation'")"
  current="$(jq -er '
    if type != "array" or length > 1 then error("Unexpected attachment result")
    elif length == 0 then ""
    else .[0].option_value | strings | gsub("^\"|\"$"; "") end
  ' <<<"$attachment")"
  if [[ -n "$current" && "$current" != "$ADMIN_PROJECT.$reservation_name" ]]; then
    echo "${project}.${dataset} is attached to a different reservation; refusing cleanup." >&2
    exit 1
  fi
  if [[ -n "$current" ]]; then
    echo "Detaching ${project}.${dataset} from ${current}"
    query "$primary" "ALTER SCHEMA \`${project}.${dataset}\` SET OPTIONS (failover_reservation = NULL)"
  fi

  while IFS= read -r replica; do
    [[ -z "$replica" ]] && continue
    echo "Removing secondary replica ${replica} from ${project}.${dataset}"
    query "$primary" "ALTER SCHEMA \`${project}.${dataset}\` DROP REPLICA IF EXISTS \`${replica}\`"
  done <<<"$secondaries"
done <<<"$datasets"
