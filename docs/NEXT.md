# Next batch

Status: sections 1–6 applied on 2026-11-10. The battery query left `Power Management` blank. Last result is still `267011` because the task has not run. The checklist at the bottom was accepted before the edit. Do not expand the skill allow list. Do not delete `bleep-home`, `observations.db`, or any file under `/home/bleep/.bleep/aoi/reports/`. Do not exercise the schema-restore or schema-downgrade path in `scripts/bleep-update.sh`.

Applied result:

- Repo seed and live `/opt/data/skills/bluetooth/bleep/SKILL.md` are `1.3.2`, sha256 `869936769a3010a290a2c0a7057814e5bda0b7ddfb4e5f6d8a47fd270ffe028f`, live uid `10000` mode `644`.
- Scan prompt is 1807 characters and still starts `Use the bleep skill.` Report prompt is 2162 characters and still contains `Do not pass --out`. `jobs.json` is uid `10000` mode `600`.
- `hermes cron list` shows `b470c8e8c1e7` as `5,35 * * * *`, next run `2026-11-10T21:35:00Z`. `8f19578228c5` stays `50 2,6,10,14,18,22 * * *`, next run `2026-11-10T22:50:00Z`.
- `bash scripts/bleep-status.sh --self-test` printed `self-test ok`. The real run exited 1 and named `2026-11-10_20-59-25.md` (no `rssi_last`) and `2026-11-10_18-51-02.md` (`rest of report continues`). The AOI directory still has only the six names below. Jobs `400acca5173f`, `2754ce497c3c`, and `7685f41fc72b` were not edited.

## Evidence

These were true before the edit. The applied result is the status block above. The batch does not re-investigate them.

- Live skill `/opt/data/skills/bluetooth/bleep/SKILL.md` and the repo seed are version `1.3.1`. Phase 3 run `run_66618cc2b4d84dcf99c83c9743917c4e` wrote that version. `scripts/up.sh` copies the seed only when the live file is missing, so a seed edit does not reach the running agent by itself.
- Scan job `b470c8e8c1e7` is `every 30m`. Report job `8f19578228c5` is `50 2,6,10,14,18,22 * * *`. Both are `ok` in `hermes cron list`. `ok` is not a quote.
- The 16:27 UTC scan loaded skill `1.3.0`. Scans at 17:05, 17:41, 18:20, 19:05, 19:44, 20:21, and 20:59 UTC loaded `1.3.1`. None of those response sections contain `rssi_last`. `17:05`, `19:44`, `20:21`, and `20:59` quote a `[*] Discovered` banner. `17:41`, `18:20`, and `19:05` are summary tables.
- At 19:41 UTC, during the 19:44 scan, the model ran `gatt-enum` in `hermes-agent`. The shell returned `command not found` five times. It also called `skill_view` for `bleutooth-analysis-research` and a `web_search` that failed DNS.
- The 16:27 run wrote `/opt/data/cron/output/b470c8e8c1e7/2026-11-10_16-27-30_gatt-enum-report.md`, mode `644`. Cron's own files in that directory are mode `600`. Leave the extra file.
- The 18:51 UTC report, execution `a56b9965ab7a4af884da8b7bada4bfaf`, cut its quote at `... [rest of report continues]`, then printed `10/10` and `6/10` rows that are not in that quote. It said `classic-enum --connectionless` extracts GATT and that `scan --variant pokey` connects. The skill and the stored prompt already say the opposite. At 18:50:15 UTC the tool wrote `/home/bleep/.bleep/aoi/reports/db_report_20261110_185015.md`.
- `bluetoothd` is attempting A2DP and HFP because `bluealsa` registered those profiles. Connection refused, device busy, and `bap profile probe failed` are that behavior on this kernel. Do not remove the profiles in this batch.
- Task `HermesUsbipdBluetooth` was created from an elevated prompt on 2026-11-10. `schtasks /Query` showed it enabled, at logon, last result `267011` (the task has not run). Power management was "Stop On Battery Mode, No Start On Batteries." `hci0` being present now is the attach from this session.
- The next scan after the 20:59 UTC file was `2026-11-10T21:29:25Z`. The next report was `2026-11-10T22:50:00Z`. The scan anchor moves because the next start is about 30 minutes after the previous run finishes. A scan that starts at 22:29 can still be running at 22:50. There is one controller.

## Not in this batch

- Schema restore and schema downgrade. Both paths in `scripts/bleep-update.sh` copy a snapshot back over `observations.db` and retag the image. They stay unexercised until `main` moves, and they are not forced by deleting the volume.
- Pairing, adapter writes, `enum-scan --variant brute`, phone-book and file transfer, audio intercept, and `bleep ctf`.
- Deleting AOI reports, deleting `2026-11-10_16-27-30_gatt-enum-report.md`, or chmod of `/home/user/hermes/openclaw`.
- Editing jobs `400acca5173f`, `2754ce497c3c`, or `7685f41fc72b`.
- A new Hermes API turn. This batch is a file edit and a `hermes cron edit`, not `skill_manage`.

## 1. Record the evidence

After acceptance, update the current-state sentences. Do not leave `docs/OPERATOR.md` telling the operator to create `HermesUsbipdBluetooth`.

- `docs/TODO.md`: the scan-quote box stays open until a response section contains `rssi_last`. Name the 17:05 through 20:59 files as the failed check. The schema boxes and the explicitly-later box stay open.
- `docs/CHANGELOG.md`: skill `1.3.2` when it is written, the schedule change, the status-script check, the task's `267011` result, and the battery setting after the user changes it.
- `docs/PLAN.md`: job `b470c8e8c1e7` is `5,35 * * * *` after that edit. The report expression stays. The radio task exists and has not run.
- `docs/OPERATOR.md`: replace the "access denied, create the task" paragraph with the query result. Add the battery command from section 5. The cron table shows `5,35 * * * *` only after the edit succeeds.

## 2. Skill 1.3.2

Edit `skills/bluetooth/bleep/SKILL.md` and copy that file onto `/opt/data/skills/bluetooth/bleep/SKILL.md`. `chown 10000:10000`. Mode stays `644`. Bump `version: 1.3.1` to `version: 1.3.2`. Do not change the allow list or the not-allowed list.

Add, after the sentence "The shell in this container is not that host.":

```text
`command not found` means that command ran in this container. Run it only as the remote command of the SSH line above. Do not write a second file under `/opt/data/cron/output/`. The scheduler writes the cron record.
```

Add, on step 6:

```text
The response quotes that command's output, and the quote contains `rssi_last`. A markdown table is not that quote.
```

Add, in the database-report section, after the `--out` prohibition:

```text
Quote the db report output through the end of the command. Do not write `rest of report continues`. Do not add an n/10 row that the quote does not contain. `scan --variant pokey` repeats short discovery and does not connect. `classic-enum --connectionless` runs l2ping and then SDP. A failed l2ping is printed and the SDP query still runs. It does not extract GATT.
```

The diff is the version line plus those three insertions. `enum-scan --variant brute`, `--write-char`, and `bleep ctf` stay under `## Not allowed`.

## 3. Cron prompts

Append. Do not replace the prompts stored on 2026-11-10. Edit as uid `10000` with `HOME=/opt/data`. A root `docker exec` rewrites `/opt/data/cron/jobs.json` to `root:root` mode `600`. Write each prompt to a file, `docker cp` it to `hermes-agent:/tmp`, and pass it to `hermes cron edit` from a Python argument list. Do not put the prompt through PowerShell quotes. Delete the temp files after. Do not print secrets.

Scan job `b470c8e8c1e7`, appended:

```text
Step 5 is a fenced quote of the db list output and that quote contains rssi_last. A markdown table is not that quote. Do not state rssi_last, first_seen, or a persisted GATT profile unless that quote contains it. command not found means the command ran in the Hermes container. Do not write a file under /opt/data/cron/output or /home/bleep.
```

Report job `8f19578228c5`, appended:

```text
Quote the db report output through the end of the command. Do not write "rest of report continues". Do not add an n/10 row that the quote does not contain. scan --variant pokey does not connect. classic-enum --connectionless does not extract GATT. Do not pass --out. Do not create a file under /home/bleep.
```

Then confirm `jobs.json` is uid `10000` mode `600`, both prompts still contain `Do not pass --out`, and the allow list in the skill file is unchanged.

## 4. Scan schedule

After the prompt append, and only if `hermes cron list` shows job `b470c8e8c1e7` is not `running`:

```bash
docker exec -u 10000 -e HOME=/opt/data hermes-agent hermes cron edit b470c8e8c1e7 --schedule "5,35 * * * *"
```

Do not pass `--grace-minutes`. Do not change job `8f19578228c5`. The report stays `50 2,6,10,14,18,22 * * *`. Minutes 5 and 35 cannot be minute 50. Pass when `hermes cron list` shows that expression and the next scan is not during the next report. If the CLI rejects the expression, stop and record the error. Do not invent a second expression in the same attempt.

## 5. Status script

Extend `scripts/bleep-status.sh`. Do not call the new checks from `scripts/up.sh` or `scripts/verify-bleep.sh`. A stack with no cron file yet still passes the radio check.

Read the newest file in each directory with `docker exec -u 10000 -e HOME=/opt/data hermes-agent`. Judge only the text after the last line that is `## Response`. The prompt above that line already contains `rssi_last`, so a whole-file search is not the check.

- Scan file present and the response lacks `rssi_last`: print the filename and set a gap.
- Report file present and the response contains `rest of report continues`: print the filename and set a gap.
- `/home/bleep/.bleep/aoi/reports/` contains a name that is not in this list: print the name and set a gap.

```text
db_report_20261110_093303.md
db_report_20261110_102233.md
db_report_20261110_102248.md
db_report_20261110_142503.md
db_report_20261110_151632.md
db_report_20261110_185015.md
```

A mtime comparison against the cron file misses `db_report_20261110_185015.md`, because that file was written at 18:50:15 and the cron file was closed at 18:51:02. The name list is the check. Exit 1 when any gap is set, including the gaps the script already has. The existing `PASS` line stays the last line on success.

The first run after this change fails the scan check until a new response contains `rssi_last`. That failure is the point of the check. Do not delete the old scan files to make it pass.

## 6. Battery flag on the logon task

The agent does not run this. From an elevated Windows PowerShell, after the repo edits are in:

```powershell
$task = Get-ScheduledTask -TaskName HermesUsbipdBluetooth
$task.Settings.DisallowStartIfOnBatteries = $false
$task.Settings.StopIfGoingOnBatteries = $false
Set-ScheduledTask -InputObject $task
schtasks /Query /TN HermesUsbipdBluetooth /V /FO LIST
```

Pass when the query no longer says "Stop On Battery Mode, No Start On Batteries." The 2026-11-10 query passed: `Power Management` is blank, `Set-ScheduledTask` returned Ready, and the action is unchanged. Last result `267011` remains until the next interactive logon. Do not recreate the task. Do not start host `bluetooth.service`. The command line stays `C:\Program Files\usbipd-win\usbipd.exe attach --wsl --busid 1-14`.

## Acceptance after implementation

1. Repo seed and live skill are `1.3.2`, same sha256, uid `10000` on the live file. The allow list and the not-allowed list match `1.3.1` byte for byte aside from the three insertions and the version line.
2. `hermes cron list` shows `b470c8e8c1e7` as `5,35 * * * *` and `8f19578228c5` unchanged. `jobs.json` is uid `10000` mode `600`.
3. `bash scripts/bleep-status.sh` exits 1 on the current newest scan because that response has no `rssi_last`, and it names that file. It does not remove the file.
4. A copied fixture of a response that contains `rssi_last`, a report response without `rest of report continues`, and only the six AOI names is what the new function would accept. Exercise that function on strings in the shell. Do not point it at a fabricated cron file in `/opt/data`.
5. The elevated query shows the task allowed on battery. The 2026-11-10 query did: `Power Management` is blank. Last result `267011` remains.
6. No new file under `/home/bleep/.bleep/aoi/reports/`. No edit to the other three cron jobs. `scripts/verify-bleep.sh` is unchanged.

## VV&A before implementation

Accept or reject each line. Implementation waits until 1 through 5 are accepted. Section 6 can stay with the user.

1. Skill `1.3.2` is the three insertions above and no allow-list change.
2. The two prompt appendices are appended, not a replacement of the 2026-11-10 prompts.
3. The scan schedule becomes `5,35 * * * *`. The report schedule stays on minute 50.
4. `scripts/bleep-status.sh` fails closed on the current scans and uses the six-name AOI list.
5. Schema paths, the volume, the AOI files, and the later skill commands stay untouched.
6. The battery settings are changed from an elevated PowerShell prompt by the user.
