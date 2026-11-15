#!/usr/bin/env python3
"""Network-local broker. POST /objectives starts a Hermes /v1/runs task.

The Hermes API key stays in this process. Callers on hermes-net do not
receive it. Flagged command approvals are denied and the run is stopped.
"""

from __future__ import annotations

import json
import os
import socket
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class ApprovalDenied(Exception):
    def __init__(self, command: str) -> None:
        self.command = command
        super().__init__(command)


class HermesClient:
    def __init__(self, base_url: str, api_key: str, session_key: str, timeout_s: float) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.session_key = session_key
        self.timeout_s = timeout_s

    def _headers(self) -> dict[str, str]:
        headers = {"Content-Type": "application/json", "Authorization": "Bearer " + self.api_key}
        if self.session_key:
            headers["X-Hermes-Session-Key"] = self.session_key
        return headers

    def _request(self, method: str, path: str, body: dict | None = None, timeout: float = 30) -> dict:
        data = None if body is None else json.dumps(body).encode("utf-8")
        request = urllib.request.Request(
            self.base_url + path, data=data, headers=self._headers(), method=method
        )
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read().decode("utf-8")
        return json.loads(raw) if raw else {}

    def run(self, text: str) -> dict:
        started = self._request("POST", "/v1/runs", {"input": text}, timeout=30)
        run_id = started.get("run_id")
        if not run_id:
            raise RuntimeError("hermes did not return a run_id")
        try:
            final = self._consume(str(run_id))
        except ApprovalDenied as denied:
            return {
                "run_id": run_id,
                "status": "failure",
                "output": "",
                "summary": "denied: " + denied.command,
            }
        status = str(final.get("status") or "")
        output = final.get("output")
        if output is None:
            output = final.get("text") or ""
        return {"run_id": run_id, "status": status, "output": output}

    def _consume(self, run_id: str) -> dict:
        deadline = time.time() + self.timeout_s
        request = urllib.request.Request(
            self.base_url + f"/v1/runs/{run_id}/events",
            headers=self._headers(),
            method="GET",
        )
        try:
            response = urllib.request.urlopen(request, timeout=self.timeout_s)
        except urllib.error.HTTPError:
            return self._poll(run_id, deadline)
        try:
            while True:
                if time.time() > deadline:
                    self._stop(run_id)
                    raise TimeoutError(f"hermes run {run_id} timed out")
                try:
                    raw = response.readline()
                except socket.timeout:
                    continue
                if not raw:
                    break
                line = raw.decode("utf-8", "replace").rstrip("\r\n")
                if not line or line.startswith(":"):
                    continue
                if line.startswith("data:"):
                    self._dispatch(run_id, line[5:].strip())
        finally:
            response.close()
        return self._request("GET", f"/v1/runs/{run_id}", timeout=30)

    def _poll(self, run_id: str, deadline: float) -> dict:
        while time.time() < deadline:
            current = self._request("GET", f"/v1/runs/{run_id}", timeout=15)
            state = str(current.get("status") or "").lower()
            if state == "waiting_for_approval":
                self._resolve(run_id, approved=False)
                self._stop(run_id)
                raise ApprovalDenied("(command not available via polling)")
            if state in {"completed", "failed", "error", "cancelled", "stopped"}:
                return current
            time.sleep(1)
        self._stop(run_id)
        raise TimeoutError(f"hermes run {run_id} timed out")

    def _dispatch(self, run_id: str, data: str) -> None:
        try:
            event = json.loads(data)
        except json.JSONDecodeError:
            return
        if not isinstance(event, dict) or event.get("event") != "approval.request":
            return
        command = str(event.get("command") or "")
        self._resolve(run_id, approved=False)
        self._stop(run_id)
        raise ApprovalDenied(command)

    def _resolve(self, run_id: str, approved: bool) -> None:
        choice = "once" if approved else "deny"
        try:
            self._request("POST", f"/v1/runs/{run_id}/approval", {"choice": choice}, timeout=10)
        except urllib.error.HTTPError as exc:
            if exc.code != 409:
                raise

    def _stop(self, run_id: str) -> None:
        try:
            self._request("POST", f"/v1/runs/{run_id}/stop", {}, timeout=10)
        except Exception:
            return


def load_key(path: str) -> str:
    with open(path, encoding="utf-8") as handle:
        key = handle.read().strip()
    if len(key) < 32:
        raise SystemExit("Hermes API key file is missing or shorter than 32 characters")
    return key


class Broker:
    def __init__(self, client: HermesClient) -> None:
        self.client = client
        self._slot = threading.Lock()

    def health(self) -> tuple[int, dict]:
        return 200, {"ok": True}

    def objective(self, payload: dict) -> tuple[int, dict]:
        text = payload.get("input")
        if not isinstance(text, str) or not text.strip():
            return 400, {"error": "input is required"}
        if not self._slot.acquire(blocking=False):
            return 429, {"error": "a delegated run is already in progress"}
        try:
            return 200, self.client.run(text.strip())
        except Exception as exc:
            return 502, {"status": "failure", "error": type(exc).__name__}
        finally:
            self._slot.release()


def make_handler(broker: Broker) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt: str, *args: object) -> None:
            return

        def _send(self, status: int, payload: dict) -> None:
            body = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:  # noqa: N802
            path = self.path.split("?", 1)[0]
            if path != "/health":
                self._send(404, {"error": "not found"})
                return
            status, payload = broker.health()
            self._send(status, payload)

        def do_POST(self) -> None:  # noqa: N802
            path = self.path.split("?", 1)[0]
            if path != "/objectives":
                self._send(404, {"error": "not found"})
                return
            length = int(self.headers.get("Content-Length", "0") or "0")
            raw = self.rfile.read(length) if length else b""
            try:
                payload = json.loads(raw.decode("utf-8") or "{}")
            except json.JSONDecodeError:
                self._send(400, {"error": "invalid json"})
                return
            if not isinstance(payload, dict):
                self._send(400, {"error": "json object required"})
                return
            status, body = broker.objective(payload)
            self._send(status, body)

    return Handler


def serve(broker: Broker, host: str, port: int) -> None:
    server = ThreadingHTTPServer((host, port), make_handler(broker))
    server.serve_forever()


def main() -> None:
    key = load_key(os.environ.get("HERMES_KEY_FILE", "/keys/hermes_api.key"))
    client = HermesClient(
        base_url=os.environ.get("HERMES_URL", "http://hermes-agent:8642"),
        api_key=key,
        session_key=os.environ.get("BROKER_SESSION_KEY", "broker-executor"),
        timeout_s=float(os.environ.get("HERMES_TIMEOUT_S", "180")),
    )
    host = os.environ.get("BROKER_HOST", "0.0.0.0")
    port = int(os.environ.get("BROKER_PORT", "8787"))
    serve(Broker(client), host, port)


if __name__ == "__main__":
    main()
