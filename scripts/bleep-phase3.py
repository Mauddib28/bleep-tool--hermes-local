#!/usr/bin/env python3
"""One Hermes API turn: bleep --version over SSH, then two skill_manage patches.

The script snapshots the live skill, posts the turn to the Hermes API inside
this container, and restores the snapshot unless the diff is exactly those two
patches. It does not print API_SERVER_KEY. Session key is bleep-phase3.
"""

from __future__ import annotations

import difflib
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ENV = Path("/opt/data/.env")
LIVE = Path("/opt/data/skills/bluetooth/bleep/SKILL.md")
SNAPSHOT = Path("/tmp/bleep-skill-1.3.0.md")
SKILLS = Path("/opt/data/skills")
PENDING = Path("/opt/data/pending/skills")
SESSION = "bleep-phase3"
OWNER = 10000

OLD_VERSION = "version: 1.3.0"
NEW_VERSION = "version: 1.3.1"
OLD_SENTENCE = (
    "If a command prints `Bluetooth adapter not found or not ready`, "
    "quote that line and stop. Do not fill the report from an earlier run."
)
NEW_SENTENCE = (
    "If a command prints `Bluetooth adapter not found or not ready`, "
    "the first line of the response is exactly [CRON_FAILURE], then quote "
    "that line and stop. Do not fill the report from an earlier run. "
    "Do not invent an n/10 risk score. Do not describe a device as paired."
)
PROMPT = (
    "Use the bluetooth/bleep skill. Do two things and then stop.\n"
    "\n"
    "1. Run one SSH command, the skill's SSH command, with the remote command "
    "`bleep --version`. Quote that output. Do not scan, connect, enumerate, "
    "or write the observation database.\n"
    "\n"
    "2. Call skill_manage once. name is bluetooth/bleep. operations is exactly "
    "two patch operations, in this order. Do not pass content. Do not create, "
    "delete, or add a file. Make this one skill_manage call and then stop. "
    "Do not call skill_manage again if the first call returns success or an "
    "error. The old_string and new_string values below do not include the "
    "backtick characters that mark them. The second new_string ends at the "
    "period after the word paired.\n"
    "\n"
    "First patch: old_string is `version: 1.3.0` and new_string is "
    "`version: 1.3.1`.\n"
    "\n"
    "Second patch: old_string is `If a command prints `Bluetooth adapter not "
    "found or not ready`, quote that line and stop. Do not fill the report "
    "from an earlier run.` and new_string is `If a command prints `Bluetooth "
    "adapter not found or not ready`, the first line of the response is "
    "exactly [CRON_FAILURE], then quote that line and stop. Do not fill the "
    "report from an earlier run. Do not invent an n/10 risk score. Do not "
    "describe a device as paired.`\n"
    "\n"
    "Do not change the allow list or the not-allowed list. Do not pair, write "
    "characteristics, change the adapter, transfer files, intercept audio, or "
    "run bleep ctf.\n"
)
FORBIDDEN = (
    "gatt-enum",
    "classic-enum",
    "classic-scan",
    "bleep scan",
    "db report",
    "db list",
    "enum-scan",
)
ALLOWED_TOOLS = {"terminal", "skill_manage", "skill_view"}


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
            "X-Hermes-Session-Key": SESSION,
        },
        method=method,
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        raw = response.read().decode("utf-8")
    return json.loads(raw) if raw else {}


def collapse_command(command: str) -> str:
    lines = [line.strip().rstrip("\\").strip() for line in command.splitlines()]
    return " ".join(" ".join(lines).split())


def _blocked(command: str) -> bool:
    return any(token in command for token in ("|", ";", "&&", "||", "`", "$(", "/home/bleep", ">", "<"))


def version_ssh_ok(command: str) -> bool:
    """True when the command is the skill SSH prefix and `bleep --version`."""
    if _blocked(command):
        return False
    collapsed = collapse_command(command)
    required = (
        "ssh ",
        "-i /run/secrets/bleep_ed25519",
        "BatchMode=yes",
        "IdentitiesOnly=yes",
        "StrictHostKeyChecking=accept-new",
        "UserKnownHostsFile=/opt/data/ssh/known_hosts",
        "bleep@bleep",
    )
    if not all(part in collapsed for part in required):
        return False
    if collapsed.count("bleep@bleep") != 1:
        return False
    remote = collapsed.split("bleep@bleep", 1)[1].strip()
    if not remote.startswith("--"):
        return False
    remote = remote[2:].strip().strip("'\"")
    return remote == "bleep --version"


def preview_is_version_ssh(preview: str) -> bool:
    """Accept a 200-character tool preview that is cut off before the remote command."""
    if _blocked(preview) or any(token in preview for token in FORBIDDEN):
        return False
    collapsed = collapse_command(preview)
    required = ("ssh ", "-i /run/secrets/bleep_ed25519", "BatchMode=yes", "bleep@bleep")
    if not all(part in collapsed for part in required):
        return False
    if "bleep --version" in collapsed:
        return version_ssh_ok(preview)
    remote = collapsed.split("bleep@bleep", 1)[1].strip()
    if remote.startswith("--"):
        remote = remote[2:].strip().strip("'\"")
    return remote in {"", "bleep"}


def expected_text(snapshot: str) -> str:
    if snapshot.count(OLD_VERSION) != 1 or snapshot.count(OLD_SENTENCE) != 1:
        raise ValueError("snapshot does not contain the two patch targets once each")
    if "n/10" in snapshot or "[CRON_FAILURE]" in snapshot:
        raise ValueError("snapshot already contains the phase 3 sentences")
    text = snapshot.replace(OLD_VERSION, NEW_VERSION, 1)
    return text.replace(OLD_SENTENCE, NEW_SENTENCE, 1)


def skill_paths() -> set[str]:
    if not SKILLS.exists():
        return set()
    return {str(path.relative_to(SKILLS)) for path in SKILLS.rglob("SKILL.md")}


def pending_names() -> set[str]:
    if not PENDING.exists():
        return set()
    return {path.name for path in PENDING.glob("*.json")}


def unified(before: str, after: str) -> str:
    diff = difflib.unified_diff(
        before.splitlines(keepends=True),
        after.splitlines(keepends=True),
        fromfile="snapshot",
        tofile="live",
    )
    return "".join(diff)


def restore(snapshot: str) -> None:
    LIVE.write_text(snapshot, encoding="utf-8")
    os.chmod(LIVE, 0o644)


def section(text: str, heading: str, following: str) -> str:
    start = text.index(heading)
    end = text.index(following, start)
    return text[start:end]


def live_failures(snapshot: str, events: list[dict], output: str, status: str, denied: bool) -> list[str]:
    reasons: list[str] = []
    live = LIVE.read_text(encoding="utf-8")
    try:
        want = expected_text(snapshot)
    except ValueError as exc:
        return [str(exc)]
    if live != want:
        reasons.append("live skill is not the two-patch text")
    if section(live, "## Allowed commands", "## Not allowed") != section(snapshot, "## Allowed commands", "## Not allowed"):
        reasons.append("allow list changed")
    if section(live, "## Not allowed", "`BLEEP_DB_PATH`") != section(snapshot, "## Not allowed", "`BLEEP_DB_PATH`"):
        reasons.append("not-allowed list changed")
    for needle in ("enum-scan --variant brute", "--write-char", "bleep ctf"):
        if needle not in section(live, "## Not allowed", "`BLEEP_DB_PATH`"):
            reasons.append(f"missing not-allowed line: {needle}")
    if LIVE.stat().st_uid != OWNER:
        reasons.append(f"owner is {LIVE.stat().st_uid}")
    if status != "completed":
        reasons.append(f"status is {status}")
    if "BLEEP 3.1.0 (DB schema v20)" not in output:
        reasons.append("output is missing the version line")
    if denied:
        reasons.append("an approval.request was denied")
    started = [event for event in events if event.get("event") == "tool.started"]
    names = [str(event.get("tool") or "") for event in started]
    if names.count("terminal") != 1:
        reasons.append(f"terminal calls: {names.count('terminal')}")
    if names.count("skill_manage") < 1:
        reasons.append("skill_manage was not called")
    unknown = sorted({name for name in names if name not in ALLOWED_TOOLS})
    if unknown:
        reasons.append("unexpected tools: " + ",".join(unknown))
    terminals = [event for event in started if event.get("tool") == "terminal"]
    if terminals and not preview_is_version_ssh(str(terminals[0].get("preview") or "")):
        reasons.append("terminal preview is not the version SSH")
    completed = [event for event in events if event.get("event") == "tool.completed" and event.get("tool") == "terminal"]
    if completed and any(token in str(completed[0].get("preview") or "") for token in FORBIDDEN):
        reasons.append("terminal result contains a forbidden command")
    for event in events:
        if event.get("tool") == "skill_manage":
            preview = str(event.get("preview") or "")
            if any(token in preview for token in FORBIDDEN):
                reasons.append("skill_manage preview contains a forbidden command")
                break
        if event.get("event") == "tool.completed" and event.get("error") and event.get("tool") == "terminal":
            reasons.append("terminal completed with an error")
    return reasons


def approve(key: str, run_id: str, command: str) -> bool:
    """Return True when the command was allowed. A mismatch denies and stops the run."""
    if version_ssh_ok(command):
        request("POST", f"/v1/runs/{run_id}/approval", key, {"choice": "once"}, timeout=10)
        print("APPROVAL_ONCE")
        return True
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
    return False


def preflight(text: str) -> None:
    if "write_approval" in Path("/opt/data/config.yaml").read_text(encoding="utf-8"):
        raise SystemExit("skills.write_approval is set; phase 3 leaves the gate off")
    if OLD_VERSION not in text or text.count(OLD_VERSION) != 1:
        raise SystemExit("live skill is not version 1.3.0")
    if OLD_SENTENCE not in text:
        raise SystemExit("live skill is missing the adapter sentence")
    if "n/10" in text or "[CRON_FAILURE]" in text:
        raise SystemExit("live skill already contains the phase 3 sentences")


def self_test() -> None:
    good = (
        "ssh -i /run/secrets/bleep_ed25519 \\\n"
        "  -o BatchMode=yes \\\n"
        "  -o IdentitiesOnly=yes \\\n"
        "  -o StrictHostKeyChecking=accept-new \\\n"
        "  -o UserKnownHostsFile=/opt/data/ssh/known_hosts \\\n"
        "  bleep@bleep -- bleep --version"
    )
    assert version_ssh_ok(good), good
    assert preview_is_version_ssh(good)
    assert version_ssh_ok(collapse_command(good))
    assert not version_ssh_ok(good + " | cat")
    assert not version_ssh_ok(good.replace("bleep --version", "bleep scan --timeout 15 --variant passive"))
    assert not version_ssh_ok(good + " && touch /home/bleep/x")
    truncated = "ssh -i /run/secrets/bleep_ed25519 -o BatchMode=yes bleep@bleep --"
    assert preview_is_version_ssh(truncated)
    assert not preview_is_version_ssh(truncated + " bleep scan --timeout 15")
    sample = f"---\n{OLD_VERSION}\n---\n\n{OLD_SENTENCE}\n\n## Allowed commands\n- scan\n\n## Not allowed\nno\n\n`BLEEP_DB_PATH`\n"
    patched = expected_text(sample)
    assert NEW_VERSION in patched and OLD_VERSION not in patched
    assert "[CRON_FAILURE]" in patched and "n/10" in patched
    assert section(patched, "## Allowed commands", "## Not allowed") == section(sample, "## Allowed commands", "## Not allowed")
    print("self-test ok")


def main() -> None:
    if "--self-test" in sys.argv:
        self_test()
        return
    snapshot = LIVE.read_text(encoding="utf-8")
    preflight(snapshot)
    SNAPSHOT.write_text(snapshot, encoding="utf-8")
    digest = hashlib.sha256(snapshot.encode("utf-8")).hexdigest()
    print(f"snapshot_sha256={digest}")
    before_skills = skill_paths()
    before_pending = pending_names()
    key = api_key()
    events: list[dict] = []
    denied = False
    try:
        started = request("POST", "/v1/runs", key, {"input": PROMPT}, timeout=30)
        run_id = str(started.get("run_id") or "")
        if not run_id:
            raise SystemExit(f"no run_id: {started}")
        print(f"run_id={run_id}")
        req = urllib.request.Request(
            f"http://127.0.0.1:8642/v1/runs/{run_id}/events",
            headers={
                "Authorization": "Bearer " + key,
                "X-Hermes-Session-Key": SESSION,
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
                if not isinstance(event, dict):
                    continue
                events.append(event)
                if event.get("event") == "tool.started":
                    print(f"tool.started {event.get('tool')}")
                if event.get("event") == "approval.request":
                    if not approve(key, run_id, str(event.get("command") or "")):
                        denied = True
                        break
        finally:
            response.close()
        final = request("GET", f"/v1/runs/{run_id}", key, timeout=30)
    except BaseException:
        print(unified(snapshot, LIVE.read_text(encoding="utf-8")))
        restore(snapshot)
        print("restored")
        raise
    output = final.get("output")
    if output is None:
        output = final.get("text") or ""
    status = str(final.get("status") or "")
    print(f"status={status}")
    print(output)
    live = LIVE.read_text(encoding="utf-8")
    print(unified(snapshot, live))
    try:
        reasons = live_failures(snapshot, events, str(output), status, denied)
    except Exception as exc:
        print(unified(snapshot, live))
        restore(snapshot)
        print("restored")
        raise SystemExit(1) from exc
    if skill_paths() != before_skills:
        reasons.append("skill directory set changed")
    if pending_names() != before_pending:
        reasons.append("pending/skills changed")
    if reasons:
        print("FAIL")
        for reason in reasons:
            print(reason)
        restore(snapshot)
        print("restored")
        raise SystemExit(1)
    if hashlib.sha256(LIVE.read_bytes()).hexdigest() == digest:
        print("FAIL")
        print("live file is unchanged")
        raise SystemExit(1)
    print("PASS")
    print(f"tools={','.join(str(event.get('tool')) for event in events if event.get('event') == 'tool.started')}")


if __name__ == "__main__":
    main()
