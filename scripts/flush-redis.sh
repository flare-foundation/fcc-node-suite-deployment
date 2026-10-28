#!/usr/bin/env bash
#
# Flush tee-proxy's Redis queue.
#
# While tee-machine is unreachable, tee-proxy enqueues a TEE_INFO action every
# 5s with no cap, and the node drains FIFO at roughly 1/s. A backlog built up
# during an outage therefore outlives the outage by hours - the stack cannot
# recover on its own. tee-proxy logs "queue direct depth N exceeds threshold
# 100" when this is happening, but nothing acts on it.
#
# Memorystore has no public endpoint, so this goes through tee-proxy over IAP.

# shellcheck source=scripts/_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

usage() {
    cat >&2 <<'USAGE'
Usage: ../../scripts/flush-redis.sh [--dry-run]

  Run from an env directory. Reports the queue depth and flushes it.

  --dry-run  Report the depth and exit without flushing.

  Needs allow_tee_proxy_ssh (default true) and roles/iap.tunnelResourceAccessor.
USAGE
    exit 1
}

dry_run=0
case "${1:-}" in
    --dry-run) dry_run=1 ;;
    -h|--help) usage ;;
    "") ;;
    *) usage ;;
esac

require_cmd terraform
require_cmd gcloud
require_env_dir

proxy=$(tf_output tee_proxy_instance_name)
host=$(tf_output redis_host)
port=$(tf_output redis_port)

# One SSH round trip per redis-cli call; the image is cached after the first.
redis() {
    gcloud compute ssh "$proxy" --tunnel-through-iap --quiet \
        --command "docker run --rm redis:7.4@sha256:b6b6e3dc0c0952737748e55d5d885272840c7e42ba41ab1d5489f693419882f5 redis-cli -h $host -p $port $*"
}

echo "tee-proxy: $proxy"
echo "redis:     $host:$port"
echo

before=$(redis DBSIZE | tr -d '\r')
echo "keys before: $before"

if (( dry_run )); then
    echo "(--dry-run, nothing flushed)"
    exit 0
fi

if [[ "$before" == "0" ]]; then
    echo "Queue is already empty - nothing to flush."
    exit 0
fi

echo
echo "FLUSHALL drops tee-proxy's queue and its cached payloads. In-flight"
echo "actions are lost; tee-proxy rebuilds its cache on the next cycle."
confirm "Flush?"

redis FLUSHALL >/dev/null
after=$(redis DBSIZE | tr -d '\r')
echo "keys after:  $after"
