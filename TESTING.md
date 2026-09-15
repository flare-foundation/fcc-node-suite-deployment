# Testing a deployment

How to check that a freshly-applied stack (tee-machine + tee-proxy +
tee-indexer) is actually working, not just that Terraform succeeded. Examples
below use `envs/coston-sandbox`'s naming (`deploy_suffix = "coston"`,
`project = "flare-network-sandbox"`, `zone = "europe-west1-b"`) - substitute
your own if you're testing a different env.

## 1. `/info` - the main external check

```
terraform output tee_proxy_info_url
curl -s "$(terraform output -raw tee_proxy_info_url)" | jq .
```

This hits tee-proxy's public port (6662). A **healthy, settled** response
looks like:

```jsonc
{
  "teeInfo": {
    "challenge": "0x...",                 // latest C-chain block hash the indexer has seen - should change on every request
    "publicKey": { "x": "0x...", "y": "0x..." },
    "initialSigningPolicyId": 123,         // non-zero once a policy has been read from the Relay contract
    "initialSigningPolicyHash": "0x...",   // NOT all-zero (0x000...000)
    "lastSigningPolicyId": 123,
    "lastSigningPolicyHash": "0x...",      // NOT all-zero
    "chainId": 16,
    "teeTimestamp": 1767200000,            // recent unix time, close to "now" on every request
    ...
  },
  "machineData": {
    "extensionId": "0x000...000",          // expected all-zero here - coston-sandbox doesn't set extension_id
    "initialOwner": "0xEfFDC9d60eaa243b2fCC5c2A21FA938B3A872d07", // NOT zero (module default)
    "codeHash": "0x...",                   // non-empty once tee-machine has attested
    "platform": "...",
    "publicKey": { "x": "0x...", "y": "0x..." }
  },
  "dataSignature": "0x...",                // non-empty
  "attestation": "...",                    // non-empty JWT-like string
  "proxySignature": "0x..."                // non-empty - tee-proxy always adds this once it responds at all
}
```

What "wrong" looks like: `initialSigningPolicyHash`/`lastSigningPolicyHash`
staying `0x000...000`, `initialSigningPolicyId`/`lastSigningPolicyId`
staying `0`, or `attestation`/`dataSignature`/`codeHash` staying empty for
more than a few minutes after apply.

**Don't be fooled by `machineData.extensionId` being all-zero** - that's
correct for this deployment, since `envs/coston-sandbox` doesn't set
`extension_id` (module default is the zero address). Only `initialOwner`
being zero (or wrong) would indicate a real problem.

**Timing note specific to this stack:** the indexer only starts collecting
from a recent block (`indexer_start_index` in `envs/coston-sandbox/main.tf`,
currently `53650000`) rather than from genesis. tee-proxy's signing-policy
values come from `SigningPolicyInitialized` events on the Relay contract, so
if no such event has landed on-chain at or after that start block yet, the
policy fields can legitimately stay empty until the next natural rollover on
Coston. If they're still empty after a long wait, first confirm (step 4)
that the indexer has actually caught up to chain tip before assuming
something's broken.

If `curl` returns nothing / connection refused: tee-proxy isn't up yet, or
the external firewall/IP is wrong - check `terraform output
tee_proxy_external_endpoint` and tee-proxy's logs (step 3).

## 2. `/healthy`, `/startup`, `/ready` - internal checks

These live on tee-proxy's **internal** port (6661), which the firewall only
opens to tee-machine's IP - you can't hit them from your laptop. SSH into
tee-proxy instead (debug mode is on in coston-sandbox, so this works):

```
gcloud compute ssh tee-proxy-coston --zone europe-west1-b --project flare-network-sandbox --tunnel-through-iap
curl -s localhost:6661/healthy   # trivial 200 - only tells you the process is up
curl -s localhost:6661/startup   # 200 once initial startup finished
curl -s -i localhost:6661/ready  # the useful one
```

`/ready` checks, in order, and its response body names the failing step:
startup finished -> Redis `PING` -> indexer delay (`c-chain indexer delay`,
fails if indexer is >140s behind chain tip) -> info service present -> info
freshness (fails if `/info` hasn't updated in >140s) -> attestation sticky
error -> result-storage sticky error. A non-200 here with a body like
`"c-chain indexer delay: ..."` or `"attestation failing: ..."` tells you
exactly which subsystem to go look at next.

## 3. Logs

**tee-proxy** (Container-Optimized OS VM, container run by a systemd unit):

```
gcloud compute ssh tee-proxy-coston --zone europe-west1-b --project flare-network-sandbox --tunnel-through-iap
journalctl -u tee-proxy -f
```

`systemctl status tee-proxy` shows whether the unit itself is healthy - a
container that is crash-looping shows up as repeated restarts there before it
shows up in the application log. `docker logs -f tee-proxy` still works too;
the container is named, so you no longer need `docker ps` to find its id.

Look for:
- `"connecting to database: %v"` (panic) - can't reach the indexer's Cloud SQL instance
- `"c-chain indexer: %v"` (panic) - failed waiting on indexer sync; also watch for repeated `"Database out of sync. Delayed for %v"` warnings
- `"fetching initial TEE info"` then `"initial TEE info fetched"` - tee-proxy successfully talked to tee-machine; if you only ever see `"tee info attempt %d failed, retrying..."` or `"tee info update failed in %d consecutive cycles..."`, tee-machine isn't reachable or isn't responding
- `"initialized for policy %d"` / `"restart: loaded policies %d and %d..."` / `"updated signing policy to %d"` - signing policy was read successfully
- `"attestation verification failed (sticky, readiness fails until restart): %v"` - attestation problem, requires a restart once fixed
- `"attestation verification disabled — bootstrap relies on network isolation only"` - expected/benign if attestation is deliberately off for this env, not a bug

**tee-machine** (Confidential Space - no direct `docker logs` access; stdout
is redirected to the serial console because `tee_machine_debug_mode = true`
enables `tee-container-log-redirect`):

```
gcloud compute instances get-serial-port-output tee-machine-coston --zone europe-west1-b --project flare-network-sandbox
```

Look for `"Node initialized."` / `"tee node initialized"` and per-queue
`"%s queue: processing started"` lines as signs of a normal boot. Repeated
`"%s queue: error getting action: %v"` (often a `dial tcp ... connection
refused` underneath) means tee-node can't reach tee-proxy at
`PROXY_URL` - check `tee-env-PROXY_URL` in the instance metadata and that
tee-proxy is actually listening on 6661. tee-node itself doesn't emit an
explicit attestation-success line; look on the tee-proxy side instead
(above) for confirmation that an info exchange completed.

**tee-indexer** (also a COS VM with a systemd unit):

```
gcloud compute ssh tee-indexer-coston --zone europe-west1-b --project flare-network-sandbox --tunnel-through-iap
journalctl -u tee-indexer -f
curl -s -o /dev/null -w '%{http_code}
' localhost:8080/health
```

`/health` is the quickest answer to "is it caught up": 503 while startup
catchup is still running, 200 once continuous indexing has begun.

Errors here (RPC failures against the `chain_rpc_endpoint`, DB write
failures) are the most common root cause of tee-proxy's indexer-delay
readiness failures - check this first if `/ready` complains about the
indexer.

## 4. Supporting infra sanity checks

**Indexer caught up?** Ask the indexer itself first - `/health` on port 8080
answers in one call (503 during startup catchup, 200 once continuous indexing
has begun):

```
gcloud compute ssh tee-indexer-coston --zone europe-west1-b --project flare-network-sandbox --tunnel-through-iap
curl -s -o /dev/null -w '%{http_code}
' localhost:8080/health
```

That tells you *whether* it is caught up, not *how far behind* it is. For the
latter, query the database. It is private-IP-only, so do it from the indexer
VM rather than your laptop; get credentials without adding a Terraform output:

```
cd envs/coston-sandbox
terraform console
> module.tee_indexer.database_config
```

Then from inside the tee-indexer VM (it has Docker, no local mysql client):

```
docker run --rm -it --network host mysql:8 mysql -h <hostname> -u indexer-reader -p<password> indexer
mysql> SELECT MAX(number) FROM blocks;
mysql> SELECT * FROM states;
```

`blocks` is the indexed chain data; `states` holds the indexer's own progress
rows. If the most recent indexed block is far behind Coston's current tip,
that's your indexer-delay problem, not a tee-proxy bug.

**Redis:** `/ready` already `PING`s it, so that's normally sufficient. If
you want to check by hand, it's unauthenticated and only reachable inside
the VPC - SSH into tee-proxy and use `docker run --rm -it --network host
redis:7 redis-cli -h <redis-host> -p <redis-port> ping`.

What `/ready` will *not* tell you is that the queue has backed up. While
tee-machine is unreachable, tee-proxy enqueues a TEE_INFO action every 5s with
no cap, and the node drains FIFO at roughly 1/s - so a backlog built during an
outage outlives the outage by hours, and the stack cannot recover on its own
even after the original fault is fixed. tee-proxy logs `queue direct depth N
exceeds threshold 100` while this is happening, but nothing acts on it. Check
the depth with `redis-cli ... DBSIZE`, or just run
`../../scripts/flush-redis.sh --dry-run`, which reports it and exits.

**GCS bucket** (`terraform output` doesn't expose it at env level, but
`gsutil ls gs://flare-network-sandbox-tee-proxy-coston/` works directly from
your laptop with normal GCP auth): this is tee-proxy's result-storage
backend. Being empty right after a fresh apply is normal - it fills in as
wallet/backup actions happen. A `"result storage failing"` error from
`/ready` is the more reliable signal that this is broken, not bucket
emptiness by itself.

## 5. Applying a config change to an already-running deployment

Short version: use the scripts in `scripts/`, run from an env directory.

| Change | Command |
|---|---|
| tee-proxy config, unit, image, or any `tee-env-*` value | `../../scripts/redeploy-proxy.sh` |
| indexer config or image | `../../scripts/redeploy-indexer.sh` |
| indexer config **and** you moved `start_index` backwards | `../../scripts/redeploy-indexer.sh --drop-db` |
| tee-proxy's queue has backed up | `../../scripts/flush-redis.sh` |

Why a plain `terraform apply` is not enough: cloud-init runs only on **first
boot**, and Confidential Space reads its metadata only at boot. Terraform will
happily update `metadata` in place on a running VM, but nothing then tells the
guest to re-read it, so the change silently does not take effect. The scripts
wrap `terraform apply -replace=...`, which recreates the instance instead.

Two things the scripts handle that are easy to get wrong by hand:

- **tee-machine must be replaced alongside tee-proxy.** tee-machine's
  `PROXY_URL` is baked into its boot metadata from tee-proxy's internal IP. A
  replaced proxy can come back on a different IP, and tee-machine has no way to
  notice. `redeploy-proxy.sh` always replaces both.
- **`--drop-db` is a two-pass apply.** `drop_table_at_start` has to go back to
  `false` afterwards, or the indexer wipes its database on every subsequent
  restart. The script does the second pass for you.

If you are working on the box directly rather than through Terraform:

- **tee-proxy / tee-indexer** run their container from a systemd unit, so
  `sudo systemctl restart tee-proxy` is a real restart path. It restarts the
  process with the config that is already on disk - it does not pick up a
  changed Terraform config, which still needs a replace. (Under the old Konlet
  setup there was no reliable restart at all: cloud-init's `write_files` raced
  Konlet mounting the same path and could leave `config.toml` as an empty
  directory, fataling with `read config.toml: is a directory`. That race is
  gone - `write_files` now always completes before the unit starts.)
- **tee-machine** has no live-reload path at all. `sudo systemctl restart
  container-runner.service` fails immediately with `status=4/NOPERMISSION`;
  Confidential Space's launcher refuses to re-run within the same boot by
  design, since the workload is tied to boot-time attestation. Only a real
  `gcloud compute instances reset` (or the replace the script does) applies a
  metadata change here.

## Quick symptom -> cause table

| Symptom | Likely cause | Check |
|---|---|---|
| `/info` unreachable | tee-proxy down, or wrong external IP/firewall | tee-proxy logs, `terraform output tee_proxy_external_endpoint` |
| `/info` returns data but signing-policy fields stay zero | indexer hasn't seen a `SigningPolicyInitialized` log yet, or hasn't caught up | `/ready` indexer-delay check, tee-indexer logs, indexer DB row recency |
| `/info` `attestation`/`dataSignature`/`codeHash` empty | tee-machine hasn't attested / isn't reachable from tee-proxy | tee-machine serial console, tee-proxy's `"fetching initial TEE info"` logs |
| tee-proxy panics `error signing: could not sign` / `/info` signature fields are 0 bytes | tee-node has no `CHAIN_ID` - it signs nothing until `ChainID()` succeeds (`tee-env-CHAIN_ID` in `tee-machine.tf`) | tee-machine serial console for `router.go:164 ... error signing`; confirm `tee-env-CHAIN_ID` is in the instance's metadata |
| tee-proxy panics `initializing signing policy: ... no signing policy logs found in db` | indexer's `start_index` is after the Relay's last `SigningPolicyInitialized` log, so that event was never indexed | find the actual block via a block explorer's log API (30-block `eth_getLogs` RPC caps make scanning for it directly impractical), set `start_index` at or before it |
| indexer makes little/no progress, repeated `Backoff exhausted: ... requested too many blocks ..., maximum is set to 30` | `log_range` unset/too wide for this RPC's `eth_getLogs` block-range cap | `modules/tee-indexer/templates/indexer/config.toml.tftpl`'s `[indexer]` block - `log_range` must be <= the RPC's cap |
| indexer progresses but very slowly (~1000 blocks per 2-3 minutes) against `coston-api.flare.network` | largely public-RPC rate limiting. **Re-measure before accepting this** - the figure was taken on indexer 1.x, and v2.0.1 both fixed continuous indexing issuing one `eth_getLogs` per filter serially and raised the per-attempt RPC timeout default from 1s to 5s | if it is still slow on v2: let it run, or get the deploying project allowlisted for less-limited public RPC access (Cloud Armor IP/API-key allowlist on Flare's side) - the `*.svc.cluster.local` internal validator RPC infra's own staging env uses isn't reachable from an external project without new Private Service Connect plumbing |
| `/ready` fails on Redis | Redis instance not up / network peering issue | Redis instance status in GCP console, `redis-cli ping` from tee-proxy |
| `/ready` fails on indexer delay | RPC endpoint down, indexer stuck/crashing, or still working through a large backlog | tee-indexer logs, `chain_rpc_endpoint` reachability |
| tee-proxy healthy but stuck, `queue direct depth N exceeds threshold 100` in its logs | TEE_INFO actions enqueued every 5s with no cap while tee-machine was unreachable; the node drains FIFO at ~1/s, so the backlog outlives the outage by hours | `scripts/flush-redis.sh` (`--dry-run` to see the depth first) |
| tee-machine restarted; tee-proxy keeps serving a stale payload and never re-pairs | tee-proxy caches the last TEE info and has no re-pair trigger | `sudo systemctl restart tee-proxy` over IAP (needs `allow_tee_proxy_ssh`, default true), or `scripts/redeploy-proxy.sh` |
| indexer exits at startup complaining about the `states` table | indexer 2.x adds a unique index on `states.name`, and `AutoMigrate` refuses to create it if a 1.x database holds duplicate names | `SELECT name, COUNT(*) FROM states GROUP BY name HAVING COUNT(*) > 1;` - keep the row with the highest `index` per name, delete the rest. An empty result means this is not your problem |
| `/ready` fails on attestation (sticky) | attestation error, needs a tee-proxy restart after root cause is fixed | tee-proxy logs for the sticky attestation error line |
