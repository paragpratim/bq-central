# bq-central

## DR datasets

Datasets listed in `terraform/assignments.auto.tfvars` are created in their
specified projects in the reservation's primary location. Each dataset must be
given a `_dr` suffix: `raw_data` becomes `raw_data_dr`, and an existing `_dr`
suffix is not duplicated. Each dataset must be managed by only one Terraform
state. Do not also create or manage its access
blocks in the data-management Terraform configuration. Existing datasets need a
carefully planned ownership transfer and import, not a second creation.

Datasets have `prevent_destroy` enabled and their tables are not automatically
deleted. Removing a dataset from the configuration will therefore require an
explicit decision about its lifecycle.

Terraform configures DR using the `bq` CLI and `jq`; both must be available to
the machine running `terraform apply`. The deployment identity needs BigQuery
job creation permissions in the central project and dataset permissions in the
dataset project. The setup checks for an existing replica, creates it if
needed, waits up to 30 minutes for backfill, attaches the dataset and verifies
the attachment. If it times out or fails, inspect the error and reapply: the
setup checks existing state before retrying.

The earlier `google_bigquery_job` resources could report success when their DDL
jobs had failed. Terraform now forgets those job resources without deleting the
historical BigQuery jobs. Review the plan before applying this migration; no
dataset replacement or deletion is intended.

The DR setup runs when its Terraform inputs change; it does not continuously
detect external changes to replication or attachment. Verify DR status before
relying on it, especially after manual changes or a failover.

Changing the configured dataset names also changes Terraform resource addresses.
Review the plan before applying, especially if a dataset is already managed;
`prevent_destroy` will block Terraform from replacing or destroying it.

## Test a Parquet load job

The script loads `gs://dataflow-staging-dataflow-test-290e/test_data/*.parquet`
into `gcp-data-management-e0e9.raw_data_dr.test_parquet_1`, submitting the job
in `dataflow-test-290e`. It waits for completion and reports errors. The
destination uses `WRITE_EMPTY`: a non-empty existing table is not overwritten.

Set up a local environment and authenticate using Application Default
Credentials for the service account granted access by this Terraform:

```sh
python3 -m venv .venv
.venv/bin/pip install -r scripts/requirements.txt
gcloud auth application-default login --impersonate-service-account=dataflow@dataflow-test-290e.iam.gserviceaccount.com
```

The caller needs permission to impersonate that service account. The service
account needs permission to create jobs in `dataflow-test-290e`, edit the
destination dataset, and get and list the source bucket's objects. Confirm the
bucket location is compatible with the dataset's region.

Run without explicitly selecting a reservation:

```sh
.venv/bin/python scripts/load_parquet.py
```

Then test an explicit reservation, replacing the central project ID:

```sh
.venv/bin/python scripts/load_parquet.py --reservation \
  projects/CENTRAL_PROJECT_ID/locations/europe-west4/reservations/central-dr
```

Use `--location europe-west1` and the matching reservation path after failover.
Google's managed DR documentation says load jobs require a `PIPELINE`
assignment; whether explicitly selecting a reservation works without one is
the behavior this experiment is intended to test. If the first load succeeds,
the second will fail on `WRITE_EMPTY` unless the table is empty.