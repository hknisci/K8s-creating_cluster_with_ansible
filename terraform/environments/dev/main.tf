locals {
  environment = "dev"
  project_id  = var.project_id
  region      = var.region
}

terraform {
  backend "gcs" {
    # Bucket configured via -backend-config or TF_CLI_ARGS_init
    # bucket = "PROJECT_ID-terraform-state"
    prefix = "dev/terraform.tfstate"
  }
}

provider "google" {
  project = local.project_id
  region  = local.region
}

provider "google-beta" {
  project = local.project_id
  region  = local.region
}

module "network" {
  source = "../../modules/network"

  project_id    = local.project_id
  environment   = local.environment
  region        = local.region
  subnet_cidr   = var.subnet_cidr
  pods_cidr     = var.pods_cidr
  services_cidr = var.services_cidr
}

module "gke" {
  source = "../../modules/gke"

  project_id          = local.project_id
  environment         = local.environment
  region              = local.region
  network_name        = module.network.network_name
  subnet_name         = module.network.subnet_name
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
  release_channel     = "RAPID"

  master_authorized_networks = var.master_authorized_networks
}

module "node_pool" {
  source = "../../modules/node-pool"

  project_id            = local.project_id
  environment           = local.environment
  region                = local.region
  cluster_name          = module.gke.cluster_name
  machine_type          = "e2-standard-2"
  disk_size_gb          = 50
  min_node_count        = 1
  max_node_count        = 3
  service_account_email = module.gke.gke_nodes_service_account_email
}

module "registry" {
  source = "../../modules/registry"

  project_id               = local.project_id
  environment              = local.environment
  region                   = local.region
  repository_id            = "nodejs-express-dev"
  ci_service_account_email = var.ci_service_account_email
}

module "secret_manager" {
  source = "../../modules/secret-manager"

  project_id    = local.project_id
  environment   = local.environment
  region        = local.region
  eso_namespace = "external-secrets"
  secrets = {
    "nodejs-express-dev/database-url" = "placeholder"
    "nodejs-express-dev/api-key"      = "placeholder"
  }
}
