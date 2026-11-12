import sys
import unittest
from unittest.mock import patch

import copy_table


class CopyTableTest(unittest.TestCase):
    @patch("copy_table.bigquery.Client")
    def test_explicit_and_unset_reservation(self, client):
        reservation = "projects/central/locations/europe-west4/reservations/central-dr"

        for args, expected in [([], None), (["--reservation", reservation], reservation)]:
            with self.subTest(reservation=expected), patch.object(sys, "argv", ["copy_table.py", *args]):
                client.reset_mock()
                copy_table.main()
                client.assert_called_once_with(project=copy_table.JOB_PROJECT)
                call = client.return_value.query.call_args
                self.assertEqual(call.args, (f"SELECT * FROM `{copy_table.SOURCE}`",))
                self.assertEqual(call.kwargs["location"], "europe-west4")
                config = call.kwargs["job_config"].to_api_repr()
                self.assertEqual(config.get("reservation"), expected)
                self.assertEqual(config["query"]["writeDisposition"], "WRITE_EMPTY")
                self.assertEqual(
                    config["query"]["destinationTable"],
                    {"projectId": "gcp-data-management-e0e9", "datasetId": "raw_data_dr", "tableId": "test_parquet_2"},
                )
                client.return_value.query.return_value.result.assert_called_once()

    @patch("copy_table.bigquery.Client")
    def test_query_failure_is_propagated(self, client):
        client.return_value.query.return_value.result.side_effect = RuntimeError("query failed")
        with patch.object(sys, "argv", ["copy_table.py"]):
            with self.assertRaisesRegex(RuntimeError, "query failed"):
                copy_table.main()


if __name__ == "__main__":
    unittest.main()
