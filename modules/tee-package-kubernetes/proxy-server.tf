# resource "helm_release" "tee_proxy_server" {
#   name         = join("-", compact(["tee-proxy-server", var.deploy_suffix]))
#   namespace    = var.namespace
#   chart        = "${path.module}/helm"
#   wait         = false
#   force_update = false

#   set {
#     name  = "hostname"
#     value = trimsuffix(google_dns_record_set.internal_dns_record.name, ".")
#   }

#   set {
#     name  = "publicHostname"
#     value = local.externalHostname
#   }

#   set {
#     name  = "image.repository"
#     value = split(":", var.tee_proxy_docker_image)[0]
#   }

#   set {
#     name  = "image.tag"
#     value = split(":", var.tee_proxy_docker_image)[1]
#   }

#   set {
#     name  = "redis.host"
#     value = google_redis_instance.tee_proxy_redis.host
#   }

#   set {
#     name  = "redis.port"
#     value = google_redis_instance.tee_proxy_redis.port
#   }

#   set_sensitive {
#     name  = "privateKey"
#     value = data.google_secret_manager_secret_version.proxy_private_key.secret_data
#   }

#   set {
#     name  = "indexer.host"
#     value = var.tee_indexer_database.hostname
#   }

#   set {
#     name  = "indexer.port"
#     value = var.tee_indexer_database.port
#   }

#   set {
#     name  = "indexer.database.name"
#     value = var.tee_indexer_database.databaseName
#   }

#   set {
#     name  = "indexer.database.user"
#     value = var.tee_indexer_database.user
#   }

#   set_sensitive {
#     name  = "indexer.database.password"
#     value = var.tee_indexer_database.password
#   }
# }
