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
  tee-proxy's storage, and the secrets/networking that wire it all together

## Before you start

You'll need:

1. **A GCP project** with billing enabled.
2. **The `gcloud` CLI**, authenticated (`gcloud auth application-default login`)
   against that project.
3. **[Terraform](https://developer.hashicorp.com/terraform/install)**, `>1.11`.
4. **A service account** in that project for the VMs to run as. It needs
   (at minimum): `roles/confidentialcomputing.workloadUser`,
   `roles/compute.instanceAdmin.v1`, `roles/iam.serviceAccountUser`,
   `roles/secretmanager.admin`, `roles/cloudsql.admin`, `roles/storage.admin`,
   `roles/redis.admin`.
5. **A tee-proxy signing key.** Generate a fresh one with:
   ```
   ./scripts/generate-key.sh
   ```
   This prints an address and private key to your terminal and writes
   nothing to disk — copy both somewhere safe, you'll need them in a minute.

   The two halves belong to **one keypair**, and both go into your tfvars:
   the private key as `tee_proxy_private_key`, and the matching address as
   the package's `initial_owner`. They are not two independent secrets.
   (`initial_owner` is the address tee-node treats as the machine's owner —
   the identity allowed to configure it before any governance is in place.)

   The other identity variable, `extension_id`, is **not** something you
   choose: it is assigned per extension, and identifies which extension this
   machine runs. Leave it at the module default (all zeros) until you have
   been given one — `/info` reporting an all-zero `machineData.extensionId`
   is correct in that case, not a fault.

## Setting it up

```
cd envs/example
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and fill in:
- `project` — your GCP project ID
- `service_account_email` — the service account from step 4 above
- `tee_node_docker_image` — the workload image you want tee-machine to run
- `tee_proxy_docker_image` — the image you want tee-proxy to run
- `tee_proxy_private_key` — the key you just generated

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
  example/         generic template - bring your own project
  coston-sandbox/  concrete example targeting Coston
scripts/
  generate-key.sh  generates a throwaway signing keypair
```
