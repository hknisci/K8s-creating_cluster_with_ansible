output "bucket_name" {
  value = google_storage_bucket.static_assets.name
}

output "backend_bucket_name" {
  value = google_compute_backend_bucket.static_assets.name
}
