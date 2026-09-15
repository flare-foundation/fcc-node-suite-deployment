# tee-package

Stands up a single tee-node package on GCP:

- **tee-machine**: a Confidential Space GCE VM running the workload image
  (`tee_node_docker_image`).
- **tee-proxy**: a Container-Optimized-OS GCE VM that brokers between
  tee-machine and the outside world - reads chain state via the
  `tee-indexer` database, caches via Memorystore Redis, and persists its
  own state to a GCS bucket this module creates.

No Kubernetes cluster required - both are plain GCE VMs.

## Prerequisites

- A GCP project and VPC network (self-link) already created.
- A service account with permission to run Confidential Space VMs, and
  access to Secret Manager, Cloud SQL, GCS, and Memorystore in the project.
- A `tee_indexer_database` value - normally `module.tee_indexer.database_config`
  from the sibling `tee-indexer` module.
- A tee-proxy signing private key you generate/manage yourself with
  `/scripts/generate-key.sh`. Its address is also this package's
  `initial_owner` - one keypair, two variables.

## Notable defaults

`chain_id`, `flare_systems_manager`, `relay`, and `voter_registry` default
to Coston2's current values. If you're deploying against a different Flare
network (or the same network after a contract redeploy), override them.
Check they are still current before relying on them; contract redeploys
happen and these values are a snapshot.

`tee_machine_debug_mode` (default `false`) adds a public IP + SSH/node-exporter
access to tee-machine and SSH access to tee-proxy - useful when standing
this up for the first time, turn it off once you've confirmed it works.
