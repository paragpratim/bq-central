"""Submit a BigQuery Parquet load job with an optional reservation."""

import argparse

from google.cloud import bigquery


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--job-project", required=True, help="Job and billing project")
    parser.add_argument("--dataset-project", required=True, help="Destination dataset project")
    parser.add_argument("--dataset", required=True, help="Destination dataset ID")
    parser.add_argument("--table", required=True, help="Destination table ID")
    parser.add_argument("--source-uri", required=True, help="Parquet Cloud Storage URI")
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
    destination = f"{args.dataset_project}.{args.dataset}.{args.table}"

    config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.PARQUET,
        create_disposition=bigquery.CreateDisposition.CREATE_IF_NEEDED,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
    )
    if args.reservation:
        config.reservation = args.reservation

    client = bigquery.Client(project=args.job_project)
    job = client.load_table_from_uri(
        args.source_uri, destination, job_config=config, location=args.location
    )
    print(f"Submitted job {job.project}:{job.location}.{job.job_id}", flush=True)
    job.result()
    print(f"Loaded {job.output_rows} rows into {destination}")


if __name__ == "__main__":
    main()
