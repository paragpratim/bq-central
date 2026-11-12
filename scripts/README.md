# BigQuery DR load and query tests

These scripts test writes to the replicated dataset with and without an
explicit reservation. For the architecture and Terraform setup, see the
[main README](../README.md).

## Prerequisites

Run the commands below from the repository root. Use the Dataflow service
account through Application Default Credentials (ADC). Your user needs permission
to impersonate it, typically `roles/iam.serviceAccountTokenCreator` on that
service account. Avoid service-account keys.

```sh
python3 -m venv .venv
.venv/bin/pip install -r scripts/requirements.txt
gcloud auth application-default login \
  --impersonate-service-account=dataflow@dataflow-test-290e.iam.gserviceaccount.com
```

`GOOGLE_APPLICATION_CREDENTIALS`, if set, takes precedence over the local ADC
file. The Dataflow service account also needs `bigquery.jobs.create` in the
job project, dataset read/write access, and reservation-use access. For the
load test, it needs access to the source bucket, including object listing for
the wildcard. The bucket location must be compatible with the dataset region.

Both Python scripts wait for job completion and print its ID. They use
`CREATE_IF_NEEDED` and `WRITE_APPEND`: a missing table is created, and an
existing table must have a compatible schema. Repeated successful runs append
duplicate rows. The query script appends **all** rows currently in the source,
including rows from earlier runs; it does not delete the source.

## Test cases and observed results

The following results were observed on 12 November 2026, after confirming that
the dataset was attached and both replicas had completed backfill. These
historical tests used `WRITE_EMPTY`, before the scripts were changed to append.

| Test | Reservation specified | Observed result |
|---|---|---|
| Load Parquet into `test_parquet_1` | No | Failed: only Enterprise Plus reservation jobs can write to the failover dataset. Job `347b081f-c833-4863-8005-467d5be7867d`. |
| Load Parquet into `test_parquet_1` | Yes | Succeeded; 5,000 rows loaded. Job `10404093-c85a-42d4-b884-a368114b8a90` reported `bq-central-56a6:europe-west4.central-dr`. |
| Query-copy `test_parquet_1` into `test_parquet_2` | No | Failed with the same failover-dataset write restriction. Job `bdd2f32c-2cd8-4557-b794-898e9287f7ea`. |
| Query-copy `test_parquet_1` into `test_parquet_2` | Yes | Succeeded. Job `087aec88-b5a1-4776-bfad-efa3458460a0` reported `bq-central-56a6:europe-west4.central-dr`. |

The two successful jobs were confirmed as running under the Dataflow service
account. An earlier load succeeded on `default-pipeline` **before** the DR
attachment was fixed; it does not demonstrate behavior on an attached dataset.
Reads, writes to other datasets, extract jobs and failback were not tested
here.

### Results after failover to Belgium

After the dataset's `europe-west1` replica became primary, the same service
account ran the following tests against tables suffixed `_2`. These historical
tests used `WRITE_EMPTY`, before the scripts were changed to append. Job
metadata confirmed the reservation on both successful jobs.

| Test | Reservation specified | Observed result |
|---|---|---|
| Load into `test_parquet_1_2` | No | Failed with the Enterprise Plus write restriction; job used `default-pipeline`. Job `1864a5f4-2613-45ca-9c5c-d23018c17bfd`. |
| Load into `test_parquet_1_2` | Yes | Succeeded; 5,000 rows loaded using `bq-central-56a6:europe-west1.central-dr`. Job `66b6426e-7752-4301-a5e6-8bbe0125196c`. |
| Query-copy into `test_parquet_2_2` | No | Failed with the Enterprise Plus write restriction. Job `8c994d15-23d5-47ed-af0f-c0aa586954a1`. |
| Query-copy into `test_parquet_2_2` | Yes | Succeeded using `bq-central-56a6:europe-west1.central-dr`. Job `1237c0b4-cb84-4269-a69e-d88564eaaab1`. |

Google's [managed DR limitations](https://cloud.google.com/bigquery/docs/managed-disaster-recovery#limitations)
state that load and extract jobs require a `PIPELINE` assignment. These tests
observed successful loads with an explicit reservation and no assignment
created by this Terraform. This is a result for the tested configuration, not
a general guarantee of supported behavior.

## Run the tests

The [primary](test_primary.sh) and [secondary](test_secondary.sh) helpers run
the four test cases above, first without and then with the regional reservation
for each job. Choose the helper matching the **current dataset primary**, not
merely the region originally configured as primary:

```sh
bash scripts/test_primary.sh   # Netherlands, europe-west4
bash scripts/test_secondary.sh # Belgium, europe-west1
```

The Netherlands helper uses `test_parquet_1` and `test_parquet_2`; the Belgium
helper uses `test_parquet_1_2` and `test_parquet_2_2`. Both expect the
no-reservation jobs to fail with the Enterprise Plus restriction and stop on
an unexpected result. If a no-reservation job unexpectedly succeeds, it can
append rows before the helper stops. Ensure the ADC identity is correct and
appending to these tables is acceptable. Set `PYTHON` to use an interpreter
other than `.venv/bin/python`.

The [load script](load_parquet.py) and [query script](copy_table.py) also accept
parameters directly. For example, the successful Belgium cases are:

```sh
.venv/bin/python scripts/load_parquet.py \
  --job-project dataflow-test-290e \
  --dataset-project gcp-data-management-e0e9 --dataset raw_data_dr \
  --table test_parquet_1_2 \
  --source-uri 'gs://dataflow-staging-dataflow-test-290e/test_data/*.parquet' \
  --location europe-west1 \
  --reservation projects/bq-central-56a6/locations/europe-west1/reservations/central-dr

.venv/bin/python scripts/copy_table.py \
  --job-project dataflow-test-290e \
  --dataset-project gcp-data-management-e0e9 --dataset raw_data_dr \
  --source-table test_parquet_1_2 --destination-table test_parquet_2_2 \
  --location europe-west1 \
  --reservation projects/bq-central-56a6/locations/europe-west1/reservations/central-dr
```

Omit `--reservation` for the negative cases. The query's source and destination
are in the specified dataset; supply complete table names, including any
suffixes, directly. The source Parquet files and the query source table must
exist. After a failover, use the new primary region for both `--location` and
the reservation path.

To inspect a Belgium job, set the console query location to `europe-west1` and
replace `JOB_ID` with the ID printed by the script:

```sql
SELECT job_id, job_type, user_email, state, reservation_id, error_result
FROM `dataflow-test-290e.region-europe-west1.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE job_id = 'JOB_ID';
```

`DONE` means the job finished, not necessarily that it succeeded: inspect
`error_result` too. Job metadata can take a short time to appear, and the
querying identity needs permission to view project jobs. Use the matching
regional view and query location for jobs run in another region.
