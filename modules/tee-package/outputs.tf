output "tee_proxy_external_ip" {
  description = "External IP address of the tee-proxy VM"
  value       = google_compute_address.tee_proxy_ip.address
}

output "tee_proxy_external_endpoint" {
  description = "External endpoint for tee-proxy"
  value       = "http://${google_compute_address.tee_proxy_ip.address}:${local.external_port}"
}

output "tee_proxy_internal_endpoint" {
  description = "Internal endpoint for tee-proxy"
  value       = "http://${google_compute_instance.tee_proxy.network_interface[0].network_ip}:${local.internal_port}"
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

output "tee_proxy_instance_name" {
  description = "Instance name of tee-proxy, for `gcloud compute ssh --tunnel-through-iap` and for the -replace address the redeploy scripts use"
  value       = google_compute_instance.tee_proxy.name
}

output "redis_host" {
  description = "Private IP of the Memorystore instance tee-proxy queues through. Needed by scripts/flush-redis.sh - it is not reachable from outside the VPC, so flushing means going through tee-proxy."
  value       = google_redis_instance.tee_proxy_redis.host
}

output "redis_port" {
  description = "Port of the Memorystore instance tee-proxy queues through"
  value       = google_redis_instance.tee_proxy_redis.port
}
