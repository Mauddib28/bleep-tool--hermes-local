#!/usr/bin/env bash
# Create the BLEEP SSH key under /home/user/hermes/keys. Does not print the key.
set -euo pipefail

docker run --rm -v /home/user/hermes/keys:/keys alpine:latest \
  sh -c 'apk add --no-cache openssh-keygen >/dev/null
    mkdir -p /keys
    if [ ! -s /keys/bleep_ed25519 ]; then
      ssh-keygen -q -t ed25519 -f /keys/bleep_ed25519 -N "" -C bleep-hermes
    fi
    chown 10000:10000 /keys /keys/bleep_ed25519 /keys/bleep_ed25519.pub
    chmod 700 /keys
    chmod 600 /keys/bleep_ed25519
    chmod 644 /keys/bleep_ed25519.pub'
echo "BLEEP SSH key is in place."
