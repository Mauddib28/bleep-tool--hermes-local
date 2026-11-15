# Hermes agent stack with a headless BLEEP container

Compose project for a local agent stack: Ollama, Hermes Agent, a protocol broker, OpenClaw, and [BLEEP](https://github.com/Mauddib28/bleep-tool) in its own container. Hermes schedules read-only Bluetooth discovery and a database report. BLEEP runs only in the `bleep` container. The Hermes shell is a different host.

Linux commands run from this directory. `scripts/attach-radio.ps1` runs on Windows when the radio is a USB device shared into the Linux host.

| Document | Role |
|---|---|
| `docs/PLAN.md` | Design constraints. |
| `docs/OPERATOR.md` | Repeatable checks and the commands for one running stack. |
| `docs/CHANGELOG.md` | Deployment history. |
| `docs/TODO.md` | Open and completed checks. |

## Stack

All five services join the compose network `hermes-net`.

| Service | Container | Role |
|---|---|---|
| `ollama` | `ollama-local` | Model API. No published host port. GPU when the host provides one. Context length from `.env.example`. Named volume `ollama`. |
| `hermes` | `hermes-agent` | Gateway. Dashboard published on loopback port `9119` only. API port `8642` stays on the compose network. |
| `protocol-broker` | `protocol-broker` | Accepts `POST /objectives` and forwards one run at a time to Hermes. Port `8787` is unpublished. Denies every `approval.request`. |
| `openclaw-gateway` | `openclaw-gateway` | Gateway binds loopback inside the container. Reaches Hermes through the `direct-hermes` skill. |
| `bleep` | `bleep` | Ubuntu 24.04, its own BlueZ, SSH on `hermes-net`, no published ports. |

Image pins and `BLEEP_REVISION` live in `.env.example`. `scripts/up.sh` and `scripts/lib.sh` load that file. Hermes and OpenClaw stay on digest pins. BLEEP stays on the commit named by `BLEEP_REVISION`. `scripts/up.sh` does not replace that commit with upstream `main`.

`bleep/Dockerfile` clones that commit, checks `git rev-parse HEAD`, applies `bleep/patches/` in order, then runs `pip install -e .`. The image label `org.opencontainers.image.revision` remains `BLEEP_REVISION`.

| Patch | Effect |
|---|---|
| `bleep/patches/db-report-stdout.patch` | `db report` with no `--out` prints the markdown and skips `save_report`. `--out` still writes a file. |
| `bleep/patches/sdp-source-stdout.patch` | Each SDP source failure is printed on stdout. |
| `bleep/patches/classic-hostnet.patch` | `sdptool` and `l2ping` run in the host network namespace through `bleep-hostnetd`. |
| `bleep/patches/sdp-continue.patch` | A failed `l2ping` is printed and the SDP query still runs. The `records` source is skipped when `browse` and `xml` already returned records. |

`scripts/bleep-update.sh` rebuilds when the running label matches `BLEEP_REVISION` and the container is healthy but a local patch marker is missing. A further local change is a new patch applied after these four, plus a new rollback tag of the image that is about to be replaced. `docs/REPORT-SCORE.md` is the note for scoring stored SDP records by 16-bit UUID. `docs/bleep-fidelity.md` is the ledger for a move of upstream `main`. A local patch is not a ledger row.

## Scheduled work

`scripts/install-bleep-cron.sh` reconciles Hermes cron as uid `10000` with `HOME` set to the Hermes data directory. A root `hermes cron` rewrites `jobs.json` to `root:root` mode `600`, and the scheduler then cannot read it. The script edits a BLEEP job only when that job is not `running`.

| Name | Schedule in `scripts/install_bleep_cron.py` | Work |
|---|---|---|
| BLEEP scan and enumerate | `5,35 * * * *` | `scripts/bleep-scan.py`, no agent. |
| BLEEP database report | `50 2,6,10,14,18,22 * * *` | `scripts/bleep-db-report.py`, no agent. |
| Daily Bluetooth Tooling Examinations | `0 9 * * * *` | Research prompt on Hermes. Created only when the name is absent. |
| Update Bluetooth Findings | `0 10 * * * * *` | Research prompt on Hermes. Created only when the name is absent. |
| Review and Update | `every 43200m` | Research prompt on Hermes. Created only when the name is absent. |

An existing research job is left as stored. The research jobs stay on Hermes. They are not moved onto `bleep`.

`scripts/up.sh` copies `skills/bluetooth/bleep/SKILL.md`, `scripts/bleep-scan.py`, and `scripts/bleep-db-report.py` into the Hermes data directory on every run. The skill is the allow list: passive and active discovery, read-only GATT, connectionless Classic SDP, and one database report. Pairing, characteristic writes, adapter writes, phone-book and file transfer, audio intercept, and `bleep ctf` are outside that list.

The scan script discovers, then enumerates each address from that pass. `classic-enum --connectionless --analyze --sdp-source merge` runs when `classic-scan` printed the address or the GATT output contains `br-connection-`. An LE-only miss stays on GATT. A GATT success does not continue into `classic-enum`. Connectionless enumeration runs `l2ping` and then SDP. It does not pair and it does not extract GATT.

The report script runs one command and passes no `--out`:

```text
bleep db report --format markdown --all-in-window --recon --name-audit --group-identity --identity-contrast
```

Hermes stores that stdout after a header and a line that is exactly `---`. Cron status `ok` means the process exited. It does not mean the stdout was quoted.

## Layout

```text
docker-compose.yaml       service definitions and bind mounts
.env.example              image pins, BLEEP_REVISION, context length, Hermes uid
bleep/Dockerfile          image build
bleep/entrypoint.sh       dbus, bluetoothd, obexd, bluealsa, sshd
bleep/hostnet/            host-net daemon, client, sdptool and l2ping wrappers
bleep/patches/            local diffs applied at build
config/config.yaml        first-boot Hermes seed
config/hermes.env         seed copied to the live env file when that file is absent
skills/bluetooth/bleep/   Hermes skill seed
openclaw/                 direct-hermes skill and openclaw.json.template
broker/                   protocol-broker
scripts/up.sh             create host state if missing, start the stack, install cron
scripts/down.sh           remove this project's containers; keep images and named volumes
scripts/verify.sh         pins, unpublished ports, host ollama unit
scripts/verify-bleep.sh   container, SSH, skill and script hashes, cron names
scripts/bleep-status.sh   daemons, radio node, newest scan and report text
scripts/install-bleep-cron.sh
scripts/docker-clean.sh   scoped removal of recorded leftovers; --dry-run prints the commands
scripts/attach-radio.ps1  attach the USB bus named in that script when it is not already attached
docs/                     design, operator commands, and history
```

`.gitignore` keeps credentials, key material, observation databases, cron output, and filled `openclaw.json` out of the tree. `config/config.yaml`, `config/hermes.env`, `.env.example`, and `openclaw/openclaw.json.template` stay in the tree. The live Hermes config, with the dashboard password hash and API key, is the copy `scripts/up.sh` writes outside the repo.

## Host state

`docker-compose.yaml` bind-mounts three host directories and two named volumes. `scripts/up.sh` creates the directories and generates a secret only when the file is missing.

| State | Holds |
|---|---|
| Keys directory | Dashboard password, dashboard bearer token, Hermes API key, OpenClaw gateway token, BLEEP SSH private key and public key. Directory mode `700`, private files mode `600`, owner uid `10000`. |
| Hermes data directory | Live `config.yaml`, live `.env`, cron, skills, and the copied scan and report scripts. Mounted at `/opt/data` in `hermes-agent`. |
| OpenClaw state directory | Filled `openclaw.json` and workspace. The gateway token is substituted from the keys directory. |
| Volume `bleep-home` | `/home/bleep` in the BLEEP container, including `observations.db`. |
| Volume `ollama` | Model files. Compose expects this volume to exist; `scripts/up.sh` creates it when it is absent. |

`scripts/down.sh` removes this project's containers and keeps the images, both named volumes, and the three host directories. `scripts/docker-clean.sh` removes only the leftovers named in that script. It does not run `docker volume prune` or `docker system prune -a`.

`scripts/bleep-keys.sh` creates the BLEEP SSH key in the keys directory when the private file is missing. `scripts/bootstrap_state.py` fills the Hermes env, the dashboard basic-auth hash, and the OpenClaw config from those keys.

## Radio

BLEEP needs a Bluetooth controller visible as `hci0` inside the container. The host `bluetooth.service` stays disabled so it does not hold the L2CAP socket. The host `ollama.service` stays disabled so it does not take the GPU or port `11434`. `scripts/up.sh` disables either unit when passwordless sudo is available, and it exits if `bluetooth.service` is still active.

On a Windows host that shares the adapter with `usbipd`, `scripts/attach-radio.ps1` attaches the bus id written in that script. The attach does not survive reboot. The script does not create or change a scheduled task. A Linux host with the adapter already on `hci0` skips that script.

`AF_BLUETOOTH` fails in the container network namespace. Compose mounts the host network namespace at `/hostns/net`. `bluetoothd`, `obexd`, and `bluealsa` start with `nsenter` into that namespace. GATT and `bluetoothctl` use D-Bus to `bluetoothd`. `sdptool` and `l2ping` open their own sockets, so user `bleep` reaches them through `/usr/local/sbin/bleep-hostnetd`. That daemon accepts only those two programs. Compose sets `no-new-privileges`. The image does not install sudo.

The container has `NET_ADMIN`, `NET_RAW`, and `SYS_ADMIN`. `SYS_ADMIN` is what lets `bluetoothd` enter the host network namespace. SSH stays on `hermes-net`. The Docker socket and the host `/var/run/dbus` are not mounted. `terminal.backend` stays local: only the BLEEP skill SSHes to `bleep@bleep`.

Show the controller from the host network namespace:

```bash
docker exec bleep nsenter --net=/hostns/net bluetoothctl show
```

`scripts/bleep-status.sh` treats the radio as present when `/sys/class/bluetooth/hci0` exists. `scripts/verify-bleep.sh` checks the container and the SSH path and does not require the radio.

## Run

From the repo root on the Linux host:

```bash
bash scripts/up.sh
bash scripts/verify.sh
bash scripts/verify-bleep.sh
bash scripts/bleep-status.sh
```

`scripts/up.sh` is safe to re-run. It copies the skill and both cron scripts, reconciles cron, and runs `scripts/verify-bleep.sh`. Stop this project's containers with:

```bash
bash scripts/down.sh
```

List cron as the Hermes user:

```bash
docker exec -u 10000 -e HOME=/opt/data hermes-agent hermes cron list
```

The dashboard listens on `127.0.0.1:9119`. The username is `admin`. The password is the dashboard password file in the keys directory. Hermes Desktop uses the dashboard token file as `Authorization: Bearer`.

## BLEEP image

Rebuild and recreate only `bleep` when a patch or the pinned revision changes. Copy `observations.db` to a dated file on the `bleep-home` volume first, and tag the current image under a new rollback name. Leave the live database in place. Recreate while the scan job is scheduled and not `running`, and outside the report minute.

`scripts/lib.sh` exports `BLEEP_REVISION` from `.env.example`. Pass that value into Compose explicitly when the shell would expand it:

```bash
BLEEP_REVISION=<commit> docker compose --env-file .env.example build bleep
BLEEP_REVISION=<commit> docker compose --env-file .env.example up -d --force-recreate --no-deps bleep
```

A healthy container runs `sshd`, a system bus, `bluetoothd --nodetach -E`, a session bus, `obexd` as user `bleep`, `bluealsa`, and `bleep-hostnetd`. The entrypoint waits until each bus accepts a connection, then restarts a daemon that exits.

The scan and report scripts omit `--out`, so a normal cron run prints the report and does not add a file under `~/.bleep/aoi/reports/`. A new file there means some command called `save_report`.

## Boundaries

- Named volumes `bleep-home` and `ollama` hold the observation database and the model. `scripts/down.sh` leaves them mounted data in place.
- Host `bluetooth.service` and host `ollama.service` stay disabled.
- `terminal.backend` stays local. The Docker socket stays out of `hermes-agent`. The host system bus stays out of `hermes-agent` and `bleep`.
- Research cron stays on Hermes.
- Schema restore and schema downgrade in `scripts/bleep-update.sh` copy a snapshot back over `observations.db`. They are for a failed upstream move, not for a routine rebuild.
