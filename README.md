# BigQuery managed disaster recovery

This Terraform setup separates reservation management, data storage, and
workload execution:

| Project | Purpose |
|---|---|
| Central BigQuery admin project | Hosts the Enterprise Plus failover reservation. |
| Data projects | Host the BigQuery datasets attached to the reservation. |
| Execution projects | Run workloads using their existing service accounts. |

Terraform creates the reservation and datasets, configures active-passive
replication between the selected primary and secondary regions, and attaches
the datasets to the reservation. After failover, the secondary becomes primary.

## Access and reservations

Terraform grants execution service accounts access to their configured datasets
and permission to use eligible reservations in the central project. It does
not create project-wide reservation assignments. Jobs that support explicit
reservation selection can select the reservation; other jobs use applicable
assignments or capacity defaults. BigQuery managed DR load and extract jobs
require a `PIPELINE` assignment; see the
[managed DR limitations](https://cloud.google.com/bigquery/docs/managed-disaster-recovery#limitations).
Execution service accounts also need permission to create jobs and access
source storage; this setup does not grant those permissions.

## Configuration and operation

Configure the reservation, execution service accounts, and dataset lists in
[assignments.auto.tfvars](terraform/assignments.auto.tfvars). Dataset IDs receive
an `_dr` suffix if needed. Terraform, `bq`, `jq`, and credentials with the
required cross-project permissions are required.

Use the [failover workflow](.github/workflows/bq-failover.yml) to promote a
region. Verify the new primary and update job locations and reservation paths
after failover. Hard failover can lose unreplicated data.

**Cleanup:** The current test configuration allows datasets and their contents
to be deleted. Review the plan and back up data before destroying resources.
The manual GitHub Actions destroy requires `DESTROY` confirmation and removes
dataset replication before Terraform destroy; local `terraform destroy` does
not perform this cleanup. Stop running workloads first.

**Production:** Disable dataset content deletion and add `prevent_destroy = true`
to the dataset lifecycle in [datasets.tf](terraform/datasets.tf). The workflow's
environment selection does not provide separate configuration or state.

See the [test scripts](scripts/README.md) and
[Dataflow test](dataflow/README.md) for examples and prerequisites.
