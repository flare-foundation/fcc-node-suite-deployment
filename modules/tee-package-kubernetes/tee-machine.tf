locals {
  tee_instance_image_family = var.tee_machine_debug_mode ? "confidential-space-debug" : "confidential-space"
}

resource "google_compute_address" "tee_machine_ip" {
  name   = join("-", compact(["tee-machine-ip", var.deploy_suffix]))
  region = var.region

  //Enable only in debug
  count = var.tee_machine_debug_mode ? 1 : 0
}
resource "google_compute_instance" "tee_machine" {
  name         = join("-", compact(["tee-machine", var.deploy_suffix]))
  zone         = var.zone
  machine_type = "c3d-standard-4"

  depends_on = [google_compute_instance.tee_proxy]

  # Image details
  boot_disk {
    initialize_params {
      image = "projects/confidential-space-images/global/images/family/${local.tee_instance_image_family}"
    }
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  network_interface {
    network = var.network
    dynamic "access_config" {
      for_each = google_compute_address.tee_machine_ip
      content {
        nat_ip = access_config.value.address
      }
    }
  }

  tags = var.tee_machine_debug_mode ? ["tee-machine-debug"] : ["tee-machine"]

  metadata = {
    startup-script = var.tee_machine_debug_mode ? templatefile("${path.module}/templates/tee-machine-debug-init.sh", {}) : ""

    "tee-image-reference" = var.tee_docker_image
    # https://cloud.google.com/confidential-computing/confidential-space/docs/reference/launch-policies#allow-env-override:~:text=tee.launch_policy.log_redirect
    "tee-container-log-redirect"   = var.tee_machine_debug_mode # Only allowed in debug
    "tee-monitoring-memory-enable" = var.tee_machine_debug_mode
    "tee-env-LOG_LEVEL"            = "INFO"
    "tee-env-PROXY_URL"            = "http://${google_compute_instance.tee_proxy.network_interface[0].network_ip}:6661"
    "tee-env-INITIAL_OWNER"        = var.initial_owner
    "tee-env-EXTENSION_ID"         = var.extension_id
  }
  # Metadata documentation: https://cloud.google.com/confidential-computing/confidential-space/docs/reference/metadata-variables
}

resource "google_compute_instance_iam_member" "gitlab_ci_admin_tee_machine" {
  project       = var.project
  zone          = var.zone
  instance_name = google_compute_instance.tee_machine.name
  role          = "roles/compute.instanceAdmin.v1"
  member        = "serviceAccount:${var.deploy_account_email}"
}

resource "google_compute_firewall" "allow_tee_machine_ports" {
  name          = join("-", compact(["allow-tee-machine-ports", var.deploy_suffix]))
  network       = var.network
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["tee-machine-debug"]

  //Enable only in debug
  count = var.tee_machine_debug_mode ? 1 : 0

  allow {
    protocol = "tcp"
    ports = [
      # SSH
      22,
      # Node exporter
      9100
    ]
  }

  description = "Allow SSH (22) and node exporter (9100) to tee-machine tagged instances in debug mode"
}

resource "google_service_account_iam_member" "deployer_sa_user" {
  service_account_id = "projects/flare-network-staging/serviceAccounts/confidential-sa@flare-network-staging.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.deploy_account_email}"
}
