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

variable "cluster_name" {
  type = string
}

variable "node_pool_name" {
  type    = string
  default = "general"
}

variable "machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "disk_size_gb" {
  type    = number
  default = 100
}

variable "initial_node_count" {
  type    = number
  default = 1
}

variable "min_node_count" {
  type    = number
  default = 1
}

variable "max_node_count" {
  type    = number
  default = 5
}

variable "service_account_email" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "taints" {
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}
