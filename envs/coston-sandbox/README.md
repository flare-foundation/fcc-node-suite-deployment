# coston-sandbox

A concrete (not generic-placeholder) example: one tee-package + tee-indexer
deployed against Coston in Flare's `flare-network-sandbox` GCP project,
using the existing `confidential-sa` service account there.

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
`roles/iam.serviceAccountUser` (self) — plus whatever this module itself
needs beyond that (`roles/secretmanager.admin`, `roles/cloudsql.admin`,
`roles/storage.admin`, `roles/redis.admin`), which aren't part of that SA's
existing grants in the reference repo and may need adding.

See `envs/example/` instead if you want a fully generic template for an
arbitrary project/network.
