#!/usr/bin/env bash
# Confirm the stack is up, loopback-only on the host, and the broker can see Hermes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Run this from Ubuntu-22.04: bash scripts/verify.sh" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$ROOT/scripts/lib.sh"
load_env

compose ps

running=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  running="$(docker inspect -f '{{.State.Running}}' hermes-agent 2>/dev/null || true)"
  if [[ "$running" == "true" ]]; then
    break
  fi
  sleep 2
done
[[ "$running" == "true" ]] || fail "hermes-agent is not running"

pin="$(docker image inspect "$HERMES_IMAGE" --format '{{.Id}}')"
actual="$(docker inspect -f '{{.Image}}' hermes-agent)"
[[ "$actual" == "$pin" ]] || fail "hermes-agent image is ${actual}, expected ${pin}"

docker exec hermes-agent curl -fsS http://ollama:11434/api/tags | grep -q 'qwen3.5' \
  || fail "hermes-agent cannot list qwen3.5 at http://ollama:11434"

docker exec ollama-local sh -c 'nvidia-smi -L | grep -q "RTX 5090"' \
  || fail "ollama-local does not see the RTX 5090"

docker exec hermes-agent grep -q 'http://ollama:11434/v1' /opt/data/config.yaml \
  || fail "hermes-agent config is not pointed at the Ollama service"

ctx="$(docker exec ollama-local ollama ps | python3 -c '
import sys
lines = [line.rstrip("\n") for line in sys.stdin]
header = lines[0]
start = header.index("CONTEXT")
end = header.index("UNTIL")
rows = [line[start:end].strip() for line in lines[1:] if line.strip()]
print(rows[0] if rows else "idle")
')"
[[ "$ctx" == "65536" || "$ctx" == "idle" ]] || fail "loaded qwen3.5 context is '${ctx}', expected 65536"
docker exec hermes-agent grep -q 'ollama_num_ctx: 65536' /opt/data/config.yaml \
  || fail "config.yaml is missing ollama_num_ctx: 65536"

if systemctl is-active --quiet ollama; then
  fail "Host ollama.service is still active"
fi

bindings="$(docker inspect -f '{{json .HostConfig.PortBindings}}' hermes-agent)"
[[ "$bindings" == *'"9119/tcp":[{"HostIp":"127.0.0.1"'* ]] || fail "dashboard is not published on 127.0.0.1 only: ${bindings}"
[[ "$bindings" != *8642* ]] || fail "8642 is published on the host: ${bindings}"

ollama_bindings="$(docker inspect -f '{{json .HostConfig.PortBindings}}' ollama-local)"
[[ "$ollama_bindings" == "{}" || "$ollama_bindings" == "null" || "$ollama_bindings" == "map[]" ]] \
  || fail "ollama-local publishes host ports: ${ollama_bindings}"

if ss -lnt | awk '
  $4 ~ /:11434$/ || $4 ~ /:8642$/ { found=1 }
  $4 ~ /^(\*|0\.0\.0\.0|\[::\]):9119$/ { found=1 }
  END { exit found ? 0 : 1 }
'; then
  fail "a stack port is listening on all interfaces"
fi

dash_code=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  dash_code="$(curl -sS -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:9119/api/config || echo 000)"
  [[ "$dash_code" == "401" ]] && break
  sleep 2
done
[[ "$dash_code" == "401" ]] || fail "Unauthenticated dashboard /api/config returned ${dash_code:-none}, expected 401"

dash_auth="$(docker exec hermes-agent /opt/hermes/.venv/bin/python3 -c 'import json, urllib.request
token=open("/run/secrets/dashboard.token").read().strip()
request=urllib.request.Request("http://127.0.0.1:9119/api/status", headers={"Authorization":"Bearer "+token})
with urllib.request.urlopen(request, timeout=5) as response:
    status=json.load(response)
page=urllib.request.urlopen("http://127.0.0.1:9119/", timeout=5).read().decode("utf-8", "replace")
print(status.get("auth_required"))
print(status.get("version",""))
print("token-embedded" if "__HERMES_SESSION_TOKEN__=" in page else "token-absent")')"
[[ "$(printf '%s\n' "$dash_auth" | sed -n '1p')" == "True" ]] || fail "Dashboard auth_required is not true"
[[ "$(printf '%s\n' "$dash_auth" | sed -n '2p')" == *.* ]] || fail "Dashboard did not return a version"
[[ "$(printf '%s\n' "$dash_auth" | sed -n '3p')" == "token-absent" ]] || fail "Dashboard HTML still embeds a session token"

docker exec hermes-agent /command/s6-svstat /run/service/dashboard | grep -q '^up ' \
  || fail "Dashboard s6 service is not up"

unauth="$(docker exec protocol-broker /opt/hermes/.venv/bin/python3 -c 'import urllib.request, urllib.error
try:
    urllib.request.urlopen("http://hermes-agent:8642/v1/models", timeout=5)
    print(200)
except urllib.error.HTTPError as exc:
    print(exc.code)')"
[[ "$unauth" == "401" ]] || fail "Hermes API without a key returned ${unauth}, expected 401"

if python3 - << 'PY'
import socket
s = socket.socket()
s.settimeout(3)
try:
    s.connect(("127.0.0.1", 8642))
except OSError:
    raise SystemExit(0)
else:
    raise SystemExit(1)
finally:
    s.close()
PY
then
  :
else
  fail "host port 8642 accepted a connection"
fi

broker_ok=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if docker exec protocol-broker /opt/hermes/.venv/bin/python3 -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8787/health", timeout=3)'; then
    broker_ok=yes
    break
  fi
  sleep 2
done
[[ -n "$broker_ok" ]] || fail "protocol-broker /health did not answer"

claw=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if docker exec openclaw-gateway node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"; then
    claw=yes
    break
  fi
  sleep 2
done
[[ -n "$claw" ]] || fail "openclaw-gateway /healthz did not answer inside the container"

if systemctl is-enabled --quiet ollama 2>/dev/null; then
  fail "Host ollama.service is still enabled. Run: sudo systemctl disable --now ollama"
fi

echo "PASS"
echo "Dashboard: http://127.0.0.1:9119/ on the Docker host"
