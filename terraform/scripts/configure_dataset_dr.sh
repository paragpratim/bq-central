#!/usr/bin/env bash
set -euo pipefail

for name in ADMIN_PROJECT DATASET_PROJECT DATASET_ID PRIMARY_LOCATION SECONDARY_LOCATION RESERVATION; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
done

if [[ ! "$ADMIN_PROJECT" =~ ^[a-z][a-z0-9-]*$ ||
      ! "$DATASET_PROJECT" =~ ^[a-z][a-z0-9-]*$ ||
      ! "$DATASET_ID" =~ ^[a-zA-Z0-9_]+$ ||
      ! "$PRIMARY_LOCATION" =~ ^[a-z0-9-]+$ ||
      ! "$SECONDARY_LOCATION" =~ ^[a-z0-9-]+$ ||
      ! "$RESERVATION" =~ ^[a-z0-9-]+$ ]]; then
  echo "Invalid project, dataset, location or reservation identifier" >&2
  exit 1
fi

query() {
  bq --project_id="$ADMIN_PROJECT" --location="$PRIMARY_LOCATION" --format=json \
    query --use_legacy_sql=false "$@"
}

replica_status() {
  query --parameter="dataset::${DATASET_ID}" --parameter="location::${SECONDARY_LOCATION}" \
    "SELECT replica_name, creation_complete
     FROM \`${DATASET_PROJECT}.region-${PRIMARY_LOCATION}\`.INFORMATION_SCHEMA.SCHEMATA_REPLICAS
     WHERE schema_name = @dataset AND LOWER(location) = LOWER(@location)"
}

attachment_status() {
  query --parameter="dataset::${DATASET_ID}" \
    "SELECT option_value
     FROM \`${DATASET_PROJECT}.region-${PRIMARY_LOCATION}\`.INFORMATION_SCHEMA.SCHEMATA_OPTIONS
     WHERE schema_name = @dataset AND option_name = 'failover_reservation'"
}

replica=$(replica_status)
jq -e 'type == "array" and length <= 1' <<<"$replica" >/dev/null
if [[ $(jq 'length' <<<"$replica") -eq 0 ]]; then
  echo "Creating replica for ${DATASET_PROJECT}.${DATASET_ID}"
  query "ALTER SCHEMA \`${DATASET_PROJECT}.${DATASET_ID}\`
         ADD REPLICA \`${SECONDARY_LOCATION}\`
         OPTIONS (location = '${SECONDARY_LOCATION}')"
fi

deadline=$(( $(date +%s) + 1800 ))
while :; do
  replica=$(replica_status)
  jq -e 'type == "array" and length <= 1' <<<"$replica" >/dev/null
  ready=$(jq -r 'if length == 0 then "pending" else .[0].creation_complete | tostring end' <<<"$replica")
  if [[ "$ready" == "true" ]]; then
    break
  elif [[ "$ready" != "false" && "$ready" != "pending" ]]; then
    echo "Unexpected replica status: $ready" >&2
    exit 1
  fi
  if (( $(date +%s) >= deadline )); then
    echo "Replica backfill did not complete within 30 minutes; reapply to retry." >&2
    exit 1
  fi
  sleep 10
done

expected="${ADMIN_PROJECT}.${RESERVATION}"
attachment=$(attachment_status)
jq -e 'type == "array" and length <= 1' <<<"$attachment" >/dev/null
current=$(jq -r 'if length == 0 then "" else .[0].option_value | gsub("^\"|\"$"; "") end' <<<"$attachment")
if [[ -n "$current" && "$current" != "$expected" ]]; then
  echo "Dataset is already attached to a different reservation: $current" >&2
  exit 1
fi
if [[ -z "$current" ]]; then
  echo "Attaching ${DATASET_PROJECT}.${DATASET_ID} to $expected"
  query "ALTER SCHEMA \`${DATASET_PROJECT}.${DATASET_ID}\`
         SET OPTIONS (failover_reservation = '${expected}')"
fi

attachment=$(attachment_status)
jq -e --arg expected "$expected" \
  'type == "array" and length == 1 and (.[0].option_value | gsub("^\"|\"$"; "")) == $expected' \
  <<<"$attachment" >/dev/null || {
    echo "Could not verify dataset attachment to $expected" >&2
    exit 1
  }
echo "Verified DR attachment for ${DATASET_PROJECT}.${DATASET_ID}"
