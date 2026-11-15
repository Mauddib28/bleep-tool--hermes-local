#!/usr/bin/env python3
"""Run one BLEEP observation pass and print each command's stdout."""
from __future__ import annotations

import re
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
]
ADAPTER = "Bluetooth adapter not found or not ready"
CONTROLLER = "94:E6:F7:A1:D6:B3"
MAC = re.compile(r"(?i)\b[0-9a-f]{2}(?::[0-9a-f]{2}){5}\b")
FIELDS = "mac,name,rssi_last,rssi_min,rssi_max,first_seen,last_seen"
NO_GATT = "no GATT characteristics were resolved"


def run(args: list[str]) -> tuple[int, str, str]:
    completed = subprocess.run(
        SSH + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    out = completed.stdout.decode("utf-8", "replace")
    err = completed.stderr.decode("utf-8", "replace")
    if ADAPTER in out or ADAPTER in err:
        print("[CRON_FAILURE]")
        print(ADAPTER)
        raise SystemExit(1)
    print("$ bleep " + " ".join(args))
    if out and not out.endswith("\n"):
        out += "\n"
    sys.stdout.write(out)
    if err.strip():
        if not err.endswith("\n"):
            err += "\n"
        sys.stdout.write(err)
    sys.stdout.flush()
    return completed.returncode, out, err


def no_gatt(code: int, out: str, err: str) -> bool:
    blob = out + "\n" + err
    return code != 0 or NO_GATT in blob or "ServicesNotResolved" in blob


def read_failed(out: str, err: str) -> bool:
    blob = out + "\n" + err
    return "Read failed" in blob or "Failed to read" in blob


def addresses(chunks: list[str]) -> list[str]:
    found: set[str] = set()
    ordered: list[str] = []
    for text in chunks:
        for match in MAC.findall(text):
            mac = match.upper()
            if mac == CONTROLLER or mac in found:
                continue
            found.add(mac)
            ordered.append(mac)
    return ordered


def disconnect(addr: str) -> None:
    """Drop the LE session gatt-enum left open so SDP can use the BR/EDR channel."""
    completed = subprocess.run(
        SSH[:-1] + ["bluetoothctl", "disconnect", addr],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    out = completed.stdout.decode("utf-8", "replace")
    err = completed.stderr.decode("utf-8", "replace")
    if ADAPTER in out or ADAPTER in err:
        print("[CRON_FAILURE]")
        print(ADAPTER)
        raise SystemExit(1)
    print("$ bluetoothctl disconnect " + addr)
    if out and not out.endswith("\n"):
        out += "\n"
    sys.stdout.write(out)
    if err.strip():
        if not err.endswith("\n"):
            err += "\n"
        sys.stdout.write(err)
    sys.stdout.flush()


BR = "br-connection-"


def enumerate_address(addr: str, classic: bool) -> None:
    code, out, err = run(["gatt-enum", addr])
    blob = out + "\n" + err
    if no_gatt(code, out, err):
        code, out, err = run(["gatt-enum", "--correlate", addr])
        blob += "\n" + out + "\n" + err
        if no_gatt(code, out, err):
            if classic or BR in blob:
                disconnect(addr)
                run(
                    [
                        "classic-enum",
                        "--connectionless",
                        "--analyze",
                        "--sdp-source",
                        "merge",
                        addr,
                    ]
                )
        elif read_failed(out, err):
            run(["gatt-enum", "--deep", addr])
    elif read_failed(out, err):
        run(["gatt-enum", "--deep", addr])


def list_database() -> None:
    offset = 0
    while offset <= 10000:
        _, out, _ = run(
            [
                "db",
                "list",
                "--fields",
                FIELDS,
                "--limit",
                "100",
                "--offset",
                str(offset),
            ]
        )
        if len(MAC.findall(out)) < 100:
            return
        offset += 100


def main() -> None:
    le_chunks: list[str] = []
    for args in (
        ["scan", "--timeout", "15", "--variant", "passive"],
        ["scan", "--timeout", "15", "--variant", "naggy"],
    ):
        _, out, err = run(args)
        le_chunks.append(out + "\n" + err)
    _, out, err = run(["classic-scan", "--timeout", "10"])
    classic_text = out + "\n" + err
    le_addrs = addresses(le_chunks)
    classic_addrs = addresses([classic_text])
    if not le_addrs and not classic_addrs:
        for args in (
            ["scan", "--timeout", "15", "--variant", "pokey"],
            ["scan", "--timeout", "15", "--variant", "brute"],
        ):
            _, out, err = run(args)
            le_chunks.append(out + "\n" + err)
        le_addrs = addresses(le_chunks)
    classic_set = set(classic_addrs)
    ordered: list[str] = []
    seen: set[str] = set()
    for addr in le_addrs + classic_addrs:
        if addr not in seen:
            seen.add(addr)
            ordered.append(addr)
    for addr in ordered:
        enumerate_address(addr, addr in classic_set)
    list_database()


if __name__ == "__main__":
    main()
