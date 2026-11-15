---
name: bleep
description: Run BLEEP on the dedicated bleep container. Use for a passive scan, an active discovery scan, read-only enumeration of each device that scan saw, or a read-only report of the observation database.
version: 1.3.10
platforms: [linux]
hermes:
  tags: [Bluetooth, BLEEP]
  requires_toolsets: [terminal]
---

# BLEEP

BLEEP is installed only in the `bleep` container. The shell in this container is not that host. `command not found` means that command ran in this container. Run it only as the remote command of the SSH line above. Do not write a second file under `/opt/data/cron/output/`. The scheduler writes the cron record. One `ssh` command runs one `bleep` subcommand there.

```bash
ssh -i /run/secrets/bleep_ed25519 \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile=/opt/data/ssh/known_hosts \
  bleep@bleep -- bleep scan --timeout 15 --variant passive
```

Replace only the final `bleep` command. Do not add a pipeline. Quote the command output.

## Order

If a command prints `Bluetooth adapter not found or not ready`, the first line of the response is exactly [CRON_FAILURE], then quote that line and stop. Do not fill the report from an earlier run. Do not invent an n/10 risk score. Do not describe a device as paired.

1. `bleep scan --timeout 15 --variant passive`
2. `bleep scan --timeout 15 --variant naggy`. `ble_scan_modes.md` uses naggy for an RSSI series and for rotating addresses. It is not a fallback for an empty room.
3. `bleep classic-scan --timeout 10`
4. Pokey, then `scan --variant brute`, only when those three scans printed no addresses. `brute` here is the BR/EDR-then-LE discovery scan.
5. For each address from those scans, one command at a time. A failure is recorded and the next address is tried.
   - `bleep gatt-enum ADDRESS`. This pass persists services and characteristics.
   - If that address has no GATT: `bleep gatt-enum --correlate ADDRESS`
   - If it still has no GATT and either `classic-scan` printed that address or the GATT output contains `br-connection-`: `bluetoothctl disconnect ADDRESS`, then `bleep classic-enum --connectionless --analyze --sdp-source merge ADDRESS`. An LE-only miss stays on GATT.
   - If it connected and a read failed: `bleep gatt-enum --deep ADDRESS`. `--deep` still persists. `--report` does not: `gatt_enumeration.md` says `--report` skips characteristic persistence and prints only the landmine and security JSON. Run `bleep gatt-enum --report ADDRESS` only after a persisting pass, and only when that JSON is needed.
6. `bleep db list --fields mac,name,rssi_last,rssi_min,rssi_max,first_seen,last_seen`. The response quotes that command's output, and the quote contains `rssi_last`. A markdown table is not that quote.

The scheduled scan job runs `/opt/data/scripts/bleep-scan.py` and stores that stdout. It pages `db list` with `--limit 100` and `--offset` until a page has fewer than 100 addresses. Do not write `GATT Enumeration Summary`, `GATT profiles persisted`, or `Latest 50 devices`. Do not install packages. Do not write a script under `/opt/data/cache`.

`ADDRESS` is a MAC from the scan output or from `bleep db report`. Do not invent one. RSSI for a scan line comes from that scan. RSSI stored on the device row is `rssi_last`, `rssi_min`, and `rssi_max`. `observation_db.md` does not store an RSSI change as its own advertisement row.

## Database report

A database report reads `observations.db`. It does not scan and it does not connect.

Run this command once:

`bleep db report --format markdown --all-in-window --recon --name-audit --group-identity --identity-contrast`

Do not pass `--out`, `--export-targets`, or `--promote`. Do not run `db maintain`, `db export`, `db show`, or `db timeline` in this job. Do not run a second command. The remote user is `bleep`. Do not use `hermes@bleep`. Do not read a path under `/home/bleep`. Do not create a file under `/home/bleep` or `/opt/data/cache`. Do not write a parser script. `scan --variant pokey` repeats short discovery and does not connect. `classic-enum --connectionless` runs l2ping and then SDP. A failed l2ping is printed and the SDP query still runs. `--sdp-source merge` unions D-Bus `GetServiceRecords` with `sdptool browse` and `browse --xml`. It skips `records` when those two already returned records. It does not extract GATT.

The scheduled report job runs `/opt/data/scripts/bleep-db-report.py` and stores that stdout. Do not summarize it. Do not say the report is too large. Do not invent a `db_report_` filename. Do not add a title, a Report ID, an analysis, or an Improvements section. Do not add a flag that is not in the allow list.

## Allowed commands

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
- `bleep classic-enum --connectionless --analyze --sdp-source merge ADDRESS`
- `bleep enum-scan --variant passive ADDRESS`
- `bleep enum-scan --variant naggy ADDRESS`
- `bleep connect --ble-only --no-profiles ADDRESS`
- `bleep db list`
- `bleep db list --fields mac,name,rssi_last,rssi_min,rssi_max,first_seen,last_seen`
- `bleep db report --format markdown --all-in-window --recon --name-audit --group-identity --identity-contrast`
- `bleep db show --full ADDRESS`
- `bleep db timeline ADDRESS`

## Not allowed

Do not open the REPL, `bleep user --menu`, or `bleep debug`. Do not pair, run a pairing agent, change adapter settings, advertise, or start a GATT server. Do not run `bleep ctf`. Do not use `enum-scan --variant brute`, `--write-char`, `--force`, `--range`, `--patterns`, or `--payload-file`. Do not download phone books, messages, or files, and do not play, record, or intercept audio.

`BLEEP_DB_PATH` on that container is `/home/bleep/.bleep/observations.db`. Do not copy, delete, or replace that file.
