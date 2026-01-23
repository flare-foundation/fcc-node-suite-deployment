module "database" {
  source = "../../sql/mysql"

  project           = var.project
  region            = var.region
  name = join("-", compact(["tee-c-chain-indexer", var.cli ? "cli" : "", var.deploy_suffix]))
  network           = var.project
  availability_type = local.is_production ? "REGIONAL" : "ZONAL"

  preferred_zone     = "${var.region}-b"
  dns_zone_internal  = "internal"
  sql_tier           = var.sql_tier
  enable_backups     = local.is_production
  binary_log_enabled = local.is_production
  backup_start_time  = "12:00"

  public_ipv4_enabled = var.cli
  database_name       = local.db_name
  database_user       = local.db_username
  database_password   = data.google_secret_manager_secret_version.db_password.secret_data

  authorized_networks = [
    {
      "name" : "abelium",
      "network" : "188.230.128.78"
    }
  ]
}
