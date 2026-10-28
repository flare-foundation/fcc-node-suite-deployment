#!/usr/bin/env bash
#
# Replace tee-indexer, optionally wiping its database first.

# shellcheck source=scripts/_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

usage() {
    cat >&2 <<'USAGE'
Usage: ../../scripts/redeploy-indexer.sh [--drop-db] [terraform apply args...]

  Run from an env directory. Replaces tee-indexer, which is what picks up a
  changed indexer config.

  --drop-db  Also wipe the indexer database on the way through. Needed to move
             start_index backwards: the indexer otherwise resumes from its last
             state row and never re-reads earlier blocks.

             This runs TWO applies - one with drop_table_at_start=true, then a
             second putting it back to false. The second is not optional: left
             true, the indexer wipes its database on every restart.

  Pass -auto-approve to skip Terraform's own prompt. ASSUME_YES=1 skips ours.
USAGE
    exit 1
}

drop_db=0
if [[ "${1:-}" == "--drop-db" ]]; then
    drop_db=1
    shift
fi
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

require_cmd terraform
require_env_dir

indexer=$(tf_output tee_indexer_instance_name)
target="module.tee_indexer.google_compute_instance.tee_indexer"

echo "Will replace: $indexer"
if (( drop_db )); then
    echo
    echo "AND DROP THE INDEXER DATABASE. Everything indexed so far is lost and"
    echo "re-collected from start_index, which against a public RPC is hours."
fi
echo
confirm "Proceed?"

if (( drop_db )); then
    echo
    echo "==> pass 1/2: replacing with drop_table_at_start=true"
    terraform apply -replace="$target" -var indexer_drop_table_at_start=true "$@"

    echo
    echo "==> pass 2/2: replacing again with drop_table_at_start=false"
    echo "    (skipping this would wipe the database on every future restart)"
    terraform apply -replace="$target" "$@"
else
    terraform apply -replace="$target" "$@"
fi

cat <<EOF

Done. Watch it catch up:

  gcloud compute ssh $indexer --tunnel-through-iap -- journalctl -u tee-indexer -f
  gcloud compute ssh $indexer --tunnel-through-iap -- curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/health

/health is 503 while startup catchup runs and 200 once continuous indexing begins.
EOF
