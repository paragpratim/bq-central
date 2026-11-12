"""Copy a BigQuery table with a query job and an optional reservation."""

import argparse

from google.cloud import bigquery

JOB_PROJECT = "dataflow-test-290e"
SOURCE = "gcp-data-management-e0e9.raw_data_dr.test_parquet_1"
DESTINATION = "gcp-data-management-e0e9.raw_data_dr.test_parquet_2"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--reservation",
        help="Full reservation name: projects/PROJECT/locations/LOCATION/reservations/NAME",
    )
    parser.add_argument(
        "--location",
        default="europe-west4",
        help="Dataset and job location (default: europe-west4)",
    )
    args = parser.parse_args()

    config = bigquery.QueryJobConfig(
        destination=DESTINATION,
        write_disposition=bigquery.WriteDisposition.WRITE_EMPTY,
    )
    if args.reservation:
        config.reservation = args.reservation

    client = bigquery.Client(project=JOB_PROJECT)
    job = client.query(
        f"SELECT * FROM `{SOURCE}`", job_config=config, location=args.location
    )
    print(f"Submitted job {job.project}:{job.location}.{job.job_id}", flush=True)
    job.result()
    print(f"Copied rows from {SOURCE} to {DESTINATION}")


if __name__ == "__main__":
    main()
