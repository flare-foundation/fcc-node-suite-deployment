# Generated here rather than requiring the caller to pre-create Secret Manager
# secrets by hand (upstream's approach) - a fresh GCP project has no such
# secrets to point at.
resource "random_password" "db_admin" {
  length  = 24
  special = false
}

resource "random_password" "db_reader" {
  length  = 24
  special = false
}

# Cloud SQL MySQL instance for indexer
resource "google_sql_database_instance" "indexer_db" {
  name             = join("-", compact(["tee-indexer-db", var.cli ? "cli" : "", var.deploy_suffix]))
  database_version = "MYSQL_8_0"
  region           = var.region
  project          = var.project

  settings {
    tier              = var.sql_tier
    availability_type = local.is_production ? "REGIONAL" : "ZONAL"
    disk_size         = 10
    disk_type         = "PD_SSD"

    backup_configuration {
      enabled            = local.is_production
      binary_log_enabled = local.is_production
      start_time         = "12:00"
    }

    ip_configuration {
      ipv4_enabled    = var.cli
      private_network = var.network

      dynamic "authorized_networks" {
        for_each = var.cli ? [1] : []
        content {
          name  = "abelium"
          value = "188.230.128.78"
        }
      }
    }

    location_preference {
      zone = "${var.region}-b"
    }
  }

  deletion_protection = local.is_production
}

# Create the indexer database
resource "google_sql_database" "indexer" {
  name     = local.db_name
  instance = google_sql_database_instance.indexer_db.name
  project  = var.project
}

# Admin user
resource "google_sql_user" "indexer_admin" {
  name     = local.db_username
  instance = google_sql_database_instance.indexer_db.name
  password = random_password.db_admin.result
  project  = var.project
}

# Read-only user
resource "google_sql_user" "indexer_reader" {
  name     = "indexer-reader"
  instance = google_sql_database_instance.indexer_db.name
  password = random_password.db_reader.result
  project  = var.project
}

# Output for internal DNS record (using private IP if available, otherwise public IP)
locals {
  db_host = var.cli ? google_sql_database_instance.indexer_db.public_ip_address : google_sql_database_instance.indexer_db.private_ip_address
}
