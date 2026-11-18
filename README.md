<div align="center">
  <a href="https://flare.network/" target="blank">
    <img src="https://content.flare.network/Flare-2.svg" width="300" alt="Flare Logo" />
  </a>
  <br />
  <a href="CONTRIBUTING.md">Contributing</a>
  ·
  <a href="SECURITY.md">Security</a>
  ·
  <a href="CHANGELOG.md">Changelog</a>
</div>

# TEE Node Suite Deployment

Terraform to stand up a Flare TEE node on a Google Cloud project you control.
`terraform apply` gives you a tee-machine, a tee-proxy, and a chain indexer.
No Kubernetes cluster required.

The workload images come from
[tee-node](https://github.com/flare-foundation/tee-node) and
[tee-proxy](https://github.com/flare-foundation/tee-proxy).
The walkthrough for deploying your own extension on Coston2 is
[Deploy an Extension on Google Cloud](https://dev.flare.network/fcc/guides/deploy-on-gcp).
This repository contains the Terraform used in the guide.

## Overview

- **tee-machine** runs the workload image inside a Confidential Space VM.
  It has no public IP. You cannot pass `docker run -e` flags to it. Terraform
  writes each setting as VM metadata named `tee-env-<KEY>`, and the
  Confidential Space launcher turns that into an environment variable at
  start. A key the image does not list in
  `tee.launch_policy.allow_env_override` makes the launcher exit with code
  `4` before the workload starts.
- **tee-proxy** brokers between tee-machine and the outside world. Its
  process listens on `6662`. The host publishes that as port **80**, because
  callers' egress policies often allow only standard ports. Register
  `http://<static-ip>`, not `:6662`.
- **tee-indexer** indexes the chain data tee-proxy needs, into its own
  Cloud SQL database. You can point tee-proxy at an external indexer instead,
  or run it with no indexer, reading a C-chain node's JSON-RPC directly.
- Alongside those: a Redis cache, a GCS bucket for tee-proxy's storage, and
  the VPC and Cloud NAT that give the private VMs a way out.

`envs/example` is a network-agnostic template. It deploys extension `0` (the
stock tee-node image) and runs its own indexer. `chain_id`,
`chain_rpc_endpoint`, the contract addresses, and `deploy_suffix` all come
from `terraform.tfvars`. `envs/coston-sandbox` and `envs/coston2-sandbox` are
filled-in examples. `envs/coston2-shielded-transfers` is an extension
deployment.

## Prerequisites

- A Google Cloud project with billing enabled, and its project ID (for
  example `my-project-123456`). That ID is the `PROJECT_ID` column from
  `gcloud projects list`, and the same value as `project` in
  `terraform.tfvars`. It is not the display name or the project number.
- The [`gcloud` CLI](https://cloud.google.com/sdk/docs/install).
- [Terraform](https://developer.hashicorp.com/terraform/install) `> 1.11`.
- [Python 3](https://www.python.org/downloads/) and
  [uv](https://docs.astral.sh/uv/getting-started/installation/), for
  `scripts/generate-key.sh`. The script uses `uv` when it is installed and
  falls back to a temporary `python3` virtual environment.
- Docker, when the workload image is your own extension, and you build it
  yourself. The stock images are pulled from `ghcr.io`.

The environments keep state in a local `terraform.tfstate`. That state holds
the tee-proxy key and the database passwords in plain text. For anything
beyond a throwaway test, add a `gcs` backend to the environment's
`terraform.tf`, pointing at a bucket with versioning on and access limited
to whoever deploys. Terraform does not create that bucket. The state has to
exist before the first `apply`.

## Set up Google Cloud

Run this once per project. Replace `PROJECT_ID` everywhere below.

The `gcloud` commands use your user credentials. Terraform uses
application-default credentials. The scripts in `scripts/`, such as
`flush-redis.sh`, call `gcloud` without `--project`, so they use the default
project.

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project PROJECT_ID
```

Enable the APIs the stack uses:

```bash
gcloud services enable \
  compute.googleapis.com \
  redis.googleapis.com \
  secretmanager.googleapis.com \
  confidentialcomputing.googleapis.com \
  sqladmin.googleapis.com \
  servicenetworking.googleapis.com \
  iap.googleapis.com \
  --project=PROJECT_ID
```

### Runtime service account

Both VMs run as one service account. It needs
`roles/confidentialcomputing.workloadUser` (the Confidential Space launcher
exits without it), plus log and metric writer. Terraform grants
`roles/storage.objectUser` on the bucket it creates. If the images live in
Artifact Registry rather than a public registry, it also needs
`roles/artifactregistry.reader` on that repository.

If the project already has a service account with these roles, skip creation
and use its email as `service_account_email`. Find it with
`gcloud iam service-accounts list --project=PROJECT_ID`. Granting the roles
requires permission to change the project IAM policy, which shared projects
often restrict.

```bash
gcloud iam service-accounts create tee-runtime \
  --project=PROJECT_ID \
  --display-name="TEE runtime"

SA="tee-runtime@PROJECT_ID.iam.gserviceaccount.com"

for role in \
  roles/confidentialcomputing.workloadUser \
  roles/logging.logWriter \
  roles/monitoring.metricWriter
do
  gcloud projects add-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:${SA}" \
    --role="$role" \
    --condition=None
done
```

`--condition=None` grants each role across the whole project, with no IAM
condition attached. Some projects already have conditional bindings, for
example, a role limited to one Cloud SQL instance. In that project `gcloud`
requires a condition on every new binding, and without this flag it stops
and asks you to pick one. Choose `None`. Picking an existing condition
limits the role to that one resource, so the VMs do not get it, and the
launcher exits without `roles/confidentialcomputing.workloadUser`.

Whoever runs Terraform attaches this account to the VMs, so that identity
needs `roles/iam.serviceAccountUser` on it. Project Editor (`roles/editor`)
plus that binding is enough to apply the stack: the modules avoid resources
Editor cannot manage, such as Secret Manager secret versions and secret or
instance IAM bindings. That is why the service account is an input rather
than created here. To SSH in later, the same identity needs
`roles/iap.tunnelResourceAccessor`. The VMs are reached through
[IAP TCP forwarding](https://cloud.google.com/iap/docs/using-tcp-forwarding),
so they do not need an open SSH port on the internet.

```bash
gcloud iam service-accounts add-iam-policy-binding "$SA" \
  --project=PROJECT_ID \
  --member="user:YOU@example.com" \
  --role="roles/iam.serviceAccountUser"
```

## Workload image

`envs/example/terraform.tfvars.example` points
`tee_node_docker_image` at `ghcr.io/flare-foundation/tee-node:v0.0.29` and
`tee_proxy_docker_image` at `ghcr.io/flare-foundation/tee-proxy:v0.0.27`.
Extension `0` uses those. You do not build a proxy image for the scaffold:
tee-proxy stays on the stock image.

A custom extension replaces `tee_node_docker_image` with your image pinned by
digest, `ghcr.io/OWNER/your-image@sha256:DIGEST`. A tag such as `v0.1.0` can
later point at a different image, which changes the measured code hash with
no change in Terraform. A digest always refers to the same image. Build for
`linux/amd64`. Confidential Space runs on AMD SEV, and an Apple Silicon build
without that platform produces an `arm64` image the VM cannot run.

GitHub Container Registry creates a package as private on the first push.
The VM pulls with no registry login, so a private package fails the pull and
the launcher never starts. Make the package public. That cannot be undone.

These are the `tee-env-*` keys the module sends. Every one of them has to be
on the image's `tee.launch_policy.allow_env_override` label.

| Key | Set by |
| --- | --- |
| `LOG_LEVEL`, `PROXY_URL` | The module |
| `INITIAL_OWNER`, `EXTENSION_ID` | The module, from `terraform.tfvars` |
| `CHAIN_ID` | The module, from `chain_id` |
| `GOVERNANCE_SIGNERS`, `GOVERNANCE_THRESHOLD` | The module, when governance is set |
| `CHAIN_URL`, `MODE`, and any other extension setting | Your `extension_env` map |

The stock tee-node image already allows these keys. The
[FCC Extension Scaffold](https://github.com/flare-foundation/fce-extension-scaffold)
image does not list `CHAIN_ID`, `GOVERNANCE_SIGNERS`, or
`GOVERNANCE_THRESHOLD` until you add them. The
[deploy guide](https://dev.flare.network/fcc/guides/deploy-on-gcp) has the
Dockerfile change and the build commands. Leave `ENV MODE=1` in the image so
local `docker run` still simulates attestation, and set `MODE=0` in
`extension_env` for the real machine.

## Configure

Copy `envs/example` when you want a named environment. The template itself
is what you fill in for a single stack.

```bash
cp -R envs/example envs/coston2-extension-scaffold
cd envs/coston2-extension-scaffold
cp terraform.tfvars.example terraform.tfvars
```

In `terraform.tfvars.example`, the governance and custom-extension fields
are commented out.

- `governance_signers` and `governance_threshold` are not required to boot
  the machine. They are required to register it, including extension `0`.
- `extension_id` and `extension_env` stay at their defaults for extension
  `0`. Uncomment them only when the workload image is your own extension.

### Identities

Generate a tee-proxy signing key. The script prints an address and a private
key and writes nothing to disk.

```bash
../../scripts/generate-key.sh
```

Generate it on a machine you trust. Store the private key in a password
manager, not in a chat or a ticket. `terraform.tfvars` holds it in plain
text. It is gitignored. Once state is in a remote backend, delete the file
and pass the key with `TF_VAR_tee_proxy_private_key` instead.

On an extension deployment the proxy key and the machine owner are separate
identities.

| Variable | Value |
| --- | --- |
| `tee_proxy_private_key` | The private key from `generate-key.sh`. tee-proxy signs with it. |
| `initial_owner` | The address your registration tooling registers the machine as. For the scaffold, that is `INITIAL_OWNER` from `.env.coston2`. |
| `extension_id` | The id the chain assigned. For the scaffold, `EXTENSION_ID` from `config/coston2/extension.env`. |
| `governance_signers` | The signer set `set-governance` writes. When the scaffold leaves `GOVERNANCE_SIGNERS` unset, that set is `INITIAL_OWNER` alone. |
| `governance_threshold` | `GOVERNANCE_THRESHOLD`, or `1` when unset. |

For extension `0`, `initial_owner` is usually the address `generate-key.sh`
printed. For your own extension it is the deployer address, not the proxy
address. The node and `set-governance` must see the same signer set. A
mismatch reverts registration with `InvalidGovernanceHash`.

### Network values

`main.tf` does not pin the chain. Fill `chain_id`, `chain_rpc_endpoint`, and
the four Flare system contracts for the network you target. The example
passes `chain_rpc_endpoint` into the indexer. An extension reads the same URL
from `extension_env.CHAIN_URL`.

Coston2, which the deploy guide targets:

| Field | Value |
| --- | --- |
| `chain_id` | `114` |
| `chain_rpc_endpoint` | `https://coston2-api.flare.network/ext/C/rpc` |
| `flare_systems_manager` | `FlareSystemsManager` |
| `voter_registry` | `VoterRegistry` |
| `relay` | `Relay` |
| `machine_path_manager` | `FlareTeeManager` |

Take the four addresses from the scaffold's
`config/coston2/deployed-addresses.json`. The module's own default `relay`
is a retired address with no policy logs, so leaving `relay` unset fails.
Other networks use the same fields: Coston is chain id `16`, Songbird `19`,
Flare `14`.

Override `deploy_suffix` when the name should not be `example`. An empty
suffix leaves a trailing dash on `allow-internal-`, which Google Cloud
rejects. With `coston2-scaffold`, the VMs are named
`tee-machine-coston2-scaffold` and `tee-proxy-coston2-scaffold`.

### `terraform.tfvars`

The copied example points at the stock tee-node image and leaves governance
and extension fields commented out. For your own extension, replace the
image with the digest and uncomment both blocks.

```hcl
project               = "PROJECT_ID"
service_account_email = "tee-runtime@PROJECT_ID.iam.gserviceaccount.com"
deploy_suffix         = "coston2-scaffold"

tee_node_docker_image  = "ghcr.io/OWNER/extension-scaffold@sha256:DIGEST"
tee_proxy_docker_image = "ghcr.io/flare-foundation/tee-proxy:v0.0.27"

tee_proxy_private_key = "0x..."
initial_owner         = "0x..." # INITIAL_OWNER

# Needed to register the machine. Must match set-governance.
governance_signers   = ["0x..."] # same address as initial_owner when GOVERNANCE_SIGNERS is unset
governance_threshold = 1

# Custom extension image only. Leave commented for stock tee-node (extension 0).
extension_id = "0x..." # EXTENSION_ID
extension_env = {
  CHAIN_URL = "https://coston2-api.flare.network/ext/C/rpc"
  MODE      = "0"
}

chain_id           = 114
chain_rpc_endpoint = "https://coston2-api.flare.network/ext/C/rpc"

flare_systems_manager = "0x..." # FlareSystemsManager
voter_registry        = "0x..." # VoterRegistry
relay                 = "0x..." # Relay
machine_path_manager  = "0x..." # FlareTeeManager
```

Every `extension_env` key must appear in the image label. `CHAIN_URL` and
`MODE` are already on the scaffold label. `CHAIN_ID` and the governance keys
are sent by the module, which is why the label has to list them too.

`envs/example/main.tf` sets `tee_machine_debug_mode = true`. The module then
uses the debug Confidential Space image, redirects container logs to the
serial console, and opens SSH through IAP. The machine still has no public
IP. Turn the flag off after `/info` looks right, and replace the instance so
the production image boots. See [Apply a config change](#apply-a-config-change).

### Use an external indexer

By default the example runs its own indexer on Cloud SQL. To point tee-proxy
at an indexer you already have:

1. Uncomment the `indexer_db_*` variables in `variables.tf`.
2. In `main.tf`, comment `module "tee_indexer"` and the three
   service-networking resources used only for Cloud SQL, then switch
   `tee_indexer_database` to the commented object that reads `var.indexer_db_*`.
3. Remove the `tee_indexer_instance_name` output from `outputs.tf` and the
   `indexer_drop_table_at_start` variable.
4. In `terraform.tfvars`, set `indexer_db_host`, `indexer_db_user`, and
   `indexer_db_password`.

### Run without an indexer

tee-proxy v0.0.26 and later can read the chain from a C-chain node's
JSON-RPC endpoint instead of an indexer database. That drops the indexer VM
and Cloud SQL.

1. In `main.tf`, comment `tee_indexer_database` and uncomment the
   `chain_source = "rpc"` block under it. tee-proxy reads
   `chain_rpc_endpoint`.
2. Comment `module "tee_indexer"` and the three service-networking resources
   used only for Cloud SQL.
3. Remove the `tee_indexer_instance_name` output from `outputs.tf` and the
   `indexer_drop_table_at_start` variable.
4. If the endpoint needs a key, uncomment the `chain_rpc_api_key` variable
   and set it in `terraform.tfvars`.

The URL and key reach tee-proxy as `NODE_URL` and `NODE_API_KEY` through its
`0600` env file, not the config. On a fresh start tee-proxy sends the TEE
node its initial signing policy and voter keys, which the node cannot
verify. In RPC mode they are only as trustworthy as the endpoint. Use public
endpoints for testing, and a node you run in production.

Keep the VPC, Cloud NAT, and router blocks either way. tee-machine has no
public IP, so it reaches the internet through Cloud NAT to pull its image
and call the attestation service.

## Apply

```bash
terraform init
terraform apply
```

The apply creates a VPC, Cloud NAT, a Redis instance, a Cloud SQL database,
the indexer VM, and the tee-machine and tee-proxy VMs. When it finishes:

```bash
terraform output tee_proxy_info_url
curl -s "$(terraform output -raw tee_proxy_info_url)" | jq .
```

`tee_proxy_info_url` is `http://<static-ip>/info`.
`tee_proxy_external_endpoint` is that URL without `/info`, and it is the
value to register on chain. Signing-policy fields stay zero when `relay`
does not match the Relay your indexer has collected, or when the indexer has
not caught up yet.

A healthy `machineData` looks like this:

| Field | Expected |
| --- | --- |
| `platform` | Begins with `0x4743505f414d445f534556` (`GCP_AMD_SEV`) |
| `codeHash` | A measured hash. The simulated hash `0x194844cf…` means `MODE` is still `1`. |
| `extensionId` | Your `extension_id`. All zeros for extension `0`. |
| `initialOwner` | Matches `initial_owner` |
| `chainId` on `teeInfo` | The `chain_id` you set (`114` on Coston2) |

Both `initialSigningPolicyHash` and `lastSigningPolicyHash` should be
non-zero once a policy has been indexed. Both `attestation` and
`dataSignature` should be non-empty.
[TESTING.md](TESTING.md) covers the internal `/healthy`, `/startup`, and
`/ready` checks. [`modules/tee-package/README.md`](modules/tee-package/README.md)
describes each variable.

Logs from tee-machine go to the serial console while debug mode is on. The
example zone is `europe-west1-b`.

```bash
gcloud compute instances get-serial-port-output "$(terraform output -raw tee_machine_name)" \
  --zone europe-west1-b \
  --project PROJECT_ID
```

Look for `Node initialized.` tee-proxy logs to systemd. SSH goes through IAP,
which is what `--tunnel-through-iap` selects:

```bash
gcloud compute ssh "$(terraform output -raw tee_proxy_instance_name)" \
  --zone europe-west1-b \
  --project PROJECT_ID \
  --tunnel-through-iap
sudo journalctl -u tee-proxy -f
```

On the tee-proxy VM, `curl -s localhost:6661/ready` names the failing check.
A `c-chain indexer delay` result means the indexer, or in RPC mode the
node, is behind the chain tip.
A `connecting to database` result means tee-proxy cannot reach the indexer
database.

## Register the machine

Registration is done by your extension tooling, not by this Terraform. For
the scaffold, the
[deploy guide](https://dev.flare.network/fcc/guides/deploy-on-gcp#register-the-machine)
sets `EXT_PROXY_URL` to `terraform output -raw tee_proxy_external_endpoint`
(no `/info` suffix, no `:6662`) and runs `post-build.sh`. A new workload
image has a new `codeHash`. After you replace the machine, register that
version again.

## Apply a config change

Cloud-init runs on first boot, and Confidential Space reads workload metadata
only at boot. A later `terraform apply` can update metadata on a running VM,
and the guest keeps the old values. Run the scripts from the environment
directory.

| Change | Command |
| --- | --- |
| tee-proxy config, image, or any `tee-env-*` value | `../../scripts/redeploy-proxy.sh` |
| Indexer host, user, or password, or the chain source | `../../scripts/redeploy-proxy.sh` |
| Bundled indexer start block or wipe | `../../scripts/redeploy-indexer.sh` |
| tee-proxy queue backed up | `../../scripts/flush-redis.sh` |

`redeploy-proxy.sh` replaces the tee-machine VM as well. Its `PROXY_URL` is
the proxy's internal IP, baked in at boot, and a replaced proxy can come
back on a different address.

### A deployment registered on `:6662`

`terraform apply`, then reset tee-proxy so it boots the unit that publishes
port 80:

```bash
gcloud compute instances reset <tee-proxy instance> --zone <zone> --project <project>
```

Register the new `tee_proxy_external_endpoint` and check `/info` on it. A
reset keeps the internal IP, so tee-machine is untouched. Port `6662` stops
answering at the apply.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Launcher exits with code 4 | Every `tee-env-*` key is in `tee.launch_policy.allow_env_override`. The runtime service account has `roles/confidentialcomputing.workloadUser`. |
| Image pull fails | The `ghcr.io` package is public. The VM cannot pull a private package. |
| `codeHash` is `0x194844cf…` | `extension_env` sets `MODE` to `"0"`, and the instance was replaced after that change. |
| `extensionId` is all zeros | `extension_id` is set, and the tee-machine was replaced after you set it. Expected for extension `0`. |
| `InvalidGovernanceHash` | `governance_signers` and `governance_threshold` match the signer set your registration tooling writes. |
| `connecting to database` | With the bundled indexer, wait for Cloud SQL and the indexer VM. With an external indexer, check `indexer_db_host`, `indexer_db_user`, and `indexer_db_password`. |
| `no signing policy logs found in db` | `relay` is the live Relay for that chain. The module default is a retired address. |
| `/info` never answers | tee-proxy logs (`journalctl -u tee-proxy`) and the serial console. The public URL is port 80. tee-machine reaches tee-proxy on port **6661** inside the VPC. |
| `/ready` reports indexer delay | The indexer is behind the chain tip. Wait, then check again. For the bundled indexer, also check `journalctl -u tee-indexer`. |
| Queue depth keeps growing | tee-proxy enqueues a TEE info action every few seconds while tee-machine is down. After the machine is back, run `../../scripts/flush-redis.sh`. |

## Repository layout

```text
modules/
  tee-package/                 tee-machine and tee-proxy
  tee-indexer/                 the chain indexer and its database
envs/
  example/                     network-agnostic template, extension 0
  coston-sandbox/              Coston
  coston2-sandbox/             Coston2
  coston2-shielded-transfers/  an extension deployment on Coston2
scripts/
  generate-key.sh              tee-proxy signing key
  redeploy-proxy.sh            replace tee-proxy and tee-machine
  redeploy-indexer.sh          replace tee-indexer, optionally wiping its database
  flush-redis.sh               drain tee-proxy's Redis queue
```
