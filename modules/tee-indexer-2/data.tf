
data "google_secret_manager_secret_version" "db_password" {
  project = var.project
  version = "latest"
  secret  = "tee_indexer_db_password"
}

data "google_secret_manager_secret_version" "db_reader_password" {
  project = var.project
  version = "latest"
  secret  = "tee_indexer_reader_password"
}