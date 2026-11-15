#!/usr/bin/env bash
# Reconcile the two BLEEP no-agent jobs. Does not edit the research jobs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Run this from Ubuntu-22.04: bash scripts/install-bleep-cron.sh" >&2
  exit 1
fi

ready=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if docker exec -u 10000 -e HOME=/opt/data hermes-agent true >/dev/null 2>&1; then
    ready=yes
    break
  fi
  sleep 2
done
[[ -n "$ready" ]] || { echo "hermes-agent is not running" >&2; exit 1; }

docker exec -i -u 10000 -e HOME=/opt/data hermes-agent python3 - \
  < "$ROOT/scripts/install_bleep_cron.py"
docker exec -u 10000 -e HOME=/opt/data hermes-agent \
  stat -c '%u %a %n' /opt/data/cron/jobs.json
