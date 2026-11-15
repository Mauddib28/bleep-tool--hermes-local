# TODO

The BLEEP service is running at `main` commit `dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85`. Check a remaining BLEEP item only after the fidelity ledger in `docs/bleep-fidelity.md` has the evidence named on that item.

The Hermes and OpenClaw deployment from `docs/CHANGELOG.md` (2026-11-09) is running. Its remaining checks are in the first section. Repeatable commands, including the elevated Windows logon task, are in `docs/OPERATOR.md`.

## Deployed stack

Checked on 2026-11-09. Evidence is in the changelog's Deployment section.

- [x] Pin Hermes to digest `sha256:adb7890916de63245523492be8f68f9d2095fecbec4e2a6dab7960381f0fc002` and OpenClaw to digest `sha256:6cb72e1599b3b76e2ea3dcc2f4dd7f112247367fbecadfcdee8caa7423f4989b`.
- [x] Leave Ollama, Hermes API `8642`, broker `8787`, and OpenClaw `18789` unpublished. Publish the dashboard as `127.0.0.1:9119:9119` only.
- [x] Require the dashboard session token file. Unauthenticated `GET /api/config` is `401`. The HTML does not contain `__HERMES_SESSION_TOKEN__=`.
- [x] Keep `qwen3.5:latest` at context `65536`, and set `database.journal_mode` to `wal` in the seed and in the live `/opt/data/config.yaml`.
- [x] Leave `terminal.backend` unset and keep the Docker socket off `hermes-agent`.
- [x] Add `protocol-broker` and the OpenClaw `direct-hermes` skill. One delegated run returned `pong` (`run_69376c03f81d47b28b58ea1c750537fb`) and loaded `qwen3.5:latest` at context `65536`.
- [x] Store keys under `/home/user/hermes/keys/` and OpenClaw state under `/home/user/hermes/openclaw`. Do not commit them.
- [x] Disable the host unit. `ollama.service` is disabled and inactive. `bash scripts/verify.sh` printed `PASS` on 2026-11-10.
- [x] Stop the host Bluetooth daemon. `bluetooth.service` is disabled. After `bleep` was recreated, `bleep --check-env` reports `AdvertisementMonitorManager1` and `Adapter1.ConnectDevice` on `hci0`.
- [x] Browser sign-in is `dashboard.basic_auth`, username `admin`. The password is `/home/user/hermes/keys/dashboard.password` (mode `600`, uid `10000`). The session-token file remains the bearer credential for Hermes Desktop and `/api/status`.

## BLEEP image and service

- [x] Add `bleep/Dockerfile` based on `ubuntu:24.04`, with BlueZ, PyGObject, D-Bus, and OpenSSH. Clone `https://github.com/Mauddib28/bleep-tool` `main` at build and record `git rev-parse HEAD` in `org.opencontainers.image.revision`. Built `dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85`.
- [x] Add a headless entrypoint: system D-Bus, a session bus for user `bleep`, `bluetoothd --nodetach -E`, `obexd`, `bluealsa`, and `sshd -D`. The Bluetooth daemons join the host network namespace. The entrypoint waits until each bus accepts a connection, then a supervisor restarts a daemon that exits. Do not mount the WSL host `/var/run/dbus`.
- [x] Add the `bleep` service to `docker-compose.yaml` on `hermes-net`, with `NET_ADMIN`, `NET_RAW`, and `SYS_ADMIN` for the host network namespace, no published ports, no GPU, and `BLEEP_DB_PATH=/home/bleep/.bleep/observations.db`.
- [x] Mount a named volume at `/home/bleep` so `~/.bleep/observations.db` and `~/.local/share/bleep/logs/` survive rebuilds.
- [x] Create the `bleep` user in group `bluetooth`. Install only that user's public key for SSH.

## Hermes access

- [x] Generate an ed25519 key for uid 10000 at `/home/user/hermes/keys/bleep_ed25519`. Mount it read-only into `hermes-agent` at `/run/secrets/bleep_ed25519`.
- [x] Leave `terminal.backend` unset (`local`). Confirm `config/config.yaml` and the live `/opt/data/config.yaml` do not gain an SSH backend.
- [x] Seed skill `bluetooth/bleep` with the allow list in `docs/PLAN.md`. The skill SSHes to `bleep@bleep` with `BatchMode=yes`.
- [x] Confirm the Docker socket is still absent from `hermes-agent`.

## Tracking `main`

- [x] Add `scripts/bleep-update.sh`. It records the running revision and `bleep --version`, snapshots `observations.db` to `observations.db.<utc>.schema<N>`, rebuilds from `main`, recreates only `bleep`, runs `bleep --version` and `bleep db list`, and appends a ledger row.
- [ ] On a failed `bleep db list`, restore the snapshot, keep the previous image, and write a failed row. Do not delete the volume. The script has this path. It has not been exercised.
- [ ] Refuse to continue when the new schema integer is lower than the snapshot's schema integer. The script has this path. It has not been exercised.
- [x] Diff upstream `README.md`, `setup.py`, and `dockerfile` for new apt packages. Add any new package to `bleep/Dockerfile` in the same change. Done for `dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85`. The image also installs `libbluetooth3`, `libbluetooth-dev`, `bluez-obexd`, `bluez-alsa-utils`, ALSA, sox, and the GStreamer 1.0 typelib and plugins. Those are beyond the upstream dockerfile and are recorded in `docs/CHANGELOG.md`. Repeat when `main` moves.
- [x] Diff `bleep --help` against the skill allow list. Update the skill only for accepted command changes, and record that in `docs/CHANGELOG.md`. Skill 1.1.0 adds the enumeration commands. Skill 1.2.0 adds the read-only `db report` path. Skill 1.3.0 splits `--deep` from `--report` and adds `--correlate`. Repeat when `main` moves.

## Verification

- [x] Phase 1: `bleep --version` over SSH from uid 10000. Hostname is the BLEEP container (`bleep`). Ledger row written.
- [x] Phase 1: a second build of the same commit leaves the schema row unchanged. `scripts/bleep-update.sh` printed `not rebuilding` and did not append a row.
- [x] Phase 1: `docker info` inside `hermes-agent` still cannot reach a daemon.
- [x] Phase 2: Intel controller `94:E6:F7:A1:D6:B3` is `Powered: yes` inside `bleep`. `bleep scan --timeout 15 --variant passive` returned 16 devices with no prompt.
- [x] Phase 3: one Hermes turn uses the skill, and the `skill_manage` edit is on disk. Run `run_66618cc2b4d84dcf99c83c9743917c4e` quoted `BLEEP 3.1.0 (DB schema v20)` and patched `/opt/data/skills/bluetooth/bleep/SKILL.md` to version `1.3.1`. The repo seed matches that file. Run `run_e1863356831c48fbb93fd218afd685f9` is the earlier version-only turn.
- [x] Implement `docs/REPORT-WRITER.md`. The 02:50 UTC job wrote no AOI file. The tool stdout is the markdown. The cron response rewrote it. That quote failure is the next open item.
- [x] Skill `1.3.4` told a truncated report to page `full_output_path`. The stored prompt still required four sections. The 06:50 and 10:50 UTC responses rewrote the report and invented `db_report_` names. The AOI directory stayed at 29 names.
- [x] The 14:50 UTC model response `2026-11-12_14-51-56.md` copied 10 device rows of a 5901-line report and wrote `[truncated`. The AOI directory stayed at 29 names.
- [x] Read the no-agent reports. `2026-11-12_22-50-18.md` through `2026-11-13_14-50-25.md` start with `[identity-contrast]`, contain `# Aggregate Security Report` and `**Other AD structures:**`, and contain no `[truncated`, no `db_report_`, and no `saved to`. The 14:50 report loaded 948, analyzed 140, and listed 808 as not reachable. The AOI directory is still the same 29 names, last `db_report_20261111_225014.md`.
- [x] `2026-11-14_05-41-27.md` through `2026-11-14_16-09-59.md`: inquiry was empty, and `00:01:95:4B:40:69` reached `classic-enum` from `br-connection-`. Eighteen scans printed 10 SDP records from `browse+xml`, with RFCOMM channels, no `Connecting to`, and no `Pairing required`. Four scans stopped at `not reachable via L2CAP` and skipped SDP. The `records` source timed out after browse and xml had already returned. Reports `06:50`, `10:50`, and `14:50` are complete. Analyzed went from 170 to 199. The AOI directory is still 29 names.
- [x] `discover_services_sdp_connectionless` prints `[classic_sdp] l2ping failed: …; continuing with SDP` and still runs the SDP query. `_discover_sdp_merged` prints `[classic_sdp] records skipped: browse and xml already returned records` and does not run `records` in that case. Image patch `bleep/patches/sdp-continue.patch`. At 01:41 UTC a scan wrote pip and `bleep scan` scripts under `/opt/data/cache/`. Leave those files.
- [x] `scripts/up.sh` pins `BLEEP_REVISION`, copies the bleep skill and both no-agent scripts, and `scripts/install-bleep-cron.sh` reconciles the scan and report jobs without editing the three research jobs. `scripts/down.sh` keeps `ollama`, `bleep-home`, and `/home/user/hermes`.
- [ ] A `down.sh` then `up.sh` drill has not been run. Do not delete `bleep-home` or the `ollama` volume to run it. Run it only while both BLEEP jobs are scheduled.
- [x] `scripts/docker-clean.sh` is the scoped cleanup. `--dry-run` prints the commands. It has not been run. Tagged BLEEP images and volumes `bleep-home` and `ollama` are not in the removal list.
- [x] Scans `2026-11-14_17-11-47.md` through `2026-11-15_12-39-39.md`: 36 runs found 10 SDP records and printed `records skipped`. Eleven of those also printed `l2ping failed` and still finished SDP. None printed `records timed out`, `SDP query skipped`, `Connecting to`, or `Pairing required`. Four scans had no `br-connection-` and no inquiry hit, so they did not run `classic-enum`. Reports `18:50` through `10:50` are complete. Analyzed went from 205 to 240. The AOI directory is still 29 names.
- [ ] The 10:50 report lists 10 SDP records for `00:01:95:4B:40:69`, including PBAP, MAP, OPP, and HFP, and still prints `Services: None` and `Risk Score: 0/10`. The summary row is `0/10`. SDP is stored and not scored. The correction is `docs/REPORT-SCORE.md`. That plan has not been applied.
- [x] Keep the database report off the scan's current minute. Job `8f19578228c5` is `50 2,6,10,14,18,22 * * *`, next `2026-11-10T22:50:00Z`. Job `b470c8e8c1e7` is `5,35 * * * *`, next `2026-11-10T21:35:00Z`.
- [x] Implement `docs/NEXT.md` sections 1–5. Skill `1.3.2` (sha256 `869936769a3010a290a2c0a7057814e5bda0b7ddfb4e5f6d8a47fd270ffe028f`) is on the seed and the live file. Both prompts were appended. The scan schedule is `5,35 * * * *`. `scripts/bleep-status.sh` exits 1 on the current newest scan and report.
- [x] Clear the battery flags on `HermesUsbipdBluetooth` from an elevated PowerShell prompt. `Set-ScheduledTask` returned Ready. `schtasks /Query` now leaves `Power Management` blank. Last result is still `267011`: the task has not run. The action is still `usbipd.exe attach --wsl --busid 1-14`. Logon mode is Interactive only.

## Explicitly later

- [ ] Pairing, adapter writes, GATT characteristic writes (`enum-scan --variant brute`), file or phone-book profiles, audio intercept, and `bleep ctf`. Needs a separate acceptance. Read-only GATT and SDP enumeration is already on the skill.
- [x] BlueALSA is installed and started in the BLEEP image so `gatt-enum` has one profile handler. PipeWire and PulseAudio are not installed. Audio intercept, phone-book, and file-transfer commands stay off the skill.
