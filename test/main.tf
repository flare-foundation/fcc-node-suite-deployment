locals {
  gcp_project_name = "flare-network-staging"
}

resource "google_service_account" "tee_gitlab_ci" {
  account_id   = "tee-gitlab-ci-deployer-test"
  display_name = "GitLab CI Deployer for TEE"
}

module "tee_package_kubernetes" {
  source = "../modules/tee-package-kubernetes"

  deploy_suffix         = "test-1"
  service_account_email = "confidential-sa@flare-network-staging.iam.gserviceaccount.com"
  tee_docker_image      = "europe-west1-docker.pkg.dev/flare-network-staging/containers/tee-node:0.0.14"
  # tee_indexer_database   = module.tee_indexer.database_config
  deploy_account_email   = google_service_account.tee_gitlab_ci.email
  tee_machine_debug_mode = true
}
