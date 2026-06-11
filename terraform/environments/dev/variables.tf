variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west1"
}

variable "subnet_cidr" {
  type    = string
  default = "10.10.0.0/20"
}

variable "pods_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "services_cidr" {
  type    = string
  default = "10.30.0.0/20"
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "ci_service_account_email" {
  description = "Service account used by CI to push images"
  type        = string
}
