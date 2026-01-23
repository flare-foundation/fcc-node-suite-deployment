locals {
  db_name       = "indexer"
  db_username   = "indexer"
  is_production = var.project == "flare-network-production"

  indexer_config_template_name = var.cli ? "values-cli.yaml.tftpl" : "values.yaml.tftpl"
}