locals {
  gcp_project_name = "flare-network-staging"
}

resource "google_service_account" "tee_gitlab_ci" {
  account_id   = "tee-gitlab-ci-deployer-test"
  display_name = "GitLab CI Deployer for TEE"
}

# Create network first to avoid circular dependency
resource "google_compute_network" "tee_network" {
  name                    = "tee-network-test-1"
  auto_create_subnetworks = true
  project                 = local.gcp_project_name
}

module "tee_indexer" {
  source = "../modules/tee-indexer-2"

  deploy_suffix         = "test-1"
  service_account_email = "confidential-sa@flare-network-staging.iam.gserviceaccount.com"
  project               = local.gcp_project_name
  region                = "europe-west1"
  zone                  = "europe-west1-b"
  network               = google_compute_network.tee_network.self_link
  dns_zone_public       = ""
  cli                   = false
  sql_tier              = "db-custom-1-3840"
}

module "tee_package_kubernetes" {
  source = "../modules/tee-package-kubernetes"

  deploy_suffix          = "test-1"
  service_account_email  = "confidential-sa@flare-network-staging.iam.gserviceaccount.com"
  tee_docker_image       = "europe-west1-docker.pkg.dev/flare-network-staging/containers/tee-node:0.0.14"
  tee_proxy_docker_image = "europe-west1-docker.pkg.dev/flare-network-staging/containers/tee-proxy-demo:0.1"
  tee_indexer_database   = module.tee_indexer.database_config
  deploy_account_email   = google_service_account.tee_gitlab_ci.email
  tee_machine_debug_mode = true
  network                = google_compute_network.tee_network.self_link
}
