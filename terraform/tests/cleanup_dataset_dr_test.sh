#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -f "$tmp/terraform" "$tmp/bq" "$tmp/state" "$tmp/log" "$tmp/out"; rmdir "$tmp"' EXIT

cat >"$tmp/terraform" <<'EOF'
#!/usr/bin/env bash
cat "$TEST_TMP/state"
EOF
cat >"$tmp/bq" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_TMP/log"
case "$*" in
  *SCHEMATA_REPLICAS*)
    case "$SCENARIO" in
      primary) echo '[{"replica_name":"europe-west4","location":"europe-west4","replica_primary_assigned":"true","replica_primary_assignment_complete":"true"},{"replica_name":"europe-west1","location":"europe-west1","replica_primary_assigned":"false","replica_primary_assignment_complete":"false"}]' ;;
      failover) echo '[{"replica_name":"europe-west4","location":"europe-west4","replica_primary_assigned":"false","replica_primary_assignment_complete":"false"},{"replica_name":"europe-west1","location":"europe-west1","replica_primary_assigned":"true","replica_primary_assignment_complete":"true"}]' ;;
      pending) echo '[{"replica_name":"europe-west1","location":"europe-west1","replica_primary_assigned":"true","replica_primary_assignment_complete":"false"}]' ;;
      empty) echo '[]' ;;
    esac ;;
  *SCHEMATA_OPTIONS*)
    if [[ "${FOREIGN_RESERVATION:-}" == "yes" ]]; then
      echo '[{"option_value":"\"other.reservation\""}]'
    elif [[ "${DETACHED:-}" == "yes" ]]; then
      echo '[]'
    else
      echo '[{"option_value":"\"admin-project.central-dr\""}]'
    fi ;;
  *ALTER*) echo '[]' ;;
  *) echo "Unexpected command: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/terraform" "$tmp/bq"
cat >"$tmp/state" <<'EOF'
{"values":{"root_module":{"resources":[
  {"mode":"managed","type":"google_bigquery_dataset","name":"dr","values":{"project":"data-project","dataset_id":"raw_dr","location":"europe-west4"}},
  {"mode":"managed","type":"google_bigquery_reservation","name":"central","values":{"name":"central-dr","location":"europe-west4","primary_location":"europe-west4","secondary_location":"europe-west1"}}
]}}}
EOF
export PATH="$tmp:$PATH" TEST_TMP="$tmp" ADMIN_PROJECT=admin-project

run() {
  : >"$tmp/log"
  bash "$root/terraform/scripts/cleanup_dataset_dr.sh" >"$tmp/out" 2>&1
}

SCENARIO=primary run
grep -q -- '--location=europe-west4.*SET OPTIONS (failover_reservation = NULL)' "$tmp/log"
grep -q -- '--location=europe-west4.*DROP REPLICA IF EXISTS `europe-west1`' "$tmp/log"

SCENARIO=failover run
grep -q -- '--location=europe-west1.*SET OPTIONS (failover_reservation = NULL)' "$tmp/log"
grep -q -- '--location=europe-west1.*DROP REPLICA IF EXISTS `europe-west4`' "$tmp/log"

SCENARIO=primary DETACHED=yes run
if grep -q 'SET OPTIONS' "$tmp/log"; then exit 1; fi
grep -q 'DROP REPLICA' "$tmp/log"

if SCENARIO=pending run; then echo "Pending primary was accepted" >&2; exit 1; fi
if grep -q 'ALTER SCHEMA' "$tmp/log"; then exit 1; fi

if SCENARIO=primary FOREIGN_RESERVATION=yes run; then echo "Foreign reservation was accepted" >&2; exit 1; fi
if grep -q 'ALTER SCHEMA' "$tmp/log"; then exit 1; fi

SCENARIO=empty run
if grep -q 'ALTER SCHEMA' "$tmp/log"; then exit 1; fi

echo '{"values":{"root_module":{"resources":[]}}}' >"$tmp/state"
SCENARIO=empty run
if [[ -s "$tmp/log" ]]; then echo "Unexpected BigQuery call with no datasets" >&2; exit 1; fi

echo "DR cleanup mock tests passed."
