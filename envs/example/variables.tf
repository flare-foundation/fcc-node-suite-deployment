variable "project" {
  description = "GCP project to deploy into. Must already exist - this example does not create it."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources"
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP zone for zonal resources"
  default     = "europe-west1-b"
}

variable "service_account_email" {
  description = "Email of an existing service account with permission to run Confidential Space VMs, pull the container images, and access Secret Manager/Cloud SQL/GCS in this project."
  type        = string
}

variable "tee_node_docker_image" {
  description = "Docker image for the tee-machine workload"
  type        = string
}

variable "tee_proxy_docker_image" {
  description = "Docker image for tee-proxy"
  type        = string
}

variable "tee_proxy_private_key" {
  description = "Signing private key for tee-proxy (see modules/tee-package/variables.tf and OPEN_QUESTIONS.md)"
  type        = string
  sensitive   = true
}
