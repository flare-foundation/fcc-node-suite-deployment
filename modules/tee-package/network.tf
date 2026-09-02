# Allow internal communication between VMs in the network
resource "google_compute_firewall" "internal_allow" {
  name    = "allow-internal-${var.deploy_suffix}"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["6661", "6662"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.128.0.0/9"] # GCP default auto-created subnet range
  description   = "Allow internal communication between tee-machine and tee-proxy"
}
