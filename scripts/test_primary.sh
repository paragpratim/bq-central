#!/usr/bin/env bash
set -euo pipefail

expect_reservation_failure() {
  local output
  if output="$("$@" 2>&1)"; then
    printf '%s\n' "$output"
    echo "Unexpected success without a reservation; rows may have been appended." >&2
    return 1
  fi
  printf '%s\n' "$output"
  if [[ "$output" != *ENTERPRISE_PLUS* ]]; then
    echo "Job failed for an unexpected reason, not the Enterprise Plus restriction." >&2
    return 1
  fi
}

run_dr_tests() {
  local location="$1" source_table="$2" destination_table="$3"
  local root python reservation
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  python="${PYTHON:-$root/.venv/bin/python}"
  reservation="projects/bq-central-56a6/locations/$location/reservations/central-dr"
  local -a common=(
    --job-project dataflow-test-290e
    --dataset-project gcp-data-management-e0e9
    --dataset raw_data_dr
    --location "$location"
  )
  local -a load=(
    "$python" "$root/scripts/load_parquet.py" "${common[@]}"
    --table "$source_table"
    --source-uri 'gs://dataflow-staging-dataflow-test-290e/test_data/*.parquet'
  )
  local -a query=(
    "$python" "$root/scripts/copy_table.py" "${common[@]}"
    --source-table "$source_table"
    --destination-table "$destination_table"
  )

  echo "Load without a reservation (expected failure)"
  expect_reservation_failure "${load[@]}"
  echo "Load with the $location reservation"
  "${load[@]}" --reservation "$reservation"

  echo "Query without a reservation (expected failure)"
  expect_reservation_failure "${query[@]}"
  echo "Query with the $location reservation"
  "${query[@]}" --reservation "$reservation"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if (( $# != 0 )); then
    echo "Usage: bash scripts/test_primary.sh" >&2
    exit 2
  fi
  run_dr_tests europe-west4 test_parquet_1 test_parquet_2
fi
