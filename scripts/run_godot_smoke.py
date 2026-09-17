#!/usr/bin/env python3
"""Run Godot headless tests in isolated sessions."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "godot_pet"
TEST_SCRIPTS = [
    "res://tests/config_test.gd",
    "res://tests/behavior_test.gd",
    "res://tests/window_test.gd",
    "res://tests/companion_test.gd",
    "res://tests/runtime_smoke.gd",
]


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
        for index, script in enumerate(TEST_SCRIPTS, start=1):
            label = Path(script).name
            print(f"[{index}/{len(TEST_SCRIPTS)}] {label}", flush=True)
            config_dir = Path(temp_dir) / Path(script).stem
            env = os.environ.copy()
            env.update({
                "CRAYON_PET_CONFIG_DIR": str(config_dir),
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
                    script,
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
                print(proc.stderr, end="")
            if proc.returncode != 0:
                print(f"{label} failed with exit code {proc.returncode}.", file=sys.stderr)
                return proc.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
