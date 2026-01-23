# resource "google_redis_instance" "tee_proxy_redis" {
#   project            = var.project
#   name               = join("-", compact(["tee-proxy-redis", var.deploy_suffix]))
#   region             = "europe-west1"
#   memory_size_gb     = 1
#   authorized_network = var.project
#   # https://cloud.google.com/memorystore/docs/redis/networking#direct_peering
#   connect_mode = "DIRECT_PEERING"
#   auth_enabled = false
#   redis_configs = {
#     maxmemory-policy = "noeviction"
#   }
# }
