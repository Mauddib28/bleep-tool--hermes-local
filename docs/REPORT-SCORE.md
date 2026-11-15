# Report score

Status: not applied. Written 2026-11-15. The running image was not rebuilt, `bleep` was not recreated, and `observations.db` was not opened for a write. Job `8f19578228c5` still runs `scripts/bleep-db-report.py`. Job `b470c8e8c1e7` still runs `scripts/bleep-scan.py`. Skill `1.3.10` stays the seed and the live file.

This batch scores Classic SDP records that are already stored. It does not scan, pair, connect, or read a phone book.

## Evidence

Read from the running image `bleep-local:dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85`, package `/opt/bleep/bleep`, on 2026-11-15. `bleep --version` is `BLEEP 3.1.0 (DB schema v20)`.

The 10:50 UTC report on 2026-11-15 lists `00:01:95:4B:40:69` (Dingo) in the analyzed table as `| 1 | 00:01:95:4B:40:69 | Dingo | 0/10 | 0 | 0 | 0 |`. The device section prints `**Risk Score:** 0/10` and `## Services` / `- None.` The same section's `## SDP Discovery` inventory is 10 records. The ServiceName attribute on the sensitive records is `iPhone 14` or `SIM Access Server`. The UUID is what identifies the profile. BlueZ still names the device Dingo.

| ServiceName | UUID | Channel | Assigned profile |
|---|---|---|---|
| (unnamed) | `0x1200` |  | Device ID (PnP) |
| AVRCP CT | `0x110e` |  | AVRCP |
| AVRCP TG | `0x110c` |  | AVRCP |
| Audio Source | `0x110a` |  | A2DP |
| SIM Access Server | `0x112d` | 8 | SIM Access |
| iPhone 14 | `0x1101` | 3 | Serial Port |
| iPhone 14 | `0x1105` | 9 | OBEX Object Push |
| iPhone 14 | `0x111f` | 13 | Hands-Free Audio Gateway |
| iPhone 14 | `0x112f` | 15 | Phone Book Access |
| iPhone 14 | `0x1132` | 16 | Message Access |

`_device_was_enumerated` already treats `sdp_summary` as an enumeration surface, so Dingo is in the analyzed table. The sentence "These devices were observed/loaded but produced no enumeration surface" is the header of the later not-reachable section. It is not a label on the Dingo row.

The score is the sum of `analysis["summary"]["security_concerns"]` in `_calculate_security_score`: high = 3, medium = 2, low = 1, capped at 10. An empty concern list scores 0. `analyse_device` appends one concern per string in `sdp_analysis["security_flags"]`, and `_assign_concern_risk` marks that concern medium when the reason contains `classic profile`.

`_analyse_sdp_records` builds those flags from the service name only:

```python
for rec in records:
    name = rec.get("name") or ""
    svc_names.append(name or rec.get("uuid", "unknown"))
    lower = name.lower()
    if any(kw in lower for kw in ("obex", "ftp", "opp", "pbap", "map", "spp", "serial")):
        security_flags.append(f"Classic profile exposed: {name}")
```

`iPhone 14`, `AVRCP CT`, `Audio Source`, and `SIM Access Server` contain none of those substrings, so `security_flags` is empty and the score stays 0. The SDP inventory is rendered later from `services_inventory` and is not an input to the score.

`## Services` prints GATT. The empty branch is:

```python
if "services" in device_data:
    report.extend(["## Services", ""])
    if not device_data["services"]:
        report.extend(["- None.", ""])
```

`device_data["services"]` is empty for this device. The Classic records are under `## SDP Discovery`. The text renderer has no Services heading. The cron command is `--format markdown`.

`SDPAnalyzer._detect_anomalies` flags multiple profile versions, an unknown profile version, a missing service name, and `source_conflicts`. It does not flag PBAP, MAP, OPP, HFP, or SAP. The anomaly table on this device was empty. Those anomalies are stored on the SDP summary and are not passed through `_assign_concern_risk`, so they do not move the score today.

The 16-bit values already exist in the image. `bleep/bt_ref/constants.py` defines `SPP_UUID_SHORT` `0x1101`, `OPP_UUID_SHORT` `0x1105`, `FTP_UUID_SHORT` `0x1106`, `PBAP_PSE_UUID_SHORT` `0x112f`, `MAP_MSE_UUID_SHORT` `0x1132`, `MAP_MNS_UUID_SHORT` `0x1133`, and `MAP_UUID_SHORT` `0x1134`. `SERVICE_CLASS_TO_PROFILE` in `bleep/bt_ref/sdp_profile_attr_ids.py` maps `0x111e` and `0x111f` to `hands_free_profile`, `0x112e`/`0x112f`/`0x1130` to `phone_book_access_profile`, and `0x1200` to `device_identification_profile`. No test in the image names `_analyse_sdp_records`.

Reports `18:50` on 2026-11-14 through `10:50` on 2026-11-15 are complete. Analyzed went from 205 to 240. Average risk (analyzed only) went from 2.4 to 2.1. The AOI directory is still 29 names, last `db_report_20261111_225014.md`. Recon still says 10 SDP items because the same ten records are upserted.

## Score this batch produces

One medium concern per distinct sensitive 16-bit UUID. Snapshot copies of the same UUID add nothing. A second RFCOMM channel of the same UUID adds nothing.

Dingo's six sensitive UUIDs are `0x112d`, `0x1101`, `0x1105`, `0x111f`, `0x112f`, and `0x1132`. Six medium concerns score `6 × 2 = 12`. `_calculate_security_score` caps that at 10. The summary row becomes:

```text
| 1 | `00:01:95:4B:40:69` | Dingo | 10/10 | 0 | 6 | 0 |
```

The device section prints `**Risk Score:** 10/10` and six vulnerability lines, one per UUID. PnP `0x1200`, AVRCP `0x110c`/`0x110e`, and A2DP `0x110a` stay out of the medium set. The SDP inventory still lists all ten rows.

A single combined concern would score 2. That understates phone book, messages, files, and the headset gateway sitting on one device. This batch follows the weights already in `_calculate_security_score`.

The analyzed average includes about 240 devices. Moving one device from 0 to 10 changes that average by about 0.04. The acceptance row is the Dingo line. A tenth of a point on the average is not the check.

## Not in this batch

- Rebuilding or recreating `bleep` while this document is only the plan.
- `scripts/bleep-update.sh`. Its healthy-SHA exit skips a rebuild when `patches_present` matches, and it does not know a new patch until section 3 adds a marker.
- A ledger row in `docs/bleep-fidelity.md`. The upstream revision stays `dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85`.
- Retagging `bleep-local:dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85-pre-report-stdout`, `-pre-sdp-stdout`, `-pre-hostnet`, or `-pre-sdp-continue`.
- Editing `scripts/bleep-scan.py`, `scripts/bleep-db-report.py`, the skill allow list, or jobs `b470c8e8c1e7`, `8f19578228c5`, `400acca5173f`, `2754ce497c3c`, and `7685f41fc72b`.
- Pairing, `classic-connect`, PBAP, MAP, OPP, FTP, `classic-rfcomm`, adapter writes, and `bleep ctf`. Scoring reads stored records.
- Copying SDP rows into `device_data["services"]`. That list is GATT.
- Feeding `SDPAnalyzer` anomalies into `security_concerns`. The same UUID would then be counted twice.
- Scoring PnP, AVRCP, or A2DP as medium. Section 4 records them as a later choice. Adding them as low does not move a device that is already at the cap of 10. It only fills the Low column.
- Changing the recon item count. Ten stored records stay ten items.
- Treating the SDP ServiceName `iPhone 14` as a rename of Dingo. Name-audit already has its own section.
- Deleting `bleep-home`, `observations.db`, or any file under `/home/bleep/.bleep/aoi/reports/`.

## 1. Flag the profile by UUID

Patch `bleep/analysis/aoi_analyser.py` only. Keep the name test for a record whose UUID is absent from the map and whose name already matches the current keywords, so a device that scores today still scores. A UUID that is in the map produces one flag and skips the name test.

Add this map next to `_analyse_sdp_records`. The integers are the shorts already defined in `bleep.bt_ref.constants` and `SERVICE_CLASS_TO_PROFILE`. The analyser keeps the dict locally and does not import the OBEX modules.

```python
_SDP_RISK_UUIDS = {
    0x1101: "Serial Port",
    0x1105: "OBEX Object Push",
    0x1106: "OBEX File Transfer",
    0x111E: "Hands-Free",
    0x111F: "Hands-Free Audio Gateway",
    0x112D: "SIM Access",
    0x112E: "Phone Book Access",
    0x112F: "Phone Book Access",
    0x1130: "Phone Book Access",
    0x1132: "Message Access",
    0x1133: "Message Access",
    0x1134: "Message Access",
}

def _sdp_uuid16(uuid: Any) -> int | None:
    text = str(uuid or "").strip().lower().replace("-", "")
    if text.startswith("0x"):
        text = text[2:]
    if not text or any(c not in "0123456789abcdef" for c in text):
        return None
    # Bluetooth base UUID: 0000XXXX-0000-1000-8000-00805F9B34FB
    if len(text) == 32 and text.endswith("00001000800000805f9b34fb"):
        text = text[4:8]
    if len(text) > 4:
        return None
    return int(text, 16)
```

Replace the name-only loop with:

```python
seen: set[int] = set()
for rec in records:
    name = rec.get("name") or ""
    svc_names.append(name or rec.get("uuid", "unknown"))
    uuid16 = _sdp_uuid16(rec.get("uuid"))
    label = _SDP_RISK_UUIDS.get(uuid16 if uuid16 is not None else -1)
    if label is not None:
        if uuid16 in seen:
            continue
        seen.add(uuid16)
        security_flags.append(
            f"Classic profile exposed: {label} ({rec.get('uuid')})"
        )
        continue
    lower = name.lower()
    if any(kw in lower for kw in ("obex", "ftp", "opp", "pbap", "map", "spp", "serial")):
        security_flags.append(f"Classic profile exposed: {name}")
```

The reason starts with `Classic profile exposed`, which is the medium branch already in `_assign_concern_risk` (`"classic profile"`). Hands-Free and SIM Access are medium because of that phrase. Serial Port, OPP, PBAP, and MAP would also match `serial`, `opp`, `pbap`, and `map`. No new branch in `_assign_concern_risk`.

`_dedup_concerns` groups on `(name, description, risk)`. Each flag has a different description, so the vulnerability list shows six lines. The score counts the raw concern list, which is also six, then caps at 10. The Med column is 6.

`services_found` and `services_inventory` stay as they are. JSON already includes `sdp_summary`. The next `db report` rebuilds the concerns from the stored records. There is no schema change and no new scan.

## 2. Say that the empty service list is GATT

In `_generate_markdown_report`, replace the empty-GATT line. `analysis` is already a parameter. Use the same SDP lookup the SDP Discovery section uses.

```python
if not device_data["services"]:
    sdp_info = analysis.get("sdp_summary") or device_data.get("sdp_summary")
    if sdp_info:
        report.extend([
            "- None in GATT. Classic services are listed under SDP Discovery.",
            "",
        ])
    else:
        report.extend(["- None.", ""])
```

A device with no GATT and no SDP still prints `- None.` The advertisement dissection at the other `- None.` (about line 280) stays. The text renderer stays, because it has no Services heading and the cron format is markdown.

## 3. How to apply it later

Do this only after this plan is accepted. The container is unchanged until then.

1. Add `bleep/patches/sdp-risk.patch` covering sections 1 and 2. `git apply --check` it against `/opt/bleep/bleep/analysis/aoi_analyser.py` from the running container before the Dockerfile copies it. The running file is the source of the diff. Normalize both sides to end with a newline before generating the diff, and end every diff line with a newline.
2. In `bleep/Dockerfile`, `COPY` and `git apply` that patch after `patches/sdp-continue.patch` and before `pip install -e .`. Leave the image revision label at `dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85`.
3. Extend `patches_present` in `scripts/bleep-update.sh` with a grep for `def _sdp_uuid16` in `/opt/bleep/bleep/analysis/aoi_analyser.py`. The string `Classic profile exposed` is already in the unpatched file, so it is the wrong marker. Until that grep exists, a healthy container at this SHA will print `not rebuilding` and drop the patch.
4. Tag the current image as a new rollback name. Do not reuse `-pre-sdp-continue` or any older `-pre-*` tag. Copy `observations.db` to `observations.db.<utc>.schema20` on the same volume. Leave the live file in place.
5. Build with `BLEEP_REVISION=dc49063ae3d0c831e1f9e12d04ffecdb9c4c3a85 docker compose --env-file .env.example build bleep`, then `up -d --force-recreate --no-deps bleep`. Hardcode the SHA. Recreate only while job `b470c8e8c1e7` is scheduled and its state is not `running`, and outside the report minute `:50`. The window used for the previous recreate was UTC minute `% 30` outside `>= 27` and `<= 12`.
6. Confirm `bleep --version` is still `BLEEP 3.1.0 (DB schema v20)`, `grep -n _sdp_uuid16` hits `aoi_analyser.py`, and `/home/bleep/.bleep/aoi/reports/` is still 29 names.

The report script already runs `bleep db report --format markdown --all-in-window --recon --name-audit --group-identity --identity-contrast` with no `--out`. The next scheduled report is the observation. A hand `db report` before that slot also writes the score onto stdout and, with no `--out`, must not add an AOI file.

## 4. Left for a later plan

These are real report limits. They are not required to move Dingo off `0/10`.

- AVRCP and A2DP can be a low concern (`risk` set explicitly, because a reason that lacks the medium keywords falls through to low only when the source is not `characteristic`). Three low concerns add 3 and do not change a score that is already capped at 10. The Low column would become 3. Decide that before writing it into the same patch.
- `_detect_anomalies` can keep ignoring sensitive profiles. The flag list is the score. An anomaly row for the same UUID would repeat it.
- The vulnerability block and the SDP flag block will both print `Classic profile exposed: …`. That is the current shape for a name match. Collapsing those two renderers is a separate edit.
- Devices that never return SDP stay at their GATT score. An LE-only miss is still outside `classic-enum`. This plan does not SDP every historical BR address on every cycle.

## Acceptance

After a later apply, the first report whose tool stdout is the patched code must show all of these for `00:01:95:4B:40:69`:

- Summary row `10/10 | 0 | 6 | 0`.
- `**Risk Score:** 10/10`.
- Six medium lines whose reasons are `Classic profile exposed:` plus Serial Port `0x1101`, OBEX Object Push `0x1105`, Hands-Free Audio Gateway `0x111f`, SIM Access `0x112d`, Phone Book Access `0x112f`, and Message Access `0x1132`.
- `## Services` contains `None in GATT. Classic services are listed under SDP Discovery.`
- `## SDP Discovery` still lists 10 unique inventory rows, including PnP `0x1200`, both AVRCP rows, and Audio Source `0x110a`.
- The stdout has no `saved to`, and the AOI directory is still the same 29 names.
- The scan files after the recreate still have no `Connecting to` and no `Pairing required`.

Update `docs/TODO.md`, `docs/CHANGELOG.md`, and `docs/PLAN.md` when that report is read. Leave the scoring box open until the row above is in the tool stdout.
