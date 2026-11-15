#!/usr/bin/env python3
"""Keep the Ollama model settings, and do not leave a config stamp newer than this binary."""

from __future__ import annotations

import json
import urllib.request
from pathlib import Path

from ruamel.yaml import YAML

CONFIG = Path("/opt/data/config.yaml")
WANTED = {
    "default": "qwen3.5:latest",
    "provider": "custom",
    "base_url": "http://ollama:11434/v1",
    "api_key": "ollama",
    "context_length": 65536,
    "ollama_num_ctx": 65536,
}


def main() -> None:
    yaml = YAML()
    yaml.preserve_quotes = True
    with CONFIG.open(encoding="utf-8") as handle:
        config = yaml.load(handle) or {}
    token = Path("/run/secrets/dashboard.token").read_text(encoding="utf-8").strip()
    request = urllib.request.Request(
        "http://127.0.0.1:9119/api/status",
        headers={"Authorization": "Bearer " + token},
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        status = json.load(response)
    changed = False
    latest = int(status["latest_config_version"])
    current = int(config.get("_config_version") or 0)
    if current > latest:
        config["_config_version"] = latest
        changed = True
    model = config.get("model")
    database = config.get("database")
    if not isinstance(database, dict):
        database = {}
        config["database"] = database
    if database.get("journal_mode") != "wal":
        database["journal_mode"] = "wal"
        changed = True
    if not isinstance(model, dict):
        model = {}
        config["model"] = model
    for key, value in WANTED.items():
        if model.get(key) != value:
            model[key] = value
            changed = True
    if changed:
        with CONFIG.open("w", encoding="utf-8") as handle:
            yaml.dump(config, handle)
        print(f"CHANGED current={current} latest={latest}")
    else:
        print(f"UNCHANGED current={current} latest={latest}")


if __name__ == "__main__":
    main()
