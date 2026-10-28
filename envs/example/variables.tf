variable "project" {
  description = "GCP project to deploy into. Must already exist - this example does not create it."
  type        = string
}

variable "region" {
  description = "GCP region for regional resources"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP zone for zonal resources"
  type        = string
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
  description = "Signing private key for tee-proxy. Generate with ../../scripts/generate-key.sh. See modules/tee-package/variables.tf."
  type        = string
  sensitive   = true
}

variable "deploy_suffix" {
  description = "Suffix appended to every resource name. Must be non-empty: an empty value leaves a trailing dash on allow-internal-, which Google Cloud rejects."
  type        = string
  default     = "example"
}

variable "indexer_drop_table_at_start" {
  description = "Drop and recreate the indexer's tables on container start. Needed to move the indexer's start block backwards. Set true for exactly one instance replace, then set it back to false - otherwise every restart wipes the database. scripts/redeploy-indexer.sh --drop-db does that two-step for you."
  type        = bool
  default     = false
}

variable "initial_owner" {
  description = "Address registered as the machine owner."
  type        = string
}

variable "extension_id" {
  description = "On-chain extension ID this machine serves. The zero id is extension 0, the stock tee-node image. Set this when the workload image is your own extension."
  type        = string
  default     = "0x0000000000000000000000000000000000000000000000000000000000000000"
}

variable "governance_signers" {
  description = "Signer set used for machine-path governance. Empty leaves governance unset: the machine boots but cannot be registered, extension 0 included. Set it, together with governance_threshold, before registering the machine. It must match the set the registration tooling writes with set-governance."
  type        = list(string)
  default     = []
}

variable "governance_threshold" {
  description = "Minimum number of governance_signers required per machine-path list. Leave at 0 when governance_signers is empty."
  type        = number
  default     = 0
}

variable "extension_env" {
  description = "Extra tee-env-* metadata for a custom extension image, as KEY => value. Leave empty for the stock tee-node image. Each key must appear in that image's tee.launch_policy.allow_env_override label."
  type        = map(string)
  default     = {}
}

variable "chain_id" {
  description = "Chain ID tee-proxy reports itself as running against."
  type        = number
}

variable "chain_rpc_endpoint" {
  description = "Public RPC URL for the target chain. Used by the indexer. A custom extension that reads CHAIN_URL sets that itself in extension_env."
  type        = string
}

# Contract addresses are inputs so this example does not pin a network snapshot.
variable "flare_systems_manager" {
  description = "FlareSystemsManager contract address for the target chain."
  type        = string
}

variable "voter_registry" {
  description = "VoterRegistry contract address for the target chain."
  type        = string
}

variable "relay" {
  description = "Relay contract address for the target chain. Do not leave this at a retired address with no SigningPolicyInitialized logs."
  type        = string
}

variable "machine_path_manager" {
  description = "FlareTeeManager / MachinePathManager contract address for the target chain."
  type        = string
}

# Optional external indexer. This environment runs module.tee_indexer instead.
# Uncomment these, and the matching tee_indexer_database block in main.tf, to
# use a shared indexer and skip running your own.
# variable "indexer_db_host" {
#   description = "Hostname of an external c-chain indexer database."
#   type        = string
# }
#
# variable "indexer_db_port" {
#   type    = number
#   default = 3306
# }
#
# variable "indexer_db_name" {
#   type    = string
#   default = "indexer"
# }
#
# variable "indexer_db_user" {
#   description = "Read-only user on the external indexer database."
#   type        = string
# }
#
# variable "indexer_db_password" {
#   description = "Password for the indexer user. Supply via terraform.tfvars."
#   type        = string
#   sensitive   = true
# }
