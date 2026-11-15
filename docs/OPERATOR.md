# Operator commands

Repeatable checks and repairs for this stack. Design constraints stay in `docs/PLAN.md`. The event log is `docs/CHANGELOG.md`. Open work is `docs/TODO.md`.

Run the Ubuntu commands from `/home/user/Documents/hermes-agent-docker` in Ubuntu-22.04. Run the Windows commands in `cmd.exe` or PowerShell on the Windows host. Do not pass them through a nested quote from PowerShell into `bash -lc`. A cron edit runs as uid `10000` with `HOME=/opt/data`. A root `docker exec` rewrites `/opt/data/cron/jobs.json` to `root:root` mode `600`, and the scheduler then gets `Permission denied`.

Do not delete the `bleep-home` volume. Do not start the WSL host unit `bluetooth.service`. Do not mount `docker.sock` or the host `/var/run/dbus` into `hermes-agent` or `bleep`. Do not set `terminal.backend` to `ssh`.

## Every check

```bash
bash scripts/verify.sh
bash scripts/bleep-status.sh
docker exec -u 10000 -e HOME=/opt/data hermes-agent hermes cron list
```

`verify.sh` printed `PASS` on 2026-11-10 after host `ollama.service` was disabled and inactive. It checks the container images, the unpublished ports, context `65536`, and that host `ollama.service` is neither active nor enabled. `bleep-status.sh` exits 1 when one of the five BLEEP daemons is missing, `/sys/class/bluetooth/hci0` is absent, the newest scan response has no `db list` header line, the newest report response contains `rest of report continues`, `db_report_`, `The report is too large`, `Bleep Database Report Analysis`, `Report ID`, or `Improvements`, the newest scan response contains `GATT Enumeration Summary`, `GATT profiles persisted`, or `Latest 50 devices`, the newest report response contains `GATT extraction` or `uses connection attempts`, or an AOI report name is outside the 29 names allowed in `scripts/bleep-status.sh`. The scan check looks for `MAC NAME RSSI_LAST RSSI_MIN RSSI_MAX FIRST_SEEN LAST_SEEN` after the last `## Response` line. `bleep db list` prints those names in upper case. A markdown `RSSI_Last` column does not match. `hermes cron list` status `ok` is not a scan. On 2026-11-11 the 00:43 UTC scan passed the header check and the 22:55 UTC report was not abbreviated. The same run exited 1 because `/home/bleep/.bleep/aoi/reports/` gained `db_report_20261110_225040.md`, `db_report_20261110_225044.md`, and `db_report_20261110_225322.md`. Leave those files. `bash scripts/bleep-status.sh --self-test` checks the same split on strings and does not read `/opt/data`. A no-agent file is judged after the `---` line. The report body has to start with `[identity-contrast]` and contain `# Aggregate Security Report` and `**Other AD structures:**`. `[truncated` fails that check.

`scripts/verify-bleep.sh` checks the BLEEP container, the SSH path, and the five processes. It does not require the radio and it does not run the quote check. `scripts/up.sh` calls it. `scripts/bleep-phase3.py` is the one-turn check that quotes `bleep --version` and patches the live skill. It passed once, as `run_66618cc2b4d84dcf99c83c9743917c4e`. Running it again exits before a new turn because the live skill is no longer version `1.3.0`. The live file and the repo seed are `1.3.6`. The scheduled report is `bleep-db-report.py` and the scheduled scan is `bleep-scan.py`. A terminal `db report` with no `--out` prints the markdown. The rollback image tag is `bleep-local:dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85-pre-report-stdout`.

## Teardown and redeploy

`bash scripts/down.sh` removes this project's containers and keeps the images, the `ollama` and `bleep-home` volumes, and `/home/user/hermes`. It does not start host `ollama.service` or `bluetooth.service`. Do not add `-v`. Deleting `bleep-home` deletes `observations.db`. Deleting the `ollama` volume deletes the model.

`bash scripts/docker-clean.sh` removes dangling images, the build cache, stopped containers `hermes-agent-previous` and `openclaw-openclaw-gateway-1`, and the three unused anonymous volumes recorded on 2026-11-14. `--dry-run` prints the commands. It does not run `docker volume prune` or `docker system prune -a`. Tagged images stay, including `bleep-local:dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85` and its rollback tags. Volumes `bleep-home`, `ollama`, `ai-stack_*`, and `ollama_*` stay. The broker volume `74370f2c6f6c` stays.

`bash scripts/up.sh` is the redeploy. It disables host `ollama.service` and host `bluetooth.service` when passwordless sudo works, creates the `ollama` volume if it is absent, and pulls `qwen3.5:latest` if that volume does not already have it. `BLEEP_REVISION` comes from `.env.example` and is not replaced with upstream `main`. The image rebuilds when the running container's label matches that pin but `continuing with SDP` or `/usr/local/sbin/bleep-hostnetd` is missing. The bleep skill and `direct-hermes` skill are copied from the repo on every run. `bleep-scan.py` and `bleep-db-report.py` are copied to `/opt/data/scripts` as uid `10000` mode `755`. `scripts/install-bleep-cron.sh` creates or edits only the scan job (`5,35 * * * *`, `bleep-scan.py`) and the report job (`50 2,6,10,14,18,22 * * *`, `bleep-db-report.py`). Both stay `--no-agent`. Jobs `400acca5173f`, `2754ce497c3c`, and `7685f41fc72b` are created when their names are absent and are not edited when they already exist. A BLEEP job whose state is `running` is not edited. Existing dashboard, API, gateway, and BLEEP SSH keys are kept.

From Windows, after a reboot, `powershell -File scripts\attach-radio.ps1` attaches bus `1-14` when it is not already attached.

## Windows radio

Bus `1-14`, VID:PID `8087:0029`, is the Intel adapter. `usbipd list` state `Shared` means Windows will allow the attach. WSL does not have the device until `Attached`. The attach does not survive reboot or a WSL restart. Controller `94:E6:F7:A1:D6:B3` is owned by `bluetoothd` inside `bleep`.

One attach, from any Windows prompt that can run `usbipd`:

```bat
"C:\Program Files\usbipd-win\usbipd.exe" list
"C:\Program Files\usbipd-win\usbipd.exe" attach --wsl --busid 1-14
```

`scripts/attach-radio.ps1` runs that attach and leaves it alone when bus `1-14` is already `Attached`. It does not create or change `HermesUsbipdBluetooth`.

Logon task `HermesUsbipdBluetooth` was created from an elevated prompt on 2026-11-10. A second elevated prompt the same day set both battery flags false. `Set-ScheduledTask` returned Ready. `schtasks /Query /TN HermesUsbipdBluetooth /V /FO LIST` now leaves `Power Management` blank. Last result is still `267011` (it has not run). Last run time is `11/30/1999 12:00:00 AM`. Logon mode is Interactive only, so it runs when PAW logs on and not at the login screen. The command that was used:

```powershell
$task = Get-ScheduledTask -TaskName HermesUsbipdBluetooth
$task.Settings.DisallowStartIfOnBatteries = $false
$task.Settings.StopIfGoingOnBatteries = $false
Set-ScheduledTask -InputObject $task
schtasks /Query /TN HermesUsbipdBluetooth /V /FO LIST
```

That query passed: `Power Management` is blank, so the battery restriction is gone. Last result `267011` remains until the next interactive logon. Do not recreate the task. Do not start host `bluetooth.service`. The task action stays:

```bat
C:\Program Files\usbipd-win\usbipd.exe attach --wsl --busid 1-14
```

Confirm after the next logon with `usbipd list` showing bus `1-14` as `Attached`, then `bash scripts/bleep-status.sh` from Ubuntu. Leave host `bluetooth.service` disabled. If that unit is started, container `bluetoothd` logs `l2cap_bind: Address already in use` and cannot register the adapter.

## BLEEP container

`BLEEP_REVISION` is `dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85` in `.env.example`. `scripts/up.sh` uses that pin. It does not follow upstream `main`.

```bash
export BLEEP_REVISION=dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85
docker compose --env-file .env.example up -d --force-recreate --no-deps bleep
docker exec bleep ps -eo pid,user,args
```

A healthy start shows `sshd`, `dbus-daemon --system`, `bluetoothd --nodetach -E`, `dbus-daemon --session`, `obexd` as user `bleep`, and `bluealsa`. The entrypoint waits until each bus accepts a connection, then a supervisor restarts a daemon that exits. `docker restart` is not the repair for a container whose only process is `sshd`. Recreate it with the command above.

`bluetoothctl` and `btmgmt` in the container network namespace cannot open the management socket. Show the controller with:

```bash
docker exec bleep nsenter --net=/hostns/net bluetoothctl show
```

`bleep --check-env` reports `AdvertisementMonitorManager1` and `Adapter1.ConnectDevice` on `hci0` when the radio is attached. `btmgmt` in that same check can still say no controller, because it runs outside the host network namespace.

These log lines are properties of this WSL kernel, including after `bluealsa` has registered HFP, HSP, and A2DP:

- `br-connection-profile-unavailable` for kali `00:01:95:6F:D4:99`
- `br-connection-key-missing` for Dingo `00:01:95:4B:40:69`
- `Method "Connect" doesn't exist` for iPhone 14 `D8:3A:DD:0B:69:B9`
- `BAP requires ISO Socket which is not enabled`
- `Failed to set privacy: Rejected (0x0b)`
- `Failed to open RFKILL control device`

The follow-up for an address with no GATT is when `classic-scan` printed that address, or when the GATT output contains `br-connection-`: `bluetoothctl disconnect`, then `classic-enum --connectionless --analyze --sdp-source merge`. An LE-only miss stays on GATT. `l2ping` and `sdptool` run in the host network namespace. A failed `l2ping` is printed and the SDP query still runs. `records` is skipped when `browse` and `xml` already returned records. That command does not call `Device1.Connect` and it does not extract GATT. `scan --variant pokey` repeats short discovery. It does not connect. Pairing, characteristic writes, file and phone-book transfer, audio intercept, and `bleep ctf` stay off the skill.

## Cron

| Job | ID | Schedule | Skill |
|---|---|---|---|
| BLEEP scan and enumerate | `b470c8e8c1e7` | `5,35 * * * *` | `bleep` |
| BLEEP database report | `8f19578228c5` | `50 2,6,10,14,18,22 * * *` | `bleep` |
| Daily Bluetooth Tooling Examinations | `400acca5173f` | `0 9 * * * *` | research, not the BLEEP box |
| Update Bluetooth Findings | `2754ce497c3c` | `0 10 * * * * *` | research, not the BLEEP box |
| Review and Update | `7685f41fc72b` | `every 43200m` | `bleep` plus the two analysis skill names |

The report was moved onto minute 50 on 2026-11-10. The scan was moved the same day from `every 30m` to `5,35 * * * *`. After that edit the next scan was `2026-11-10T21:35:00Z` and the next report was `2026-11-10T22:50:00Z`. Both jobs have continuity on. The prompts were appended, not replaced, and both still contain `Do not pass --out`. On 2026-11-12 the scan and report prompts were replaced. Later the same day both jobs were switched to no-agent. `b470c8e8c1e7` runs `/opt/data/scripts/bleep-scan.py`. `8f19578228c5` runs `/opt/data/scripts/bleep-db-report.py`. The saved text after the `---` line is the script stdout.

```bash
docker exec -u 10000 -e HOME=/opt/data hermes-agent hermes cron list
docker exec -u 10000 -e HOME=/opt/data hermes-agent hermes cron edit 8f19578228c5 --schedule "50 2,6,10,14,18,22 * * *"
```

A long `--prompt` does not survive a PowerShell quote. Write the prompt to a file, `docker cp` it into `hermes-agent:/tmp`, `chmod 644`, and run `hermes cron edit JOB --prompt` as uid `10000` with `HOME=/opt/data` from a Python `subprocess` list so the shell does not split it. The prompts stored on 2026-11-10 require:

- One `ssh` command runs one `bleep` command. No pipelines.
- The scan response is the quoted output of the passive scan, the naggy scan, the classic scan, each enumeration command, and `bleep db list --fields mac,name,rssi_last,rssi_min,rssi_max,first_seen,last_seen`. It does not add `GATT Enumeration Summary` or `Latest 50 devices`.
- Addresses come from those three scans in that run.
- The report runs `bleep db report --format markdown --all-in-window --recon --name-audit --group-identity --identity-contrast` once. The response is that output, or the paged terminal log, and nothing else. The report job does not run `db show` or `db timeline`.
- Neither job passes `--out` or creates files under `/home/bleep`.
- Neither job invents an n/10 risk score or describes a device as paired.
- If the adapter line `Bluetooth adapter not found or not ready` appears, the first line of the scan response is exactly `[CRON_FAILURE]`.

The 14:27 UTC report wrote `/home/bleep/.bleep/aoi/reports/db_report_20261110_142503.md` before that prompt was stored. Leave the file. Do not delete `observations.db` to remove it.

Output files:

```text
/opt/data/cron/output/b470c8e8c1e7/
/opt/data/cron/output/8f19578228c5/
```

A failed run whose token is `[CROn FAILURE]` or `[CROn_FAILURE]` is stored as `ok`. The scheduler token is `[CRON_FAILURE]`.

## Dashboard

Publish stays `127.0.0.1:9119:9119`. `GET /` is `302` to `/login?next=%2F` with an empty body. `GET /login` is HTTP 200, about 10 KB, title `Sign in — Hermes Agent`.

```bash
curl -sS -D - --max-time 8 http://127.0.0.1:9119/login -o /tmp/hermes-login.html
```

Curl exit 52 (`Empty reply from server`) or `Connection reset by peer` on Windows or Ubuntu localhost is the `com.docker.backend` listener. `docker restart hermes-agent` can leave that socket in place. Replace it with:

```bash
docker stop hermes-agent
docker start hermes-agent
```

Confirm from inside the container before blaming uvicorn:

```bash
docker exec hermes-agent curl -sS -D - --max-time 8 http://127.0.0.1:9119/login -o /tmp/dash-login.txt
```

A `wget` of the container bridge address from the outer `docker-desktop` shell times out. That shell is not on `hermes-net`. The engine network namespace can reach `127.0.0.1:9119` with `nsenter -t <dockerd pid> -n` inside the `docker-desktop` distro.

## What not to automate

Do not schedule `enum-scan --variant brute`, `--write-char`, pairing, adapter changes, phone-book or file transfer, audio intercept, or `bleep ctf`. Do not exercise the schema-restore or schema-downgrade path in `scripts/bleep-update.sh` by deleting the volume. Those branches are still untested. Do not move the daily research crons onto the BLEEP container.
