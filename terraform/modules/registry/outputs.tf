output "repository_url" {
  description = "Full URL of the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository_id}"
}

output "repository_id" {
  value = google_artifact_registry_repository.app.repository_id
}
