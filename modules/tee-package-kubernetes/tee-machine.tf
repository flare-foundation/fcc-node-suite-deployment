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
  machine_type = var.tee_machine_type

  # Enable Confidential VM
  confidential_instance_config {
    enable_confidential_compute = true
  }

  # Set the maintenance policy
  scheduling {
    on_host_maintenance = "TERMINATE"
    automatic_restart   = false
  }

  # Enable Shielded VM options
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

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
    network = google_compute_network.tee_network.self_link
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
    # "tee-env-PROXY_URL"            = "http://${trimsuffix(google_dns_record_set.internal_dns_record.name, ".")}"
    "tee-env-INITIAL_OWNER" = var.initial_owner
    "tee-env-EXTENSION_ID"  = var.extension_id
  }
  # Metadata documentation: https://cloud.google.com/confidential-computing/confidential-space/docs/reference/metadata-variables
}

resource "google_compute_instance_iam_member" "gitlab_ci_admin_tee_machine" {
  project       = "flare-network-staging"
  zone          = var.zone
  instance_name = google_compute_instance.tee_machine.name
  role          = "roles/compute.instanceAdmin.v1"
  member        = "serviceAccount:${var.deploy_account_email}"
}

resource "google_compute_firewall" "allow_tee_machine_ports" {
  name          = join("-", compact(["allow-tee-machine-ports", var.deploy_suffix]))
  network       = google_compute_network.tee_network.self_link
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["tee-machine-debug"]

  //Enable only in debug
  count = var.tee_machine_debug_mode ? 1 : 0

  allow {
    protocol = "tcp"
    ports = [
      # Node exporter
      9100
    ]
  }

  description = "Allow port 9100 to tee-machine tagged instances"
}

resource "google_service_account_iam_member" "deployer_sa_user" {
  service_account_id = "projects/flare-network-staging/serviceAccounts/confidential-sa@flare-network-staging.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.deploy_account_email}"
}
