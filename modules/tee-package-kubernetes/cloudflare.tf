# resource "cloudflare_dns_record" "tee-proxy" {
#   zone_id = data.cloudflare_zone.default.zone_id
#   name    = join("-", compact(["tee-proxy", var.deploy_suffix]))
#   content = data.google_compute_global_address.gateway_external.address
#   type    = "A"
#   ttl     = 1
#   proxied = true
# }
