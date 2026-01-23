
# data "google_compute_address" "gateway_internal" {
#   project = var.project
#   name    = "gateway-internal-ip"
#   region  = "europe-west1"
# }

# resource "google_dns_record_set" "internal_dns_record" {
#   name         = local.internalHostname
#   project      = var.project
#   managed_zone = data.google_dns_managed_zone.env_dns_zone.name
#   type         = "A"
#   ttl          = 300

#   rrdatas = [data.google_compute_address.gateway_internal.address]
# }

# data "google_compute_global_address" "gateway_external" {
#   project = var.project
#   name    = "gateway-external-ip"
# }
