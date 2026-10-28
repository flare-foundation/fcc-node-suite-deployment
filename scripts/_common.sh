# shellcheck shell=bash
# Shared helpers for the operator scripts. Source, don't execute.
#
# Why these scripts exist at all: cloud-init runs only on first boot and
# Confidential Space reads its metadata only at boot, so any change to a
# rendered config, a systemd unit or a tee-env-* key needs the instance
# replaced. A plain `terraform apply` will not do it - it sees no diff worth
# recreating for, or updates metadata on a VM that will never read it again.

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

require_env_dir() {
    [[ -f main.tf ]] || die "run this from an env directory (envs/coston-sandbox, envs/example), not $PWD"
    [[ -d .terraform ]] || die "no .terraform here - run 'terraform init' first"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required but was not found on PATH"
}

# terraform output, with a clear message when the stack has not been applied.
#
# -json, not -raw: with no outputs in state at all, `terraform output -raw x`
# exits 0 and prints its "No outputs found" warning banner on stdout, so the
# caller silently gets the banner as the value. -json exits 1 like it should.
tf_output() {
    local name="$1" value
    value=$(terraform output -no-color -json "$name" 2>/dev/null) \
        || die "no '$name' output - has this env been applied? (try: terraform apply)"
    value=${value#\"}
    value=${value%\"}
    [[ -n "$value" && "$value" != "null" ]] || die "'$name' output is empty"
    printf '%s' "$value"
}

confirm() {
    local prompt="$1"
    if [[ "${ASSUME_YES:-}" == "1" ]]; then
        echo "$prompt -> yes (ASSUME_YES=1)"
        return 0
    fi
    [[ -t 0 ]] || die "refusing to prompt with no terminal; re-run with ASSUME_YES=1 if you mean it"
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" == "y" || "$reply" == "Y" ]] || die "aborted"
}
