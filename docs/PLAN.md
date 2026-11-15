# Plan: headless BLEEP container tracked to upstream `main`

Status: running. Image `bleep-local:dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85`. `bleep --version` is `BLEEP 3.1.0 (DB schema v20)`. `scripts/verify-bleep.sh` passed on 2026-11-10 UTC.

This plan supersedes the earlier pin to BLEEP v3.1.0. The BLEEP application follows `main`. The Ubuntu base image stays pinned.

The stack this service joins is running. See `docs/CHANGELOG.md`. Repeatable commands are in `docs/OPERATOR.md`. `docs/NEXT.md` sections 1–6 are applied. The report-writer batch is `docs/REPORT-WRITER.md`. It was applied on 2026-11-12. The 02:50 UTC job wrote no AOI file. Jobs `b470c8e8c1e7` and `8f19578228c5` are no-agent scripts `bleep-scan.py` and `bleep-db-report.py`. The 22:50 UTC report ran. Skill `1.3.10` also runs `classic-enum --connectionless --analyze --sdp-source merge` when GATT output contains `br-connection-`. The image revision is still `dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85`, pinned in `.env.example`. `scripts/up.sh` does not follow upstream `main`. Local patches are `bleep/patches/db-report-stdout.patch`, `bleep/patches/sdp-source-stdout.patch`, `bleep/patches/classic-hostnet.patch`, and `bleep/patches/sdp-continue.patch`. `docs/REPORT-SCORE.md` is the report-scoring plan. It has not been applied, and the image was not rebuilt for it. `sdptool` and `l2ping` enter the host network namespace through `/usr/local/sbin/bleep-hostnetd`. The five no-agent reports through 14:50 UTC passed, and the 14:50 report left 808 devices unanalyzed. The daemon image was recreated at 22:15 UTC on 2026-11-13. Scans from 22:42 through 04:39 UTC found no classic devices, so SDP did not run. A failed `l2ping` is printed and the SDP query still runs. `records` is skipped when `browse` and `xml` already returned records. The next scan is the check. The logon task allows battery, and it has not run (`267011`). `ollama-local`, `hermes-agent`, `protocol-broker`, `openclaw-gateway`, and `bleep` are up. Host `ollama.service` is disabled and inactive. `bash scripts/verify.sh` printed `PASS` on 2026-11-10. Host `bluetooth.service` is disabled and must stay disabled. The dashboard is loopback-only. Browser sign-in is `dashboard.basic_auth`. The session token remains the bearer credential. A browser open of port `9119` is not a BLEEP check.

## Intent

Run BLEEP in its own headless Linux container. Hermes uses that container for BLEEP commands and records procedure changes as skills. The WSL distro is not the BLEEP host, and the Hermes container is not the BLEEP host.

```text
hermes-net
  ollama-local       model API, no host port
  hermes-agent       gateway; dashboard 127.0.0.1:9119; API 8642 unpublished
  protocol-broker    POST /objectives to Hermes; port 8787 unpublished
  openclaw-gateway   loopback inside the container; directs Hermes through the broker
  bleep              Ubuntu 24.04, its own BlueZ, bleep from main dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85, sshd
```

## Invariants

These stay true across upstream `main` updates.

1. `bleep` is a compose service on `hermes-net` with no published ports.
2. Hermes reaches it as `bleep@bleep` over SSH, key only, `BatchMode=yes`. The private key is `/home/user/hermes/keys/bleep_ed25519`, mode `600`, uid `10000`, mounted read-only at `/run/secrets/bleep_ed25519`. It is not under the Hermes data directory and it is not in git.
3. `terminal.backend` stays `local`. That shell is the Hermes container. Only the BLEEP skill SSHes to the BLEEP container. The daily research cron must not start running on the BLEEP box.
4. The Docker socket stays out of `hermes-agent`.
5. BlueZ runs inside the BLEEP container: system D-Bus, a session bus for user `bleep`, `bluetoothd --nodetach -E`, `obexd`, and `bluealsa`. The container does not mount the WSL host `/var/run/dbus`. The WSL host `bluetooth.service` stays disabled so it does not hold the L2CAP socket.
6. Capabilities are `NET_ADMIN`, `NET_RAW`, and `SYS_ADMIN`. `SYS_ADMIN` exists so `bluetoothd` can enter the host network namespace. A container network namespace returns `EAFNOSUPPORT` for `AF_BLUETOOTH`, and `bluetoothd` exits. SSH stays on `hermes-net`. The SSH user is `bleep`, in group `bluetooth`. Root-only adapter writes stay out of the seed skill.
7. The base image is `ubuntu:24.04`. Upstream BLEEP's `dockerfile` uses `ubuntu:latest`; this deployment does not.
8. The BLEEP source ref is the `main` branch of https://github.com/Mauddib28/bleep-tool. It is not a floating tag and not a pinned release.
9. The observation database and BLEEP logs survive image rebuilds. See the schema section.
10. The skill may discover devices and read their GATT or SDP records. It may not write characteristics, pair, change the adapter, transfer files, intercept audio, or run `bleep ctf`.

## Image

Build from this repo, not from upstream `docker.sh`. Upstream `docker.sh` mounts the host system bus and starts an interactive shell:

```bash
docker run -v /var/run/dbus/:/var/run/dbus/:z --privileged -it bleep-project-image bash
```

Source: https://github.com/Mauddib28/bleep-tool/blob/main/docker.sh

The image installs `bluez`, `libbluetooth3`, `libbluetooth-dev`, `bluez-obexd`, `bluez-alsa-utils`, the GStreamer 1.0 typelibs and plugins `audio_codec.py` imports, `python3-gi`, `python3-gi-cairo`, `dbus`, and `openssh-server`, clones `main` at build, and runs `pip install -e .`. `dbus-python` stays the pip 1.5.1 package. Apt `python3-dbus` is 1.3.2 and is not installed over it. PulseAudio and PipeWire are not installed. The image label `org.opencontainers.image.revision` is the `git rev-parse HEAD` captured during that build. Apt package names that `main` newly requires are added to this Dockerfile in the same change that records the revision. They are not left as a runtime surprise.

Process 1 is headless: system D-Bus, a session bus for user `bleep`, `bluetoothd --nodetach -E`, `obexd`, `bluealsa`, then `sshd -D`. The entrypoint waits until each bus socket accepts a connection before it starts the clients of that bus. A supervisor then restarts a daemon that exits. The three Bluetooth daemons are started with `nsenter --net=/hostns/net`. `-E` is what `bleep --check-env` requires for `Adapter1.ConnectDevice`. Compose mounts `/proc/1/ns/net` at `/hostns/net`. Without that mount, `bluetoothd` logs `Failed to access management interface` and the healthcheck stays failed even when no adapter is present. The healthcheck is `pgrep sshd` and `pgrep bluetoothd`. It does not know whether `hci0` exists. `scripts/bleep-status.sh` checks the five processes and `hci0`. `scripts/verify-bleep.sh` checks the container and the SSH path, and it does not require the radio.

## Persistence and schema

BLEEP stores the observation database at `~/.bleep/observations.db` unless `BLEEP_DB_PATH` is set. Schema version is reported by `bleep --version`, currently `BLEEP 3.1.0 (DB schema v20)` on `main` as read on 2026-11-09. Logs are under `~/.local/share/bleep/logs/`.

Sources:

- https://github.com/Mauddib28/bleep-tool/blob/main/bleep/docs/observation_db.md
- https://github.com/Mauddib28/bleep-tool/blob/main/bleep/docs/changelog.md (3.1.0, 2026-09-13)

`observation_db.md` says migrations occur transparently when the schema version changes. The changelog's schema notes from v7 through v20 are forward and additive (new columns, new tables, or a table rebuild that keeps rows). This deployment treats that as BLEEP's job, performed the first time the new code opens the existing file.

Compose sets:

```text
BLEEP_DB_PATH=/home/bleep/.bleep/observations.db
```

and mounts a named volume at `/home/bleep`. That keeps the database, logs, and the SSH user's home across `docker compose up --build`.

Rebuild order is fixed:

1. Read `bleep --version` and the image revision from the running container.
2. Copy `observations.db` to a dated snapshot on the same volume: `observations.db.<utc-timestamp>.schema<N>`.
3. Rebuild the image from `main` and recreate only the `bleep` container.
4. Run `bleep --version`, then `bleep db list`, as the `bleep` user. `db list` opens the database and is the migration trigger.
5. Append a row to `docs/bleep-fidelity.md`.

A schema number that is lower than the snapshot's number stops the rollout. Restore the snapshot and the previous image. BLEEP's published migrations do not describe a downgrade. A jump of more than one version is allowed only when `bleep db list` exits 0 and `bleep --version` reports the new code's schema. A failed open restores the snapshot and is recorded as a failed update.

`bleep db maintain` (`VACUUM` + `ANALYZE`) is optional after a successful migration. It is not a substitute for the snapshot.

## Hermes skill

Seed `bluetooth/bleep` under the Hermes data skills directory so `skill_manage` can edit it later. `skill_manage` writes on the Hermes filesystem. The commands inside the skill run on the BLEEP container.

Allow list after the 2026-11-10 enumeration acceptance:

- `bleep --version`, `bleep --help`, `bleep --check-env`
- `bleep scan --timeout 15 --variant passive|naggy|pokey|brute`
- `bleep classic-scan --timeout 10`
- `bleep gatt-enum ADDRESS`, `bleep gatt-enum --correlate ADDRESS`, `bleep gatt-enum --deep ADDRESS`, and `bleep gatt-enum --report ADDRESS` (`--report` does not persist characteristics)
- `bleep db list --fields mac,name,rssi_last,rssi_min,rssi_max,first_seen,last_seen`
- `bleep explore --connection-mode passive --timeout 10 ADDRESS`
- `bleep classic-enum --connectionless --analyze ADDRESS`
- `bleep enum-scan --variant passive|naggy ADDRESS`
- `bleep connect --ble-only --no-profiles ADDRESS`
- `bleep db list`
- `bleep db report --format markdown --all-in-window --recon --name-audit --group-identity --identity-contrast`
- `bleep db show --full ADDRESS`
- `bleep db timeline ADDRESS`

`scan --variant brute` is BLEEP's BR/EDR-then-LE discovery scan. `enum-scan --variant brute` writes characteristic values and is not on this list.

After each `main` update, diff `bleep --help` against that allow list. New subcommands do not enter the skill until they are accepted and the changelog says so. Removed or renamed subcommands are deleted from the skill in the same update that records the new revision.

## Radio

Phase 1 does not need a controller. `bleep --version` over SSH is enough to prove the tool path.

The Intel adapter `8087:0029` on Windows bus `1-14` is attached to WSL with `usbipd attach --wsl --busid 1-14`. A logon task that runs that attach needs an elevated `schtasks` create, which this session could not register (`Access is denied`). From an elevated Windows prompt:

```bat
schtasks /Create /SC ONLOGON /TN HermesUsbipdBluetooth /TR "C:\Program Files\usbipd-win\usbipd.exe attach --wsl --busid 1-14" /F
```

That create later succeeded from an elevated prompt. A second elevated prompt cleared the battery flags on 2026-11-10. `schtasks /Query` leaves `Power Management` blank. The task is enabled, at logon, last result `267011`, and it has not run. Do not recreate the task.

`usbipd list` showing `Shared` means the device is allowed, not that WSL has it. `bluetoothd` inside `bleep` joins the host network namespace and owns controller `94:E6:F7:A1:D6:B3`. That attach does not survive reboot or a WSL restart. Until it is repeated, `/sys/class/bluetooth` is empty, `bleep --check-env` reports `Adapter1.ConnectDevice` missing, and the 30-minute job has nothing to scan. `bluetoothctl` and `btmgmt` in the container network namespace cannot open the management socket. Run them with `nsenter --net=/hostns/net`. Host `bluetooth.service` stays disabled. If that unit is started, container `bluetoothd` logs `l2cap_bind: Address already in use` and cannot register the adapter.

`bash scripts/bleep-status.sh` is the check to run from Ubuntu after a recreate, a reboot, or a cron run that looks successful. It exits 1 when one of the daemons is missing, including `bleep-hostnetd`, `hci0` is absent, the newest scan response has no `db list` header, the newest report response contains `rest of report continues`, or `/home/bleep/.bleep/aoi/reports/` has a name outside the six-file list in `docs/NEXT.md`. The scan and report files are the newest `.md` under the output directory of the job whose script is `bleep-scan.py` or `bleep-db-report.py`. The scan header is `MAC NAME RSSI_LAST RSSI_MIN RSSI_MAX FIRST_SEEN LAST_SEEN`. `bleep db list` prints it in upper case, so a search for lowercase `rssi_last` misses a real quote. It prints the recreate command or the `usbipd attach` command for a daemon or radio gap. A row in `hermes cron list` that says `ok` is not that check. The scan text is the latest file in `/opt/data/cron/output/b470c8e8c1e7/` inside `hermes-agent`, and only the text after the last `## Response` line counts. `bash scripts/bleep-status.sh --self-test` exercises that split on strings and does not read `/opt/data`. On 2026-11-11 `2026-11-11_00-43-43.md` passed the header check and `2026-11-10_22-55-32.md` was not abbreviated. The run exited 1 on `db_report_20261110_225040.md`, `db_report_20261110_225044.md`, and `db_report_20261110_225322.md`.

These BlueZ results are enumeration limits on this host, including after `bluealsa` has registered HFP, HSP, and A2DP. They are not a dead bus:

- `br-connection-profile-unavailable` — seen for kali `00:01:95:6F:D4:99`. BlueZ has no profile for that BR/EDR connection.
- `br-connection-key-missing` — seen for Dingo `00:01:95:4B:40:69`. BlueZ wants a link key. Pairing stays off the skill.
- `Method "Connect" doesn't exist` — seen for iPhone 14 `D8:3A:DD:0B:69:B9`.
- `BAP requires ISO Socket which is not enabled`, `Failed to set privacy: Rejected (0x0b)`, and `Failed to open RFKILL control device` are properties of this WSL kernel.

The allowed next command for an address with no GATT is `bluetoothctl disconnect ADDRESS`, then `classic-enum --connectionless --analyze --sdp-source merge`, when `classic-scan` printed that address or the GATT output contains `br-connection-`. `l2ping` and `sdptool` run in the host network namespace. A failed `l2ping` is printed and the SDP query still runs. `records` is skipped when `browse` and `xml` already returned records. The command does not call `Device1.Connect`. It does not extract GATT. `scan --variant pokey` repeats short discovery. It does not connect.

Job `b470c8e8c1e7` is `5,35 * * * *`, set on 2026-11-10 after the interval had drifted toward minute 50. The next scan after that edit was `2026-11-10T21:35:00Z`. Job `8f19578228c5` stays `50 2,6,10,14,18,22 * * *`, next `2026-11-10T22:50:00Z`. Both jobs still tell the run to quote command output, to skip `--out`, and to create no files under `/home/bleep`. The stored prompts were appended, not replaced. The 14:27 UTC report had already written `/home/bleep/.bleep/aoi/reports/db_report_20261110_142503.md`. That file stays. The database volume is not deleted to remove it.

## Phase 3

Done on 2026-11-10. Run `run_66618cc2b4d84dcf99c83c9743917c4e` completed with tools `terminal` and `skill_manage`, one call each. The assistant output contains `BLEEP 3.1.0 (DB schema v20)`. The live file and the repo seed `skills/bluetooth/bleep/SKILL.md` are version `1.3.1`, sha256 `f315096cc869456949a0711f5db93888b80278668ddd6866f8cafd9da83b87c6`, mode `644`, uid `10000`. The diff against `1.3.0` is the version line and the adapter sentence. The checker accepts that byte match with one or more `skill_manage` calls. This run had one. The allow list and the not-allowed list are unchanged. `jobs.json` sha256 stayed `5855735dbb0fcb590492267b61aee5c3c6766742f2045d2d3789f4dbb6b119c2`. The sorted file list under `/home/bleep` stayed sha256 `3c4ac7f4c4f351c466193f36e0bdce66b1fdf0314c299244716ce9d794da4556`. `pending/skills/` does not exist.

Two earlier turns were restored before this one. `run_74d20fe875ca4516a7275ed73d14c36d` appended a backtick to the adapter sentence. `run_ad759ee4864c4299ba1a0136e88240a3` called `skill_manage` three times and one call returned an error; its final text was the same two-line diff, and the script still restored it because that run was not one call. The snapshot of `1.3.0` remains `/tmp/bleep-skill-1.3.0.md` inside `hermes-agent`, sha256 `1df35462abff4264e9198a2c168e59e1e4d6d706d5097dcc661ef88140a48a33`.

Run `run_e1863356831c48fbb93fd218afd685f9` is not this phase. It completed with output `BLEEP 3.1.0 (DB schema v20)`, sent no `approval.request`, and left `/opt/data/skills/bluetooth/bleep/SKILL.md` untouched. `scripts/bleep-use-once.py` posts that same version-only prompt on session `bleep-verify`. Reusing that session continues a turn that was told to reply with the version line and nothing else.

This phase is one new Hermes API turn. It runs `bleep --version` through the skill's SSH command, then `skill_manage` patches the live skill. The allow list does not change. The turn is not a cron edit, not a scan, and not a broker objective.

### What the tool does

`skill_manage` is the `skills` toolset in Hermes 0.23. The advertised call is an `operations` array. A `patch` op takes `name`, `old_string`, and `new_string`. `content` on a `patch` replaces the whole file. `create`, `delete`, `write_file`, and `remove_file` are the other ops. The name `bluetooth/bleep` resolves to the directory under the profile skills root. The bare name `bleep` matches that directory too. Use the categorized name.

`skills.write_approval` is unset in `/opt/data/config.yaml`. `write_approval_enabled` treats an unset key as off, so a successful `skill_manage` writes the file in the same call. It does not emit `approval.request`, and it does not leave a record under `pending/skills/`. `scripts/bleep-use-once.py` only stops the run when that event arrives, so it would not catch a bad skill rewrite. Leave the gate off. Cron has no approver. Turning the gate on would park later skill writes in `pending/skills/` and they would never land.

`scripts/up.sh` copies `skills/bluetooth/bleep/SKILL.md` only when the live file is absent. A bad live write survives the next `up.sh`. Snapshot the live file before the turn, and restore it when the diff fails.

### Preflight

These were the gates for the run above. A later execution of `scripts/bleep-phase3.py` stops in preflight because the live file is no longer version `1.3.0`. The file on disk after `docs/NEXT.md` is `1.3.2`.

1. `docker exec -u 10000 -e HOME=/opt/data hermes-agent hermes cron list` shows job `b470c8e8c1e7` as completed, not `running`. That job and this turn both use the skill and Ollama. At 16:30 UTC on 2026-11-10 the 16:25 slot was still executing (`3669e5e23bda4e15a60709d21a77b76a`).
2. `bash scripts/bleep-status.sh` exits 0. `bleep --version` does not need `hci0`, but a down bus is not the condition this phase records.
3. Live `/opt/data/skills/bluetooth/bleep/SKILL.md` is still version `1.3.0` and still contains the sentence `If a command prints `Bluetooth adapter not found or not ready`, quote that line and stop. Do not fill the report from an earlier run.`
4. That file does not contain `n/10` or `[CRON_FAILURE]`. Those rules are only in the cron prompts.
5. Copy the live file to `/tmp/bleep-skill-1.3.0.md` inside `hermes-agent` and record its sha256. Owner stays uid `10000`.

### The turn

Add `scripts/bleep-phase3.py`. Do not change the prompt in `scripts/bleep-use-once.py`. The new script follows that file's HTTP client: it reads `API_SERVER_KEY` from `/opt/data/.env` inside the container, posts `POST /v1/runs` to `http://127.0.0.1:8642`, and reads `/v1/runs/<id>/events`. It does not print the key. Run it as uid `10000` with `HOME=/opt/data`.

Session header: `X-Hermes-Session-Key: bleep-phase3`. Do not post this to `protocol-broker`. The broker denies every `approval.request` and its Hermes timeout is 180 seconds.

Prompt:

```text
Use the bluetooth/bleep skill. Do two things and then stop.

1. Run one SSH command, the skill's SSH command, with the remote command `bleep --version`. Quote that output. Do not scan, connect, enumerate, or write the observation database.

2. Call skill_manage once. name is bluetooth/bleep. operations is exactly two patch operations, in this order. Do not pass content. Do not create, delete, or add a file.

First patch: old_string is `version: 1.3.0` and new_string is `version: 1.3.1`.

Second patch: old_string is `If a command prints `Bluetooth adapter not found or not ready`, quote that line and stop. Do not fill the report from an earlier run.` and new_string is `If a command prints `Bluetooth adapter not found or not ready`, the first line of the response is exactly [CRON_FAILURE], then quote that line and stop. Do not fill the report from an earlier run. Do not invent an n/10 risk score. Do not describe a device as paired.`

Do not change the allow list or the not-allowed list. Do not pair, write characteristics, change the adapter, transfer files, intercept audio, or run bleep ctf.
```

On `approval.request`, compare the command with the skill's SSH prefix and a remote command of `bleep --version`. Any other command is denied, the run is stopped, and the script exits 2. A shell pipeline, a second `bleep` subcommand, or a write under `/home/bleep` is that failure.

### Accept or restore

The script prints `run_id`, `status`, the assistant output, and `diff -u` of the snapshot against the live file. It then restores the snapshot unless every check below passes. A failed diff must not remain on disk for the next 30-minute scan. Print the rejected diff before the restore. Leave the snapshot in `/tmp` until the review is written down.

Pass:

- `status` is `completed`.
- The assistant output contains `BLEEP 3.1.0 (DB schema v20)`.
- The event stream shows the version SSH and one `skill_manage` call. It shows no scan, `gatt-enum`, `classic-enum`, `db report`, or `db list`.
- No `approval.request` was denied.
- The live file is still owned by uid `10000`.
- The diff is only the version line `1.3.0` to `1.3.1` and the one adapter sentence. The allow list and the not-allowed list are byte-for-byte the same.
- `enum-scan --variant brute`, `--write-char`, and `bleep ctf` remain under `## Not allowed`.
- No new skill directory appeared under `/opt/data/skills/`.
- `/home/bleep` gained no file from this turn. `pending/skills/` gained no record.

Fail and restore on any of these: a full-file `content` rewrite, a second skill, a changed allow list, a missing not-allowed line, a scan command, `status` other than `completed`, or output that does not contain the version line.

After a pass, copy the live file back to `skills/bluetooth/bleep/SKILL.md` in this repo. `up.sh` will not do that. Record the run id in `docs/CHANGELOG.md` and check the Phase 3 box in `docs/TODO.md` only after that copy. Do not edit either cron prompt in this phase. The cron text already says the same three things. This phase puts them in the skill the jobs load.

## Dashboard

`http://127.0.0.1:9119/` on Windows and on Ubuntu is Docker Desktop's forwarder (`com.docker.backend`), then uvicorn in `hermes-agent`. `GET /` answers `302` to `/login?next=%2F` with an empty body. `GET /login` answers `200` and the sign-in page.

An empty reply (curl exit 52) or `Connection reset by peer` on that port is the Windows listener, not a down dashboard. Confirm the process with `docker exec hermes-agent` against `http://127.0.0.1:9119/login`, or from the `docker-desktop` distro with `nsenter` into `dockerd`'s network namespace. The outer shell of that distro cannot route the container bridge address; a wget there times out. `docker restart hermes-agent` can leave the stuck Windows socket in place. `docker stop hermes-agent` releases the `LISTEN` socket, and `docker start hermes-agent` binds a new one. The publish stays `127.0.0.1:9119:9119`.

## Acceptance

Unchanged from the accepted design, plus the tracking gates:

1. `bleep` is up on `hermes-net`. Hermes's hostname is still its own container. SSH to port 22 on the WSL host is refused.
2. As uid 10000 inside `hermes-agent`, SSH to `bleep@bleep` runs `bleep --version`. `hostname` over that session is the BLEEP container.
3. `docker info` inside `hermes-agent` still fails closed on the missing socket.
4. The fidelity ledger has a baseline row: git revision, `bleep --version` text, schema integer, and snapshot path.
5. A second build from the same `main` commit does not change the schema row and does not require a new snapshot restore.
6. Radio check, after an adapter is attached: `bluetoothctl show` lists `hci0`, then the passive scan returns without a prompt.
