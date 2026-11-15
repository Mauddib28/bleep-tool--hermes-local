#!/usr/bin/env python3
"""Make the two BLEEP cron jobs match this repo. Other jobs are not edited.

Runs inside hermes-agent as uid 10000 with HOME=/opt/data. A job whose state
is running is left alone. Exit 2 when a running job does not match.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

JOBS_PATH = Path("/opt/data/cron/jobs.json")
WANTED = (
    {
        "name": "BLEEP scan and enumerate",
        "schedule": "5,35 * * * *",
        "script": "bleep-scan.py",
        "prompt": (
            "Use the bleep skill. The scheduled scan runs bleep-scan.py and "
            "stores that stdout. Do not pass --out."
        ),
    },
    {
        "name": "BLEEP database report",
        "schedule": "50 2,6,10,14,18,22 * * *",
        "script": "bleep-db-report.py",
        "prompt": (
            "Use the bleep skill. The scheduled report runs bleep-db-report.py "
            "and stores that stdout. Do not pass --out."
        ),
    },
)

# Created only when the name is absent. An existing job is not edited.
RESEARCH = (
    {
        "name": "Daily Bluetooth Tooling Examinations",
        "schedule": "0 9 * * * *",
        "skills": [],
        "prompt": """Please review known Bluetooth tooling, code repositories, and Bluetooth news to provide a summary of new capabilities, functionality, growth in Bluetooth, and any associated news or illuminating information.

Known Bluetooth Tools:
- https://github.com/Mauddib28/bleep-tool
- https://github.com/colonelpanichacks/oui-spy
- https://github.com/pschatzmann/ESP32-A2DP
- https://github.com/BLESPloit/device-library
- https://github.com/BLESPloit/esp32-firmware
- https://github.com/HubbleNetwork/hubble-device-sdk
- https://github.com/lukasjapan/bt-speaker
- http://github.com/dannymcc/bluehood
- https://github.com/HackingDave/btrpa-scan
- https://github.com/TarlogicSecurity/BlueSpy
- https://github.com/pythops/bluetui
- https://github.com/bluekitchen/btstack
- https://github.com/Mauddib28/Raspi--Bluetooth
- https://github.com/Matheus-Garbelini/sweyntooth_bluetooth_low_energy_attacks
""",
    },
    {
        "name": "Update Bluetooth Findings",
        "schedule": "0 10 * * * * *",
        "skills": [],
        "prompt": (
            "Take the existing Bluetooth findings that get updated and written "
            "by another cron job and add the following:\n"
            "- https://github.com/colonelpanichacks/oui-spy-unified-blue\n"
        ),
    },
    {
        "name": "Review and Update",
        "schedule": "every 43200m",
        "skills": [
            "bleep",
            "Bluetooth Analysis & Research",
            "bluetooth-analysis-research",
        ],
        "prompt": (
            "Use the BLEEP skill to examine the current version and capabilities "
            "of BLEEP as well as attempt and update of the toolset.\n"
        ),
    },
)


def load_jobs() -> list[dict]:
    if not JOBS_PATH.is_file():
        return []
    payload = json.loads(JOBS_PATH.read_text(encoding="utf-8"))
    jobs = payload.get("jobs", [])
    if not isinstance(jobs, list):
        raise SystemExit("jobs.json has no jobs list")
    return [job for job in jobs if isinstance(job, dict)]


def hermes(*args: str) -> None:
    completed = subprocess.run(["hermes", "cron", *args], check=False)
    if completed.returncode != 0:
        raise SystemExit(f"hermes cron {' '.join(args)} exited {completed.returncode}")


def ensure(spec: dict, jobs: list[dict]) -> int:
    matches = [job for job in jobs if job.get("script") == spec["script"]]
    if len(matches) > 1:
        print(f"multiple jobs use {spec['script']}; leaving the extras")
    job = matches[0] if matches else None
    if job is None:
        hermes(
            "create",
            spec["schedule"],
            spec["prompt"],
            "--name",
            spec["name"],
            "--deliver",
            "local",
            "--script",
            spec["script"],
            "--no-agent",
            "--skill",
            "bleep",
        )
        print(f"created {spec['name']}")
        return 0
    expr = (job.get("schedule") or {}).get("expr")
    skills = job.get("skills") or []
    edits: list[str] = []
    if expr != spec["schedule"]:
        edits += ["--schedule", spec["schedule"]]
    if job.get("script") != spec["script"]:
        edits += ["--script", spec["script"]]
    if job.get("no_agent") is not True:
        edits += ["--no-agent"]
    if job.get("deliver") != "local":
        edits += ["--deliver", "local"]
    if "bleep" not in skills:
        edits += ["--add-skill", "bleep"]
    if not edits:
        print(f"unchanged {job.get('id')} {spec['script']}")
        return 0
    if job.get("state") == "running":
        print(f"{job.get('id')} is running; not editing {spec['script']}")
        return 2
    hermes("edit", str(job["id"]), *edits)
    print(f"edited {job.get('id')} {spec['script']}")
    return 0


def ensure_research(spec: dict, jobs: list[dict]) -> int:
    matches = [job for job in jobs if job.get("name") == spec["name"]]
    if matches:
        print(f"unchanged {matches[0].get('id')} {spec['name']}")
        return 0
    args = [
        "create",
        spec["schedule"],
        spec["prompt"],
        "--name",
        spec["name"],
        "--deliver",
        "local",
    ]
    for skill in spec["skills"]:
        args += ["--skill", skill]
    hermes(*args)
    print(f"created {spec['name']}")
    return 0


def main() -> int:
    for spec in WANTED:
        path = Path("/opt/data/scripts") / spec["script"]
        if not path.is_file():
            raise SystemExit(f"missing {path}")
    code = 0
    jobs = load_jobs()
    for spec in WANTED:
        code = max(code, ensure(spec, jobs))
        jobs = load_jobs()
    for spec in RESEARCH:
        code = max(code, ensure_research(spec, jobs))
        jobs = load_jobs()
    return code


if __name__ == "__main__":
    raise SystemExit(main())
