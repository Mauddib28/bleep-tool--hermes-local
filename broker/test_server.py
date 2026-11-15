#!/usr/bin/env python3
"""Broker unit tests. No Hermes process and no API key."""

from __future__ import annotations

import json
import threading
import unittest
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from server import Broker, HermesClient, make_handler


class FakeHermes(BaseHTTPRequestHandler):
    events = b""
    approvals: list[str] = []
    stops = 0
    status = {"status": "completed", "output": "pong"}

    def log_message(self, fmt: str, *args: object) -> None:
        return

    def _send(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length) if length else b"{}"
        if self.path == "/v1/runs":
            self._send(200, {"run_id": "run_test"})
            return
        if self.path.endswith("/approval"):
            FakeHermes.approvals.append(json.loads(raw.decode()).get("choice", ""))
            self._send(200, {"ok": True})
            return
        if self.path.endswith("/stop"):
            FakeHermes.stops += 1
            self._send(200, {"ok": True})
            return
        self._send(404, {})

    def do_GET(self) -> None:  # noqa: N802
        if self.path.endswith("/events"):
            body = FakeHermes.events
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path.startswith("/v1/runs/"):
            self._send(200, FakeHermes.status)
            return
        self._send(404, {})


def start_fake() -> tuple[ThreadingHTTPServer, int]:
    server = ThreadingHTTPServer(("127.0.0.1", 0), FakeHermes)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, server.server_address[1]


class HermesClientTests(unittest.TestCase):
    def test_completed_run_returns_output(self) -> None:
        FakeHermes.events = b": keepalive\n\n"
        FakeHermes.approvals = []
        FakeHermes.stops = 0
        FakeHermes.status = {"status": "completed", "output": "pong"}
        server, port = start_fake()
        try:
            result = HermesClient(f"http://127.0.0.1:{port}", "k" * 32, "broker-executor", 5).run("ping")
        finally:
            server.shutdown()
        self.assertEqual(result["run_id"], "run_test")
        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["output"], "pong")
        self.assertEqual(FakeHermes.approvals, [])

    def test_approval_request_is_denied_and_stopped(self) -> None:
        payload = json.dumps({"event": "approval.request", "command": "rm -rf /"})
        FakeHermes.events = f"data: {payload}\n\n".encode()
        FakeHermes.approvals = []
        FakeHermes.stops = 0
        server, port = start_fake()
        try:
            result = HermesClient(f"http://127.0.0.1:{port}", "k" * 32, "broker-executor", 5).run("danger")
        finally:
            server.shutdown()
        self.assertEqual(result["status"], "failure")
        self.assertIn("rm -rf /", result["summary"])
        self.assertEqual(FakeHermes.approvals, ["deny"])
        self.assertEqual(FakeHermes.stops, 1)


class BrokerHttpTests(unittest.TestCase):
    def setUp(self) -> None:
        self.calls: list[str] = []

        class Client:
            def run(self, text: str) -> dict:
                self_outer.calls.append(text)
                if text == "boom":
                    raise ApprovalDenied("nope")
                return {"run_id": "run_ok", "status": "completed", "output": text}

        self_outer = self
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(Broker(Client())))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_address[1]

    def tearDown(self) -> None:
        self.server.shutdown()

    def _json(self, method: str, path: str, payload: dict | None = None) -> tuple[int, dict]:
        data = None if payload is None else json.dumps(payload).encode()
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.port}{path}", data=data, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=3) as response:
                return response.status, json.loads(response.read().decode())
        except urllib.error.HTTPError as exc:
            return exc.code, json.loads(exc.read().decode())

    def test_health_and_objective(self) -> None:
        status, body = self._json("GET", "/health")
        self.assertEqual(status, 200)
        self.assertEqual(body["ok"], True)
        status, body = self._json("POST", "/objectives", {"input": "ping"})
        self.assertEqual(status, 200)
        self.assertEqual(body["output"], "ping")
        self.assertEqual(self.calls, ["ping"])

    def test_missing_input_is_400(self) -> None:
        status, body = self._json("POST", "/objectives", {})
        self.assertEqual(status, 400)
        self.assertIn("input", body["error"])


if __name__ == "__main__":
    unittest.main()
