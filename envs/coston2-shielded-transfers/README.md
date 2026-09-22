# coston2-shielded-transfers

An **extension** deployment on Coston2, as opposed to `envs/coston2-sandbox`
which runs the stock tee-node. The extension is shielded transfers
(flare-mixer) — one of the two actually running on Coston2 today — modelled on
`module.tee_package_shielded_transfers` in `flarenetwork/infra`'s
`terraform/gcp/services/tee/staging/coston2`.

```
cd envs/coston2-shielded-transfers
cp terraform.tfvars.example terraform.tfvars   # keypair + direct API key
terraform init
terraform apply
```

## What makes a deployment an "extension" deployment

Five things, all visible in `main.tf`:

| | |
|---|---|
| `tee_node_docker_image` | the extension's own workload image |
| `tee_proxy_docker_image` | its own proxy build — **not** universal; the USDX oracle runs the stock proxy, because it has no proxy-side code |
| `extension_id` | the id it is registered under on chain, as bytes32. Assigned, not chosen |
| `extension_env` | settings the workload reads, here three contract addresses plus `CHAIN_URL` and `INSTRUCTION_SENDER` |
| `direct_api_key` | enables tee-proxy's `POST /direct`, for actions taken off-chain rather than as on-chain instructions |

Governance is **per extension**: the signers here are not the ones
`envs/coston2-sandbox` uses for the stock package.

`extension_env` is a free-form map on purpose. Each entry becomes the metadata
key `tee-env-<KEY>`, and each must also appear in the workload image's
`tee.launch_policy.allow_env_override` label — Confidential Space drops any key
that doesn't, without logging anything. If the extension behaves as though a
setting were unset, check that label first.

## Prerequisites beyond the stock env

**Artifact Registry access.** Both images live in
`europe-west1-docker.pkg.dev/flare-network-staging`, not a public registry, so:

- `confidential-sa` needs `roles/artifactregistry.reader` on
  `flare-network-staging` — a cross-project grant, since this env deploys into
  `flare-network-sandbox`.
- The systemd unit runs `docker-credential-gcr configure-docker` before pulling.
  The module adds that automatically for any `*-docker.pkg.dev` image and omits
  it for public ones. Konlet used to handle registry auth itself.

**Indexer collectors.** `machine_path_manager` is passed to *both* modules. The
package needs it because governance is configured; the indexer needs it because
tee-proxy's machine-path-list service reads `MachinePathsAdded`,
`MachinePathListSigned` and `signMachinePathList` transactions out of the
indexer database. Omit it there and the service starts, finds nothing, and
rejects every list update silently.

## Before applying

The contract addresses, `extension_id` and the image tags are a snapshot of
infra's Coston2 config on 2026-09-21 — check them against infra before relying
on this. `indexer_start_index` ages out in hours, not days;
`envs/coston2-sandbox/main.tf` documents how to re-pick it.
