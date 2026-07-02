#!/usr/bin/env python3
"""Run Godot runtime smoke tests in an isolated headless session."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "godot_pet"
SMOKE_SCRIPT = "res://tests/runtime_smoke.gd"


def find_godot() -> Path:
    env = os.environ.get("GODOT_BIN", "").strip()
    if env:
        path = Path(env)
        if path.is_file():
            return path
        raise FileNotFoundError(f"GODOT_BIN does not exist: {path}")
    candidates = sorted((ROOT / "tools" / "godot").glob("Godot_v*"), key=lambda item: item.name)
    for candidate in reversed(candidates):
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    raise FileNotFoundError("Godot executable not found. Set GODOT_BIN or run scripts/setup_godot.sh.")


def main() -> int:
    godot = find_godot()
    with tempfile.TemporaryDirectory(prefix="crayon-pet-smoke-") as temp_dir:
        env = os.environ.copy()
        env.update({
            "CRAYON_PET_CONFIG_DIR": temp_dir,
            "CRAYON_PET_ROOT": str(ROOT),
            "CRAYON_PET_SAFE_WINDOW": "1",
            "CRAYON_PET_TRANSPARENT": "0",
            "CRAYON_PET_MOUSE_PASSTHROUGH": "0",
            "CRAYON_PET_ENABLE_GLOBAL_HOTKEYS": "0",
        })
        proc = subprocess.run(
            [
                str(godot),
                "--headless",
                "--path",
                str(PROJECT),
                "--script",
                SMOKE_SCRIPT,
            ],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            timeout=90,
            check=False,
        )
    if proc.stdout:
        print(proc.stdout, end="")
    if proc.stderr:
        print(proc.stderr, end="", file=sys.stderr)
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
