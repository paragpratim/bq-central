import sys
import unittest
from unittest.mock import patch

import copy_table

ARGS = [
    "--job-project", "job-project",
    "--dataset-project", "dataset-project",
    "--dataset", "test_dataset",
    "--source-table", "source_table",
    "--destination-table", "destination_table",
    "--location", "test-region",
]


class CopyTableTest(unittest.TestCase):
    @patch("copy_table.bigquery.Client")
    def test_explicit_and_unset_reservation(self, client):
        reservation = "example-reservation"

        for args, expected in [([], None), (["--reservation", reservation], reservation)]:
            with self.subTest(reservation=expected), patch.object(sys, "argv", ["copy_table.py", *ARGS, *args]):
                client.reset_mock()
                copy_table.main()
                client.assert_called_once_with(project="job-project")
                call = client.return_value.query.call_args
                self.assertEqual(call.args, ("SELECT * FROM `dataset-project.test_dataset.source_table`",))
                self.assertEqual(call.kwargs["location"], "test-region")
                config = call.kwargs["job_config"].to_api_repr()
                self.assertEqual(config.get("reservation"), expected)
                self.assertEqual(config["query"]["createDisposition"], "CREATE_IF_NEEDED")
                self.assertEqual(config["query"]["writeDisposition"], "WRITE_APPEND")
                self.assertEqual(
                    config["query"]["destinationTable"],
                    {"projectId": "dataset-project", "datasetId": "test_dataset", "tableId": "destination_table"},
                )
                client.return_value.query.return_value.result.assert_called_once()

    @patch("copy_table.bigquery.Client")
    def test_query_failure_is_propagated(self, client):
        client.return_value.query.return_value.result.side_effect = RuntimeError("query failed")
        with patch.object(sys, "argv", ["copy_table.py", *ARGS]):
            with self.assertRaisesRegex(RuntimeError, "query failed"):
                copy_table.main()

    @patch("copy_table.bigquery.Client")
    def test_explicit_table_names(self, client):
        with patch.object(sys, "argv", [
            "copy_table.py", *ARGS, "--source-table", "another_source_2",
            "--destination-table", "another_destination_2",
        ]):
            copy_table.main()
        call = client.return_value.query.call_args
        self.assertEqual(call.args[0], "SELECT * FROM `dataset-project.test_dataset.another_source_2`")
        self.assertEqual(call.kwargs["job_config"].destination.table_id, "another_destination_2")

    @patch("copy_table.bigquery.Client")
    def test_unsafe_identifier_is_rejected(self, client):
        with patch.object(sys, "argv", ["copy_table.py", *ARGS, "--source-table", "table` UNION SELECT 1 --"]), self.assertRaises(SystemExit):
            copy_table.main()
        client.assert_not_called()


if __name__ == "__main__":
    unittest.main()
