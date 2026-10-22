#!/usr/bin/env python3
"""Validate a resolved single-host Compose model; never prints secret values."""
import argparse
import json
import re
from pathlib import Path
import stat
import sys


def validate(model, secret_dir):
    errors = []
    if model.get("name") != "homelab-sre-prod":
        errors.append("deployment must use the isolated homelab-sre-prod project")
    required = {"demo-api", "prometheus", "alertmanager", "grafana", "blackbox-exporter", "alert-receiver"}
    services = model.get("services", {})
    if not required.issubset(services):
        errors.append("hardened services are missing")
    for name, service in services.items():
        if service.get("profiles") == ["linux-host"]:
            continue  # Declared optional exporter is NOT enabled by the deploy helper.
        if name not in required:
            errors.append("unexpected active service")
        if service.get("privileged") or service.get("network_mode") == "host" or service.get("pid") == "host" or service.get("cap_add") or service.get("devices"):
            errors.append("privilege additions, devices and host namespaces are forbidden")
        if "ALL" not in service.get("cap_drop", []):
            errors.append("all active services must drop capabilities")
        if not any(x in service.get("security_opt", []) for x in ("no-new-privileges:true", "no-new-privileges=true")):
            errors.append("no-new-privileges is required")
        if not service.get("mem_limit") or not service.get("cpus"):
            errors.append("resource ceilings are required")
        log = service.get("logging", {})
        if log.get("options", {}).get("max-size") != "10m" or log.get("options", {}).get("max-file") != "3":
            errors.append("bounded container logging is required")
        for port in service.get("ports", []):
            if port.get("host_ip") != "127.0.0.1":
                errors.append("all published ports must bind loopback")
        for volume in service.get("volumes", []):
            if "docker.sock" in str(volume.get("source", "")) or volume.get("source") == "/":
                errors.append("Docker socket and host-root mounts are forbidden")
    for name in ("demo-api", "alert-receiver"):
        if not re.fullmatch(r"homelab-sre-observability/demo-api:[0-9a-f]{40}", services.get(name, {}).get("image", "")):
            errors.append("application images must use the reviewed full commit tag")
        if services.get(name, {}).get("environment", {}).get("LAB_CONTROLS_ENABLED") != "false":
            errors.append("lab controls must be explicitly disabled")
    if services.get("alert-receiver", {}).get("ports"):
        errors.append("the authenticated receiver must not publish a host port")
    if services.get("alert-receiver", {}).get("environment", {}).get("ALERT_WEBHOOK_TOKEN_FILE") != "/run/secrets/receiver_token":
        errors.append("receiver must use a mounted token file")
    grafana = services.get("grafana", {}).get("environment", {})
    if grafana.get("GF_SECURITY_ADMIN_PASSWORD") or grafana.get("GF_SECURITY_ADMIN_PASSWORD__FILE") != "/run/secrets/grafana_password":
        errors.append("Grafana must use a mounted password, not environment plaintext")
    command = services.get("prometheus", {}).get("command", [])
    if any("--web.enable-lifecycle" in x or "--web.enable-admin-api" in x for x in command):
        errors.append("Prometheus mutation endpoints must remain disabled")
    if "--storage.tsdb.retention.time=35d" not in command:
        errors.append("35-day configured retention is required for the 28-day window")
    for kind in ("volumes", "networks"):
        for entry in model.get(kind, {}).values():
            if entry.get("external") or not entry.get("name", "").startswith("homelab-sre-prod_"):
                errors.append("networks and volumes must belong only to this Compose project")
    secret_dir = Path(secret_dir)
    if not secret_dir.is_dir() or secret_dir.is_symlink() or stat.S_IMODE(secret_dir.stat().st_mode) & 0o077:
        errors.append("secret directory must be private (0700) and not a symlink")
    for name in ("grafana_password", "receiver_token"):
        raw = model.get("secrets", {}).get(name, {}).get("file", "")
        path = Path(raw)
        if not raw or path.is_symlink() or path.resolve().parent != secret_dir.resolve() or not path.is_file():
            errors.append("required secret must be a regular file inside the private directory")
            continue
        value = path.read_text().strip()
        if len(value) < 32 or len(set(value)) < 10 or value.lower().startswith(("replace", "test", "smoke", "ci-", "admin")):
            errors.append("secret is short, low-diversity or a known placeholder")
        if stat.S_IMODE(path.stat().st_mode) & 0o222:
            errors.append("secret files must be read-only before container mounting")
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--secrets-dir", required=True)
    args = parser.parse_args()
    try:
        errors = validate(json.load(sys.stdin), args.secrets_dir)
    except (OSError, ValueError, TypeError, AttributeError):
        print("deployment preflight failed: invalid model or unreadable secret files", file=sys.stderr)
        return 1
    if errors:
        for error in sorted(set(errors)):
            print("BLOCKED: " + error, file=sys.stderr)
        return 1
    print("single-host hardening checks passed; NOT HA or independent paging/restore certification")
    return 0


if __name__ == "__main__":
    sys.exit(main())
