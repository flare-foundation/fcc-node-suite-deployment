#!/usr/bin/env bash
#
# Replace tee-proxy, and tee-machine with it.
#
# Both are required together. tee-machine's PROXY_URL is baked into its boot
# metadata from tee-proxy's internal IP, and Confidential Space only reads
# metadata at boot - so a replaced proxy that comes back on a different IP
# leaves tee-machine talking to nothing until it is replaced too.

# shellcheck source=scripts/_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

usage() {
    cat >&2 <<'USAGE'
Usage: ../../scripts/redeploy-proxy.sh [terraform apply args...]

  Run from an env directory. Replaces tee-proxy and tee-machine, which is what
  picks up a changed tee-proxy config, systemd unit, or any tee-env-* value.

  Pass -auto-approve to skip Terraform's own prompt. ASSUME_YES=1 skips ours.
USAGE
    exit 1
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

require_cmd terraform
require_env_dir

proxy=$(tf_output tee_proxy_instance_name)
machine=$(tf_output tee_machine_name)

echo "Will replace:"
echo "  tee-proxy   $proxy"
echo "  tee-machine $machine"
echo
echo "tee-proxy's external IP is a reserved static address and survives; its"
echo "internal IP may change, which is why tee-machine goes with it."
echo
confirm "Proceed?"

terraform apply \
    -replace=module.tee_package.google_compute_instance.tee_proxy \
    -replace=module.tee_package.google_compute_instance.tee_machine \
    "$@"

cat <<EOF

Done. Both VMs boot from scratch, so give them a minute, then:

  gcloud compute ssh $proxy --tunnel-through-iap -- journalctl -u tee-proxy -f
  curl -s "\$(terraform output -raw tee_proxy_info_url)"

/info is the real check - see TESTING.md section 1.
EOF
