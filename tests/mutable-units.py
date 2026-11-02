# SPDX-License-Identifier: MIT
"""Give this NixOS fixture writable native unit directories, preserving links."""
from pathlib import Path
import os
import shutil


def copydir(source, target):
    target.mkdir()
    for entry in source.iterdir():
        dest = target / entry.name
        if entry.is_dir():
            copydir(entry, dest)
        elif entry.is_symlink():
            dest.symlink_to(os.readlink(entry))
        else:
            shutil.copy2(entry, dest)


source = Path("/etc/systemd/system")
temporary = Path("/var/lib/impurifier-vm/systemd-system")
temporary.parent.mkdir(parents=True, exist_ok=True)
copydir(source, temporary)
source.unlink()
source.symlink_to(temporary)
