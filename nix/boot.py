# SPDX-License-Identifier: MIT
"""Reconcile before queuing enabled units discovered after sysext boot merge."""
import json
from pathlib import Path
import re
import subprocess

subprocess.run(["/usr/sbin/nix-profile-engine", "reconcile"], check=True)
for path in sorted(Path("/usr/share/nix-profile.d").glob("*.json")):
    manifest = json.loads(path.read_text())
    host = manifest.get("host", {})
    if host.get("service") is None or host.get("supervisor", "systemd") != "systemd":
        continue
    name = manifest["name"]
    if not isinstance(name, str) or not re.fullmatch(r"[a-z0-9][a-z0-9+.-]*", name):
        raise ValueError("invalid service name")
    unit = name + ".service"
    state = subprocess.run(["/usr/bin/systemctl", "is-enabled", unit],
                           text=True, capture_output=True)
    if state.returncode == 0 and state.stdout.strip() in {"enabled", "enabled-runtime"}:
        # Waiting here would deadlock units ordered after this oneshot service.
        subprocess.run(["/usr/bin/systemctl", "--no-block", "start", unit], check=True)
