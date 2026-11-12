# BigQuery managed disaster recovery

This repository provisions a central BigQuery reservation and replicated
datasets, and provides scripts to test load and query jobs using that
reservation explicitly.

## Architecture

| Purpose | Project / resource |
|---|---|
| Reservation administration | `bq-central-56a6`, reservation `central-dr` |
| Dataset storage | `gcp-data-management-e0e9.raw_data_dr` |
| Job and billing project | `dataflow-test-290e` |
| Job identity | `dataflow@dataflow-test-290e.iam.gserviceaccount.com` |
| Primary region | `europe-west4` (Netherlands) |
| Secondary region | `europe-west1` (Belgium) |

```text
dataflow-test-290e                bq-central-56a6
  Dataflow service account  ---->  central-dr reservation
        |                           Enterprise Plus
        | reads / writes             primary: europe-west4
        v                           secondary: europe-west1
gcp-data-management-e0e9
  raw_data_dr: europe-west4  --->  replica: europe-west1
                  attached to central-dr
```

The reservation has zero baseline slots and an autoscale maximum of 50 slots.
It is configured to allow idle slot sharing, so the autoscale maximum is not
necessarily a limit on all slots the reservation can use. Storage, replication
and compute can incur charges; a zero baseline does not make DR free.

### How jobs use the reservation

- The Terraform configuration creates no `QUERY` or `PIPELINE` assignment. It
  grants the service account `bigquery.reservations.use` through a custom role
  on the **central project**, not only on `central-dr`.
- To select the reservation, a job sets
  `projects/bq-central-56a6/locations/europe-west4/reservations/central-dr`.
  The job runs in `dataflow-test-290e`; the reservation lives in the central
  project, and the dataset lives in the data-management project.
- Once attached to a failover reservation, a dataset requires an Enterprise
  Plus reservation for writes. Reads can use other capacity models. Attachment
  does not, by itself, require that writers choose *this particular*
  reservation: other eligible Enterprise Plus reservations may also work.
- Jobs that do not explicitly select a reservation follow any applicable
  project, folder or organization assignments. Without an assignment, query
  jobs use on-demand capacity; load jobs normally use the free shared pool.
  Check existing and inherited assignments before assuming this fallback.

Google's [managed DR limitations](https://cloud.google.com/bigquery/docs/managed-disaster-recovery#limitations)
state that load and extract jobs require a `PIPELINE` assignment. The load test
below observed a successful load with an explicit reservation and no assignment
created by this Terraform. This is a result for the tested configuration, not
a general guarantee of supported behavior.

## Terraform setup

Configuration is in [terraform/](terraform/). The
[assignment variables](terraform/assignments.auto.tfvars) list each consumer's
service account and datasets. A dataset ID gets `_dr` appended if it does not
already end with that suffix: `raw_data` becomes `raw_data_dr`. The consumer
project field is recorded as configuration; it does not create a project-level
reservation assignment or a job-user IAM grant.

Terraform:

1. Enables the BigQuery Reservation API and creates the Enterprise Plus
   reservation with the configured primary and secondary regions.
2. Creates each unique dataset in its specified project and grants each listed
   service account its configured dataset role (default:
   `roles/bigquery.dataEditor`).
3. Creates a custom role containing `bigquery.reservations.use` and grants it
   to each consumer service account on the central project.
4. Uses [configure_dataset_dr.sh](terraform/scripts/configure_dataset_dr.sh)
   through a Terraform provisioner to create the secondary replica if needed,
   wait for backfill, attach the dataset, and verify the attachment.

**Prerequisites:** Terraform 1.7 or later, `bq` and `jq` on the machine
running apply, and credentials authorized in both projects. The deployment
identity needs permissions to manage the reservation, IAM role and bindings,
create BigQuery jobs in the central project, and manage datasets and their
access in the data-management project. Enabling APIs can require additional
Service Usage permissions.

Each dataset must be managed by only one Terraform state. Do not manage the
same dataset or its access blocks in both this repository and the
data-management configuration. Existing datasets need a planned ownership
transfer and import. Datasets have `prevent_destroy` enabled and table
contents are not automatically deleted.

The DR provisioner waits up to 30 minutes for backfill. On timeout or failure,
inspect the error and reapply; it checks existing replica and attachment state
before retrying. It runs when its Terraform inputs change, but does **not**
continuously detect external DR changes. Verify DR status after manual changes
or failover.

Earlier versions submitted immutable `google_bigquery_job` resources whose DDL
could fail even though Terraform reported job creation. The failed historical
jobs remain in BigQuery; their creation does not prove DR is configured.

## Verify the DR configuration

In the BigQuery console, set the query location to `europe-west4`:

```sql
SELECT schema_name, replica_name, location, creation_complete,
       failover_reservation_name
FROM `bq-central-56a6.region-europe-west4.INFORMATION_SCHEMA.SCHEMATA_REPLICAS_BY_FAILOVER_RESERVATION`
WHERE catalog_name = 'gcp-data-management-e0e9'
  AND schema_name = 'raw_data_dr';
```

The observed result showed both `europe-west4` and `europe-west1` replicas
with `creation_complete = true` and `failover_reservation_name = central-dr`.
The querying identity needs permission to list failover datasets in the
reservation project.

## Reproduce the load and query tests

### Prerequisites

Use the Dataflow service account through Application Default Credentials (ADC).
Your user needs permission to impersonate it, typically
`roles/iam.serviceAccountTokenCreator` on that service account. Avoid
service-account keys.

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

Both scripts wait for job completion and print its ID. They use `WRITE_EMPTY`
and do not overwrite a non-empty destination. A repeat test against a
populated target can fail for that reason instead of testing reservation
enforcement; use a different test table if needed. The copy script copies
rows—it does not delete the source.

### Test cases and observed results

The following results were observed on 12 November 2026, after confirming that
the dataset was attached and both replicas had completed backfill.

| Test | Reservation specified | Observed result |
|---|---|---|
| Load Parquet into `test_parquet_1` | No | Failed: only Enterprise Plus reservation jobs can write to the failover dataset. Job `347b081f-c833-4863-8005-467d5be7867d`. |
| Load Parquet into `test_parquet_1` | Yes | Succeeded; 5,000 rows loaded. Job `10404093-c85a-42d4-b884-a368114b8a90` reported `bq-central-56a6:europe-west4.central-dr`. |
| Query-copy `test_parquet_1` into `test_parquet_2` | No | Failed with the same failover-dataset write restriction. Job `bdd2f32c-2cd8-4557-b794-898e9287f7ea`. |
| Query-copy `test_parquet_1` into `test_parquet_2` | Yes | Succeeded. Job `087aec88-b5a1-4776-bfad-efa3458460a0` reported `bq-central-56a6:europe-west4.central-dr`. |

The two successful jobs were confirmed as running under the Dataflow service
account. An earlier load succeeded on `default-pipeline` **before** the DR
attachment was fixed; it does not demonstrate behavior on an attached dataset.
Reads, writes to other datasets, extract jobs and an actual failover were not
tested here.

### Run the tests

The [load script](scripts/load_parquet.py) loads
`gs://dataflow-staging-dataflow-test-290e/test_data/*.parquet` into
`gcp-data-management-e0e9.raw_data_dr.test_parquet_1`. Run the negative case
first, then the explicit-reservation case:

```sh
.venv/bin/python scripts/load_parquet.py
.venv/bin/python scripts/load_parquet.py --reservation \
  projects/bq-central-56a6/locations/europe-west4/reservations/central-dr
```

The [query script](scripts/copy_table.py) copies the loaded table into
`test_parquet_2` in the same dataset:

```sh
.venv/bin/python scripts/copy_table.py
.venv/bin/python scripts/copy_table.py --reservation \
  projects/bq-central-56a6/locations/europe-west4/reservations/central-dr
```

The scripts submit jobs in `dataflow-test-290e`, default to `europe-west4`,
and accept `--location` for a different primary region. For a fresh test, the
source Parquet files and the query source table must exist.

To inspect a job, set the console query location to `europe-west4` and replace
`JOB_ID` with the ID printed by the script:

```sql
SELECT job_id, job_type, user_email, state, reservation_id, error_result
FROM `dataflow-test-290e.region-europe-west4.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE job_id = 'JOB_ID';
```

`DONE` means the job finished, not necessarily that it succeeded: inspect
`error_result` too. Job metadata can take a short time to appear, and the
querying identity needs permission to view project jobs.

## Failover

The [manual failover workflow](.github/workflows/bq-failover.yml) is
configured to promote a selected region. It has not been validated by the
tests above. The operator chooses the current secondary region, `SOFT` or
`HARD`, and enters `FAILOVER` to confirm. `SOFT` waits for replication and
requires both regions; `HARD` can lose unreplicated data. Review the
[Google managed DR guidance](https://cloud.google.com/bigquery/docs/managed-disaster-recovery)
and current replication health before use.

After failover, verify the reservation, replicas and dataset access, and
update jobs to use the new primary location and reservation path. Baseline
capacity is zero in this configuration, so autoscaling in the secondary
region depends on available capacity. Terraform ignores location changes on
the reservation and dataset; review the plan and the DR setup inputs before
applying after a failover. Do not assume a Terraform apply alone restores
every access control or reconfigures jobs.
