resource "google_project_service" "artifactregistry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "app" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = "Docker registry for ${var.environment} environment"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-tagged-releases"
    action = "KEEP"
    condition {
      tag_state    = "TAGGED"
      tag_prefixes = ["v", "release-"]
    }
  }

  cleanup_policies {
    id     = "delete-untagged-after-30-days"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "2592000s"
    }
  }

  depends_on = [google_project_service.artifactregistry]
}

resource "google_artifact_registry_repository_iam_member" "ci_writer" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.app.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${var.ci_service_account_email}"
}
