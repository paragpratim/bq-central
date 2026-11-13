# Dataflow streaming write test

This Java Beam job generates random integers continuously and writes them to a
BigQuery table with the exactly-once `STORAGE_WRITE_API` method. It uses the
workload service account and does **not** select a BigQuery reservation. This
tests the Storage Write API, not the load or query jobs in
[scripts/README.md](../scripts/README.md).
Those earlier job failures do not prove that Storage Write API writes will fail; record
the actual result and error. The job can keep running and retrying an error
instead of reaching a terminal failed state. This is a test, not a production
pipeline or a reliable dead-letter strategy.

The destination table is created if needed with this schema:

| Column | Type | Mode |
|---|---|---|
| `generated_at` | `TIMESTAMP` | `REQUIRED` |
| `random_value` | `INTEGER` | `REQUIRED` |

Use an isolated test table in the DR-attached dataset. If the table already
exists, it must have a compatible schema; successful inserts append data.
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
  staging bucket, and BigQuery access to create the table and write to it.
  See [Dataflow security and permissions](https://cloud.google.com/dataflow/docs/concepts/security-and-permissions).

Run local tests from the repository root:

```sh
mvn -f dataflow/pom.xml test
```

## Submit from your machine

The [submission script](submit.sh) builds the job and submits it to
`dataflow-test-290e` as
`dataflow@dataflow-test-290e.iam.gserviceaccount.com`. It defaults to
`europe-west4`, `gcp-data-management-e0e9:raw_data_dr.df_test`, and subnet
`regions/europe-west4/subnetworks/dataflow-subnet-dataflow-test-290e-europewest4`.
Confirm that `europe-west4` is the current primary.

```sh
bash dataflow/submit.sh
```

Set `REGION`, `OUTPUT_TABLE`, `STAGING_BUCKET`, or `SUBNETWORK` to override
those defaults. Use an accessible subnet in the job region with Private Google
Access. For example:

```sh
SUBNETWORK=regions/europe-west4/subnetworks/SUBNETWORK_NAME bash dataflow/submit.sh
```

The script uses private IPs, starts with one worker and caps it at one worker.
It submits billable resources using local ADC and stages code and dependencies
in the bucket. A successful submission is not evidence that the insert test
passed.

The test uses the BigQuery Storage Write API, which does not submit a
BigQuery load or query job and does not expose a per-job reservation option.
It uses one write stream with a five-second triggering frequency. Use Dataflow
job logs and the `Write with Storage Write API` and `Surface write errors`
stages to distinguish BigQuery rejection from setup, IAM, networking, or
missing-table failures. Row-level write errors are surfaced through a worker
exception; other errors can occur before they reach that output. Dataflow may
retry bundles repeatedly.

This is an unbounded job and can continue accruing charges even on errors.
Cancel it in the Dataflow console when finished. Do not infer success or failure
from job state alone: inspect worker logs and, if writes are accepted, the test
table. No particular failure has been verified for this pipeline.
