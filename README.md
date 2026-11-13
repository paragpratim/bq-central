# BigQuery managed disaster recovery

This Terraform setup separates BigQuery reservation management, dataset
storage and workload execution across three projects:

| Project | Purpose |
|---|---|
| `bq-central-56a6` | Hosts the `central-dr` Enterprise Plus reservation. |
| `gcp-data-management-e0e9` | Hosts datasets such as `raw_data_dr`. |
| `dataflow-test-290e` | Runs jobs as the existing `dataflow` service account. |

Terraform creates the reservation and the configured datasets, replicates the
datasets from the initial primary region `europe-west4` (Netherlands) to
`europe-west1` (Belgium), and attaches them to the failover reservation.
After a failover the primary region changes.

## Access and reservation usage

- Terraform grants the workload service account its configured dataset role
  (default `roles/bigquery.dataEditor`) for dataset reads and writes.
- Terraform grants the service account `bigquery.reservations.use` through a
  custom role on the **central project**. This is permission to use eligible
  reservations in that project, not an assignment to a specific reservation.
- No project-wide `QUERY` or `PIPELINE` assignment is created. A job that
  needs this reservation selects it explicitly and runs in the current primary
  location. Other jobs follow their applicable reservation assignments or
  capacity defaults.
- The service account also needs `bigquery.jobs.create` in the execution
  project, and access to any source storage. These permissions are not granted
  by this Terraform setup.

Google's [managed DR limitations](https://cloud.google.com/bigquery/docs/managed-disaster-recovery#limitations)
state that load and extract jobs require a `PIPELINE` assignment. See the
[test results](scripts/README.md#test-cases-and-observed-results) for observed
behavior in this configuration.

## Configuration and operation

Configure the reservation, workload service accounts and dataset list in
[assignments.auto.tfvars](terraform/assignments.auto.tfvars). Dataset IDs
receive an `_dr` suffix if they do not already have one.

Terraform 1.7+, `bq`, `jq` and deployment credentials with the required
cross-project permissions are needed. The DR provisioner waits up to 30 minutes
for replication and verifies attachment, but does not continuously detect DR
changes. Check DR status after manual changes or failover. Datasets must be
managed by only one Terraform state.

**Test cleanup:** This configuration permits Terraform to destroy datasets and
sets `delete_dataset_contents_on_destroy = true`, deleting all contained tables
and data. Apply this setting before running destroy so it is recorded in state;
review the plan and back up any data first. The manual GitHub Actions destroy
requires `DESTROY` confirmation and detaches managed datasets and removes their
secondary replicas before destroying resources. Stop Dataflow jobs first. This
cleanup applies to that workflow, not a local `terraform destroy`. It uses
the current primary and stops on inconsistent replica state or an unexpected
reservation; a failed run may have partially completed and can need inspection
before retrying.

**Production:** Before deployment, set `delete_dataset_contents_on_destroy` to
`false` and add `prevent_destroy = true` to the dataset's lifecycle block in
[datasets.tf](terraform/datasets.tf). Terraform requires `prevent_destroy` to
be a literal, not a variable. The workflow's `env` choice does not currently
select separate configuration or state and does not provide production
protection by itself.

The reservation has zero baseline slots, an autoscale maximum of 50 and idle
slot sharing enabled, so total available slots may exceed 50. Storage,
replication and compute can incur charges.

The [manual failover workflow](.github/workflows/bq-failover.yml) promotes a
selected region; hard failover can lose unreplicated data. Verify the new
primary is ready and update job locations and reservation paths after
failover. See the [scripts README](scripts/README.md) for test prerequisites,
commands and results, and the [Dataflow streaming test](dataflow/README.md)
for a separate streaming-insert experiment.
