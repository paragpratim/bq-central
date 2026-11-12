import sys
import unittest
from unittest.mock import patch

import load_parquet


class LoadParquetTest(unittest.TestCase):
    @patch("load_parquet.bigquery.Client")
    def test_explicit_and_unset_reservation(self, client):
        reservation = "projects/central/locations/europe-west4/reservations/central-dr"

        for args, expected in [([], None), (["--reservation", reservation], reservation)]:
            with self.subTest(reservation=expected), patch.object(sys, "argv", ["load_parquet.py", *args]):
                client.reset_mock()
                load_parquet.main()
                client.assert_called_once_with(project=load_parquet.JOB_PROJECT)
                call = client.return_value.load_table_from_uri.call_args
                self.assertEqual(call.args, (load_parquet.SOURCE_URI, load_parquet.DESTINATION))
                self.assertEqual(call.kwargs["location"], "europe-west4")
                config = call.kwargs["job_config"].to_api_repr()
                self.assertEqual(config.get("reservation"), expected)
                self.assertEqual(config["load"]["sourceFormat"], "PARQUET")
                self.assertEqual(config["load"]["writeDisposition"], "WRITE_EMPTY")
                client.return_value.load_table_from_uri.return_value.result.assert_called_once()

    @patch("load_parquet.bigquery.Client")
    def test_load_failure_is_propagated(self, client):
        client.return_value.load_table_from_uri.return_value.result.side_effect = RuntimeError("load failed")
        with patch.object(sys, "argv", ["load_parquet.py"]):
            with self.assertRaisesRegex(RuntimeError, "load failed"):
                load_parquet.main()


if __name__ == "__main__":
    unittest.main()
