variable "project_id" {
  description = "The GCP project ID where resources will be created."
  type        = string
}

variable "region" {
  description = "The GCP region where resources will be created."
  type        = string
}

variable "bq_reservation" {
  description = "Central BigQuery reservation (Enterprise Plus, managed DR, active-passive)."
  type = object({
    name                = optional(string, "central-dr")
    location            = optional(string, "europe-west4") # Netherlands (primary)
    secondary_location  = optional(string, "europe-west1") # Belgium (secondary)
    autoscale_max_slots = optional(number, 20)
  })
  default = {}

  validation {
    condition     = var.bq_reservation.autoscale_max_slots >= 0 && var.bq_reservation.autoscale_max_slots <= 20
    error_message = "autoscale_max_slots must be between 0 and 20."
  }
}

variable "bq_consumers" {
  description = "Map of consumers: the project assigned to the reservation, its existing service account, and the datasets (any project) it may access."
  type = map(object({
    project_id            = string
    service_account_email = string
    datasets = list(object({
      project_id = string
      dataset_id = string
      role       = optional(string, "roles/bigquery.dataEditor")
    }))
  }))
  default = {}
}
