variable "deploy_suffix" {
  description = "Deployment suffix, used to prefix resource names in case of testing multiple deploys at the same time"
  default     = ""
}

variable "service_account_email" {
  description = "Email of service account with proper permissions to pull images from repo etc..."
}

variable "region" {
  description = "Deployment region"
  default     = "europe-west1"
}

variable "zone" {
  description = "Deployment zone"
  default     = "europe-west1-b"
}

variable "network" {
  description = "VPC network for the indexer instance"
}

variable "dns_zone_public" {

}

variable "project" {}

variable "sql_tier" {
  default = "db-custom-1-3840"
}

variable "cli" {
  default     = false
  description = "If true loads a different config and makes indexer db public"
}
