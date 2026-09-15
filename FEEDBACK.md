# Notes from deploying this suite into an external project

Findings from standing the suite up in a fresh GCP project (Coston and Coston2,
one package each). Ordered by how much they cost to work around.

## 1. Konlet is discontinued — nothing deploys in a new project

`tee-proxy` and `tee-indexer` are container VMs driven by the
`gce-container-declaration` metadata key (`modules/tee-package/proxy-server.tf:135`,
`modules/tee-indexer/indexer.tf:88`). GCE stopped accepting it on 2026-07-31:

```
Error 400: You are creating a container VM. The option to deploy a container during
VM instance creation that relies on a container startup agent is discontinued.
```

Existing instances keep running, so this is invisible until someone applies into a
project that has none. Google's replacement is a startup script or cloud-init
([shutdown notice][konlet], [migration guide][migrate]).

Both modules already write a cloud-init `user-data`, so the fix is to add a systemd
unit there that runs the container, and drop the metadata key. Two things to keep:

- publish ports with `-p`, as Konlet did. COS runs `iptables INPUT` with policy DROP,
  so `--network host` leaves the listener reachable on localhost but not from
  tee-machine or the internet.
- tee-proxy's key can go in a `0600` `EnvironmentFile` instead of the container spec.

Side benefit: `systemctl restart tee-proxy` becomes a real reload path, which retires
the metadata-reload race in TESTING.md section 5. Note that container logs then live in
`journalctl -u tee-proxy`, not `docker logs` — TESTING.md section 3 needs updating.

[konlet]: https://docs.cloud.google.com/compute/docs/containers/prepare-for-container-agent-shutdown
[migrate]: https://docs.cloud.google.com/compute/docs/containers/migrate-containers

## 2. `scripts/generate-key.sh` fails on a clean host

`eth-keys` cannot hash on its own, so `to_checksum_address()` dies with
`ImportError: None of these hashing backends are installed`. Adding
`eth-hash[pycryptodome]` to the install line fixes it. Installing into the caller's
site-packages is also unfriendly — `uv run --with ...`, or a throwaway venv, keeps the
user's Python untouched.

## 3. `indexer_start_index` must precede the voter registrations, not the policy log

TESTING.md and the module comments say to start at or before the Relay's last
`SigningPolicyInitialized` log. That is not sufficient: building the policy recovers
each voter's public key from the `v,r,s` in their `VoterRegistered` event on
VoterRegistry, which is emitted earlier. Starting between the two panics on loop with:

```
initializing signing policy: ... preparing initialize policy message for reward epoch N:
recovering pub key for 0x...: invalid number of logs
```

`registerVoter` requires `newSigningPolicyInitializationStartBlockNumber != 0` (set at `RandomAcquisitionStarted`)
and `votePowerBlock != 0` (set at `VotePowerBlockSelected`), so the earliest possible
`VoterRegistered` for an epoch is the block of `VotePowerBlockSelected` for that epoch.
Suggested wording: *start at or before the `VotePowerBlockSelected` block of the epoch
`initial_signing_policy_offset` selects* — two epochs back from the newest policy.

## 4. No governance configuration

Registering a machine needs `GOVERNANCE_SIGNERS` and `GOVERNANCE_THRESHOLD`, plus
`GOVERNANCE_SAFE` and `GOVERNANCE_TEE_MANAGER` on networks that use them. The module
sets neither the `tee-env-GOVERNANCE_*` metadata nor a `[governance]` block in
tee-proxy's config, so a machine deployed from this repo cannot be registered as-is.
`flarenetwork/infra`'s `modules/helm/tee-package` has both, gated on optional variables
— porting that shape works unchanged here.

While there: a line in the README on what `initial_owner` and `extension_id` are for
would help. `generate-key.sh` implies the owner address and the proxy signing key are
one keypair, which is worth stating explicitly, and `extension_id` appears to be
assigned per extension rather than chosen.

## 5. A redeploy helper would save operators a lot

`flarenetwork/infra` ships `terraform/gcp/services/tee/redeploy-module.sh` and
`redeploy-indexer.sh`. The equivalents are needed here too, because cloud-init only runs
on first boot and Confidential Space only reads metadata at boot — so a config change
means `terraform apply -replace=<instance>`, not a plain apply, and tee-machine must be
replaced alongside tee-proxy whenever the proxy's internal IP changes.

Two operations in particular are hard to discover:

- **Flushing Redis.** While tee-machine is unreachable, tee-proxy enqueues a TEE_INFO
  action every 5s with no cap. Ours reached ~7800; the node drains FIFO at ~1/s, so the
  stack could not recover on its own for hours after the underlying fault was fixed.
  `queue direct depth N exceeds threshold 100` is logged but nothing acts on it.
- **Dropping the indexer database.** `drop_table_at_start` is hardcoded `false` in
  `modules/tee-indexer/templates/indexer/config.toml.tftpl` with no variable behind it,
  so moving `start_index` backwards requires dropping the database by hand over SSH —
  the indexer otherwise resumes from its last state row and never re-reads the earlier
  blocks.

Related: `allow_tee_proxy_ssh` is gated on `tee_machine_debug_mode`
(`modules/tee-package/proxy-server.tf:175`), so turning off debug on the Confidential
Space VM also removes operator SSH to tee-proxy, which has no attestation posture to
protect. Separate flags would be better. It bites when tee-machine restarts: tee-proxy
keeps serving its cached payload and never re-pairs, and with debug off there is no way
to restart it except replacing the VM.

## 6. The indexer image floats on `:main`, which is now 2.x

`modules/tee-indexer/indexer.tf:23` pins
`ghcr.io/flare-foundation/flare-system-c-chain-indexer:main`. That tag is currently
`v2.0.2` (2026-09-04); `v2.0.0` landed 2026-08-18 ([changelog][indexer-changelog]). So the same commit of this repo
deployed either side of that date gets a different major version of the indexer, and
nothing in the plan says so. The repo's `build-docker.yml` publishes `v*` and `latest`
alongside `main`, so pinning `:v2.0.2` costs nothing.

The config survives the jump as-is: `indexer.mode` defaults to `full`, and the one
renamed key that hard-fails startup — `indexer.num_parallel_req` -> `indexer.rpc_concurrency`
— is already spelled the 2.x way at `config.toml.tftpl:23`. (The other rename,
`timeout.timeout_millis` -> `timeout.rpc_timeout_millis`, doesn't apply; there's no
`[timeout]` block.) So this is an upgrade to take deliberately, not an outage.

### What 2.x is worth on full mode alone

- `GET /health` on port 8080: 503 during startup catchup, 200 once continuous indexing
  begins. That replaces the "SSH in and query the DB by hand" dance in TESTING.md
  section 4, and gives the systemd unit from note 1 a real readiness check — it needs
  `-p 8080:8080` there, since Konlet's port publishing is what's being replaced.
- `rpc_concurrency`, `batch_size` and `log_range` are now independent, and the
  "uneven split silently drops the batch's tail blocks" bug is fixed. The divisibility
  reasoning in the comment at `config.toml.tftpl:26-28` is obsolete — `log_range = 25`
  is still right for the 30-block public-RPC `eth_getLogs` cap, but that's the only
  reason left for it. `rpc_concurrency` is also now a process-wide ceiling rather than
  a per-fan-out limit, so the module's `10` means less node load than it used to.
- `rpc_timeout_millis` defaults to 5s instead of 1s, and continuous indexing fetches
  its `collect_logs` filters concurrently instead of one round trip each per block
  (v2.0.1). Between them these plausibly account for some of the public-RPC slowness
  TESTING.md's symptom table currently writes off as inherent rate limiting — worth
  re-measuring before accepting that entry as final.
- v2.0.2 indexes `Relay` at both its deployments ahead of the redeploy. This module
  hardcodes one `relay` address (`modules/tee-indexer/variables.tf`), so on full mode
  the cutover will silently leave a gap in signing policies on one side of it.

### FSP mode would dissolve notes 3 and half of 5, but needs checking first

`mode = "fsp"` builds the FSP filters in, resolves addresses by name through the
ContractRegistry, and derives both retention boundaries from on-chain reward epochs
instead of a block number or a wall clock ([upstream README][indexer-readme]). `indexer.start_index` and `db.history_drop`
are ignored entirely, which retires `indexer_start_index` as a variable, the whole of
note 3, and the `drop_table_at_start` half of note 5 — moving the window backwards
stops meaning "drop the database over SSH". The `relay` / `voter_registry` /
`flare_systems_manager` variables would stay only for tee-package.

The catch: FSP's selective indexing backfills **events** below the fully-indexed
window, not transactions, and tee-proxy reads two things from the `transactions` table
that the built-in FSP collectors don't cover —

- FlareSystemsManager `signNewSigningPolicy` (`6b4c7bd6`), which `pkg/policy/signatures.go`
  extracts policy signatures from;
- VoterRegistry `registerVoter` (`8f7d0957`), used in `pkg/policy/init.go`.

Both must be kept as explicit `[[indexer.collect_transactions]]` entries — 2.x merges
user entries with the built-ins, so that part is free. What isn't free is the window:
`history_epochs = 0`, the setting the upstream README recommends for providers, fully
indexes only the last ~1 hour, while `initial_signing_policy_offset = 2`
(`modules/tee-package/templates/tee-proxy/config.toml.tftpl:5`) means tee-proxy wants a
policy from two reward epochs back — ~14 hours on Coston/Coston2, ~7 days on
Flare/Songbird. So `history_epochs` has to cover at least that; 3 is the obvious
starting point, but this is the one thing to confirm against a real deploy before
switching, because the failure mode is a policy that won't initialize rather than
anything the indexer reports.

Note for either mode: 2.x adds a unique index on `states.name`, and `AutoMigrate`
refuses to create it if an existing database holds duplicates. Check before upgrading
in place:

```sql
SELECT name, COUNT(*) FROM states GROUP BY name HAVING COUNT(*) > 1;
```

[indexer-changelog]: https://github.com/flare-foundation/flare-system-c-chain-indexer/blob/v2.0.2/CHANGELOG.md
[indexer-readme]: https://github.com/flare-foundation/flare-system-c-chain-indexer/blob/v2.0.2/README.md
