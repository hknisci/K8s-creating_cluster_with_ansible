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

variable "allowed_origins" {
  type    = list(string)
  default = ["*"]
}
