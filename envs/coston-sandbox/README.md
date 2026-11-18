# coston-sandbox

A concrete (not generic-placeholder) example: one tee-package deployed
against Coston in Flare's `flare-network-sandbox` GCP project, using the
existing `confidential-sa` service account there.

There is no indexer. tee-proxy reads the chain from the public Coston RPC
(`chain_source = "rpc"`). The TEE node cannot verify the signing policy and
voter keys that endpoint returns, which is fine for a sandbox and not for
production.

```
cd envs/coston-sandbox
cp terraform.tfvars.example terraform.tfvars   # fill in tee_proxy_private_key
terraform init
terraform apply
```

Once applied, get tee-proxy's `/info` URL with:

```
terraform output tee_proxy_info_url
```

`service_account_email` defaults to
`confidential-sa@flare-network-sandbox.iam.gserviceaccount.com` — per
`flarenetwork/infra`'s `terraform/gcp/services/tee/sandbox/hackaton/service_account_permissions.tf`,
that SA needs (at least): `roles/artifactregistry.reader`,
`roles/confidentialcomputing.workloadUser`, `roles/compute.instanceAdmin.v1`,
`roles/iam.serviceAccountUser` (self). The module needs nothing more on it;
whoever runs `terraform` needs project Editor plus `roles/iam.serviceAccountUser`
on the SA.

See `envs/example/` instead if you want a fully generic template for an
arbitrary project/network.
