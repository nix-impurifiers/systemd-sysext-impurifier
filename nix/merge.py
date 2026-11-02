# SPDX-License-Identifier: MIT
"""Compose a single extension, rejecting unsupported roots and file collisions."""
from pathlib import Path
import shutil
import sys

out = Path(sys.argv[1])
out.mkdir()
for source in map(Path, sys.argv[2:]):
    for path in sorted(source.rglob("*")):
        relative = path.relative_to(source)
        if relative.parts[0] != "usr":
            raise ValueError("sysext cannot install outside /usr: " + str(relative))
        target = out / relative
        if path.is_dir() and not path.is_symlink():
            target.mkdir(parents=True, exist_ok=True)
        else:
            if target.exists() or target.is_symlink():
                raise ValueError("extension file collision: " + str(relative))
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target, follow_symlinks=False)
