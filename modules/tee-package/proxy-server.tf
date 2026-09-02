locals {
  config_toml = templatefile("${path.module}/templates/tee-proxy/config.toml.tftpl", {
    redis_host                = google_redis_instance.tee_proxy_redis.host
    redis_port                = google_redis_instance.tee_proxy_redis.port
    indexer_host              = var.tee_indexer_database.hostname
    indexer_port              = var.tee_indexer_database.port
    indexer_database_name     = var.tee_indexer_database.databaseName
    indexer_database_user     = var.tee_indexer_database.user
    indexer_database_password = var.tee_indexer_database.password
    internal_port             = 6661
    external_port             = 6662
    chain_id                  = var.chain_id
    flare_systems_manager     = var.flare_systems_manager
    relay                     = var.relay
    voter_registry            = var.voter_registry
    gcs_bucket                = google_storage_bucket.tee_proxy.name
    gcs_prefix                = var.deploy_suffix
  })

  # Konlet container declaration for Container-Optimized OS
  container_declaration = <<-EOT
    spec:
      containers:
      - name: tee-proxy
        image: ${var.tee_proxy_docker_image}
        stdin: false
        tty: false
        env:
        - name: PRIVATE_KEY
          value: ${var.tee_proxy_private_key}
        ports:
        - containerPort: 6661
          hostPort: 6661
        - containerPort: 6662
          hostPort: 6662
        volumeMounts:
        - mountPath: /app/config/config.toml
          name: config
          readOnly: true
      volumes:
      - name: config
        hostPath:
          path: /etc/tee-proxy/config.toml
      restartPolicy: Always
  EOT

  # Cloud-init configuration to write the config file
  cloud_config = <<-EOT
    #cloud-config
    write_files:
    - path: /etc/tee-proxy/config.toml
      permissions: 0644
      owner: root
      encoding: b64
      content: ${base64encode(local.config_toml)}
  EOT
}

resource "google_secret_manager_secret" "config" {
  secret_id = "tee-proxy-config-${var.deploy_suffix}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "config" {
  secret      = google_secret_manager_secret.config.id
  secret_data = local.config_toml
}

resource "google_secret_manager_secret_iam_member" "proxy_config_access" {
  secret_id = google_secret_manager_secret.config.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service_account_email}"
}

# tee-proxy's signing key. Stored here for auditability/rotation even though
# it also ends up in plain-text instance metadata below (Konlet has no other
# way to pass container env vars, and tee-proxy runs on a plain COS VM rather
# than inside Confidential Space, so there's no attestation-based secret
# unwrapping available to it either).
resource "google_secret_manager_secret" "proxy_private_key" {
  secret_id = "tee-proxy-private-key-${var.deploy_suffix}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "proxy_private_key" {
  secret      = google_secret_manager_secret.proxy_private_key.id
  secret_data = var.tee_proxy_private_key
}

resource "google_secret_manager_secret_iam_member" "proxy_private_key_access" {
  secret_id = google_secret_manager_secret.proxy_private_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service_account_email}"
}

# Static IP for tee-proxy VM
resource "google_compute_address" "tee_proxy_ip" {
  name   = join("-", compact(["tee-proxy-ip", var.deploy_suffix]))
  region = var.region
}

# Container-Optimized OS VM for tee-proxy
resource "google_compute_instance" "tee_proxy" {
  name         = join("-", compact(["tee-proxy", var.deploy_suffix]))
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
    access_config {
      nat_ip = google_compute_address.tee_proxy_ip.address
    }
  }

  tags = ["tee-proxy"]

  metadata = {
    gce-container-declaration = local.container_declaration
    user-data                 = local.cloud_config
  }
}

# Firewall rule for tee-proxy external port (6662)
resource "google_compute_firewall" "allow_tee_proxy_external" {
  name          = join("-", compact(["allow-tee-proxy-external", var.deploy_suffix]))
  network       = var.network
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["tee-proxy"]

  allow {
    protocol = "tcp"
    ports    = ["6662"]
  }

  description = "Allow external port 6662 for tee-proxy"
}

# Firewall rule for tee-proxy internal port (6661) - only from tee-machine
resource "google_compute_firewall" "allow_tee_proxy_internal" {
  name          = join("-", compact(["allow-tee-proxy-internal", var.deploy_suffix]))
  network       = var.network
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["${google_compute_instance.tee_machine.network_interface[0].network_ip}/32"]
  target_tags   = ["tee-proxy"]

  allow {
    protocol = "tcp"
    ports    = ["6661"]
  }

  description = "Allow internal port 6661 for tee-proxy from tee-machine only"
}

# Firewall rule for SSH access to tee-proxy (debug mode)
resource "google_compute_firewall" "allow_tee_proxy_ssh" {
  count = var.tee_machine_debug_mode ? 1 : 0

  name      = join("-", compact(["allow-tee-proxy-ssh", var.deploy_suffix]))
  network   = var.network
  direction = "INGRESS"
  priority  = 1000
  # Google's IAP TCP-forwarding range, not 0.0.0.0/0 - see allow_tee_machine_ports
  # in tee-machine.tf for why.
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["tee-proxy"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  description = "Allow SSH access to tee-proxy for debugging in debug mode, via IAP only"
}
