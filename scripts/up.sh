#!/usr/bin/env bash
# Bring up the Ollama, Hermes, broker, and OpenClaw stack. Safe to re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Run this from Ubuntu-22.04: bash scripts/up.sh" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$ROOT/scripts/lib.sh"
load_env

if systemctl is-enabled --quiet ollama 2>/dev/null; then
  if sudo -n systemctl disable --now ollama; then
    echo "Disabled host ollama.service so it cannot take port 11434 or the GPU on boot."
  else
    echo "WARNING: host ollama.service is still enabled. Passwordless sudo is unavailable." >&2
    echo "Run: sudo systemctl disable --now ollama" >&2
  fi
elif systemctl is-active --quiet ollama; then
  if sudo -n systemctl stop ollama; then
    echo "Stopped host ollama.service."
  else
    echo "Host ollama.service is active. Stop it, then rerun." >&2
    exit 1
  fi
fi

if systemctl is-enabled --quiet bluetooth 2>/dev/null || systemctl is-active --quiet bluetooth; then
  if sudo -n systemctl disable --now bluetooth; then
    echo "Disabled host bluetooth.service so container bluetoothd can own the adapter."
  else
    echo "WARNING: host bluetooth.service is enabled or active. Passwordless sudo is unavailable." >&2
    echo "Run: sudo systemctl disable --now bluetooth" >&2
    if systemctl is-active --quiet bluetooth; then
      exit 1
    fi
  fi
fi

if ! docker volume inspect ollama >/dev/null 2>&1; then
  echo "Docker volume 'ollama' is missing. Creating it so qwen3.5:latest can be pulled."
  docker volume create ollama >/dev/null
fi

if docker ps --format '{{.Names}}' | grep -qx 'wonderful_banzai'; then
  echo "wonderful_banzai is running setup against ~/.hermes-bluetooth."
  echo "This stack uses /home/user/hermes/ollama-stack and does not mount that directory."
fi

release_foreign_container() {
  local name="$1"
  local action="$2"
  local cid state project
  cid="$(docker ps -aq -f "name=^/${name}$")"
  if [[ -z "$cid" ]]; then
    return 0
  fi
  state="$(docker inspect -f '{{.State.Status}}' "$cid")"
  project="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$cid")"
  if [[ "$project" == "$ROOT" ]]; then
    return 0
  fi
  if [[ "$state" == "running" || "$state" == "restarting" || "$state" == "paused" ]]; then
    echo "Container ${name} is ${state} and is not part of this project. Stop it before bring-up." >&2
    exit 1
  fi
  if [[ "$action" == "rename" ]]; then
    if [[ -n "$(docker ps -aq -f "name=^/${name}-previous$")" ]]; then
      echo "Container ${name}-previous already exists. Move it aside before bring-up." >&2
      exit 1
    fi
    echo "Renaming stopped container ${name} to ${name}-previous. Its mounts are unchanged."
    docker rename "$cid" "${name}-previous" >/dev/null
    return 0
  fi
  echo "Removing stopped container ${name}. Volumes and host data directories are kept."
  docker rm "$cid" >/dev/null
}

release_foreign_container ollama rm
release_foreign_container ollama-local rm
release_foreign_container hermes-agent rename
release_foreign_container protocol-broker rm
release_foreign_container openclaw-gateway rm
release_foreign_container bleep rm

pin="$(docker image inspect "$HERMES_IMAGE" --format '{{.Id}}')"
current="$(docker inspect -f '{{.Image}}' hermes-agent 2>/dev/null || true)"
if [[ -n "$current" && "$current" != "$pin" ]]; then
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  echo "Backing up /home/user/hermes/ollama-stack before the Hermes image change."
  docker run --rm \
    -v /home/user/hermes:/hosthermes \
    alpine:latest \
    tar -C /hosthermes -czf "/hosthermes/ollama-stack-${stamp}.tgz" ollama-stack
fi

docker run --rm \
  -v /home/user/hermes:/hosthermes \
  -v "$ROOT/config:/src:ro" \
  -v "$ROOT/skills:/skills:ro" \
  -v "$ROOT/scripts:/reposcripts:ro" \
  alpine:latest \
  sh -c 'mkdir -p /hosthermes/ollama-stack /hosthermes/ollama-stack/ssh \
      /hosthermes/ollama-stack/skills/bluetooth/bleep \
      /hosthermes/ollama-stack/scripts
    if [ ! -f /hosthermes/ollama-stack/config.yaml ]; then
      cp /src/config.yaml /hosthermes/ollama-stack/config.yaml
    fi
    if [ ! -f /hosthermes/ollama-stack/.env ]; then
      cp /src/hermes.env /hosthermes/ollama-stack/.env
    fi
    cp /skills/bluetooth/bleep/SKILL.md /hosthermes/ollama-stack/skills/bluetooth/bleep/SKILL.md
    cp /reposcripts/bleep-scan.py /hosthermes/ollama-stack/scripts/bleep-scan.py
    cp /reposcripts/bleep-db-report.py /hosthermes/ollama-stack/scripts/bleep-db-report.py
    chmod 644 /hosthermes/ollama-stack/skills/bluetooth/bleep/SKILL.md
    chmod 755 /hosthermes/ollama-stack/scripts/bleep-scan.py \
      /hosthermes/ollama-stack/scripts/bleep-db-report.py
    chown -R 10000:10000 /hosthermes/ollama-stack
    chmod 700 /hosthermes/ollama-stack/ssh'

docker run --rm --user 0 --entrypoint /opt/hermes/.venv/bin/python3 \
  -e HOST_HERMES=/hosthermes \
  -e SEED_DIR=/seed \
  -v /home/user/hermes:/hosthermes \
  -v "$ROOT/openclaw:/seed:ro" \
  -v "$ROOT/scripts/bootstrap_state.py:/bootstrap_state.py:ro" \
  "$HERMES_IMAGE" /bootstrap_state.py

bash "$ROOT/scripts/bleep-keys.sh"
[[ -n "${BLEEP_REVISION:-}" ]] || { echo "BLEEP_REVISION is empty. Set it in .env.example." >&2; exit 1; }
bash "$ROOT/scripts/bleep-update.sh"

compose up -d --remove-orphans

if ! docker exec ollama-local ollama list | awk 'NR>1 {print $1}' | grep -qx "$OLLAMA_MODEL"; then
  docker exec ollama-local ollama pull "$OLLAMA_MODEL"
fi

ready=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if docker exec hermes-agent /opt/hermes/.venv/bin/python3 -c 'import urllib.error, urllib.request
try:
    urllib.request.urlopen("http://127.0.0.1:9119/api/status", timeout=3)
except urllib.error.HTTPError:
    pass
else:
    pass' >/dev/null 2>&1; then
    ready=yes
    break
  fi
  sleep 2
done
[[ -n "$ready" ]] || { echo "Hermes dashboard did not answer /api/status" >&2; exit 1; }

align="$(docker exec -i hermes-agent /opt/hermes/.venv/bin/python3 - < "$ROOT/scripts/align_hermes_config.py")"
echo "$align"
if [[ "$align" == CHANGED* ]]; then
  docker restart hermes-agent >/dev/null
fi

bash "$ROOT/scripts/install-bleep-cron.sh"
bash "$ROOT/scripts/verify-bleep.sh"
bash "$ROOT/scripts/verify.sh"

echo "Dashboard: http://127.0.0.1:9119/ from Ubuntu and from the Windows host."
echo "Hermes API and the broker are on hermes-net only."
