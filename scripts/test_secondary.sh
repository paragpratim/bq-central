#!/usr/bin/env bash
set -euo pipefail

if (( $# != 0 )); then
  echo "Usage: bash scripts/test_secondary.sh" >&2
  exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$root/scripts/test_primary.sh"
run_dr_tests europe-west1 test_parquet_1_2 test_parquet_2_2
