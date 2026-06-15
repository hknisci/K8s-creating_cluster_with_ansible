variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "subnet_cidr" {
  type    = string
  default = "10.12.0.0/20"
}

variable "pods_cidr" {
  type    = string
  default = "10.22.0.0/16"
}

variable "services_cidr" {
  type    = string
  default = "10.32.0.0/20"
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "ci_service_account_email" {
  type = string
}

variable "allowed_origins" {
  type    = list(string)
  default = ["https://app.prod.example.com"]
}
