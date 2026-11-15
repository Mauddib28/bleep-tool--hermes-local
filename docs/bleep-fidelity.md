# BLEEP deployment fidelity

This file is the check that the running BLEEP container still matches `docs/PLAN.md` after `main` moves. Update it when a build is taken, when a schema migration runs, or when an invariant is intentionally changed. An intentional change is also a `docs/CHANGELOG.md` entry and a `docs/PLAN.md` edit. A drift that was not accepted is a failed row, not a quiet edit of the plan.

## Invariants

| ID | Intended | How to check |
|---|---|---|
| F1 | Service `bleep` is on `hermes-net` and publishes no ports | `docker compose ps` and `docker port bleep` prints nothing |
| F2 | Hermes SSH user is `bleep@bleep`, key only, `BatchMode=yes` | SSH from uid 10000 inside `hermes-agent` |
| F3 | `terminal.backend` is local | Live `/opt/data/config.yaml` has no `terminal:` block, or `backend: local` |
| F4 | `hermes-agent` has no Docker socket | `docker exec hermes-agent docker info` fails on `unix:///var/run/docker.sock` |
| F5 | BlueZ is inside the BLEEP container | `bluetoothd` pid is in that container; `/var/run/dbus` on the WSL host is not a mount source |
| F6 | Base image is `ubuntu:24.04` | `bleep/Dockerfile` `FROM` line |
| F7 | BLEEP code is the `main` commit recorded in this ledger | Image label `org.opencontainers.image.revision` equals the ledger SHA |
| F8 | Database file survives rebuild and is the file BLEEP opens | `BLEEP_DB_PATH=/home/bleep/.bleep/observations.db` and that file's inode is on the `bleep` home volume |
| F9 | Schema moves only forward, and only after a snapshot | Ledger schema column never decreases on a successful row |
| F10 | Skill allow list matches the last accepted command set | `bleep --help` diff recorded in the ledger note |

## Upstream baseline

Read from `main` on 2026-11-09. The first build, ledger row `20261110T041823Z`, reports the same version and schema.

| Field | Value | Source |
|---|---|---|
| Application version | 3.1.0 | `bleep/docs/changelog.md`, section 3.1.0 (2026-09-13) |
| DB schema | 20 | Same section: `bleep --version` reports `BLEEP 3.1.0 (DB schema v20)` |
| Database path | `~/.bleep/observations.db`, override `BLEEP_DB_PATH` | `bleep/docs/observation_db.md` |
| Migration behavior | Transparent on schema change. v7 through v20 in the changelog are forward and additive | `observation_db.md` schema table; changelog schema notes |
| Unreleased section | "No unreleased changes yet." | changelog as fetched 2026-11-09 |

Re-read these at the first build. If `main` has moved, the first ledger row uses the new `bleep --version` output, and `docs/CHANGELOG.md` records the delta from this baseline.

Schema v20 added `devices.enumerated_at`. v19 added multi-antenna provenance columns. v18 added `sdp_records.source`. Those are examples of the bump this ledger exists to catch. The full table is in upstream `bleep/docs/observation_db.md`.

## Update procedure

Run from Ubuntu-22.04 in this repo, after `scripts/bleep-update.sh` exists. Until that script exists, do not rebuild by hand without the same steps.

1. From the running container, as user `bleep`: `bleep --version`. Parse the schema integer out of `DB schema vN`.
2. Read the image revision: `docker inspect bleep --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'`.
3. Snapshot the database on the volume:

   ```text
   /home/bleep/.bleep/observations.db.<YYYYMMDDTHHMMSSZ>.schema<N>
   ```

   Copy, do not move. Leave the live file in place so BLEEP can migrate it.
4. Build from `main` and recreate only `bleep`. Leave `ollama-local`, `hermes-agent`, `protocol-broker`, and `openclaw-gateway` running.
5. As user `bleep`: `bleep --version`, then `bleep db list`. The second command opens the database and runs BLEEP's migration.
6. Compare apt inputs. If upstream `README.md`, `setup.py`, or `dockerfile` added a system package, add it to `bleep/Dockerfile` and rebuild before calling the update successful. `bleep --check-env` is the runtime witness.
7. Diff `bleep --help` against the skill allow list in `docs/PLAN.md`.
8. Append a ledger row. On failure, restore the snapshot over `observations.db`, start the previous image, and append a failed row. Do not delete the volume.

`bleep db maintain` may run after a successful `db list`. It is not the migration.

A schema integer lower than the snapshot is a failed update even if `db list` exits 0. Restore the snapshot. This stack does not downgrade the observation database.

## Surrounding stack

Checked 2026-11-10 UTC, after the library rebuild of the same `main` commit. `bleep` is the fifth container. `scripts/verify-bleep.sh` passed earlier the same day: no published ports, no host D-Bus mount, SSH from uid 10000, hostname `bleep`, `BLEEP_DB_PATH` set, and `docker info` inside `hermes-agent` failed. `bluetoothd --nodetach -E`, `obexd`, and `bluealsa` are processes in that container and use the host network namespace. User `bleep` owns a session bus at `/run/bleep-session/bus`. Host `bluetooth.service` is disabled. That is invariant 5 and 6 in `docs/PLAN.md`. F8's database file was absent at the build snapshot (`NOFILE`). `bleep db list` later opened it, and the file now holds device rows. The library rebuild did not change the git SHA or the schema, so it did not add a ledger row. F9 and F10 for a later `main` move are still future rows. The failed-restore and schema-downgrade branches in `scripts/bleep-update.sh` have not been exercised.

At 12:20:34 UTC a stack restart left `sshd` running and the buses dead. Health was `unhealthy` until a recreate at 13:38 UTC. The entrypoint from that image started each daemon once. The same SHA now waits for the socket and supervises the daemons. That change is not a `main` move and does not add a ledger row. After the recreate, bus `1-14` was `Shared` and `/sys/class/bluetooth` was empty. Attaching it restored controller `94:E6:F7:A1:D6:B3`. `scripts/bleep-status.sh` reports a missing daemon and a missing `hci0`. `scripts/verify-bleep.sh` requires the five processes and does not require the radio.

`hermes-agent` publishes only `127.0.0.1:9119`. `ollama-local` publishes nothing. `protocol-broker` and `openclaw-gateway` publish nothing. The seed `config/config.yaml` has no `terminal:` block, and the Hermes compose service does not mount a Docker socket. Host `ollama.service` is disabled and inactive. `bash scripts/verify.sh` printed `PASS` on 2026-11-10. The operator commands are in `docs/OPERATOR.md`. The dashboard at `http://127.0.0.1:9119/` redirects to the basic-auth login page. The session token remains the bearer credential. On 2026-11-10 the Windows listener for that port returned an empty reply while uvicorn inside the container still served `/login` (HTTP 200, 10180 bytes). `docker stop` and `docker start` of `hermes-agent` replaced the listener. That was not a BLEEP image change. The 14:00 UTC scan then recorded `br-connection-profile-unavailable` for kali and `br-connection-key-missing` for Dingo with BlueALSA already registered. Those results are host limits. Pairing stays off the skill.

On 2026-11-12 the running image still reports revision `dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85` and `BLEEP 3.1.0 (DB schema v20)`. It diverges from that commit by `bleep/patches/db-report-stdout.patch`: a terminal `db report` without `--out` prints the markdown and does not call `save_report`. `--out` still writes a file. The 02:50 UTC cron run confirmed that split: the tool stdout is the markdown and the AOI directory did not gain a file. That divergence is local. It is not a `main` move and it does not add a ledger row. The pre-patch image tag is `bleep-local:dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85-pre-report-stdout`. The database copy taken before the recreate is `observations.db.20261112T003242Z.schema20` on the `bleep-home` volume.

## Ledger

Successful and failed updates both get a row. The baseline is not a deployment. The 2026-11-09 Hermes and OpenClaw deployment is recorded in `docs/CHANGELOG.md`, not in this table.

| Date (UTC) | Result | Git SHA | `bleep --version` | Schema before | Schema after | Snapshot | Notes |
|---|---|---|---|---|---|---|---|
| 2026-11-09 | baseline | not built | 3.1.0 (DB schema v20), from upstream changelog | — | — | — | Planning read of `main`. No container, no database file. |
| 20261110T041349Z | failed | `dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85` | container not healthy | none | none | NOFILE | health=starting |
| 20261110T041823Z | built | `dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85` | BLEEP 3.1.0 (DB schema v20) | 20 | 20 | NOFILE | no database file before build; db list exited 0 |
| 20261111T221128Z | built | `dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85` | BLEEP 3.1.0 (DB schema v20) | none | 20 | NOFILE | no database file before build; db list exited 0 |

## Skill allow list

Updated 2026-11-10 after the passive scan returned devices. Job `b470c8e8c1e7` runs every 30 minutes: passive scan, naggy scan, classic scan, then read-only enumeration of each address from that run. Job `8f19578228c5` runs the read-only database report every 4 hours.

- `bleep --version`
- `bleep --help`
- `bleep --check-env`
- `bleep scan --timeout 15 --variant passive`
- `bleep scan --timeout 15 --variant naggy`
- `bleep scan --timeout 15 --variant pokey`
- `bleep scan --timeout 15 --variant brute`
- `bleep classic-scan --timeout 10`
- `bleep gatt-enum ADDRESS`
- `bleep gatt-enum --correlate ADDRESS`
- `bleep gatt-enum --deep ADDRESS`
- `bleep gatt-enum --report ADDRESS`
- `bleep explore --connection-mode passive --timeout 10 ADDRESS`
- `bleep classic-enum --connectionless --analyze ADDRESS`
- `bleep enum-scan --variant passive ADDRESS`
- `bleep enum-scan --variant naggy ADDRESS`
- `bleep connect --ble-only --no-profiles ADDRESS`
- `bleep db list`
- `bleep db list --fields mac,name,rssi_last,rssi_min,rssi_max,first_seen,last_seen`
- `bleep db report --format markdown --all-in-window --recon --name-audit --group-identity --identity-contrast`
- `bleep db show --full ADDRESS`
- `bleep db timeline ADDRESS`

Not accepted: REPL, `bleep user --menu`, `bleep debug`, pairing, adapter writes, advertising, GATT server, `enum-scan --variant brute` and its write flags, phone-book or file profiles, audio intercept, `bleep ctf`, `db maintain`, `db export`, `--out`, `--export-targets`, `--promote`.
