resource "helm_release" "indexer" {
  name = join("-", compact(["tee-c-chain-indexer", var.cli ? "cli" : "", var.deploy_suffix]))
  namespace        = "tee"
  chart            = "${path.module}/../../../../../helm/ftso_v2_c_chain_indexer"
  atomic           = true
  create_namespace = true


  values = [
    templatefile("${path.module}/templates/indexer/${local.indexer_config_template_name}", {
      db_host        = module.database.internal_dns_record
      db_user        = local.db_username
      db_pass        = data.google_secret_manager_secret_version.db_password.secret_data
      db_reader_pass = data.google_secret_manager_secret_version.db_reader_password.secret_data
    })
  ]
}
