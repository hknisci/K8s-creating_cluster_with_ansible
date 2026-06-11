resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_secret_manager_secret" "secrets" {
  for_each  = var.secrets
  project   = var.project_id
  secret_id = each.key

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_service_account" "eso_sa" {
  project      = var.project_id
  account_id   = "${var.environment}-eso-sa"
  display_name = "External Secrets Operator SA - ${var.environment}"
}

resource "google_project_iam_member" "eso_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.eso_sa.email}"
}

resource "google_service_account_iam_member" "eso_workload_identity" {
  service_account_id = google_service_account.eso_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.eso_namespace}/external-secrets]"
}
