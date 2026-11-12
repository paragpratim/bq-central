import sys
import unittest
from unittest.mock import patch

import load_parquet

ARGS = [
    "--job-project", "job-project",
    "--dataset-project", "dataset-project",
    "--dataset", "test_dataset",
    "--table", "source_table",
    "--source-uri", "gs://bucket/input/*.parquet",
    "--location", "test-region",
]


class LoadParquetTest(unittest.TestCase):
    @patch("load_parquet.bigquery.Client")
    def test_explicit_and_unset_reservation(self, client):
        reservation = "example-reservation"

        for args, expected in [([], None), (["--reservation", reservation], reservation)]:
            with self.subTest(reservation=expected), patch.object(sys, "argv", ["load_parquet.py", *ARGS, *args]):
                client.reset_mock()
                load_parquet.main()
                client.assert_called_once_with(project="job-project")
                call = client.return_value.load_table_from_uri.call_args
                self.assertEqual(call.args, ("gs://bucket/input/*.parquet", "dataset-project.test_dataset.source_table"))
                self.assertEqual(call.kwargs["location"], "test-region")
                config = call.kwargs["job_config"].to_api_repr()
                self.assertEqual(config.get("reservation"), expected)
                self.assertEqual(config["load"]["sourceFormat"], "PARQUET")
                self.assertEqual(config["load"]["createDisposition"], "CREATE_IF_NEEDED")
                self.assertEqual(config["load"]["writeDisposition"], "WRITE_APPEND")
                client.return_value.load_table_from_uri.return_value.result.assert_called_once()

    @patch("load_parquet.bigquery.Client")
    def test_load_failure_is_propagated(self, client):
        client.return_value.load_table_from_uri.return_value.result.side_effect = RuntimeError("load failed")
        with patch.object(sys, "argv", ["load_parquet.py", *ARGS]):
            with self.assertRaisesRegex(RuntimeError, "load failed"):
                load_parquet.main()

    @patch("load_parquet.bigquery.Client")
    def test_explicit_table_name(self, client):
        with patch.object(sys, "argv", ["load_parquet.py", *ARGS, "--table", "another_table_2"]):
            load_parquet.main()
        call = client.return_value.load_table_from_uri.call_args
        self.assertEqual(call.args[1], "dataset-project.test_dataset.another_table_2")


if __name__ == "__main__":
    unittest.main()
