#!/usr/bin/env bash
# BLEEP container checks. Independent of scripts/verify.sh and the host ollama unit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Run this from Ubuntu-22.04: bash scripts/verify-bleep.sh" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$ROOT/scripts/lib.sh"
load_env

running=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  health="$(docker inspect -f '{{.State.Health.Status}}' bleep 2>/dev/null || true)"
  if [[ "$health" == "healthy" ]]; then
    running=yes
    break
  fi
  sleep 2
done
[[ "$running" == "yes" ]] || fail "bleep is not healthy (last status ${health:-absent})"

procs="$(docker exec bleep ps -eo args)"
for needle in \
  'dbus-daemon --system' \
  'bluetoothd --nodetach -E' \
  'dbus-daemon --session' \
  '/usr/libexec/bluetooth/obexd' \
  'bluealsa -p a2dp-source' \
  'bleep-hostnetd'
do
  grep -q -F -- "$needle" <<<"$procs" || fail "bleep process list is missing: ${needle}"
done

bindings="$(docker inspect -f '{{json .HostConfig.PortBindings}}' bleep)"
[[ "$bindings" == "{}" || "$bindings" == "null" || "$bindings" == "map[]" ]] \
  || fail "bleep publishes host ports: ${bindings}"

mounts="$(docker inspect -f '{{range .Mounts}}{{.Source}} {{end}}' bleep)"
[[ "$mounts" != */var/run/dbus* ]] || fail "bleep mounts a host dbus socket"

if docker exec hermes-agent docker info >/dev/null 2>&1; then
  fail "hermes-agent can reach a Docker daemon"
fi

if docker exec hermes-agent grep -Eq 'backend:[[:space:]]*"?ssh"?' /opt/data/config.yaml; then
  fail "terminal.backend is ssh"
fi

ssh_base=(
  ssh
  -i /run/secrets/bleep_ed25519
  -o BatchMode=yes
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/opt/data/ssh/known_hosts
  -o ConnectTimeout=10
  bleep@bleep
  --
)

version="$(docker exec -u 10000 -e HOME=/opt/data hermes-agent "${ssh_base[@]}" bleep --version)" \
  || fail "ssh bleep --version failed"
echo "$version" | grep -Eq 'DB schema v[0-9]+' || fail "version line has no schema: ${version}"

remote_host="$(docker exec -u 10000 -e HOME=/opt/data hermes-agent "${ssh_base[@]}" hostname)"
hermes_host="$(docker exec hermes-agent hostname)"
wsl_host="$(hostname)"
[[ -n "$remote_host" && "$remote_host" != "$hermes_host" && "$remote_host" != "$wsl_host" ]] \
  || fail "remote hostname '${remote_host}' is not a separate container"

db_path="$(docker exec -u 10000 -e HOME=/opt/data hermes-agent "${ssh_base[@]}" printenv BLEEP_DB_PATH || true)"
[[ "$db_path" == "/home/bleep/.bleep/observations.db" ]] \
  || fail "BLEEP_DB_PATH is '${db_path:-empty}'"

if systemctl is-active --quiet bluetooth; then
  fail "Host bluetooth.service is active. Disable it. Do not start it."
fi
if systemctl is-enabled --quiet bluetooth 2>/dev/null; then
  fail "Host bluetooth.service is enabled. Run: sudo systemctl disable --now bluetooth"
fi

hash_of() {
  sha256sum "$1" | awk '{print $1}'
}
live_hash() {
  docker exec -u 10000 -e HOME=/opt/data hermes-agent sha256sum "$1" | awk '{print $1}'
}
seed_skill="$(hash_of "$ROOT/skills/bluetooth/bleep/SKILL.md")"
live_skill="$(live_hash /opt/data/skills/bluetooth/bleep/SKILL.md)"
[[ "$seed_skill" == "$live_skill" ]] || fail "live bleep skill does not match the repo seed"
for script in bleep-scan.py bleep-db-report.py; do
  [[ "$(hash_of "$ROOT/scripts/$script")" == "$(live_hash "/opt/data/scripts/$script")" ]] \
    || fail "live $script does not match the repo"
done

if ! docker exec -i -u 10000 -e HOME=/opt/data hermes-agent python3 - <<'PY'
import json
from pathlib import Path
jobs = json.loads(Path("/opt/data/cron/jobs.json").read_text()).get("jobs", [])
wanted = {
    "bleep-scan.py": "5,35 * * * *",
    "bleep-db-report.py": "50 2,6,10,14,18,22 * * *",
}
found = {}
for job in jobs:
    script = job.get("script")
    if script in wanted:
        found[script] = job
for script, expr in wanted.items():
    job = found.get(script)
    if not job or job.get("no_agent") is not True:
        raise SystemExit(script)
    if (job.get("schedule") or {}).get("expr") != expr:
        raise SystemExit(script)
    if "bleep" not in (job.get("skills") or []):
        raise SystemExit(script)
names = {job.get("name") for job in jobs}
for name in (
    "Daily Bluetooth Tooling Examinations",
    "Update Bluetooth Findings",
    "Review and Update",
):
    if name not in names:
        raise SystemExit(name)
print("cron ok")
PY
then
  fail "BLEEP cron jobs do not match the repo"
fi

echo "PASS"
echo "BLEEP version: ${version}"
echo "BLEEP hostname: ${remote_host}"
