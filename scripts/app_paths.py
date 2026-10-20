"""Shared desktop data paths. v1.3 deliberately does not read legacy folders."""

from __future__ import annotations

import os
import sys
from pathlib import Path

DATA_DIR_NAME = "mascotmate-desktop"


def data_dir(explicit: str | Path | None = None) -> Path:
    override = explicit or os.environ.get("CRAYON_PET_CONFIG_DIR", "").strip()
    if override:
        return Path(override).expanduser().resolve()
    if sys.platform == "win32":
        base = Path(os.environ.get("APPDATA") or Path.home() / "AppData" / "Roaming")
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")
    return base / DATA_DIR_NAME
