#!/usr/bin/env bash
# Stop and remove this project's containers. Keeps the ollama volume and Hermes data dir.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Run this from Ubuntu-22.04: bash scripts/down.sh" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$ROOT/scripts/lib.sh"
load_env
compose down --remove-orphans
echo "Stopped this project's containers. Images were kept."
echo "Kept volumes ollama and bleep-home, and /home/user/hermes/ollama-stack, /home/user/hermes/keys, and /home/user/hermes/openclaw."
echo "bash scripts/up.sh restores the pinned BLEEP image, the bleep skill, both no-agent scripts, and the scan and report jobs."
echo "Do not delete those volumes. Host ollama.service and bluetooth.service were not started."
