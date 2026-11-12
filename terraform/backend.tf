terraform {
  backend "gcs" {
    bucket = "bq-central-tf-state-56a6"
    prefix = "bq-central/terraform/state"
  }
}
