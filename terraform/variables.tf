variable "project_id" {
  description = "The GCP project ID where resources will be created."
  type        = string
}

variable "region" {
  description = "The GCP region where resources will be created."
  type        = string
}

variable "delete_dataset_contents_on_destroy" {
  description = "Allow dataset destruction to delete all contained tables and other contents."
  type        = bool
  default     = false
}

variable "bq_reservation" {
  description = "Central BigQuery reservation (Enterprise Plus, managed DR, active-passive)."
  type = object({
    name                = optional(string, "central-dr")
    location            = optional(string, "europe-west4") # Netherlands (primary)
    secondary_location  = optional(string, "europe-west1") # Belgium (secondary)
    autoscale_max_slots = optional(number, 50)
  })
  default = {}

  validation {
    condition     = var.bq_reservation.autoscale_max_slots >= 0 && var.bq_reservation.autoscale_max_slots <= 50
    error_message = "autoscale_max_slots must be between 0 and 50."
  }
}

variable "bq_consumers" {
  description = "Map of consumers, their existing service accounts, and datasets to create and grant access to. Dataset IDs receive a _dr suffix if not already present."
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
