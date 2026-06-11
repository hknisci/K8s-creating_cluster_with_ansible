variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "repository_id" {
  type        = string
  description = "Artifact Registry repository ID"
}

variable "ci_service_account_email" {
  type        = string
  description = "Service account email used by CI to push images"
}
