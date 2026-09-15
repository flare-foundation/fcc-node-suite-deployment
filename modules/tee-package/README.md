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

`tee_machine_debug_mode` (default `false`) switches tee-machine to the
`confidential-space-debug` image and opens SSH/node-exporter to it over IAP,
plus container log redirection - useful when standing this up for the first
time, turn it off once you've confirmed it works. (It does *not* add a public
IP: tee-machine has none in either mode, by design.)

## Governance

Registering a machine needs at least `governance_signers` and
`governance_threshold`; without them tee-node has nothing to check a signed
`SET_MACHINE_PATH_LIST` against and rejects every list update. They reach
tee-node as `tee-env-GOVERNANCE_*` metadata, which its launch policy already
permits.

Setting any of them also requires `machine_path_manager` — tee-proxy rejects a
`[governance]` block whose `addresses.machine_path_manager` is the zero
address, since the block exists only for the machine-path service.

`governance_safe` + `governance_tee_manager` are for Safe-backed governance,
where a Safe's `approveMachinePathList` transaction authorizes a list instead
of direct signatures. Set both or neither. For direct-signature governance
leave them empty: tee-proxy recovers the on-chain signatures itself, and
`signers`/`threshold` alone just enable a startup cross-check of the
governance hash against the node's attested one.

All the pairing and bounds rules are enforced as variable validations, so a
bad combination fails at `terraform plan` rather than at container start.
