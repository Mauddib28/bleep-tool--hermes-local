#!/usr/bin/env python3
"""Print one BLEEP database report. The cron job stores this stdout."""
import subprocess
import sys

SSH = [
    "ssh",
    "-i", "/run/secrets/bleep_ed25519",
    "-o", "BatchMode=yes",
    "-o", "IdentitiesOnly=yes",
    "-o", "ConnectTimeout=15",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "UserKnownHostsFile=/opt/data/ssh/known_hosts",
    "bleep@bleep",
    "--",
    "bleep",
    "db",
    "report",
    "--format", "markdown",
    "--all-in-window",
    "--recon",
    "--name-audit",
    "--group-identity",
    "--identity-contrast",
]


def main() -> int:
    completed = subprocess.run(SSH, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    sys.stdout.buffer.write(completed.stdout)
    if completed.returncode != 0:
        sys.stderr.buffer.write(completed.stderr)
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
