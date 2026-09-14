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
