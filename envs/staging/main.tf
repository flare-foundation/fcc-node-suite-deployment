locals {
  gcp_project_name = "flare-network-staging"
}

resource "google_service_account" "tee_gitlab_ci" {
  account_id   = "tee-gitlab-ci-deployer-k8s"
  display_name = "GitLab CI Deployer for TEE"
}

module "tee_indexer" {
  source = "../../../modules/helm/tee-indexer-2"

  deploy_suffix         = "coston-k8s"
  dns_zone_public       = "flare.rocks"
  service_account_email = "confidential-sa@flare-network-staging.iam.gserviceaccount.com"
  project               = local.gcp_project_name
}

module "tee_indexer_cli" {
  source = "../../../modules/helm/tee-indexer-2"

  deploy_suffix         = "coston-k8s"
  dns_zone_public       = "flare.rocks"
  service_account_email = "confidential-sa@flare-network-staging.iam.gserviceaccount.com"
  project               = local.gcp_project_name
  cli                   = true
}

module "tee_package_kubernetes" {
  source = "../../../modules/helm/tee-package-kubernetes"

  deploy_suffix          = "k8s-1"
  service_account_email  = "confidential-sa@flare-network-staging.iam.gserviceaccount.com"
  tee_docker_image       = "europe-west1-docker.pkg.dev/flare-network-staging/containers/tee-node:0.0.14"
  tee_indexer_database   = module.tee_indexer.database_config
  deploy_account_email   = google_service_account.tee_gitlab_ci.email
  tee_machine_debug_mode = true
}

module "tee_package_kubernetes_extension" {
  source = "../../../modules/helm/tee-package-kubernetes"

  deploy_suffix          = "k8s-extension-1"
  service_account_email  = "confidential-sa@flare-network-staging.iam.gserviceaccount.com"
  tee_docker_image       = "europe-west1-docker.pkg.dev/flare-network-staging/containers/tee-extension-example:0.0.4"
  extension_id           = "0x0000000000000000000000000000000000000000000000000000000000000003"
  tee_indexer_database   = module.tee_indexer.database_config
  deploy_account_email   = google_service_account.tee_gitlab_ci.email
  tee_machine_debug_mode = true
}

