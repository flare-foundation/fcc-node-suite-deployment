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
  description = "Runtime service account for the tee-machine/tee-proxy/tee-indexer VMs. Needs roles/confidentialcomputing.workloadUser (without it the Confidential Space launcher cannot reach the attestation verifier and the workload exits after ~3s with exit_code=4) and roles/monitoring.metricWriter. Whoever runs terraform also needs roles/iam.serviceAccountUser on this SA to attach it to the VMs."
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

variable "initial_owner" {
  description = "Address that owns the TEE machine. This is the SAME keypair as tee_proxy_private_key - generate-key.sh prints both halves, the address goes here and the private key above. Deliberately has no default: the module's own default is a Flare-held address, and silently inheriting it deploys a machine you cannot configure."
  type        = string

  validation {
    condition     = can(regex("^0x[0-9a-fA-F]{40}$", var.initial_owner))
    error_message = "initial_owner must be a 0x-prefixed 20-byte hex address."
  }
}

variable "indexer_drop_table_at_start" {
  description = "Drop and recreate the indexer's tables on container start. Needed to move the indexer's start block backwards. Set true for exactly one instance replace, then set it back to false - otherwise every restart wipes the database. scripts/redeploy-indexer.sh --drop-db does that two-step for you."
  type        = bool
  default     = false
}
