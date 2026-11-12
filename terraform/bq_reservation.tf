locals {
  # One IAM binding per consumer / dataset
  dataset_grants = merge([
    for ck, c in var.bq_consumers : {
      for d in c.datasets :
      "${ck}|${d.project_id}|${trimsuffix(d.dataset_id, "_dr")}_dr" => {
        member     = "serviceAccount:${c.service_account_email}"
        project_id = d.project_id
        dataset_id = "${trimsuffix(d.dataset_id, "_dr")}_dr"
        role       = d.role
      }
    }
  ]...)

  # Datasets that need a DR replica (unique across consumers)
  replicated_datasets = {
    for g in values(local.dataset_grants) :
    "${g.project_id}.${g.dataset_id}" => g...
  }
}

resource "google_project_service" "bigquery_reservation" {
  project            = var.project_id
  service            = "bigqueryreservation.googleapis.com"
  disable_on_destroy = false
}

# Enterprise Plus is required for managed DR (secondary_location).
# Baseline 0 + autoscale means slots are only billed while queries use them.
resource "google_bigquery_reservation" "central" {
  project            = var.project_id
  name               = var.bq_reservation.name
  location           = var.bq_reservation.location
  secondary_location = var.bq_reservation.secondary_location
  edition            = "ENTERPRISE_PLUS"
  slot_capacity      = 0
  ignore_idle_slots  = false

  autoscale {
    max_slots = var.bq_reservation.autoscale_max_slots
  }

  depends_on = [google_project_service.bigquery_reservation]

  lifecycle {
    # After a failover the primary/secondary roles swap; don't revert them.
    ignore_changes = [location, secondary_location]
  }
}

# No assignments on purpose: jobs (queries and loads) use the reservation only
# when they set it explicitly, so there is no unintended slot usage.
resource "google_project_iam_custom_role" "reservation_user" {
  project     = var.project_id
  role_id     = "bqReservationUser"
  title       = "BigQuery Reservation User"
  description = "Lets a principal pick a reservation for its own jobs."
  permissions = ["bigquery.reservations.use"]
}

resource "google_project_iam_member" "reservation_user" {
  for_each = var.bq_consumers

  project = var.project_id
  role    = google_project_iam_custom_role.reservation_user.id
  member  = "serviceAccount:${each.value.service_account_email}"
}

resource "google_bigquery_dataset_iam_member" "consumer" {
  for_each = local.dataset_grants

  project    = google_bigquery_dataset.dr["${each.value.project_id}.${each.value.dataset_id}"].project
  dataset_id = google_bigquery_dataset.dr["${each.value.project_id}.${each.value.dataset_id}"].dataset_id
  role       = each.value.role
  member     = each.value.member
}

resource "terraform_data" "dataset_dr" {
  for_each = google_bigquery_dataset.dr

  triggers_replace = {
    admin_project      = var.project_id
    dataset_project    = each.value.project
    dataset_id         = each.value.dataset_id
    primary_location   = var.bq_reservation.location
    secondary_location = var.bq_reservation.secondary_location
    reservation        = google_bigquery_reservation.central.name
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/scripts/configure_dataset_dr.sh\""
    environment = {
      ADMIN_PROJECT      = self.triggers_replace.admin_project
      DATASET_PROJECT    = self.triggers_replace.dataset_project
      DATASET_ID         = self.triggers_replace.dataset_id
      PRIMARY_LOCATION   = self.triggers_replace.primary_location
      SECONDARY_LOCATION = self.triggers_replace.secondary_location
      RESERVATION        = self.triggers_replace.reservation
    }
  }

  depends_on = [google_bigquery_reservation.central]
}
