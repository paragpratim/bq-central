# Dataflow streaming write test

This Java Beam job generates random integers continuously and writes them to a
BigQuery table using a selectable method: `STORAGE_WRITE_API`,
`STREAMING_INSERTS`, or `FILE_LOADS`. It uses the workload service account and
does **not** explicitly select a BigQuery reservation. The job can keep running
and retrying an error instead of reaching a terminal failed state. This is a
test, not a production pipeline or a reliable dead-letter strategy.

The destination table is created if needed with this schema:

| Column | Type | Mode |
|---|---|---|
| `generated_at` | `TIMESTAMP` | `REQUIRED` |
| `random_value` | `INTEGER` | `REQUIRED` |

Use an isolated test table in the DR-attached dataset. If the table already
exists, it must have a compatible schema; successful writes append data.
Confirm the dataset and reservation exist and that the job region is the
**current dataset primary**; otherwise, a missing resource or read-only replica
can produce an unrelated failure. Table creation can itself fail due to
permissions or DR restrictions, before writes are attempted.

## Prerequisites

- Java 17 and Maven locally, Application Default Credentials, and the Dataflow
  and BigQuery APIs enabled in the relevant projects.
- The submitting identity needs permission to create Dataflow jobs, access the
  staging bucket, and act as the worker service account.
- The existing staging bucket `gs://dataflow-staging-dataflow-test-290e` and
  an accessible subnetwork with Private Google Access. Verify these resources
  before running; workers use private IPs.
- The worker service account needs Dataflow Worker, read/write access to the
  staging bucket, and BigQuery access to create the table and write to it. For
  `FILE_LOADS`, it also needs permission to create BigQuery jobs in the job
  project and access to the temporary GCS objects.
  See [Dataflow security and permissions](https://cloud.google.com/dataflow/docs/concepts/security-and-permissions).

Run local tests from the repository root:

```sh
mvn -f dataflow/pom.xml test
```

The Beam dependencies use the shared `beam.version` property in `pom.xml`.
Maven checks the local repository (`~/.m2/repository`) automatically, so to use
a locally published Beam build, pass its exact published version:

```sh
mvn -f dataflow/pom.xml -Dbeam.version=LOCAL_BEAM_VERSION test
```

Find the installed version under
`~/.m2/repository/org/apache/beam/beam-sdks-java-io-google-cloud-platform/`.
The version must match the one published by your Beam checkout. All Beam
dependencies in this project use that same version. The GCP IO artifact also
depends on other Beam modules, so publishing only GCP IO is not enough for a
local snapshot: publish its Beam dependency modules locally at that same version
as well.

## Submit from your machine

The [submission script](submit.sh) builds the job and submits it to
`dataflow-test-290e` as
`dataflow@dataflow-test-290e.iam.gserviceaccount.com`. It defaults to
`europe-west4`, `gcp-data-management-e0e9:raw_data_dr.df_test`, and subnet
`regions/europe-west4/subnetworks/dataflow-subnet-dataflow-test-290e-europewest4`.
Confirm that `europe-west4` is the current primary.

Select a method for each submission:

```sh
WRITE_METHOD=STORAGE_WRITE_API bash dataflow/submit.sh
WRITE_METHOD=STREAMING_INSERTS bash dataflow/submit.sh
WRITE_METHOD=FILE_LOADS bash dataflow/submit.sh
```

`bash dataflow/submit.sh` defaults to `STORAGE_WRITE_API`. Each command submits
a separate unbounded, billable job; cancel each job when finished. To distinguish
results, optionally set `OUTPUT_TABLE` to a different table for each run.

To submit using your locally published Beam build, set its exact published
version:

```sh
BEAM_VERSION=LOCAL_BEAM_VERSION bash dataflow/submit.sh
```

Set `REGION`, `OUTPUT_TABLE`, `STAGING_BUCKET`, or `SUBNETWORK` to override
those defaults. Use an accessible subnet in the job region with Private Google
Access. For example:

```sh
SUBNETWORK=regions/europe-west4/subnetworks/SUBNETWORK_NAME bash dataflow/submit.sh
```

The script uses private IPs, starts with one worker and caps it at one worker.
It submits billable resources using local ADC and stages code and dependencies
in the bucket. A successful submission is not evidence that the write test
passed.

## Methods and results

- `STORAGE_WRITE_API`: exactly-once Storage Write API with one stream and a
  five-second triggering frequency.
- `STREAMING_INSERTS`: BigQuery streaming inserts, with failed rows surfaced
  without Beam's insert retry policy.
- `FILE_LOADS`: uses one fixed file shard, stages files in the configured GCS
  temp location and submits BigQuery load jobs every minute when data is
  available. Fixed sharding avoids the Streaming Engine requirement for
  runner-determined sharding. Load jobs count against BigQuery quotas and may
  incur costs. BigQuery managed DR requires a `PIPELINE` reservation assignment
  for load jobs; this script does not explicitly select a reservation. See
  [load tests](../scripts/README.md).

Use Dataflow logs and the `Write to BigQuery` stage to distinguish BigQuery
rejection from setup, IAM, networking, or missing-table failures. The Storage
Write API and streaming-insert methods surface row-level errors through worker
exceptions; file-load failures are reported through the pipeline and load-job
errors instead. Other failures can occur before the row-level error outputs.
Dataflow may retry bundles repeatedly.

This is an unbounded job and can continue accruing charges even on errors.
Cancel it in the Dataflow console when finished. Do not infer success or failure
from job state alone: inspect worker logs and, if writes are accepted, the test
table. A job being in the running state alone does not establish that writes
succeeded.
