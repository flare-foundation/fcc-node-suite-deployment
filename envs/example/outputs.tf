output "tee_proxy_external_endpoint" {
  value = module.tee_package.tee_proxy_external_endpoint
}

output "tee_proxy_info_url" {
  value = "${module.tee_package.tee_proxy_external_endpoint}/info"
}

output "tee_machine_name" {
  value = module.tee_package.tee_machine_name
}
