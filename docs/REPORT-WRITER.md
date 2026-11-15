# Report writer

Status: applied on 2026-11-12. The model responses through 14:50 UTC wrote no AOI file and did not store the full stdout. Job `8f19578228c5` is now no-agent script `bleep-db-report.py`. The 22:50 UTC file is the check. The 14:50 tool stdout is `/opt/data/cache/terminal-output/out-1794495067-190-3ce0.log`. The 10:50 tool stdout is `/opt/data/cache/terminal-output/out-1794480614-190-1a70.log`. The 02:50 tool stdout is `/opt/data/cache/terminal-output/out-1794451831-190-8640.log`. Do not delete `bleep-home`, `observations.db`, or any file under `/home/bleep/.bleep/aoi/reports/`. Do not add pairing, characteristic writes, or `bleep ctf`. Do not exercise schema restore or schema downgrade.

## Evidence

Read from the running image `bleep-local:dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85`, package `/opt/bleep/bleep`.

`bleep/modes/db.py` `_run_report` prints the identity, name-audit, and recon banners, then always calls `analyzer.save_report`. With no `--out`, the filename is `db_report_YYYYMMDD_HHMMSS.md`. `AOIAnalyser.save_report` in `bleep/analysis/aoi_analyser.py` writes that name under `~/.bleep/aoi/reports/`. The stdout line after the write is `[+] Report (markdown, N device(s)) saved to <path>`. The markdown body is not printed. `--json` and quiet mode return earlier, through `output.emit_result`, before the name-audit and recon sections are appended to the markdown. Upstream `bleep/docs/observation_db.md` states the same split: a normal report is saved under `~/.bleep/aoi/reports/`, and `--format json --json` is the stdout path.

That is what the 22:50 job did. `8f19578228c5` finished at 22:55:32. The response quotes the tool report generated at 22:53:21 and does not contain `--out`. Three files appeared, all owner `bleep:bluetooth`, 50398 bytes, 1605 lines:

| File | Generated inside the file | sha256 |
|---|---|---|
| `db_report_20261110_225040.md` | 22:50:40 | `4fde6074113e0abc8fe71a8526d822676de32dea2ec538562006651a26963e93` |
| `db_report_20261110_225044.md` | 22:50:44 | `05fb780b371597383444433fdb3802262d947553f1a054dcad03231a157d84b3` |
| `db_report_20261110_225322.md` | 22:53:21 | `c622f0951a6c29e5de09cf1002e05205e9953d78ab7a6f14f1074bef2bd382f7` |

The quoted report is the third file. Each header says BLEEP 3.1.0, 160 devices loaded, 25 analyzed, average risk `1.6/10`. The hashes differ.

Hermes logged `hermes@bleep: Permission denied (publickey)` at 22:50:34 and 22:53:19. At 22:50:46 `read_file` of `/home/bleep/.bleep/aoi/reports/db_report_20261110_225044.md` inside `hermes-agent` returned file not found. `execute_code` and a `python -c` terminal command were blocked. The browser tool then failed CDP on `127.0.0.1:40355`. The skill's SSH user is `bleep@bleep`. The report file exists only in the `bleep` container.

After `[QUOTE END]` the same response says the iPhone was seen paired, `classic-enum --connectionless --analyze` attempts GATT extraction, and `scan --variant pokey` uses connection attempts. The quote itself contains the tool's `1.6/10` table. That score is the tool's report, not a row the model added outside the quote.

`scripts/bleep-status.sh` passed `2026-11-11_00-43-43.md` and `2026-11-10_22-55-32.md`, then exited 1 on the three new names. The scan job's unquoted GATT claims stay out of this batch.

On 2026-11-11 at 01:15:44 UTC the same unpatched command was run by hand. Stdout was the three banners and `[+] Report (markdown, 187 device(s)) saved to /home/bleep/.bleep/aoi/reports/db_report_20261111_011544.md`. No markdown body was printed. `scripts/bleep-status.sh` then named that file plus the three 22:50 files. Leave `db_report_20261111_011544.md`.

A second probe, `bleep --json db report` with the same flags, exited 0 and wrote no file. The stdout JSON was 674329 bytes. Keys: `format`, `device_count` 187, `capped` false, `report` (markdown, 37095 characters), `identity_contrast` (187 raw, 177 collapsed), `name_audit` (placeholder 97, real 37, empty 53, foreign_mac 0), `recon`. The directory listing stayed at 10 names.

The 02:50 UTC job on 2026-11-11 finished at 03:02:56, execution `b1d8e75580014ab3a0cf8b5529d8b94f`. It wrote four more files, each 60529 bytes, 1902 lines, owner `bleep:bluetooth`, 220 devices loaded, average risk `1.4/10`:

| File | Generated inside the file |
|---|---|
| `db_report_20261111_025026.md` | 02:50:25 |
| `db_report_20261111_025105.md` | 02:51:04 |
| `db_report_20261111_025657.md` | 02:56:56 |
| `db_report_20261111_025703.md` | 02:57:03 |

The cron response quotes the 02:57:03 file through `[QUOTE END]` and does not contain `rest of report continues`. After the quote it still says `classic-enum --connectionless` attempts GATT extraction and `scan --variant pokey` uses connection attempts. Hermes then ran `cat` and `ls` of `/home/bleep/.bleep/aoi/reports/` inside `hermes-agent` (`No such file or directory`) and `execute_code` was blocked. The same turn copied the report into the Hermes data directory:

| Path | Bytes | Time |
|---|---|---|
| `/opt/data/cache/bleep_report.txt` | 366 | 02:51 |
| `/opt/data/cache/bleep_full_report.txt` | 60529 | 02:51 |
| `/opt/data/cache/bleep_report_2.txt` | 366 | 02:56 |
| `/opt/data/cache/bleep_report_2a.txt` | 60529 | 02:58 |

Leave those four files until this package is accepted. They are copies. They are not `observations.db`.

`2026-11-11_02-47-51.md` quotes the `db list` header and 14 rows, then says `100+` devices and `GATT profiles persisted`. It calls Pro PSP1806 `Already connected (paired)`. At 03:08 UTC the next scan, scheduled 03:05, was still running (`2ad18d3869314491aa1ce3cf868b66f0`). Do not edit that job while it is running.

The next report slot is `2026-11-11T06:50:00Z`. A terminal run before this patch writes another `db_report_*.md`. Implementation takes the directory listing at the start of the work.

## Which export method

`db report` has three stock outputs. The code in `_run_report` and `observation_db.md` agree.

| Method | Command shape | Where the body goes | File under `~/.bleep/aoi/reports/` |
|---|---|---|---|
| Markdown or text | `--format markdown` (the default) or `--format text` | Not on stdout. Stdout is the banners and `saved to`. | Yes. `db_report_YYYYMMDD_HHMMSS.md` or `.txt`. |
| Explicit path | `--out PATH` on a markdown, text, or file-mode JSON report | Same `saved to` line. | Yes. A relative name is still joined onto `reports/`. |
| JSON stdout | `bleep --json db report` | One JSON object on stdout. `emit_result` returns before `save_report`. | No. |

`--json` is the method upstream documents for downstream tooling, and it is the only stock method that does not write the file. It is the wrong method for this cron. The payload measured here is 674329 bytes because `name_audit.real[].devices` carries full device records. The rendered name-audit and recon sections are appended to the markdown only after that return, so they are not inside the `report` string. The cron has to quote one command's stdout through the end. A 674329-byte tool result is the truncation that `2026-11-10_22-55-32.md` already showed at 50398 bytes.

The output this deployment wants is the rendered markdown, on stdout, with no file. None of the three stock methods do that. The patch in section 1 is that output. `--out` stays off the skill. `--json` is not the cron command.

## Not in this batch

- Switching the cron command to `bleep --json db report`. That return happens before name-audit and recon are rendered into the markdown the skill asks for.
- Deleting the three files, or deleting a later file created before the patch.
- Editing jobs `b470c8e8c1e7`, `400acca5173f`, `2754ce497c3c`, or `7685f41fc72b`.
- A `skill_manage` turn, a re-run of `scripts/bleep-phase3.py`, or a `scripts/bleep-update.sh` rebuild. The update script skips a rebuild when the upstream SHA matches and the container is healthy, so it will not apply a local patch.
- A ledger row in `docs/bleep-fidelity.md`. The upstream revision stays `dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85`. The local patch is recorded as a note, not as a new `main` commit.
- Schema restore, schema downgrade, pairing, `enum-scan --variant brute`, and `bleep ctf`.

## 1. Patch the terminal report path

Add `bleep/patches/db-report-stdout.patch`. `git` is already in the image. After `bleep/Dockerfile` checks `git rev-parse HEAD` against `BLEEP_REVISION`, and before `pip install -e .`, copy the patch and run `git apply` in `/opt/bleep`. Do not change the image revision label. Do not commit the patch into the upstream clone.

In `_run_report`, keep the banner lines that already use `print_and_log`. Replace the unconditional `save_report` block:

- When `args.out` is set, call `save_report` and print the existing `[+] Report ... saved to` line.
- When `args.out` is not set, `print` the markdown string and do not call `save_report`.

Use `print` for the body. `print_and_log` also writes the BLEEP event log, and the report body does not belong there. `--out` stays off the skill. `save_report` itself stays unchanged, so an explicit `--out` still writes under `~/.bleep/aoi/reports/` when the filename is relative.

## 2. Rebuild only `bleep`

Do not run `scripts/bleep-update.sh`.

```bash
docker tag bleep-local:dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85 \
  bleep-local:dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85-pre-report-stdout
# snapshot observations.db to the same directory the update script uses
export BLEEP_REVISION=dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85
docker compose --env-file .env.example build bleep
docker compose --env-file .env.example up -d --force-recreate --no-deps bleep
```

The snapshot is a copy. It is not a restore test. If `bash scripts/bleep-status.sh` reports a missing daemon after recreate, retag the saved image back to `bleep-local:dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85` and recreate `bleep` from it. Do not delete the volume. Do not start host `bluetooth.service`.

`scripts/verify-bleep.sh` is unchanged and still does not require the radio or the quote check.

## 3. Prove the writer with one command

Run this only after the new container is healthy, and only while `hermes cron list` shows `b470c8e8c1e7` is not `running`. Record `ls -1 /home/bleep/.bleep/aoi/reports` first.

```bash
docker exec -u bleep -e HOME=/home/bleep bleep \
  bleep db report --format markdown --all-in-window --recon --name-audit \
  --group-identity --identity-contrast
```

Pass when stdout contains `# Aggregate Security Report`, the command exits 0, and a second `ls -1` matches the listing taken before the command. Fail when a new `db_report_*.md` appears. Do not pass `--out`. Do not delete a file if one appears. Stop and record the name.

This command reads `observations.db`. It does not scan and it does not connect.

## 4. Skill 1.3.3 and the report prompt

Edit `skills/bluetooth/bleep/SKILL.md` and copy it to `/opt/data/skills/bluetooth/bleep/SKILL.md`. `chown 10000:10000`. Mode `644`. Bump `version: 1.3.2` to `version: 1.3.3`. Do not change the allow list or the not-allowed list.

Add to the database-report section:

```text
A terminal db report with no --out prints the markdown and does not write a file. Run that command once. The remote user is bleep. Do not use hermes@bleep. Do not read a path under /home/bleep. Do not cat or redirect the report into /opt/data/cache. Do not run a second db report in the same job. After the quote, do not add a command description. scan --variant pokey does not connect. classic-enum --connectionless does not extract GATT.
```

Append the same rule to job `8f19578228c5` only. Do not replace the stored prompt. Edit as uid `10000` with `HOME=/opt/data`, through a Python argument list. The prompt must still contain `Do not pass --out`. `jobs.json` stays uid `10000` mode `600`.

## 5. Known AOI names

At implementation, set the known-name list in `scripts/bleep-status.sh` to the names present before the proof command. That includes the six names already listed and the three files from 22:50, plus any name created by a report that ran before the patch. A name created by the proof command is a failure, not a name to add.

Add one response check. After the last `## Response` line, a report that contains `GATT extraction` or `uses connection attempts` prints the filename and sets a gap. Exercise both strings in `--self-test`. Do not call the check from `scripts/up.sh` or `scripts/verify-bleep.sh`.

## Acceptance

1. Image label revision is still `dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85`. `bleep --version` is still `BLEEP 3.1.0 (DB schema v20)`. The pre-patch image tag exists.
2. One proof `db report` prints `# Aggregate Security Report` and leaves the AOI directory listing unchanged.
3. Repo seed and live skill are `1.3.3`, same sha256, live uid `10000` mode `644`. The allow list and the not-allowed list match `1.3.2` aside from the version line and the database-report insertion.
4. Job `8f19578228c5` still contains `Do not pass --out`. Its schedule is still `50 2,6,10,14,18,22 * * *`. The other four jobs are unchanged.
5. `bash scripts/bleep-status.sh --self-test` prints `self-test ok`. The real run does not report a new AOI name. It may still exit 1 on the current scan's unquoted GATT claims. That scan item stays open.
6. `docs/CHANGELOG.md` records the patch. `docs/bleep-fidelity.md` records the local divergence and does not add a ledger row.

## VV&A before implementation

Accept or reject each line. Implementation waits until all six are accepted.

1. Terminal `db report` without `--out` prints the markdown and does not call `save_report`.
2. `--json` is not the cron command. `--out` stays off the skill.
3. The image is rebuilt with `git apply` on the current SHA, tagged for rollback, and the database is snapshotted before recreate.
4. One operator `db report` is the writer proof. A new AOI file fails that proof.
5. Skill `1.3.3` and one appended paragraph on `8f19578228c5` tell the model to run the report once as `bleep@bleep` and not to add command descriptions after the quote.
6. The known-name list grows to the files already on disk. Future names stay gaps. The three 22:50 files are not deleted.
