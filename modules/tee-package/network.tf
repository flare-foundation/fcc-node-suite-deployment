# ICMP between this package's VMs, for debugging connectivity. TCP is opened
# per port by the tag-scoped rules in proxy_server.tf and tee_machine.tf.
resource "google_compute_firewall" "internal_allow" {
  name    = "allow-internal-${var.deploy_suffix}"
  network = var.network

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.128.0.0/9"] # GCP default auto-created subnet range
  target_tags   = ["tee-proxy", "tee-machine", "tee-machine-debug"]
  description   = "Allow ICMP to tee-machine and tee-proxy from inside the network"
}
