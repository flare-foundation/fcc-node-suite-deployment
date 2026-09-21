locals {
  # Coston2's current protocol contract addresses and RPC, taken from
  # flarenetwork/infra's terraform/gcp/services/tee/staging/coston2 (the live
  # staging deployment) and verified on chain - see the relay note below.
  chain_id              = 114
  chain_rpc_endpoint    = "https://coston2-api.flare.network/ext/C/rpc"
  flare_systems_manager = "0xA90Db6D10F856799b10ef2A77EBCbF460aC71e52"
  voter_registry        = "0x6a0AF07b7972177B176d3D422555cbc98DfDe914"

  # NOT the module default (0xa10B672D1c62e5457b17af63d4302add6A99d7dE), which is
  # a dead deployment: it has emitted no SigningPolicyInitialized logs in the last
  # 40k blocks, while this address emitted epochs 6089-6091. Using the default here
  # gives "no signing policy logs found in db" no matter how caught up the indexer is.
  relay = "0x5017728F117501A24EF9C3756C07f0d564598596"

  # Must be at or before the VotePowerBlockSelected block of the epoch
  # initial_signing_policy_offset selects - two reward epochs back from the newest
  # signing policy. See envs/coston-sandbox/main.tf for why the policy log itself is
  # not a sufficient bound, and TESTING.md's "invalid number of logs" row.
  #
  # 35614590 is epoch 6088's VotePowerBlockSelected, picked on 2026-09-21 when the
  # newest policy was 6091 - one epoch of margin below the 6089 that offset 2
  # required. Earlier is always safe and only costs catch-up time; later panics.
  # Coston2 reward epochs run roughly 10-11k blocks apart, so re-pick before a fresh
  # deploy using the explorer query documented in envs/coston-sandbox/main.tf
  # (same topic0, but against this network's FlareSystemsManager).
  indexer_start_index = 35614590

  # TEE governance, from the same staging config. governance_signers must be the
  # signer set that actually governs the extension this machine runs - with the
  # wrong set, tee-node rejects every machine-path list update. machine_path_manager
  # is required alongside it: tee-proxy refuses a [governance] block whose
  # addresses.machine_path_manager is the zero address.
  machine_path_manager = "0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE"
  governance_signers   = ["0xfD5e6AbE2829966e86FE4ACC9c44784d251AE512"]
  governance_threshold = 1
}

resource "google_compute_network" "tee" {
  name                    = "tee-coston2"
  project                 = var.project
  auto_create_subnetworks = true
}

# Cloud SQL private IP requires the VPC to be peered with Google's managed
# services network first - see
# https://cloud.google.com/sql/docs/mysql/private-ip#network_requirements
resource "google_project_service" "service_networking" {
  project = var.project
  service = "servicenetworking.googleapis.com"

  # Project-wide API, not scoped to our stack - other things in a shared project
  # may depend on it. Destroying our stack should never disable it project-wide.
  disable_on_destroy = false
}

resource "google_compute_global_address" "private_service_access" {
  name          = "tee-coston2-private-service-access"
  project       = var.project
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.tee.id
}

resource "google_service_networking_connection" "private_service_access" {
  network                 = google_compute_network.tee.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_access.name]

  # Cloud SQL keeps an active private IP on this peering, so a real delete fails
  # with "Producer services ... are still using this connection" whenever Terraform
  # wants to destroy/replace it. Abandon instead.
  deletion_policy = "ABANDON"

  depends_on = [google_project_service.service_networking]
}

# tee-machine has no public IP even in debug mode, and tee-indexer has none outside
# cli mode - both still need outbound internet (pulling images, the attestation
# service, the chain RPC), so route egress through Cloud NAT.
resource "google_compute_router" "tee" {
  name    = "tee-coston2-router"
  project = var.project
  region  = var.region
  network = google_compute_network.tee.id
}

resource "google_compute_router_nat" "tee" {
  name                               = "tee-coston2-nat"
  project                            = var.project
  router                             = google_compute_router.tee.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

module "tee_indexer" {
  source = "../../modules/tee-indexer"

  deploy_suffix         = "coston2"
  project               = var.project
  region                = var.region
  zone                  = var.zone
  network               = google_compute_network.tee.self_link
  service_account_email = var.service_account_email
  drop_table_at_start   = var.indexer_drop_table_at_start
  chain_rpc_endpoint    = local.chain_rpc_endpoint
  flare_systems_manager = local.flare_systems_manager
  relay                 = local.relay
  voter_registry        = local.voter_registry
  start_index           = local.indexer_start_index
  history_drop_seconds  = 0

  depends_on = [google_service_networking_connection.private_service_access]
}

module "tee_package" {
  source = "../../modules/tee-package"

  deploy_suffix          = "coston2"
  project                = var.project
  region                 = var.region
  zone                   = var.zone
  network                = google_compute_network.tee.self_link
  service_account_email  = var.service_account_email
  tee_node_docker_image  = var.tee_node_docker_image
  tee_proxy_docker_image = var.tee_proxy_docker_image
  tee_proxy_private_key  = var.tee_proxy_private_key
  tee_indexer_database   = module.tee_indexer.database_config
  chain_id               = local.chain_id
  flare_systems_manager  = local.flare_systems_manager
  relay                  = local.relay
  voter_registry         = local.voter_registry
  tee_machine_debug_mode = true

  # One keypair: this address is generate-key.sh's output for the same private key
  # passed above. Leaving it unset silently deploys a machine owned by the module
  # default - an address you do not hold the key for.
  initial_owner = var.initial_owner

  machine_path_manager = local.machine_path_manager
  governance_signers   = local.governance_signers
  governance_threshold = local.governance_threshold
}
