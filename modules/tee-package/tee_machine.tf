locals {
  tee_instance_image_family = var.tee_machine_debug_mode ? "confidential-space-debug" : "confidential-space"
}

resource "google_compute_instance" "tee_machine" {
  name         = join("-", compact(["tee-machine", var.deploy_suffix]))
  zone         = var.zone
  machine_type = var.tee_machine_type

  depends_on = [google_compute_instance.tee_proxy]

  # Without this, GCP boots a normal VM that happens to run the
  # confidential-space image - the launcher inside then fails attestation
  # (RIM_VALIDATION_FAILED) because the hardware was never actually enabled
  # for AMD SEV. This is what makes it a genuine Confidential VM.
  confidential_instance_config {
    enable_confidential_compute = true
  }

  # Confidential VMs can't live-migrate.
  scheduling {
    on_host_maintenance = "TERMINATE"
    automatic_restart   = false
  }

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
    network = var.network
    # No external IP, even in debug mode - debug access is via IAP TCP
    # forwarding (see allow_tee_machine_ports below), not a public address.
  }

  tags = var.tee_machine_debug_mode ? ["tee-machine-debug"] : ["tee-machine"]

  # tee-node reads the GOVERNANCE_* vars only when they are present, so the
  # optional ones are merged in rather than set to "" - an empty value is not
  # the same as an absent one. tee-node's Dockerfile already lists all four in
  # tee.launch_policy.allow_env_override, so no launch-policy change is needed.
  metadata = merge({
    # Only the debug image runs sshd at all. There, accept only keys on the
    # instance itself, not project-wide ones.
    block-project-ssh-keys = true

    startup-script = var.tee_machine_debug_mode ? templatefile("${path.module}/templates/tee_machine_debug_init.sh", {}) : ""

    "tee-image-reference" = var.tee_node_docker_image
    # https://cloud.google.com/confidential-computing/confidential-space/docs/reference/launch-policies#allow-env-override:~:text=tee.launch_policy.log_redirect
    "tee-container-log-redirect"   = var.tee_machine_debug_mode # Only allowed in debug
    "tee-monitoring-memory-enable" = var.tee_machine_debug_mode
    "tee-env-LOG_LEVEL"            = "INFO"
    "tee-env-PROXY_URL"            = "http://${google_compute_instance.tee_proxy.network_interface[0].network_ip}:${local.internal_port}"
    "tee-env-INITIAL_OWNER"        = var.initial_owner
    "tee-env-EXTENSION_ID"         = var.extension_id
    # tee-node signs every action result (and vote-hash/backup signing) with
    # this bound in - "signing fails closed" if it's unset, since Sign()
    # requires ChainID() to succeed first. Must match var.chain_id used for
    # tee-proxy's own config below.
    "tee-env-CHAIN_ID" = var.chain_id
    },
    length(var.governance_signers) == 0 ? {} : {
      "tee-env-GOVERNANCE_SIGNERS"   = join(",", var.governance_signers)
      "tee-env-GOVERNANCE_THRESHOLD" = var.governance_threshold
    },
    var.governance_safe == "" ? {} : {
      "tee-env-GOVERNANCE_SAFE"        = var.governance_safe
      "tee-env-GOVERNANCE_TEE_MANAGER" = var.governance_tee_manager
    },
    # Extension-specific settings, e.g. SHIELDED_VAULT / KYC_WHITELIST for the
    # shielded-transfers extension. The workload image's launch policy has to
    # allow each one by name or Confidential Space drops it silently.
    { for k, v in var.extension_env : "tee-env-${k}" => v }
  )
  # Metadata documentation: https://cloud.google.com/confidential-computing/confidential-space/docs/reference/metadata-variables

  # `gcloud compute ssh` adds its key to the instance - see tee_proxy.
  lifecycle {
    ignore_changes = [metadata["ssh-keys"]]
  }
}

resource "google_compute_firewall" "allow_tee_machine_ports" {
  name      = join("-", compact(["allow-tee-machine-ports", var.deploy_suffix]))
  network   = var.network
  direction = "INGRESS"
  priority  = 1000
  # Google's IAP TCP-forwarding range, not 0.0.0.0/0 - tee-machine has no
  # external IP, so SSH/metrics access only ever happens through an IAP
  # tunnel (`gcloud compute ssh --tunnel-through-iap`), never the open
  # internet. The connecting identity also needs roles/iap.tunnelResourceAccessor.
  source_ranges = ["35.235.240.0/20"]
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

  description = "Allow SSH (22) and node exporter (9100) to tee-machine tagged instances in debug mode, via IAP only"
}
