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

variable "secrets" {
  description = "Map of secret IDs to create (values are set manually in Secret Manager)"
  type        = map(string)
  default     = {}
}

variable "eso_namespace" {
  description = "Kubernetes namespace where ESO is installed"
  type        = string
  default     = "external-secrets"
}
