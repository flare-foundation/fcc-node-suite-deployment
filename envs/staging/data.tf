data "google_container_cluster" "gke" {
  name     = "k8s-west1-gke-cluster"
  project  = local.gcp_project_name
  location = "europe-west1"
}

data "google_client_config" "provider" {}
