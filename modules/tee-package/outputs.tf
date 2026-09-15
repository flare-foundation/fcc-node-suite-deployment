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

output "tee_machine_name" {
  description = "Instance name of tee-machine, for `gcloud compute ssh --tunnel-through-iap` (it has no external IP, even in debug mode)"
  value       = google_compute_instance.tee_machine.name
}

output "tee_machine_internal_ip" {
  description = "Internal IP address of tee-machine"
  value       = google_compute_instance.tee_machine.network_interface[0].network_ip
}

output "network_self_link" {
  description = "Self link of the VPC network"
  value       = var.network
}

output "tee_proxy_gcs_bucket" {
  description = "Name of the GCS bucket tee-proxy uses for persistent storage"
  value       = google_storage_bucket.tee_proxy.name
}
