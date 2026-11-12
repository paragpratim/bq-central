output "project_id" {
  description = "The GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "The GCP region"
  value       = var.region
}

output "bq_reservation_name" {
  description = "Fully qualified name of the central BigQuery reservation"
  value       = google_bigquery_reservation.central.id
}

output "bq_reservation_users" {
  description = "Service accounts allowed to select the reservation on their jobs"
  value       = [for m in google_project_iam_member.reservation_user : m.member]
}
