# Contributing

This document describes the process of contributing to this project. It is
intended for anyone considering opening an issue or pull request.

## AI Assistance

Any significant use of AI assistance in the contribution MUST be disclosed in
the pull request along with the extent of the use.

An example disclosure:

> This PR was written primarily by Claude Code.

Or a more detailed disclosure:

> I consulted ChatGPT for the following code snippets: ...

## Quick start

If you'd like to contribute, report a bug, suggest a feature, or you've
implemented a feature, open an issue or pull request.

Any contribution is expected to be formatted and linted, and existing checks
must still pass.

## Dev environment

- [Terraform](https://developer.hashicorp.com/terraform/install) `>1.11`
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install), authenticated
  with `gcloud auth application-default login` when you plan to apply
- [TFLint](https://github.com/terraform-linters/tflint)
- [ShellCheck](https://github.com/koalaman/shellcheck)

`envs/example` is the generic environment. Copy
`envs/example/terraform.tfvars.example` to `terraform.tfvars` in that
directory and fill in the values described in [README.md](README.md).
`terraform.tfvars` holds secrets and is gitignored. Do not commit it.

From an environment directory:

```bash
terraform init
terraform fmt -check -recursive
terraform validate
```

`terraform apply` creates billable GCP resources. Use a project you control.

## Linting and formatting

From the repository root:

```bash
terraform fmt -check -recursive
tflint --init
tflint --recursive
shellcheck scripts/*.sh
```

TFLint uses [`.tflint.hcl`](.tflint.hcl) (recommended Terraform rules and the
Google ruleset). ShellCheck uses [`.shellcheckrc`](.shellcheckrc).

The same checks run in CI: `terraform fmt`, TFLint, Checkov, and ShellCheck.
Checkov is allowed to fail until the remaining findings are fixed or skipped
with a reason.

## Testing

There is no unit-test suite. [TESTING.md](TESTING.md) is the end-to-end check
for a deployment you have applied: a healthy `/info` response, the internal
health endpoints, where each component logs, and a symptom to cause table.
