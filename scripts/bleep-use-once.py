#!/usr/bin/env python3
"""One Hermes API turn that must quote bleep --version. Denies approval requests."""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

ENV = Path("/opt/data/.env")
PROMPT = (
    "Use the bluetooth/bleep skill. Run only its version command over SSH. "
    "Reply with the exact bleep --version line and nothing else. Do not scan."
)


def api_key() -> str:
    for line in ENV.read_text(encoding="utf-8").splitlines():
        if line.startswith("API_SERVER_KEY="):
            return line.split("=", 1)[1].strip()
    raise SystemExit("API_SERVER_KEY is missing from /opt/data/.env")


def request(method: str, path: str, key: str, body: dict | None = None, timeout: float = 30) -> dict:
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        "http://127.0.0.1:8642" + path,
        data=data,
        headers={
            "Authorization": "Bearer " + key,
            "Content-Type": "application/json",
            "X-Hermes-Session-Key": "bleep-verify",
        },
        method=method,
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        raw = response.read().decode("utf-8")
    return json.loads(raw) if raw else {}


def deny(key: str, run_id: str, command: str) -> None:
    try:
        request("POST", f"/v1/runs/{run_id}/approval", key, {"choice": "deny"}, timeout=10)
    except urllib.error.HTTPError as exc:
        if exc.code != 409:
            print(f"approval deny returned {exc.code}", file=sys.stderr)
    try:
        request("POST", f"/v1/runs/{run_id}/stop", key, {}, timeout=10)
    except Exception:
        pass
    print("APPROVAL_REQUEST")
    print(command)
    raise SystemExit(2)


def main() -> None:
    key = api_key()
    started = request("POST", "/v1/runs", key, {"input": PROMPT}, timeout=30)
    run_id = str(started.get("run_id") or "")
    if not run_id:
        raise SystemExit(f"no run_id: {started}")
    print(f"run_id={run_id}")
    req = urllib.request.Request(
        f"http://127.0.0.1:8642/v1/runs/{run_id}/events",
        headers={
            "Authorization": "Bearer " + key,
            "X-Hermes-Session-Key": "bleep-verify",
        },
        method="GET",
    )
    try:
        response = urllib.request.urlopen(req, timeout=360)
    except urllib.error.HTTPError as exc:
        print(exc.read().decode("utf-8", "replace"), file=sys.stderr)
        raise SystemExit(1) from exc
    try:
        while True:
            raw = response.readline()
            if not raw:
                break
            line = raw.decode("utf-8", "replace").rstrip("\r\n")
            if not line.startswith("data:"):
                continue
            try:
                event = json.loads(line[5:].strip())
            except json.JSONDecodeError:
                continue
            if isinstance(event, dict) and event.get("event") == "approval.request":
                deny(key, run_id, str(event.get("command") or ""))
    finally:
        response.close()
    final = request("GET", f"/v1/runs/{run_id}", key, timeout=30)
    output = final.get("output")
    if output is None:
        output = final.get("text") or ""
    print(f"status={final.get('status')}")
    print(output)
    text = str(output)
    if "DB schema v" not in text or "BLEEP" not in text:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
