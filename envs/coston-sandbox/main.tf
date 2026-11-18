locals {
  # Coston's current protocol contract addresses and RPC, per
  # flarenetwork/infra's helm/values.yaml and services/tee/staging/coston.
  chain_id              = 16
  chain_rpc_endpoint    = "https://coston-api.flare.network/ext/C/rpc"
  flare_systems_manager = "0x85680Dd93755Fe5d0789773fd0896cEE51F9e358"
  relay                 = "0xEcD0B60Ea5E01e4D0bFd621c8920B40A32389b83"
  voter_registry        = "0x42F4526BFC6f892DB515a832a52eFc9edFADf6c0"

  # Coston's machine-path governance, the same set flarenetwork/infra's
  # staging/coston packages use. Without it the machine boots but cannot be
  # registered. governance_tee_manager is the FlareTeeManager the Safe
  # targets, which on Coston is machine_path_manager itself.
  machine_path_manager = "0xc4885998f5D792ed88C5Af7a3AaCBe333f017658"
  governance_signers = [
    "0x3E3CFF07D5b62C0B0aF4A14F5B54F60e232211Dc",
    "0x94D8eeA00fC2fee86e88C7cB828f245fcd2d1078",
    "0x63cd3c99b9fEcB3e49269f3BaDB0E1c144D6d1eE",
    "0x1c2F1A0fF05310A7BF65BCc2d7525BBEFB61fA39",
    "0x630dC7852735B31D471B64b1ea83e86A9eA0Fa14",
    "0xFB7af96a68eaEE4C88F677B91e31cDcc397dbf28",
    "0x42b0A1e3611387CeD6C2C61F427DF55719C93a93",
    "0xA40690D34bF2Efd3C0718Eeb8998Bd2Eb237dCC1",
    "0x817b1Ed5E89e932d128B9858d5EFA17F27ba64bc",
    "0xB0cB178bce33408fbc724318d88D096aD634227c",
    "0xD1de66afbF51Da5526641aFb137A15719c63De2E",
  ]
  governance_threshold = 3
  governance_safe      = "0x25365AA95F57768d598cA6C938f93F7a8D2469E8"
}

resource "google_compute_network" "tee" {
  name                    = "tee-coston"
  project                 = var.project
  auto_create_subnetworks = true
}

# Private service access existed for the indexer's Cloud SQL private IP. This
# stack no longer runs an indexer, so nothing uses it. It is left in place so
# that removing the indexer is not also a VPC peering change. Delete these
# three resources in a separate apply once Cloud SQL is gone.
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

# tee-machine has no public IP even in debug mode (see tee_machine.tf), and
# still needs outbound internet access (pulling container images, calling the
# attestation service), so route its egress through Cloud NAT instead.
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
  chain_id               = local.chain_id
  flare_systems_manager  = local.flare_systems_manager
  relay                  = local.relay
  voter_registry         = local.voter_registry
  tee_machine_debug_mode = true
  tee_machine_type       = "n2d-standard-2"
  machine_path_manager   = local.machine_path_manager
  governance_signers     = local.governance_signers
  governance_threshold   = local.governance_threshold
  governance_safe        = local.governance_safe
  governance_tee_manager = local.machine_path_manager
  # The Flare-held address this sandbox has always run under. The module no
  # longer defaults to it.
  initial_owner = "0xEfFDC9d60eaa243b2fCC5c2A21FA938B3A872d07"

  # No indexer: tee-proxy reads the chain from the public Coston RPC. The TEE
  # node cannot verify the signing policy and voter keys it returns, which is
  # acceptable for a sandbox and not for production.
  chain_source  = "rpc"
  chain_rpc_url = local.chain_rpc_endpoint
}
