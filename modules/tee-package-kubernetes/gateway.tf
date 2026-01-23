# resource "helm_release" "gateway_route" {
#   name         = "${join("-", compact(["tee-proxy-server", var.deploy_suffix]))}-route-internal"
#   namespace    = var.namespace
#   chart        = "${path.module}/../../../../../helm/gateway-route"
#   wait         = false
#   force_update = false

#   values = [templatefile("${path.module}/templates/gateway/values-internal.yaml.tftpl", {
#     name = "${join("-", compact(["tee-proxy-server", var.deploy_suffix]))}-private"
#   })]
#   set {
#     name  = "internalHostname"
#     value = trimsuffix(google_dns_record_set.internal_dns_record.name, ".")
#   }

# }

# resource "helm_release" "gateway_route_external" {
#   name         = "${join("-", compact(["tee-proxy-server", var.deploy_suffix]))}-route-external"
#   namespace    = var.namespace
#   chart        = "${path.module}/../../../../../helm/gateway-route"
#   wait         = false
#   force_update = false

#   values = [templatefile("${path.module}/templates/gateway/values-external.yaml.tftpl", {
#     name = "${join("-", compact(["tee-proxy-server", var.deploy_suffix]))}-public"
#   })]
#   set {
#     name  = "hostname"
#     value = trimsuffix(local.externalHostname, ".")
#   }
# }
