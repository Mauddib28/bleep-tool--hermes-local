#!/usr/bin/env bash
# Operator check for the BLEEP container, the WSL radio, and the newest cron responses.
# Exit 1 when a daemon is missing, hci0 is not attached, or a saved response fails the quote check.
# A hermes cron status of "ok" is not a scan.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

last_response() {
  awk '
    $0 == "## Response" { buf = ""; capture = 1; agent = 1; next }
    agent == 1 { buf = buf $0 ORS; next }
    $0 == "**Mode:** no_agent (script)" { mode = 1; next }
    mode == 1 && $0 == "---" { buf = ""; capture = 1; mode = 0; next }
    agent == 0 && capture == 1 { buf = buf $0 ORS }
    END { printf "%s", buf }
  '
}

report_rewritten() {
  grep -q -F \
    -e 'rest of report continues' \
    -e 'db_report_' \
    -e 'The report is too large' \
    -e 'Bleep Database Report Analysis' \
    -e 'Report ID' \
    -e 'Improvements' \
    -e '[truncated'
}

report_complete() {
  local body first
  body=$(cat)
  first=$(printf '%s\n' "$body" | sed -n '/[^[:space:]]/{p;q;}')
  [[ "$first" == \[identity-contrast\]* ]] || return 1
  printf '%s\n' "$body" | grep -q -F '# Aggregate Security Report' || return 1
  printf '%s\n' "$body" | grep -q -F '**Other AD structures:**' || return 1
  printf '%s\n' "$body" | report_rewritten && return 1
  return 0
}

# bleep db list prints the field names in upper case. A markdown RSSI_Last
# column is not that header.
quotes_db_list() {
  grep -E -i -q \
    'MAC[[:space:]]+NAME[[:space:]]+RSSI_LAST[[:space:]]+RSSI_MIN[[:space:]]+RSSI_MAX[[:space:]]+FIRST_SEEN[[:space:]]+LAST_SEEN'
}

aoi_allowed() {
  case "$1" in
    db_report_20261110_093303.md|\
    db_report_20261110_102233.md|\
    db_report_20261110_102248.md|\
    db_report_20261110_142503.md|\
    db_report_20261110_151632.md|\
    db_report_20261110_185015.md|\
    db_report_20261110_225040.md|\
    db_report_20261110_225044.md|\
    db_report_20261110_225322.md|\
    db_report_20261111_011544.md|\
    db_report_20261111_025026.md|\
    db_report_20261111_025105.md|\
    db_report_20261111_025657.md|\
    db_report_20261111_025703.md|\
    db_report_20261111_065022.md|\
    db_report_20261111_105035.md|\
    db_report_20261111_105042.md|\
    db_report_20261111_105105.txt|\
    db_report_20261111_105132.md|\
    db_report_20261111_135532.md|\
    db_report_20261111_145057.md|\
    db_report_20261111_145106.md|\
    db_report_20261111_145113.md|\
    db_report_20261111_145150.md|\
    db_report_20261111_145219.md|\
    db_report_20261111_145248.md|\
    db_report_20261111_145324.md|\
    db_report_20261111_225009.md|\
    db_report_20261111_225014.md)
      return 0
      ;;
  esac
  return 1
}

if [[ "${1:-}" == "--self-test" ]]; then
  header='MAC  NAME  RSSI_LAST  RSSI_MIN  RSSI_MAX  FIRST_SEEN  LAST_SEEN'
  quoted=$(printf '%s\n' '## Prompt' 'rssi_last' '## Response' "$header" | last_response)
  quotes_db_list <<<"$quoted"
  table=$(printf '%s\n' '## Prompt' 'rssi_last' '## Response' '| MAC | Name | RSSI_Last | Previous |' | last_response)
  quotes_db_list <<<"$table" && exit 1
  lower=$(printf '%s\n' '## Response' 'row rssi_last' | last_response)
  quotes_db_list <<<"$lower" && exit 1
  bad=$(printf '%s\n' '## Response' 'rest of report continues' | last_response)
  grep -q -F 'rest of report continues' <<<"$bad"
  good=$(printf '%s\n' '## Response' 'quoted report' | last_response)
  grep -q -F 'rest of report continues' <<<"$good" && exit 1
  aoi_allowed db_report_20261110_185015.md
  aoi_allowed db_report_20261111_225014.md
  aoi_allowed db_report_20261110_999999.md && exit 1
  aoi_allowed db_report_20261111_999999.md && exit 1
  narr=$(printf '%s\n' '## Response' 'classic-enum attempts GATT extraction' | last_response)
  grep -q -F 'GATT extraction' <<<"$narr"
  conn=$(printf '%s\n' '## Response' 'pokey uses connection attempts' | last_response)
  grep -q -F 'uses connection attempts' <<<"$conn"
  plain=$(printf '%s\n' '## Response' 'quoted report' | last_response)
  grep -q -F -e 'GATT extraction' -e 'uses connection attempts' -e 'db_report_' -e 'The report is too large' <<<"$plain" && exit 1
  invented=$(printf '%s\n' '## Response' 'Report ID: db_report_20261112_025032.md' | last_response)
  grep -q -F 'db_report_' <<<"$invented"
  large=$(printf '%s\n' '## Response' 'The report is too large' | last_response)
  grep -q -F 'The report is too large' <<<"$large"
  titled=$(printf '%s\n' '## Response' 'Bleep Database Report Analysis' | last_response)
  grep -q -F 'Bleep Database Report Analysis' <<<"$titled"
  scan_sum=$(printf '%s\n' '## Response' 'GATT Enumeration Summary' | last_response)
  grep -q -F 'GATT Enumeration Summary' <<<"$scan_sum"
  script_doc=$(printf '%s\n' '# Cron Job: BLEEP database report' '**Mode:** no_agent (script)' '---' '[identity-contrast] raw 1' '# Aggregate Security Report' '**Other AD structures:**' '- None.')
  script_body=$(printf '%s\n' "$script_doc" | last_response)
  report_complete <<<"$script_body"
  truncated=$(printf '%s\n' '**Mode:** no_agent (script)' '---' '[identity-contrast] raw 1' '[truncated - see full' '# Aggregate Security Report' '**Other AD structures:**')
  report_complete <<<"$(printf '%s\n' "$truncated" | last_response)" && exit 1
  prompt_rule=$(printf '%s\n' '**Mode:** no_agent (script)' '---' 'prompt junk' '## Response' 'MAC  NAME  RSSI_LAST  RSSI_MIN  RSSI_MAX  FIRST_SEEN  LAST_SEEN')
  quotes_db_list <<<"$(printf '%s\n' "$prompt_rule" | last_response)"
  echo "self-test ok"
  exit 0
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Run this from Ubuntu-22.04: bash scripts/bleep-status.sh" >&2
  exit 1
fi

gaps=0

health="$(docker inspect -f '{{.State.Health.Status}}' bleep 2>/dev/null || echo absent)"
echo "bleep health: ${health}"
[[ "$health" == "healthy" ]] || gaps=1

if ! docker exec bleep true >/dev/null 2>&1; then
  echo "bleep is not running. Start it with:"
  echo "  export BLEEP_REVISION=\$(docker inspect -f '{{index .Config.Labels \"org.opencontainers.image.revision\"}}' bleep)"
  echo "  docker compose --env-file .env.example up -d --no-deps bleep"
  exit 1
fi

procs="$(docker exec bleep ps -eo args)"
check_proc() {
  if grep -q -F -- "$1" <<<"$procs"; then
    echo "ok       ${1}"
  else
    echo "MISSING  ${1}"
    gaps=1
  fi
}

check_proc 'dbus-daemon --system'
check_proc 'bluetoothd --nodetach -E'
check_proc 'dbus-daemon --session'
check_proc '/usr/libexec/bluetooth/obexd'
check_proc 'bluealsa -p a2dp-source'
check_proc 'bleep-hostnetd'

if [[ "$gaps" -ne 0 ]]; then
  revision="$(docker inspect -f '{{index .Config.Labels "org.opencontainers.image.revision"}}' bleep 2>/dev/null || true)"
  echo
  echo "sshd can be up while the buses are dead. Recreate bleep so the entrypoint starts them:"
  echo "  export BLEEP_REVISION=${revision:-<image label>}"
  echo "  docker compose --env-file .env.example up -d --force-recreate --no-deps bleep"
fi

if [[ -e /sys/class/bluetooth/hci0 ]]; then
  echo "hci0: present"
  docker exec bleep nsenter --net=/hostns/net bluetoothctl show \
    | grep -E '^(Controller|[[:space:]]+(Powered|Pairable|Discoverable):)' || true
else
  echo "hci0: absent. Windows bus 1-14 is Shared until it is attached."
  echo "  From Windows: \"C:\\Program Files\\usbipd-win\\usbipd.exe\" attach --wsl --busid 1-14"
  echo "  Leave the WSL host unit bluetooth.service disabled."
  gaps=1
fi

newest_cron() {
  docker exec -u 10000 -e HOME=/opt/data hermes-agent \
    sh -c "ls -1t $1/*.md 2>/dev/null | head -n 1" || true
}

job_output() {
  local script="$1"
  local fallback="$2"
  local found
  found="$(docker exec -i -u 10000 -e HOME=/opt/data hermes-agent python3 - "$script" <<'PY' || true
import json, sys
from pathlib import Path
wanted = sys.argv[1]
payload = json.loads(Path("/opt/data/cron/jobs.json").read_text())
for job in payload.get("jobs", []):
    if job.get("script") == wanted and job.get("id"):
        print("/opt/data/cron/output/" + job["id"])
        break
PY
)"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
  else
    printf '%s\n' "/opt/data/cron/output/${fallback}"
  fi
}

scan_dir="$(job_output bleep-scan.py b470c8e8c1e7)"
report_dir="$(job_output bleep-db-report.py 8f19578228c5)"
scan_file="$(newest_cron "$scan_dir")"
if [[ -n "$scan_file" ]]; then
  scan_body="$(docker exec -u 10000 -e HOME=/opt/data hermes-agent cat "$scan_file" | last_response)"
  if quotes_db_list <<<"$scan_body"; then
    echo "ok       scan response quotes db list ($(basename "$scan_file"))"
  else
    echo "scan response has no db list quote: $(basename "$scan_file")"
    gaps=1
  fi
  if grep -q -F \
    -e 'GATT Enumeration Summary' \
    -e 'GATT profiles persisted' \
    -e 'Latest 50 devices' \
    -e 'GATT enumeration was performed' \
    -e 'Cron job completed' \
    -e 'Notable devices' <<<"$scan_body"; then
    echo "scan response summarizes instead of quoting: $(basename "$scan_file")"
    gaps=1
  fi
fi

report_file="$(newest_cron "$report_dir")"
if [[ -n "$report_file" ]]; then
  report_body="$(docker exec -u 10000 -e HOME=/opt/data hermes-agent cat "$report_file" | last_response)"
  if report_complete <<<"$report_body"; then
    echo "ok       report response is the command stdout ($(basename "$report_file"))"
  else
    echo "report response abbreviates or rewrites the quote: $(basename "$report_file")"
    gaps=1
  fi
  if grep -q -F -e 'GATT extraction' -e 'uses connection attempts' <<<"$report_body"; then
    echo "report response adds a command description: $(basename "$report_file")"
    gaps=1
  fi
fi

aoi_names="$(docker exec bleep ls -1 /home/bleep/.bleep/aoi/reports 2>/dev/null || true)"
if [[ -n "$aoi_names" ]]; then
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if aoi_allowed "$name"; then
      continue
    fi
    echo "unexpected AOI report: ${name}"
    gaps=1
  done <<<"$aoi_names"
fi

echo
echo "Cron status ok is not a scan. Inside hermes-agent, read the latest file under"
echo "  ${scan_dir}/"
echo "A failed scan that the model marks with a misspelled [CRON_FAILURE] token is stored as ok."

[[ "$gaps" -eq 0 ]] || exit 1
echo "PASS"
