locals {
  # tee-proxy's two listening ports, stated once. The rendered config, the
  # systemd unit and the firewall rules below all read them, and tee-machine.tf
  # builds its PROXY_URL from local.internal_port.
  internal_port = 6661
  external_port = 6662

  config_toml = templatefile("${path.module}/templates/tee-proxy/config.toml.tftpl", {
    redis_host                = google_redis_instance.tee_proxy_redis.host
    redis_port                = google_redis_instance.tee_proxy_redis.port
    indexer_host              = var.tee_indexer_database.hostname
    indexer_port              = var.tee_indexer_database.port
    indexer_database_name     = var.tee_indexer_database.databaseName
    indexer_database_user     = var.tee_indexer_database.user
    indexer_database_password = var.tee_indexer_database.password
    internal_port             = local.internal_port
    external_port             = local.external_port
    chain_id                  = var.chain_id
    flare_systems_manager     = var.flare_systems_manager
    relay                     = var.relay
    voter_registry            = var.voter_registry
    gcs_bucket                = google_storage_bucket.tee_proxy.name
    gcs_prefix                = var.deploy_suffix
    # "" means "no machine-path-list service"; tee-proxy spells that as the
    # zero address rather than an absent key.
    machine_path_manager   = var.machine_path_manager == "" ? "0x0000000000000000000000000000000000000000" : var.machine_path_manager
    governance_signers     = var.governance_signers
    governance_threshold   = var.governance_threshold
    governance_safe        = var.governance_safe
    governance_tee_manager = var.governance_tee_manager
  })

  # PRIVATE_KEY reaches the container through a 0600 EnvironmentFile rather
  # than the unit itself, so it is not visible in `systemctl cat tee-proxy`
  # or in the process table.
  tee_proxy_env = <<-EOT
    PRIVATE_KEY=${var.tee_proxy_private_key}
  EOT

  # systemd unit that runs the tee-proxy container. This replaces the Konlet
  # `gce-container-declaration` metadata key, which GCE stopped accepting on
  # 2026-07-31 ("the option to deploy a container during VM instance creation
  # that relies on a container startup agent is discontinued"). Instances
  # created before then keep running, so the breakage only shows up on the
  # first apply into a project that has none.
  # https://docs.cloud.google.com/compute/docs/containers/migrate-containers
  #
  # Ports are published with --publish rather than --network host, as Konlet
  # did: COS runs its iptables INPUT chain with policy DROP, so a host-networked
  # listener is reachable on localhost but not from tee-machine or the internet.
  #
  # The images this module is pointed at are public (ghcr.io), so `docker pull`
  # needs no credentials. A private Artifact Registry image would need an
  # `ExecStartPre=/usr/bin/docker-credential-gcr configure-docker --registries=...`
  # ahead of the pull - Konlet handled registry auth for us.
  tee_proxy_service = <<-EOT
    [Unit]
    Description=tee-proxy
    Requires=docker.service
    After=docker.service network-online.target
    Wants=network-online.target

    [Service]
    Restart=always
    RestartSec=5
    EnvironmentFile=/etc/tee-proxy/tee-proxy.env
    ExecStartPre=-/usr/bin/docker rm -f tee-proxy
    ExecStartPre=/usr/bin/docker pull ${var.tee_proxy_docker_image}
    ExecStart=/usr/bin/docker run --rm --name tee-proxy \
      --env PRIVATE_KEY \
      --publish ${local.internal_port}:${local.internal_port} \
      --publish ${local.external_port}:${local.external_port} \
      --volume /etc/tee-proxy/config.toml:/app/config/config.toml:ro \
      ${var.tee_proxy_docker_image}
    ExecStop=/usr/bin/docker stop tee-proxy

    [Install]
    WantedBy=multi-user.target
  EOT

  # Cloud-init writes the config, the key and the unit, then starts it. All
  # three go in base64 so nothing in the rendered values can break the YAML.
  #
  # write_files always completes before runcmd, which is what guarantees the
  # bind-mount source exists before `docker run` reads it. Under Konlet the two
  # raced, and losing that race left Docker to create /etc/tee-proxy/config.toml
  # as an empty directory instead ("read config.toml: is a directory").
  cloud_config = <<-EOT
    #cloud-config
    write_files:
    - path: /etc/tee-proxy/config.toml
      permissions: '0644'
      owner: root
      encoding: b64
      content: ${base64encode(local.config_toml)}
    - path: /etc/tee-proxy/tee-proxy.env
      permissions: '0600'
      owner: root
      encoding: b64
      content: ${base64encode(local.tee_proxy_env)}
    - path: /etc/systemd/system/tee-proxy.service
      permissions: '0644'
      owner: root
      encoding: b64
      content: ${base64encode(local.tee_proxy_service)}

    runcmd:
    - systemctl daemon-reload
    - systemctl enable --now tee-proxy.service
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
# the VM gets it from instance metadata instead: the cloud-init above carries
# it into a 0600 EnvironmentFile, but user-data is itself plain-text metadata,
# so that narrows who can read the file on disk without making the key any less
# visible to anyone with compute.instances.get. tee-proxy runs on a plain COS
# VM rather than inside Confidential Space, so there is no attestation-based
# secret unwrapping available to it either.
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
    user-data = local.cloud_config
  }
}

# Firewall rule for tee-proxy's external port
resource "google_compute_firewall" "allow_tee_proxy_external" {
  name          = join("-", compact(["allow-tee-proxy-external", var.deploy_suffix]))
  network       = var.network
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["tee-proxy"]

  allow {
    protocol = "tcp"
    ports    = [local.external_port]
  }

  description = "Allow external port ${local.external_port} for tee-proxy"
}

# Firewall rule for tee-proxy's internal port - only from tee-machine
resource "google_compute_firewall" "allow_tee_proxy_internal" {
  name          = join("-", compact(["allow-tee-proxy-internal", var.deploy_suffix]))
  network       = var.network
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["${google_compute_instance.tee_machine.network_interface[0].network_ip}/32"]
  target_tags   = ["tee-proxy"]

  allow {
    protocol = "tcp"
    ports    = [local.internal_port]
  }

  description = "Allow internal port ${local.internal_port} for tee-proxy from tee-machine only"
}

# Firewall rule for operator SSH access to tee-proxy.
#
# Deliberately not gated on tee_machine_debug_mode. tee-proxy is a plain COS VM
# with no attestation posture to protect, and coupling the two meant turning off
# debug on the Confidential Space VM also removed the only way to reach the
# proxy - which bites exactly when you need it, since a restarted tee-machine
# leaves tee-proxy serving its cached payload and never re-pairing.
resource "google_compute_firewall" "allow_tee_proxy_ssh" {
  count = var.allow_tee_proxy_ssh ? 1 : 0

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

  description = "Allow operator SSH access to tee-proxy, via IAP only"
}
