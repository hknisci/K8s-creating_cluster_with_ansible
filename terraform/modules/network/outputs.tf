output "network_id" {
  description = "VPC network ID"
  value       = google_compute_network.vpc.id
}

output "network_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "subnet_id" {
  description = "GKE subnet ID"
  value       = google_compute_subnetwork.gke_subnet.id
}

output "subnet_name" {
  description = "GKE subnet name"
  value       = google_compute_subnetwork.gke_subnet.name
}

output "pods_range_name" {
  description = "Secondary range name for pods"
  value       = "${var.environment}-pods-range"
}

output "services_range_name" {
  description = "Secondary range name for services"
  value       = "${var.environment}-services-range"
}
