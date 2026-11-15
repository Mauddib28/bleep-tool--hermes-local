#!/usr/bin/env python3
"""Create host state for Hermes, the broker, and OpenClaw. Secrets stay under /hosthermes."""

from __future__ import annotations

import os
import shutil
import stat
from pathlib import Path

HOST = Path(os.environ.get("HOST_HERMES", "/hosthermes"))
SEED = Path(os.environ.get("SEED_DIR", "/seed"))
HERMES_UID = 10000
HERMES_GID = 10000
OPENCLAW_UID = 1000
OPENCLAW_GID = 1000

API_KEYS = {
    "API_SERVER_ENABLED": "true",
    "API_SERVER_HOST": "0.0.0.0",
    "API_SERVER_PORT": "8642",
}


def secret(path: Path) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and path.stat().st_size > 0:
        value = path.read_text(encoding="utf-8").strip()
    else:
        value = os.urandom(32).hex()
        path.write_text(value + "\n", encoding="utf-8")
    os.chown(path.parent, HERMES_UID, HERMES_GID)
    os.chmod(path.parent, 0o700)
    os.chown(path, HERMES_UID, HERMES_GID)
    os.chmod(path, 0o600)
    return value


def upsert_env(path: Path, updates: dict[str, str]) -> None:
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    seen: set[str] = set()
    out: list[str] = []
    for line in lines:
        if not line or line.startswith("#") or "=" not in line:
            out.append(line)
            continue
        key = line.split("=", 1)[0]
        if key in updates:
            out.append(f"{key}={updates[key]}")
            seen.add(key)
        else:
            out.append(line)
    for key, value in updates.items():
        if key not in seen:
            out.append(f"{key}={value}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(out) + "\n", encoding="utf-8")
    os.chown(path, HERMES_UID, HERMES_GID)
    os.chmod(path, 0o600)


def seed_openclaw(token: str) -> None:
    root = HOST / "openclaw"
    config = root / "openclaw.json"
    skill_dest = root / "workspace" / "skills" / "direct-hermes" / "SKILL.md"
    skill_src = SEED / "skills" / "direct-hermes" / "SKILL.md"
    root.mkdir(parents=True, exist_ok=True)
    if not config.exists():
        template = (SEED / "openclaw.json.template").read_text(encoding="utf-8")
        config.write_text(template.replace("__GATEWAY_TOKEN__", token), encoding="utf-8")
    skill_dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(skill_src, skill_dest)
    for directory in (root, root / "workspace", skill_dest.parent):
        os.chown(directory, OPENCLAW_UID, OPENCLAW_GID)
        os.chmod(directory, 0o700)
    os.chown(config, OPENCLAW_UID, OPENCLAW_GID)
    os.chmod(config, 0o600)
    if skill_dest.exists():
        os.chown(skill_dest, OPENCLAW_UID, OPENCLAW_GID)
        os.chmod(skill_dest, 0o600)


def ensure_dashboard_login() -> None:
    """Give the browser a username/password form. The password stays in keys/."""
    password = secret(HOST / "keys" / "dashboard.password")
    config_path = HOST / "ollama-stack" / "config.yaml"
    if not config_path.is_file():
        print("dashboard login skipped: config.yaml is absent")
        return
    import sys

    sys.path.insert(0, "/opt/hermes")
    from plugins.dashboard_auth.basic import hash_password
    from ruamel.yaml import YAML

    yaml = YAML()
    yaml.preserve_quotes = True
    config = yaml.load(config_path.read_text(encoding="utf-8")) or {}
    dashboard = config.get("dashboard")
    if not isinstance(dashboard, dict):
        dashboard = {}
        config["dashboard"] = dashboard
    basic = dashboard.get("basic_auth")
    if not isinstance(basic, dict):
        basic = {}
        dashboard["basic_auth"] = basic
    changed = False
    if not str(basic.get("username") or "").strip():
        basic["username"] = "admin"
        changed = True
    if not str(basic.get("password_hash") or "").strip():
        basic["password_hash"] = hash_password(password)
        basic["password"] = ""
        changed = True
    if len(str(basic.get("secret") or "").strip()) < 16:
        basic["secret"] = os.urandom(32).hex()
        changed = True
    try:
        from hermes_cli.plugins_cmd import ensure_basic_auth_plugin_enabled_in_config

        if ensure_basic_auth_plugin_enabled_in_config(config):
            changed = True
    except Exception:
        plugins = config.get("plugins")
        if isinstance(plugins, dict) and isinstance(plugins.get("disabled"), list):
            kept = [item for item in plugins["disabled"] if item != "basic"]
            if kept != list(plugins["disabled"]):
                plugins["disabled"] = kept
                changed = True
    if not changed:
        print("dashboard login already configured")
        return
    with config_path.open("w", encoding="utf-8") as handle:
        yaml.dump(config, handle)
    os.chown(config_path, HERMES_UID, HERMES_GID)
    os.chmod(config_path, 0o640)
    print("dashboard login configured")


def main() -> None:
    api_key = secret(HOST / "keys" / "api_server.key")
    secret(HOST / "keys" / "dashboard.token")
    ensure_dashboard_login()
    gateway_token = secret(HOST / "keys" / "openclaw-gateway.token")
    updates = dict(API_KEYS)
    updates["API_SERVER_KEY"] = api_key
    upsert_env(HOST / "ollama-stack" / ".env", updates)
    seed_openclaw(gateway_token)
    # Touch a mode check so a world-readable key cannot pass quietly.
    key_mode = stat.S_IMODE((HOST / "keys" / "api_server.key").stat().st_mode)
    if key_mode != 0o600:
        raise SystemExit(f"api key mode is {key_mode:o}, expected 600")
    print("state ready")


if __name__ == "__main__":
    main()
