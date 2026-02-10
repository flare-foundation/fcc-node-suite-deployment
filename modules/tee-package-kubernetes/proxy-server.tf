locals {
  config_toml = templatefile("${path.module}/templates/tee-proxy/config.toml.tftpl", {
    # redis_host = google_redis_instance.tee_proxy_redis.host
    # redis_port = google_redis_instance.tee_proxy_redis.port
    redis_host = "test_redis_host"
    redis_port = 1234
    # indexer_host              = var.tee_indexer_database.hostname
    # indexer_port              = var.tee_indexer_database.port
    # indexer_database_name     = var.tee_indexer_database.databaseName
    # indexer_database_user     = var.tee_indexer_database.user
    # indexer_database_password = var.tee_indexer_database.password
    indexer_host              = "Test"
    indexer_port              = 4200
    indexer_database_name     = "Test"
    indexer_database_user     = "Test"
    indexer_database_password = "Test"
    internal_port             = 6661
    external_port             = 6662
  })

  # Konlet container declaration for Container-Optimized OS
  container_declaration = <<-EOT
    spec:
      containers:
      - name: tee-proxy
        image: ${var.tee_proxy_docker_image}
        stdin: false
        tty: false
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

# Grant service account permission to pull Docker images from Artifact Registry
# Note: This requires the repository to exist. If Terraform fails with permission errors,
# run this gcloud command manually:
# gcloud artifacts repositories add-iam-policy-binding containers \
#   --location=europe-west1 \
#   --member="serviceAccount:${var.service_account_email}" \
#   --role="roles/artifactregistry.reader"
resource "google_artifact_registry_repository_iam_member" "proxy_artifact_registry_reader" {
  project    = var.project
  location   = "europe-west1"
  repository = "containers"
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.service_account_email}"
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
    network = google_compute_network.tee_network.self_link
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
  network       = google_compute_network.tee_network.self_link
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

# Firewall rule for tee-proxy internal port (6661) - only from within VPC
resource "google_compute_firewall" "allow_tee_proxy_internal" {
  name          = join("-", compact(["allow-tee-proxy-internal", var.deploy_suffix]))
  network       = google_compute_network.tee_network.self_link
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["10.128.0.0/9"] # GCP internal ranges
  target_tags   = ["tee-proxy"]

  allow {
    protocol = "tcp"
    ports    = ["6661"]
  }

  description = "Allow internal port 6661 for tee-proxy from VPC"
}

# Firewall rule for SSH access to tee-proxy (debug mode)
resource "google_compute_firewall" "allow_tee_proxy_ssh" {
  name          = join("-", compact(["allow-tee-proxy-ssh", var.deploy_suffix]))
  network       = google_compute_network.tee_network.self_link
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["tee-proxy"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  description = "Allow SSH access to tee-proxy for debugging"
}

# IAM permissions for the proxy VM
resource "google_compute_instance_iam_member" "gitlab_ci_admin_tee_proxy" {
  project       = var.project
  zone          = var.zone
  instance_name = google_compute_instance.tee_proxy.name
  role          = "roles/compute.instanceAdmin.v1"
  member        = "serviceAccount:${var.service_account_email}"
}
