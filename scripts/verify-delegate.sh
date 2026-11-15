#!/usr/bin/env bash
# One Hermes run through the broker. Does not print the API key.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Run this from Ubuntu-22.04: bash scripts/verify-delegate.sh" >&2
  exit 1
fi

docker exec -i protocol-broker /opt/hermes/.venv/bin/python3 - << 'PY'
import json
import urllib.request

body = json.dumps({"input": "Reply with the single word pong."}).encode()
request = urllib.request.Request(
    "http://127.0.0.1:8787/objectives",
    data=body,
    headers={"Content-Type": "application/json"},
    method="POST",
)
with urllib.request.urlopen(request, timeout=200) as response:
    payload = json.loads(response.read().decode())
print("http", response.status)
print("run_id", payload.get("run_id"))
print("status", payload.get("status"))
output = str(payload.get("output") or "")
print("output_len", len(output))
print("output_has_pong", "pong" in output.lower())
if "below the minimum" in output.lower():
    raise SystemExit("context floor rejection")
if not payload.get("run_id"):
    raise SystemExit("missing run_id")
if str(payload.get("status") or "").lower() in {"failed", "failure", "error"}:
    raise SystemExit("run failed")
PY
