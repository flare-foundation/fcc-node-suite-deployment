locals {
  chain_id              = var.chain_id
  chain_rpc_endpoint    = var.chain_rpc_endpoint
  flare_systems_manager = var.flare_systems_manager
  voter_registry        = var.voter_registry
  relay                 = var.relay
  machine_path_manager  = var.machine_path_manager
}

resource "google_compute_network" "tee" {
  name                    = "tee"
  project                 = var.project
  auto_create_subnetworks = true
}

# Cloud SQL private IP requires the VPC to be peered with Google's managed
# services network first - see
# https://cloud.google.com/sql/docs/mysql/private-ip#network_requirements
resource "google_project_service" "service_networking" {
  project = var.project
  service = "servicenetworking.googleapis.com"

  # Project-wide API - other things in the project may depend on it.
  # Destroying our stack should never disable an API project-wide.
  disable_on_destroy = false
}

resource "google_compute_global_address" "private_service_access" {
  name          = "tee-private-service-access"
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

# tee-machine has no public IP even in debug mode (see modules/tee-package's
# tee-machine.tf), and tee-indexer has none outside cli mode - both still
# need outbound internet access (pulling container images, calling the
# attestation service, hitting the chain RPC), so route their egress through
# Cloud NAT instead.
resource "google_compute_router" "tee" {
  name    = "tee-router"
  project = var.project
  region  = var.region
  network = google_compute_network.tee.id
}

resource "google_compute_router_nat" "tee" {
  name                               = "tee-nat"
  project                            = var.project
  router                             = google_compute_router.tee.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

module "tee_indexer" {
  source = "../../modules/tee-indexer"

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
  machine_path_manager  = local.machine_path_manager

  depends_on = [google_service_networking_connection.private_service_access]
}

module "tee_package" {
  source = "../../modules/tee-package"

  project                = var.project
  region                 = var.region
  zone                   = var.zone
  network                = google_compute_network.tee.self_link
  service_account_email  = var.service_account_email
  tee_node_docker_image  = var.tee_node_docker_image
  tee_proxy_docker_image = var.tee_proxy_docker_image
  tee_proxy_private_key  = var.tee_proxy_private_key

  # Suffix appended to every resource name. An empty suffix leaves a trailing
  # dash on allow-internal-, which Google Cloud rejects.
  deploy_suffix = var.deploy_suffix

  # This environment runs its own indexer. To use an external indexer instead,
  # comment the line below, uncomment the block under it, uncomment the
  # indexer_db_* variables in variables.tf, and remove module.tee_indexer plus
  # the service-networking resources that exist only for Cloud SQL.
  tee_indexer_database = module.tee_indexer.database_config

  # tee_indexer_database = {
  #   hostname     = var.indexer_db_host
  #   port         = var.indexer_db_port
  #   databaseName = var.indexer_db_name
  #   user         = var.indexer_db_user
  #   password     = var.indexer_db_password
  # }

  chain_id              = local.chain_id
  flare_systems_manager = local.flare_systems_manager
  relay                 = local.relay
  voter_registry        = local.voter_registry
  machine_path_manager  = local.machine_path_manager

  initial_owner        = var.initial_owner
  extension_id         = var.extension_id
  governance_signers   = var.governance_signers
  governance_threshold = var.governance_threshold

  # Empty for the stock tee-node image (extension 0). A custom extension image
  # sets this in terraform.tfvars. Each key must be on that image's
  # tee.launch_policy.allow_env_override label.
  extension_env = var.extension_env

  tee_machine_debug_mode = true
}
