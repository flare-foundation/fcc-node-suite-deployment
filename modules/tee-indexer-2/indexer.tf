locals {
  config_yaml = templatefile("${path.module}/templates/indexer/config.yaml.tftpl", {
    db_host        = local.db_host
    db_user        = local.db_username
    db_pass        = data.google_secret_manager_secret_version.db_password.secret_data
    db_reader_pass = data.google_secret_manager_secret_version.db_reader_password.secret_data
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
        - mountPath: /app/config/config.yaml
          name: config
          readOnly: true
      volumes:
      - name: config
        hostPath:
          path: /etc/tee-indexer/config.yaml
      restartPolicy: Always
  EOT

  # Cloud-init configuration to write the config file
  cloud_config = <<-EOT
    #cloud-config
    write_files:
    - path: /etc/tee-indexer/config.yaml
      permissions: 0644
      owner: root
      encoding: b64
      content: ${base64encode(local.config_yaml)}
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

# Firewall rule for SSH access to tee-indexer (CLI mode only)
resource "google_compute_firewall" "allow_tee_indexer_ssh" {
  count         = var.cli ? 1 : 0
  name          = join("-", compact(["allow-tee-indexer-ssh", var.deploy_suffix]))
  network       = var.network
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["tee-indexer-cli"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  description = "Allow SSH access to tee-indexer for debugging in CLI mode"
}

# IAM permissions for the indexer VM
resource "google_compute_instance_iam_member" "admin_tee_indexer" {
  project       = var.project
  zone          = var.zone
  instance_name = google_compute_instance.tee_indexer.name
  role          = "roles/compute.instanceAdmin.v1"
  member        = "serviceAccount:${var.service_account_email}"
}
