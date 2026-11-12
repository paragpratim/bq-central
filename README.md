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

The replica and attachment resources submit BigQuery jobs; Terraform's resource
creation does not guarantee that the jobs finished successfully or that replica
backfill completed. Check the jobs' final status, replica backfill and dataset
attachment before relying on DR. A failed immutable job already recorded in state
is not automatically retried on a subsequent apply; investigate its status and
plan a safe recovery before retrying.

Changing the configured dataset names also changes Terraform resource addresses.
Review the plan before applying, especially if a dataset is already managed;
`prevent_destroy` will block Terraform from replacing or destroying it.