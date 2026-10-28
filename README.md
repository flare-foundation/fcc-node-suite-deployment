# tee-node-suite-deployment

Terraform to stand up your own [Flare tee-node](https://flare.network/) on a
GCP project you control. Point it at your project, fill in a handful of
values, and `terraform apply` gives you a working tee-machine, tee-proxy,
and chain indexer — no Kubernetes cluster required.

## What you'll end up with

- **tee-machine** — a Confidential Space VM that runs your workload image
  under hardware-backed attestation
- **tee-proxy** — brokers between tee-machine and the outside world
- **tee-indexer** — indexes the chain data tee-proxy needs, into its own
  Cloud SQL database
- Supporting pieces created for you: a Redis cache, a GCS bucket for
  tee-proxy's storage, and the networking that wires it all together

## Before you start

You'll need:

1. **A GCP project** with billing enabled.
2. **The `gcloud` CLI**, authenticated (`gcloud auth application-default login`)
   against that project.
3. **[Terraform](https://developer.hashicorp.com/terraform/install)**, `>1.11`.
   The envs keep state in a local `terraform.tfstate`, and that state holds
   the tee-proxy key and the database passwords in plain text. For anything
   beyond a throwaway test, add a `gcs` backend to the env's `terraform.tf`,
   pointing at a bucket with versioning on and access limited to whoever
   deploys. Terraform does not create that bucket for you: the state has to
   exist before the first `apply`.
4. **A service account** in that project for the VMs to run as. It needs:
   - `roles/confidentialcomputing.workloadUser` — without it tee-machine's
     workload cannot attest and exits.
   - `roles/logging.logWriter` and `roles/monitoring.metricWriter` — for
     tee-machine's log redirection and memory monitoring in debug mode, and
     for the COS VMs' own logs and metrics.
   - `roles/artifactregistry.reader` on the repository, if your images live
     in Artifact Registry rather than a public registry.

   The module grants it access to tee-proxy's GCS bucket itself.
5. **Permission to deploy.** Whoever runs `terraform` needs project Editor
   (`roles/editor`) plus `roles/iam.serviceAccountUser` on the service account
   above, to attach it to the VMs. That is enough on purpose: the modules
   avoid resources Editor cannot manage, such as Secret Manager secret
   versions and project or instance IAM bindings - which is also why the
   service account above is an input rather than created here. To SSH in
   (the redeploy and flush scripts do), you also need
   `roles/iap.tunnelResourceAccessor`.
6. **A tee-proxy signing key.** Generate a fresh one with:
   ```
   ./scripts/generate-key.sh
   ```
   This prints an address and private key to your terminal and writes
   nothing to disk — copy both somewhere safe, you'll need them in a minute.

   For anything that holds value:
   - Generate it on a machine you trust, ideally one that is not shared and
     has no remote access. Clear the terminal afterwards.
   - Store the private key in a password manager or secret store straight
     away, not in a file, a chat or a ticket.
   - `terraform.tfvars` holds it in plain text. It is gitignored, but delete
     it once the state is in a remote backend and pass the key with
     `TF_VAR_tee_proxy_private_key` instead.

   `tee_proxy_private_key` is the key from `generate-key.sh`.
   `initial_owner` is the address registered as the machine owner. For
   extension 0 (the stock tee-node image) that is usually the address
   `generate-key.sh` printed. For your own extension it is a separate
   identity: the address your registration tooling registers the machine
   with. `extension_id` is assigned by the chain, and stays all zeros for
   extension 0.
   `governance_signers` and `governance_threshold` are not needed to boot
   the machine, but are needed to register it, extension 0 included. They
   must match the signer set your registration tooling writes with
   `set-governance`. With a single signer, that set is usually
   `initial_owner` alone and the threshold is `1`.

## Setting it up

```
cd envs/example
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and fill in:
- `project` — your GCP project ID
- `service_account_email` — the service account from step 4 above
- `tee_node_docker_image` — the stock tee-node image for extension 0 (the
  default), or your own extension image, pinned by digest
- `tee_proxy_docker_image` — the tee-proxy image
- `tee_proxy_private_key` — the key you just generated
- `initial_owner` — the machine owner address
- `governance_signers` and `governance_threshold` — before you register
  the machine
- `extension_id` and `extension_env` — only for your own extension; leave
  them out for extension 0
- `chain_id` and `chain_rpc_endpoint` — for the Flare network you target
- `flare_systems_manager`, `voter_registry`, `relay`, and
  `machine_path_manager` — protocol contract addresses on that network

`envs/example` is network-agnostic and deploys extension 0 by default.
Concrete filled-in envs such as `envs/coston-sandbox` and
`envs/coston2-sandbox` show what real values look like for a given chain,
and `envs/coston2-shielded-transfers` shows an extension deployment. The
example runs its own indexer; external
indexer settings are commented out in `variables.tf`, `main.tf`, and
`terraform.tfvars.example` so you can switch without rewriting the module
call.

Then:

```
terraform init
terraform apply
```

This takes a few minutes — it's creating a VPC, a Cloud SQL instance, a
Redis instance, and three VMs. When it's done:

```
terraform output tee_proxy_info_url
```

gives you the URL to check that tee-proxy is up and talking to the rest of
the stack.

## If something looks stuck

- **tee-machine has no public IP by design** — even with debug mode on,
  you reach it via `gcloud compute ssh --tunnel-through-iap`, not a
  regular SSH.
- tee-machine logs to its serial console; tee-proxy and tee-indexer each run
  their container from a systemd unit, so `journalctl -u tee-proxy` /
  `journalctl -u tee-indexer` is where their logs are. Start there before
  assuming something's broken.
- `modules/tee-package/README.md` has more detail on what each variable
  does and why the defaults are what they are.
- `TESTING.md` walks through verifying a fresh deployment end to end -
  what a healthy `/info` response looks like, the internal
  `/healthy`/`/startup`/`/ready` checks, where to find logs for each
  component, and a symptom -> cause table.

## Already know which network you want?

`envs/example` is a generic starting point. `envs/coston-sandbox` is a
concrete, filled-in example targeting Coston — a good reference for what
a real set of values looks like, or to copy as a starting point for your
own network-specific env.

## Repo layout

```
modules/
  tee-package/    the tee-machine + tee-proxy module
  tee-indexer/     the chain indexer + its database
envs/
  example/         generic template - bring your own project; extension 0 by default
  coston-sandbox/  concrete example targeting Coston
  coston2-sandbox/ concrete example targeting Coston2
  coston2-shielded-transfers/  extension deployment on Coston2
scripts/
  generate-key.sh       generates a throwaway signing keypair
  redeploy-proxy.sh     replaces tee-proxy (and tee-machine with it)
  redeploy-indexer.sh   replaces tee-indexer, optionally wiping its database
  flush-redis.sh        drains tee-proxy's Redis queue
```

The three redeploy/flush scripts are run from an env directory, e.g.
`cd envs/coston-sandbox && ../../scripts/redeploy-proxy.sh`. A config change
needs one of them rather than a plain `terraform apply`: cloud-init runs only
on first boot and Confidential Space reads its metadata only at boot, so an
updated config on a running VM is never picked up. See `TESTING.md` section 5.
