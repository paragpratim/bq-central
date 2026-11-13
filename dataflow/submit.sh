#!/usr/bin/env bash
set -euo pipefail

if (( $# != 0 )); then
  echo "Use WRITE_METHOD, BEAM_VERSION, REGION, OUTPUT_TABLE, STAGING_BUCKET or SUBNETWORK to configure this script." >&2
  exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
write_method="${WRITE_METHOD:-STORAGE_WRITE_API}"
case "$write_method" in
  STORAGE_WRITE_API) method_name="storage" ;;
  STREAMING_INSERTS) method_name="streaming" ;;
  FILE_LOADS) method_name="file-loads" ;;
  *)
    echo "Invalid WRITE_METHOD: $write_method. Use STORAGE_WRITE_API, STREAMING_INSERTS or FILE_LOADS." >&2
    exit 2
    ;;
esac
region="${REGION:-europe-west4}"
output_table="${OUTPUT_TABLE:-gcp-data-management-e0e9:raw_data_dr.df_test}"
staging_bucket="${STAGING_BUCKET:-gs://dataflow-staging-dataflow-test-290e}"
subnetwork="${SUBNETWORK:-regions/europe-west4/subnetworks/dataflow-subnet-dataflow-test-290e-europewest4}"
job_name="dr-${method_name}-test-$(date +%Y%m%d-%H%M%S)"

maven_args=(-B -f "$root/pom.xml")
if [[ -n "${BEAM_VERSION:-}" ]]; then
  maven_args+=("-Dbeam.version=$BEAM_VERSION")
fi
mvn "${maven_args[@]}" package dependency:copy-dependencies -DincludeScope=runtime

exec java -cp "$root/target/dr-streaming-test-1.0.jar:$root/target/dependency/*" \
  com.example.StreamingDrTest \
  --runner=DataflowRunner \
  --project=dataflow-test-290e \
  "--region=$region" \
  "--jobName=$job_name" \
  --serviceAccount=dataflow@dataflow-test-290e.iam.gserviceaccount.com \
  "--stagingLocation=$staging_bucket/dataflow/staging" \
  "--tempLocation=$staging_bucket/dataflow/temp" \
  --usePublicIps=false \
  --numWorkers=1 \
  --maxNumWorkers=1 \
  "--outputTable=$output_table" \
  "--writeMethod=$write_method" \
  "--subnetwork=$subnetwork"
