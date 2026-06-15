project_id = "YOUR_PROJECT_ID"
region     = "europe-west1"

subnet_cidr   = "10.11.0.0/20"
pods_cidr     = "10.21.0.0/16"
services_cidr = "10.31.0.0/20"

master_authorized_networks = [
  {
    cidr_block   = "10.0.0.0/8"
    display_name = "internal-access"
  }
]

ci_service_account_email = "ci-runner@YOUR_PROJECT_ID.iam.gserviceaccount.com"
