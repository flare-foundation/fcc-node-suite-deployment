output "tee_proxy_external_endpoint" {
  value = module.tee_package.tee_proxy_external_endpoint
}

output "tee_proxy_info_url" {
  value = "${module.tee_package.tee_proxy_external_endpoint}/info"
}

output "tee_machine_name" {
  value = module.tee_package.tee_machine_name
}

# Consumed by the scripts/ helpers - see TESTING.md section 5.
output "tee_proxy_instance_name" {
  value = module.tee_package.tee_proxy_instance_name
}

output "redis_host" {
  value = module.tee_package.redis_host
}

output "redis_port" {
  value = module.tee_package.redis_port
}
