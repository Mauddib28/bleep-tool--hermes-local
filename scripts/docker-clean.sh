#!/usr/bin/env bash
# Remove leftover Docker objects recorded on 2026-11-14.
# Dangling images, build cache, two stopped containers, and three unused
# anonymous volumes. Tagged images and named volumes stay.
set -euo pipefail

dry=0
if [[ "${1:-}" == "--dry-run" ]]; then
  dry=1
elif [[ $# -gt 0 ]]; then
  echo "usage: bash scripts/docker-clean.sh [--dry-run]" >&2
  exit 1
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Run this from Ubuntu-22.04: bash scripts/docker-clean.sh" >&2
  exit 1
fi

run() {
  if [[ "$dry" -eq 1 ]]; then
    printf 'dry-run:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

# Stopped containers from other Compose projects. The running stack is not here.
stopped_containers=(
  hermes-agent-previous
  openclaw-openclaw-gateway-1
)

# Anonymous volumes with no container on 2026-11-14.
# 74370f2c6f6c is mounted at /opt/data by protocol-broker and is not in this list.
anonymous_volumes=(
  66a48282f27d3941356bfb4dbae22c68be2e5fbca39a3ca77cb8941eff03ea8c
  75f0d386fe2d1ecc5e64701451886f12135e964fae7b8d9abca39ea118590098
  769848fe5bdec2e9aeca3a2b5c5f1a3ff307870090278f82c3edb7c13a4c7b81
)

protected_volumes=(
  bleep-home
  ollama
)

for name in "${stopped_containers[@]}"; do
  cid="$(docker ps -aq -f "name=^/${name}$")"
  if [[ -z "$cid" ]]; then
    echo "absent container ${name}"
    continue
  fi
  state="$(docker inspect -f '{{.State.Status}}' "$cid")"
  if [[ "$state" == "running" || "$state" == "restarting" || "$state" == "paused" ]]; then
    echo "refusing to remove ${name}: state ${state}" >&2
    exit 1
  fi
  echo "remove container ${name} (${state})"
  run docker rm "$cid"
done

for vol in "${anonymous_volumes[@]}"; do
  for keep in "${protected_volumes[@]}"; do
    if [[ "$vol" == "$keep" ]]; then
      echo "refusing to remove protected volume ${vol}" >&2
      exit 1
    fi
  done
  if ! docker volume inspect "$vol" >/dev/null 2>&1; then
    echo "absent volume ${vol}"
    continue
  fi
  users="$(docker ps -aq --filter "volume=${vol}")"
  if [[ -n "$users" ]]; then
    echo "refusing to remove volume ${vol}: still mounted by ${users}" >&2
    exit 1
  fi
  echo "remove volume ${vol}"
  run docker volume rm "$vol"
done

echo "prune dangling images"
run docker image prune -f
echo "prune build cache"
run docker builder prune -f

echo "kept volumes bleep-home and ollama, and every ai-stack_* and ollama_* volume"
echo "kept tagged images, including the bleep-local rollback tags"
echo "did not run docker volume prune or docker system prune -a"
