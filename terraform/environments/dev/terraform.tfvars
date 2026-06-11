# dev environment tfvars
# Replace PROJECT_ID with your actual GCP project ID
project_id = "YOUR_PROJECT_ID"
region     = "europe-west1"

subnet_cidr   = "10.10.0.0/20"
pods_cidr     = "10.20.0.0/16"
services_cidr = "10.30.0.0/20"

master_authorized_networks = [
  {
    cidr_block   = "0.0.0.0/0"
    display_name = "all-dev-access"
  }
]

ci_service_account_email = "ci-runner@YOUR_PROJECT_ID.iam.gserviceaccount.com"
