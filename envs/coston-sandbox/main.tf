locals {
  # Coston's current protocol contract addresses and RPC, per
  # flarenetwork/infra's helm/values.yaml and services/tee/staging/coston.
  chain_id              = 16
  chain_rpc_endpoint    = "https://coston-api.flare.network/ext/C/rpc"
  flare_systems_manager = "0x85680Dd93755Fe5d0789773fd0896cEE51F9e358"
  relay                 = "0xEcD0B60Ea5E01e4D0bFd621c8920B40A32389b83"
  voter_registry        = "0x42F4526BFC6f892DB515a832a52eFc9edFADf6c0"

  # Must be at or before the VotePowerBlockSelected block of the epoch
  # initial_signing_policy_offset selects - two reward epochs back from the
  # newest signing policy.
  #
  # Being at or before the Relay's SigningPolicyInitialized log is necessary
  # but not sufficient: building the policy also recovers each voter's public
  # key from the v,r,s in their VoterRegistered event on VoterRegistry, which
  # is emitted earlier. Start between the two and tee-proxy panics on loop with
  # "recovering pub key for 0x...: invalid number of logs". VotePowerBlockSelected
  # is the bound because registerVoter requires a non-zero votePowerBlock, set
  # there, so no VoterRegistered for the epoch can precede it.
  #
  # 53650000 matches flarenetwork/infra's own coston config for this same relay
  # address (see commit 624b09537). Paired with history_drop_seconds = 0 below,
  # which makes the indexer actually use this instead of its own
  # history-drop-computed, more-recent start. Re-pick if this env is redeployed
  # from scratch much later and this value has aged out of whatever history the
  # RPC retains - and note that moving it backwards needs the indexer database
  # dropped (scripts/redeploy-indexer.sh --drop-db), since the indexer otherwise
  # resumes from its last state row.
  indexer_start_index = 53650000
}

resource "google_compute_network" "tee" {
  name                    = "tee-coston"
  project                 = var.project
  auto_create_subnetworks = true
}

# Cloud SQL private IP requires the VPC to be peered with Google's managed
# services network first - see
# https://cloud.google.com/sql/docs/mysql/private-ip#network_requirements
resource "google_project_service" "service_networking" {
  project = var.project
  service = "servicenetworking.googleapis.com"

  # This is a project-wide API, not something scoped to our stack - other
  # things in a shared project (flare-network-sandbox is Flare's, not a
  # project we own outright) may depend on it. Destroying our stack should
  # never disable an API project-wide as a side effect.
  disable_on_destroy = false
}

resource "google_compute_global_address" "private_service_access" {
  name          = "tee-coston-private-service-access"
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

  # Cloud SQL keeps an active private IP on this peering, so a real delete
  # (the default) fails with "Producer services ... are still using this
  # connection" whenever Terraform wants to destroy/replace it. Abandon
  # instead of trying to tear down infra something else still depends on.
  deletion_policy = "ABANDON"

  depends_on = [google_project_service.service_networking]
}

# tee-machine has no public IP even in debug mode (see tee-machine.tf), and
# tee-indexer has none outside cli mode - both still need outbound internet
# access (pulling container images, calling the attestation service, hitting
# the chain RPC), so route their egress through Cloud NAT instead.
resource "google_compute_router" "tee" {
  name    = "tee-coston-router"
  project = var.project
  region  = var.region
  network = google_compute_network.tee.id
}

resource "google_compute_router_nat" "tee" {
  name                               = "tee-coston-nat"
  project                            = var.project
  router                             = google_compute_router.tee.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

module "tee_indexer" {
  source = "../../modules/tee-indexer"

  deploy_suffix         = "coston"
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

  deploy_suffix          = "coston"
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
}
