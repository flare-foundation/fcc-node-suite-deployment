
locals {
  # internalHostname = "${join("-", compact(["tee-proxy", var.deploy_suffix]))}.${google_dns_managed_zone.env_dns_zone.dns_name}"
  # externalHostname = "${join("-", compact(["tee-proxy", var.deploy_suffix]))}.${local.dns_zone_public}"
  is_production   = var.project == "flare-network-production"
  dns_zone_public = local.is_production ? "flare.network" : "flare.rocks"
}
