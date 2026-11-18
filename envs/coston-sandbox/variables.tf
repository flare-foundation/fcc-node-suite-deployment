variable "project" {
  description = "GCP project to deploy into"
  type        = string
  default     = "flare-network-sandbox"
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "zone" {
  type    = string
  default = "europe-west1-b"
}

variable "service_account_email" {
  description = "Runtime service account for the tee-machine/tee-proxy VMs"
  type        = string
  default     = "confidential-sa@flare-network-sandbox.iam.gserviceaccount.com"
}

variable "tee_node_docker_image" {
  description = "tee-machine workload image"
  type        = string
  default     = "ghcr.io/flare-foundation/tee-node:v0.0.29@sha256:f7c8ccaaad5abe61a75bf4166c326a0db73c9bbe58d4799548ffdbd33506b836"
}

variable "tee_proxy_docker_image" {
  description = "tee-proxy image"
  type        = string
  default     = "ghcr.io/flare-foundation/tee-proxy:v0.0.27"
}

variable "tee_proxy_private_key" {
  description = "Signing private key for tee-proxy. Generate with ../../scripts/generate-key.sh - deliberately has no default. Supply it via terraform.tfvars (gitignored), not here."
  type        = string
  sensitive   = true
}

