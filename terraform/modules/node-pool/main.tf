resource "google_container_node_pool" "primary" {
  provider = google-beta

  project    = var.project_id
  name       = "${var.environment}-${var.node_pool_name}"
  location   = var.region
  cluster    = var.cluster_name
  node_count = var.initial_node_count

  autoscaling {
    min_node_count  = var.min_node_count
    max_node_count  = var.max_node_count
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
    strategy        = "SURGE"
  }

  node_config {
    machine_type    = var.machine_type
    disk_size_gb    = var.disk_size_gb
    disk_type       = "pd-ssd"
    image_type      = "COS_CONTAINERD"
    service_account = var.service_account_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = merge(var.labels, {
      environment = var.environment
      node_pool   = var.node_pool_name
    })

    dynamic "taint" {
      for_each = var.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}
