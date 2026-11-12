mock_provider "google" {}

run "dataset_suffix" {
  command = plan

  variables {
    project_id = "central-test"
    region     = "europe-west4"
    bq_consumers = {
      first = {
        project_id            = "jobs-test"
        service_account_email = "first@jobs-test.iam.gserviceaccount.com"
        datasets = [
          { project_id = "data-test", dataset_id = "raw_data" },
          { project_id = "data-test", dataset_id = "already_dr" },
        ]
      }
      second = {
        project_id            = "jobs-test"
        service_account_email = "second@jobs-test.iam.gserviceaccount.com"
        datasets = [
          { project_id = "data-test", dataset_id = "raw_data_dr" },
        ]
      }
    }
  }

  assert {
    condition     = toset(keys(google_bigquery_dataset.dr)) == toset(["data-test.raw_data_dr", "data-test.already_dr"])
    error_message = "Datasets must be suffixed exactly once and deduplicated across consumers."
  }

  assert {
    condition     = google_bigquery_dataset_iam_member.consumer["first|data-test|raw_data_dr"].dataset_id == "raw_data_dr" && google_bigquery_dataset_iam_member.consumer["second|data-test|raw_data_dr"].dataset_id == "raw_data_dr"
    error_message = "Dataset access grants must target the suffixed dataset."
  }

  assert {
    condition     = terraform_data.dataset_dr["data-test.raw_data_dr"].triggers_replace.dataset_id == "raw_data_dr"
    error_message = "DR setup must target the suffixed dataset."
  }
}
