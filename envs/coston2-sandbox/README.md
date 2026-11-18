# coston2-sandbox

One tee-package against **Coston2**, in Flare's `flare-network-sandbox` GCP
project, using the `confidential-sa` service account already there. The
Coston sibling is `envs/coston-sandbox`; the generic template is
`envs/example`.

There is no indexer. tee-proxy reads the chain from the public Coston2 RPC
(`chain_source = "rpc"`). The TEE node cannot verify the signing policy and
voter keys that endpoint returns, which is fine for a sandbox and not for
production.

```
cd envs/coston2-sandbox
cp terraform.tfvars.example terraform.tfvars   # fill in the keypair
terraform init
terraform apply
terraform output tee_proxy_info_url
```

## Get the keypair right before applying

`../../scripts/generate-key.sh` prints an address and a
private key. They are two halves of one keypair: the private key goes in
`tee_proxy_private_key`, the address in `initial_owner`. Both are required here
on purpose — inheriting the module's default `initial_owner` deploys a machine
owned by a Flare-held address you have no key for, and nothing warns you.

## Service account permissions

`confidential-sa` needs `roles/confidentialcomputing.workloadUser` and
`roles/monitoring.metricWriter` — the same two `flarenetwork/infra` grants it in
`terraform/gcp/services/hackathon/production/main.tf`. Without `workloadUser`
the Confidential Space launcher cannot reach the attestation verifier; the
workload exits after ~3 seconds with `exit_code=4`, tee-proxy never gets its TEE
info, and `/info` never answers.

Whoever runs `terraform` separately needs `roles/iam.serviceAccountUser` **on
that SA** to attach it to the VMs, plus enough project permission to create
Compute, Memorystore, Secret Manager and GCS resources, and
`roles/iap.tunnelResourceAccessor` for the SSH steps in `TESTING.md`.

## Contract addresses

Taken from `flarenetwork/infra`'s
`terraform/gcp/services/tee/staging/coston2` and verified against the chain.

Note `relay` deliberately overrides the module default: the default
(`0xa10B672D…`) is a dead deployment that emits no `SigningPolicyInitialized`
logs, so a deploy using it finds no signing policy no matter how caught up
the chain source is. Check both the relay and the governance
signers are still current before relying on this env.
