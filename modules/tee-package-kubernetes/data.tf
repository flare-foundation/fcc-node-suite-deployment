

# data "google_dns_managed_zone" "env_dns_zone" {
#   name    = "internal"
#   project = var.project
# }

# data "google_secret_manager_secret_version" "proxy_private_key" {
#   project = var.project
#   version = "latest"
#   secret  = join("-", compact(["tee-proxy-private-key", var.deploy_suffix]))
# }

# data "google_compute_network" "network" {
#   name    = var.project
#   project = var.project
# }

resource "google_compute_network" "tee_network" {
  name                    = "tee-test-network"
  auto_create_subnetworks = true
}

# data "cloudflare_zone" "default" {
#   filter = {
#     name = local.dns_zone_public
#   }
# }
