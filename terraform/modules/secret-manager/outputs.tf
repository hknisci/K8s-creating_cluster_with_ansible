output "eso_service_account_email" {
  description = "Service account email for External Secrets Operator (Workload Identity)"
  value       = google_service_account.eso_sa.email
}

output "secret_ids" {
  description = "Map of created secret resource IDs"
  value       = { for k, v in google_secret_manager_secret.secrets : k => v.id }
}
