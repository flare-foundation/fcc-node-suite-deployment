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
  description = "Runtime service account for the VMs. Needs roles/confidentialcomputing.workloadUser and roles/monitoring.metricWriter, and - because this extension's images are in Artifact Registry rather than a public registry - roles/artifactregistry.reader on the project hosting them."
  type        = string
  default     = "confidential-sa@flare-network-sandbox.iam.gserviceaccount.com"
}

variable "extension_image" {
  description = "The extension's TEE workload image. Coston2's shielded-transfers build per flarenetwork/infra."
  type        = string
  default     = "europe-west1-docker.pkg.dev/flare-network-staging/containers/tee-flare-mixer:v0.1.4"
}

variable "extension_proxy_image" {
  description = "tee-proxy build for this extension. Shielded transfers ships its own, because it adds proxy-side extension code; extensions without that (the USDX oracle, for one) use the stock ghcr.io/flare-foundation/tee-proxy image instead."
  type        = string
  default     = "europe-west1-docker.pkg.dev/flare-network-staging/containers/tee-proxy-flare-mixer:v0.1.4"
}

variable "extension_id" {
  description = "The id this extension is registered under on chain, as bytes32. Assigned per extension, not chosen - 0x...010481 is shielded transfers."
  type        = string
  default     = "0x0000000000000000000000000000000000000000000000000000000000010481"
}

variable "instruction_sender" {
  description = "Address allowed to send this extension's on-chain instructions."
  type        = string
  default     = "0x4555b0caCC1FD163A00089c4F3e2977Ab7b4FA75"
}

variable "shielded_vault" {
  description = "ShieldedVault contract, read by the extension workload."
  type        = string
  default     = "0x8E6e87AcC2313Bd02BFC4951fAd8253899d50c66"
}

variable "kyc_whitelist" {
  description = "KycWhitelist contract, read by the extension workload."
  type        = string
  default     = "0xBCc81380B96EDeb61aF385AeA54c27EF14268073"
}

variable "accredited_registry" {
  description = "AccreditedRegistry contract, read by the extension workload."
  type        = string
  default     = "0x6761a6822A02B81296D966BD952E1A18c24Fd96F"
}

variable "tee_proxy_private_key" {
  description = "Signing private key for tee-proxy. Generate with ../../scripts/generate-key.sh - no default on purpose. Supply via terraform.tfvars (gitignored)."
  type        = string
  sensitive   = true
}

variable "initial_owner" {
  description = "Address that owns the TEE machine - the other half of the tee_proxy_private_key keypair."
  type        = string

  validation {
    condition     = can(regex("^0x[0-9a-fA-F]{40}$", var.initial_owner))
    error_message = "initial_owner must be a 0x-prefixed 20-byte hex address."
  }
}

variable "direct_api_key" {
  description = "Key for tee-proxy's POST /direct endpoint, which this extension uses for off-chain actions. Defaults to the throwaway value flarenetwork/infra uses for Coston2, which is fine for a sandbox and useless as a secret - /direct is reachable from anywhere the external port is. Override it in terraform.tfvars for anything you would mind strangers calling; infra keeps the real one in the tee-direct-api-key-coston2 Secret Manager secret."
  type        = string
  default     = "12345"
  sensitive   = true
}

variable "indexer_drop_table_at_start" {
  description = "Drop and recreate the indexer's tables on container start. Set true for exactly one instance replace, then back to false. scripts/redeploy-indexer.sh --drop-db does the two-step."
  type        = bool
  default     = false
}
