#!/usr/bin/env bash
set -euo pipefail

if (( $# != 0 )); then
  echo "Use REGION, OUTPUT_TABLE, STAGING_BUCKET or SUBNETWORK to configure this script." >&2
  exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
region="${REGION:-europe-west4}"
output_table="${OUTPUT_TABLE:-gcp-data-management-e0e9:raw_data_dr.df_test}"
staging_bucket="${STAGING_BUCKET:-gs://dataflow-staging-dataflow-test-290e}"
subnetwork="${SUBNETWORK:-regions/europe-west4/subnetworks/dataflow-subnet-dataflow-test-290e-europewest4}"
job_name="dr-streaming-test-$(date +%Y%m%d-%H%M%S)"

mvn -B -f "$root/pom.xml" package dependency:copy-dependencies -DincludeScope=runtime

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
  "--subnetwork=$subnetwork"
