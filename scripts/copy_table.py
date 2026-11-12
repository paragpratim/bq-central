"""Copy a BigQuery table with a query job and an optional reservation."""

import argparse

from google.cloud import bigquery


def identifier(value: str) -> str:
    if not value or any(char in value for char in "`.\\") or any(
        ord(char) < 32 or ord(char) == 127 for char in value
    ):
        raise argparse.ArgumentTypeError("must be a single BigQuery identifier")
    return value


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--job-project", required=True, help="Job and billing project")
    parser.add_argument(
        "--dataset-project", required=True, type=identifier, help="Dataset project"
    )
    parser.add_argument("--dataset", required=True, type=identifier, help="Dataset ID")
    parser.add_argument("--source-table", required=True, type=identifier, help="Source table ID")
    parser.add_argument(
        "--destination-table", required=True, type=identifier, help="Destination table ID"
    )
    parser.add_argument(
        "--reservation",
        help="Full reservation name: projects/PROJECT/locations/LOCATION/reservations/NAME",
    )
    parser.add_argument(
        "--location",
        required=True,
        help="Dataset and job location",
    )
    args = parser.parse_args()
    source = f"{args.dataset_project}.{args.dataset}.{args.source_table}"
    destination = f"{args.dataset_project}.{args.dataset}.{args.destination_table}"

    config = bigquery.QueryJobConfig(
        destination=destination,
        create_disposition=bigquery.CreateDisposition.CREATE_IF_NEEDED,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
    )
    if args.reservation:
        config.reservation = args.reservation

    client = bigquery.Client(project=args.job_project)
    job = client.query(
        f"SELECT * FROM `{source}`", job_config=config, location=args.location
    )
    print(f"Submitted job {job.project}:{job.location}.{job.job_id}", flush=True)
    job.result()
    print(f"Copied rows from {source} to {destination}")


if __name__ == "__main__":
    main()
