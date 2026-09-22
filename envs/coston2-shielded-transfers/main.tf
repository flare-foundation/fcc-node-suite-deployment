# An EXTENSION deployment, as opposed to envs/coston2-sandbox which runs the
# stock tee-node. The extension here is shielded transfers (flare-mixer), chosen
# because it is one of the two extensions actually running on Coston2 today.
#
# Modelled on flarenetwork/infra's module.tee_package_shielded_transfers in
# terraform/gcp/services/tee/staging/coston2.
#
# What makes an extension deployment differ from the stock one:
#
#   - its own workload image, and here its own tee-proxy build too (some
#     extensions, like the USDX oracle, run the stock proxy instead)
#   - extension_id, the id the extension is registered under on chain
#   - extension_env, the settings the workload reads - for this extension the
#     three contract addresses below
#   - direct_api_key, enabling tee-proxy's POST /direct so the extension can take
#     actions off-chain rather than as on-chain instructions
#
# Both images live in Artifact Registry rather than a public registry, so the
# deploying project's service account needs roles/artifactregistry.reader on
# flare-network-staging. See README.md.
locals {
  chain_id              = 114
  chain_rpc_endpoint    = "https://coston2-api.flare.network/ext/C/rpc"
  flare_systems_manager = "0xA90Db6D10F856799b10ef2A77EBCbF460aC71e52"
  voter_registry        = "0x6a0AF07b7972177B176d3D422555cbc98DfDe914"

  # See envs/coston2-sandbox/main.tf - the module default is a dead deployment.
  relay = "0x5017728F117501A24EF9C3756C07f0d564598596"

  # Epoch 6088's VotePowerBlockSelected, picked 2026-09-21. Re-pick before a
  # fresh deploy; envs/coston2-sandbox/main.tf documents how.
  indexer_start_index = 35614590

  machine_path_manager = "0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE"

  # This extension's own governance, which is NOT the same signer set the stock
  # package uses on Coston2 - governance is per extension.
  governance_signers   = ["0xaAb2B5619F7c11C72947913B584b8BFec5654Df5"]
  governance_threshold = 1
}

resource "google_compute_network" "tee" {
  name                    = "tee-coston2-transfers"
  project                 = var.project
  auto_create_subnetworks = true
}

resource "google_project_service" "service_networking" {
  project            = var.project
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_global_address" "private_service_access" {
  name          = "tee-coston2-transfers-psa"
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
  deletion_policy         = "ABANDON"
  depends_on              = [google_project_service.service_networking]
}

resource "google_compute_router" "tee" {
  name    = "tee-coston2-transfers-router"
  project = var.project
  region  = var.region
  network = google_compute_network.tee.id
}

resource "google_compute_router_nat" "tee" {
  name                               = "tee-coston2-transfers-nat"
  project                            = var.project
  router                             = google_compute_router.tee.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

module "tee_indexer" {
  source = "../../modules/tee-indexer"

  deploy_suffix         = "coston2-transfers"
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

  # Governance is configured below, so the indexer must also collect the
  # MachinePathManager events tee-proxy's machine-path service reads.
  machine_path_manager = local.machine_path_manager

  depends_on = [google_service_networking_connection.private_service_access]
}

module "tee_package" {
  source = "../../modules/tee-package"

  deploy_suffix         = "coston2-transfers"
  project               = var.project
  region                = var.region
  zone                  = var.zone
  network               = google_compute_network.tee.self_link
  service_account_email = var.service_account_email
  tee_indexer_database  = module.tee_indexer.database_config
  chain_id              = local.chain_id
  flare_systems_manager = local.flare_systems_manager
  relay                 = local.relay
  voter_registry        = local.voter_registry

  # This extension ships its own tee-proxy build, not the stock one.
  tee_node_docker_image  = var.extension_image
  tee_proxy_docker_image = var.extension_proxy_image

  tee_proxy_private_key = var.tee_proxy_private_key
  initial_owner         = var.initial_owner
  extension_id          = var.extension_id

  # Settings this extension's workload reads. Each becomes tee-env-<KEY>, and
  # each must appear in the image's tee.launch_policy.allow_env_override label
  # or Confidential Space drops it without a word.
  extension_env = {
    CHAIN_URL           = local.chain_rpc_endpoint
    INSTRUCTION_SENDER  = var.instruction_sender
    SHIELDED_VAULT      = var.shielded_vault
    KYC_WHITELIST       = var.kyc_whitelist
    ACCREDITED_REGISTRY = var.accredited_registry
  }

  # Enables POST /direct on the proxy.
  direct_api_key = var.direct_api_key

  machine_path_manager = local.machine_path_manager
  governance_signers   = local.governance_signers
  governance_threshold = local.governance_threshold

  tee_machine_type       = "n2d-standard-2"
  tee_machine_debug_mode = true
}
