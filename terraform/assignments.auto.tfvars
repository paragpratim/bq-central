bq_reservation = {
  name                = "central-dr"
  location            = "europe-west4" # Netherlands (primary)
  secondary_location  = "europe-west1" # Belgium (secondary)
  autoscale_max_slots = 20
}

# One entry per project that runs jobs on the central reservation.
bq_consumers = {
  dataflow_test = {
    project_id            = "dataflow-test-290e"
    service_account_email = "dataflow@dataflow-test-290e.iam.gserviceaccount.com"
    datasets = [
      { project_id = "gcp-data-management-e0e9", dataset_id = "raw_data" }
    ]
  }
}
