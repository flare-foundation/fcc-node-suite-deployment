# Security policy

## Reporting a vulnerability

Please do not report a vulnerability using an issue or any other public
channel.

If you have found a possible vulnerability, please send an email to
`security at flare dot network`.

## Vulnerability disclosures

Critical vulnerabilities will be disclosed via GitHub's
[security advisory](https://github.com/flare-foundation/tee-node-suite-deployment/security)
system.

## Review scope and audits

### In scope

Terraform and shell that define or operate a deployment:

- `modules/**`
- `envs/**/*.tf`
- `scripts/**`

### Out of scope

- `envs/**/terraform.tfvars` — operator secrets, gitignored
- `**/.terraform/**` and `**/terraform.tfstate*` — local Terraform data and
  state, which holds the tee-proxy key and database passwords

### Previous audits

No audit reports have been published for this repository. Flare audit reports
for other components are published on the
[Developer Hub](https://dev.flare.network/support/audits/).
