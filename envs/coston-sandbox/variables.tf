variable "project" {
  description = "GCP project to deploy into"
  default     = "flare-network-sandbox"
}

variable "region" {
  default = "europe-west1"
}

variable "zone" {
  default = "europe-west1-b"
}

variable "service_account_email" {
  description = "Runtime service account for the tee-machine/tee-proxy/tee-indexer VMs"
  default     = "confidential-sa@flare-network-sandbox.iam.gserviceaccount.com"
}

variable "tee_node_docker_image" {
  description = "tee-machine workload image"
  default     = "ghcr.io/flare-foundation/tee-node:v0.0.26"
}

variable "tee_proxy_docker_image" {
  description = "tee-proxy image"
  default     = "ghcr.io/flare-foundation/tee-proxy:v0.0.24"
}

variable "tee_proxy_private_key" {
  description = "Signing private key for tee-proxy. Generate with ../../scripts/generate-key.sh - deliberately has no default. Supply it via terraform.tfvars (gitignored), not here."
  type        = string
  sensitive   = true
}
