output "database_hostname" {
  description = "Internal hostname of indexer db"
  value       = local.db_host
}

output "database_config" {
  description = "Configuration object for the TEE Indexer database"
  value = {
    hostname     = local.db_host
    port         = 3306
    databaseName = local.db_name
    user         = "indexer-reader"
    password     = random_password.db_reader.result
  }
  sensitive = true
}
