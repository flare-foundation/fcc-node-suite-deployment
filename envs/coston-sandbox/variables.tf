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
  description = "Runtime service account for the tee-machine/tee-proxy/tee-indexer VMs"
  type        = string
  default     = "confidential-sa@flare-network-sandbox.iam.gserviceaccount.com"
}

variable "tee_node_docker_image" {
  description = "tee-machine workload image"
  type        = string
  default     = "ghcr.io/flare-foundation/tee-node:v0.0.26@sha256:9842e0ae4f724ab71def212d72fe4c7875e18c6dd17ca1e4882aed7bf588b128"
}

variable "tee_proxy_docker_image" {
  description = "tee-proxy image"
  type        = string
  default     = "ghcr.io/flare-foundation/tee-proxy:v0.0.24"
}

variable "tee_proxy_private_key" {
  description = "Signing private key for tee-proxy. Generate with ../../scripts/generate-key.sh - deliberately has no default. Supply it via terraform.tfvars (gitignored), not here."
  type        = string
  sensitive   = true
}

variable "indexer_drop_table_at_start" {
  description = "Drop and recreate the indexer's tables on container start. Needed to move the indexer's start block backwards. Set true for exactly one instance replace, then set it back to false - otherwise every restart wipes the database. scripts/redeploy-indexer.sh --drop-db does that two-step for you."
  type        = bool
  default     = false
}
