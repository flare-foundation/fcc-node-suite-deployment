# AGENTS.md

Guidance for AI coding agents.
Humans start at [README.md](README.md).

## What this repo is

Terraform that stands up one Flare TEE node on a GCP project the operator
already owns: a Confidential Space VM (`tee-machine`), a Container-Optimized
OS VM (`tee-proxy`), and a chain indexer with its own Cloud SQL database.
`envs/example` is the template. Filled-in environments live next to it.
`modules/tee-package` and `modules/tee-indexer` are the modules those
environments call.

The operator-facing procedure is [README.md](README.md). Checking a live
stack is [TESTING.md](TESTING.md). Variable intent is
[modules/tee-package/README.md](modules/tee-package/README.md). The extension
walkthrough, including the scaffold image build and `post-build.sh`
registration, is the Developer Hub guide
[Deploy an Extension on Google Cloud](https://dev.flare.network/fcc/guides/deploy-on-gcp).

## Leave the live project alone

Do not run `terraform apply`, `terraform destroy`, `gcloud` mutations, or the
scripts in `scripts/` unless the developer asks for that environment by name.
`apply` creates billable resources and writes the tee-proxy private key and
database passwords into state.

Do not read `terraform.tfvars`, `*.auto.tfvars`, `terraform.tfstate`, or
`terraform.tfstate.*`. They hold secrets and are gitignored. Do not print a
private key, a database password, or a state file into a commit, a comment,
or a reply.

## Commands

From the repository root, after a Terraform or shell change:

```bash
terraform fmt -check -recursive
tflint --init
tflint --recursive
shellcheck scripts/*.sh
```

From an environment directory, `terraform validate` after `terraform init`.
CI runs the same fmt, TFLint (`.tflint.hcl`), Checkov, and ShellCheck jobs.
Checkov is allowed to fail until the remaining Redis and Cloud SQL TLS and
CMEK findings are fixed or skipped with a reason. Do not silence a new
finding to make that job green.

## Layout

```text
modules/tee-package/    tee-machine, tee-proxy, Redis, the GCS bucket
modules/tee-indexer/    indexer VM and its Cloud SQL database
envs/example/           network-agnostic template, extension 0
envs/<name>/            one stack; copy example, do not edit it in place
scripts/                generate-key, redeploy, flush-redis; sourced helpers in _common.sh
```

An environment owns project, chain, and image values. A module owns how a
resource is built. A new chain or extension is a new environment, not a new
branch of the module.

## Invariants

- The service account is an input (`service_account_email`). Do not create
  it, and do not add project IAM bindings, Secret Manager secret versions, or
  secret or instance IAM bindings. Project Editor plus
  `roles/iam.serviceAccountUser` is the intended apply identity, and those
  resources are outside what that identity can manage. The module may grant
  `roles/storage.objectUser` on the bucket it creates.
- tee-machine has no public IP, in debug mode too. SSH is
  `gcloud compute ssh --tunnel-through-iap`. Keep
  `enable_confidential_compute = true` and
  `on_host_maintenance = TERMINATE`. A normal VM running the Confidential
  Space image fails attestation.
- tee-proxy listens on `6661` (internal, tee-machine only) and `6662`
  (external). Publish `6662` on host port **80**. The URL to register is
  `http://<static-ip>`, from `tee_proxy_external_endpoint`. Do not put
  `:6662` back on the public URL, and do not add an HTTP-to-HTTPS redirect:
  Go clients turn a redirected POST into a GET.
- Terraform writes workload settings as `tee-env-<KEY>` metadata. The image's
  `tee.launch_policy.allow_env_override` label must list every key. The
  module already sends `LOG_LEVEL`, `PROXY_URL`, `INITIAL_OWNER`,
  `EXTENSION_ID`, `CHAIN_ID`, and, when set, `GOVERNANCE_SIGNERS` and
  `GOVERNANCE_THRESHOLD`. `extension_env` is for the rest, in
  `UPPER_SNAKE_CASE`, and must not repeat a key the module owns.
- `CHAIN_ID` has to be set. tee-node signs nothing until `ChainID()`
  succeeds. `relay` has to be the live Relay for that chain. The module
  default is a retired address and indexing it finds no policy logs.
- `governance_signers` and `governance_threshold` must match the signer set
  registration writes with `set-governance`. For extension `0`,
  `initial_owner` is the address from `scripts/generate-key.sh`. For a custom
  extension it is a different address, and `extension_id` is the id the chain
  assigned.
- Cloud-init runs on first boot, and Confidential Space reads metadata only
  at boot. A config, image, or `tee-env-*` change is applied with
  `scripts/redeploy-proxy.sh` or `scripts/redeploy-indexer.sh`, which replace
  the instance. A plain `terraform apply` updates metadata the guest never
  re-reads. Replacing tee-proxy replaces tee-machine with it, because
  `PROXY_URL` is the proxy's internal IP baked in at boot.
- `indexer_drop_table_at_start` stays false. Moving `start_index` backwards
  is `scripts/redeploy-indexer.sh --drop-db`, which sets the flag for one
  replace and then back. Left true, every later restart wipes the database.
- `google_project_service` keeps `disable_on_destroy = false`. Destroying
  this stack must not turn off a project-wide API. The service-networking
  connection uses `deletion_policy = ABANDON`.
- `deploy_suffix` is non-empty. An empty suffix leaves a trailing dash on
  `allow-internal-`, which Google Cloud rejects.
- Pin a custom workload image by digest. A moving tag changes `codeHash`
  with no Terraform diff. Stock images are the tags in
  `envs/example/terraform.tfvars.example`.

## agents: infrastructure

Flag a Terraform change that:

- creates a service account, a project IAM binding, or a Secret Manager
  secret version
- gives tee-machine an external IP, or opens SSH from `0.0.0.0/0`
- publishes tee-proxy's public API on `6662` instead of host port 80, or
  redirects port 80 to HTTPS
- drops `enable_confidential_compute` or sets host maintenance to `MIGRATE`
- writes a secret into a startup script, a systemd unit, `metadata`, or a
  file mode looser than `0600` for `tee-proxy.env`
- sets `extension_env` to a key the module already sends
- hardcodes a Flare contract address inside a module instead of taking it
  from the environment
- sets `disable_on_destroy = true` on a project API, or deletes the
  service-networking connection instead of abandoning it
- leaves `drop_table_at_start` defaulting to true

## agents: shell

Scripts in `scripts/` are bash, `set -euo pipefail`, and ShellCheck-clean
with `.shellcheckrc` (`external-sources=true`). Source `_common.sh`. Do not
execute it.

Operator scripts run from an environment directory (`require_env_dir`).
Read Terraform outputs with `tf_output`, which uses `terraform output -json`.
`terraform output -raw` exits 0 and prints a warning banner when the output
is missing.

Do not echo `tee_proxy_private_key`, a database password, or the contents of
`terraform.tfvars`. A prompt that can destroy or replace an instance goes
through `confirm`, which refuses a non-interactive stdin unless
`ASSUME_YES=1`.
