output "tee_proxy_external_ip" {
  description = "External IP address of the tee-proxy VM"
  value       = google_compute_address.tee_proxy_ip.address
}

output "tee_proxy_external_endpoint" {
  description = "External endpoint for tee-proxy (port 6662)"
  value       = "http://${google_compute_address.tee_proxy_ip.address}:6662"
}

output "tee_proxy_internal_endpoint" {
  description = "Internal endpoint for tee-proxy (port 6661)"
  value       = "http://${google_compute_instance.tee_proxy.network_interface[0].network_ip}:6661"
}

output "tee_machine_ip" {
  description = "External IP address of the tee-machine (only in debug mode)"
  value       = var.tee_machine_debug_mode ? google_compute_address.tee_machine_ip[0].address : null
}
