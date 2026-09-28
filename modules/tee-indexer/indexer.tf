locals {
  # Pinned deliberately. The `:main` tag this used to carry floats, and it
  # crossed a major version on 2026-08-18 (v2.0.0) - two applies of the same
  # commit either side of that date would deploy different indexers with
  # nothing in the plan to say so.
  indexer_image = "ghcr.io/flare-foundation/flare-system-c-chain-indexer:v2.0.2"

  # v2's readiness endpoint: 503 while startup catchup runs, 200 once
  # continuous indexing begins.
  health_port = 8080

  # Schema per flare-foundation/flare-system-c-chain-indexer's
  # internal/config/config.go (TOML, not YAML - the binary's default is a
  # relative ./config.toml, which its Dockerfile's WORKDIR /app makes
  # /app/config.toml, hence the mount path below). We stay on the default
  # `mode = "full"`; v2's fsp mode would index selectively from on-chain reward
  # epochs, but its built-in collectors do not cover the two transaction
  # filters tee-proxy reads, so switching needs a live verification first.
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
    drop_table_at_start   = var.drop_table_at_start
    machine_path_manager  = var.machine_path_manager
  })

  # systemd unit that runs the indexer container, replacing the Konlet
  # `gce-container-declaration` metadata key - see the equivalent comment in
  # modules/tee-package/proxy-server.tf for why that key is gone.
  tee_indexer_service = <<-EOT
    [Unit]
    Description=tee-indexer
    Requires=docker.service
    After=docker.service network-online.target
    Wants=network-online.target

    [Service]
    Restart=always
    RestartSec=5
    ExecStartPre=-/usr/bin/docker rm -f tee-indexer
    ExecStartPre=/usr/bin/docker pull ${local.indexer_image}
    ExecStart=/usr/bin/docker run --rm --name tee-indexer \
      --publish ${local.health_port}:${local.health_port} \
      --volume /etc/tee-indexer/config.toml:/app/config.toml:ro \
      ${local.indexer_image}
    ExecStop=/usr/bin/docker stop tee-indexer

    [Install]
    WantedBy=multi-user.target
  EOT

  # Cloud-init writes the config and the unit, then starts it. write_files
  # always completes before runcmd, so the bind-mount source exists before
  # `docker run` reads it.
  cloud_config = <<-EOT
    #cloud-config
    write_files:
    - path: /etc/tee-indexer/config.toml
      permissions: '0644'
      owner: root
      encoding: b64
      content: ${base64encode(local.config_toml)}
    - path: /etc/systemd/system/tee-indexer.service
      permissions: '0644'
      owner: root
      encoding: b64
      content: ${base64encode(local.tee_indexer_service)}

    runcmd:
    - systemctl daemon-reload
    - systemctl enable --now tee-indexer.service
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
    user-data = local.cloud_config
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
