variable "deploy_suffix" {
  description = "Deployment suffix, used to prefix resource names in case of testing multiple deploys at the same time"
  type        = string
  default     = ""
}

variable "service_account_email" {
  description = "Email of service account with proper permissions to pull images from repo etc..."
  type        = string
}

variable "region" {
  description = "Deployment region"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "Deployment zone, for the indexer VM and the Cloud SQL instance's primary"
  type        = string
  default     = "europe-west1-b"
}

variable "network" {
  description = "VPC network self link for the indexer instance"
  type        = string
}

variable "project" {
  description = "GCP project where resources will be created"
  type        = string
}

variable "sql_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-custom-1-3840"
}

variable "database_version" {
  description = "Cloud SQL MySQL version. Changing it on an existing instance runs an in-place major version upgrade."
  type        = string
  default     = "MYSQL_8_0"
}

variable "machine_type" {
  description = "Machine type for the indexer VM"
  type        = string
  default     = "e2-medium"
}

variable "high_availability" {
  description = "Use a REGIONAL Cloud SQL instance with backups enabled instead of a cheaper ZONAL instance with no backups."
  type        = bool
  default     = false
}

variable "cli" {
  description = "If true, gives the indexer VM and the database a public IP. The database then accepts connections only from cli_authorized_networks."
  type        = bool
  default     = false
}

variable "cli_authorized_networks" {
  description = "cli mode only: CIDRs allowed to reach the database's public IP, as name => CIDR. Prefer cloud-sql-proxy over listing addresses here."
  type        = map(string)
  default     = {}
}

variable "chain_rpc_endpoint" {
  description = "RPC endpoint the indexer polls for chain data. Default is Coston2's public RPC - verify it's still current."
  type        = string
  default     = "https://coston2-api.flare.network/ext/C/rpc"
}

# Must match the same variables passed to module.tee_package - the indexer
# collects transactions/logs from the same contracts tee-proxy reads state from.
variable "flare_systems_manager" {
  description = "FlareSystemsManager contract address."
  type        = string
  default     = "0xA90Db6D10F856799b10ef2A77EBCbF460aC71e52" # Coston2
}

variable "relay" {
  description = "Relay contract address."
  type        = string
  default     = "0xa10B672D1c62e5457b17af63d4302add6A99d7dE" # Coston2
}

variable "voter_registry" {
  description = "VoterRegistry contract address."
  type        = string
  default     = "0x6a0AF07b7972177B176d3D422555cbc98DfDe914" # Coston2
}

variable "start_index" {
  description = "Block height the indexer starts collecting from. Must be at or before the VotePowerBlockSelected block of the epoch tee-proxy's initial_signing_policy_offset selects - two reward epochs back from the newest signing policy. At or before the Relay's SigningPolicyInitialized log is necessary but not sufficient: policy construction also recovers voter public keys from VoterRegistered events on VoterRegistry, which are emitted earlier, and starting between the two panics tee-proxy on loop with 'invalid number of logs'. Default is a Coston2 value that predates this module - verify it's still reasonably close to current chain height before relying on it. Only takes effect on a fresh DB if history_drop_seconds is 0 - otherwise the indexer computes its own (more recent) start from history_drop_seconds and ignores this entirely. Moving it backwards needs drop_table_at_start."
  type        = number
  default     = 46000000
}

variable "history_drop_seconds" {
  description = "Seconds of history the indexer guarantees to (re)collect from chain instead of trusting start_index, expressed via the config's history_drop field. Left unset (null) by default, which keeps the binary's own per-chain floor (2 days on Coston/Coston2, 14 days on Songbird/Flare) - on a fresh DB this always wins over start_index if it computes a more recent block. Set to 0 to disable that floor and make start_index authoritative instead, e.g. for a fresh sandbox deploy where you want to start right near current chain tip rather than walk a multi-day backlog."
  type        = number
  default     = null
}

variable "drop_table_at_start" {
  description = "Drop and recreate the indexer's tables when the container starts. Needed to move start_index backwards - the indexer otherwise resumes from its last state row and never re-reads earlier blocks. Leave false: set true for exactly one replace of the instance, then set it back, or every subsequent restart wipes the database. scripts/redeploy-indexer.sh --drop-db does that two-step for you."
  type        = bool
  default     = false
}

variable "machine_path_manager" {
  description = "MachinePathManager (FlareTeeManager) contract address. Set it to the same value passed to the tee-package module whenever governance is configured there: tee-proxy's machine-path-list service reads MachinePathsAdded, MachinePathListSigned and signMachinePathList transactions out of THIS database, so without these collectors the service starts, finds nothing, and every list update is rejected with no error anywhere. Empty collects nothing, which is correct when the machine-path service is disabled."
  type        = string
  default     = ""
}
