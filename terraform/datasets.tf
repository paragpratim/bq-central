resource "google_bigquery_dataset" "dr" {
  for_each = local.replicated_datasets

  project                    = each.value[0].project_id
  dataset_id                 = each.value[0].dataset_id
  location                   = var.bq_reservation.location
  delete_contents_on_destroy = var.delete_dataset_contents_on_destroy

  lifecycle {
    ignore_changes = [location]
  }
}
