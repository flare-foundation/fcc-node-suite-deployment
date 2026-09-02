locals {
  # Schema per flarenetwork/flare-system-c-chain-indexer's internal/config/config.go
  # (TOML, not YAML - the binary's default is a relative ./config.toml, which
  # its Dockerfile's WORKDIR /app makes /app/config.toml, hence the mount path
  # below).
  config_toml = templatefile("${path.module}/templates/indexer/config.toml.tftpl", {
    chain_rpc_endpoint    = var.chain_rpc_endpoint
    db_host               = local.db_host
    db_user               = local.db_username
    db_pass               = random_password.db_admin.result
    flare_systems_manager = var.flare_systems_manager
    relay                 = var.relay
    voter_registry        = var.voter_registry
    start_index           = var.start_index
    history_drop_seconds  = var.history_drop_seconds
  })

  # Konlet container declaration for Container-Optimized OS
  container_declaration = <<-EOT
    spec:
      containers:
      - name: tee-indexer
        image: ghcr.io/flare-foundation/flare-system-c-chain-indexer:main
        stdin: false
        tty: false
        volumeMounts:
        - mountPath: /app/config.toml
          name: config
          readOnly: true
      volumes:
      - name: config
        hostPath:
          path: /etc/tee-indexer/config.toml
      restartPolicy: Always
  EOT

  # Cloud-init configuration to write the config file
  cloud_config = <<-EOT
    #cloud-config
    write_files:
    - path: /etc/tee-indexer/config.toml
      permissions: 0644
      owner: root
      encoding: b64
      content: ${base64encode(local.config_toml)}
  EOT
}

# Static IP for tee-indexer VM (optional, for debugging)
resource "google_compute_address" "tee_indexer_ip" {
  name   = join("-", compact(["tee-indexer-ip", var.cli ? "cli" : "", var.deploy_suffix]))
  region = var.region
  count  = var.cli ? 1 : 0
}

# Container-Optimized OS VM for tee-indexer
resource "google_compute_instance" "tee_indexer" {
  name         = join("-", compact(["tee-indexer", var.cli ? "cli" : "", var.deploy_suffix]))
  zone         = var.zone
  machine_type = "e2-medium"

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "projects/cos-cloud/global/images/family/cos-stable"
    }
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  network_interface {
    network = var.network
    dynamic "access_config" {
      for_each = var.cli ? google_compute_address.tee_indexer_ip : []
      content {
        nat_ip = access_config.value.address
      }
    }
  }

  tags = var.cli ? ["tee-indexer-cli"] : ["tee-indexer"]

  metadata = {
    gce-container-declaration = local.container_declaration
    user-data                 = local.cloud_config
  }
}

# Firewall rule for SSH access to tee-indexer, cli mode or not - via IAP only,
# same as the debug-mode SSH rules in tee-package (see tee-machine.tf there).
resource "google_compute_firewall" "allow_tee_indexer_ssh" {
  name          = join("-", compact(["allow-tee-indexer-ssh", var.deploy_suffix]))
  network       = var.network
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["tee-indexer", "tee-indexer-cli"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  description = "Allow SSH access to tee-indexer for debugging, via IAP only"
}

# IAM permissions for the indexer VM
resource "google_compute_instance_iam_member" "admin_tee_indexer" {
  project       = var.project
  zone          = var.zone
  instance_name = google_compute_instance.tee_indexer.name
  role          = "roles/compute.instanceAdmin.v1"
  member        = "serviceAccount:${var.service_account_email}"
}
