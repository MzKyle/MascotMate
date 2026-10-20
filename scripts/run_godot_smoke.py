#!/usr/bin/env python3
"""Run Godot headless tests in isolated sessions."""

from __future__ import annotations

import json
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
    "res://tests/aggregate_test.gd",
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
        # Unlike the isolated suites, this checks real platform defaults without an override.
        env = os.environ.copy()
        env.pop("CRAYON_PET_CONFIG_DIR", None)
        env.update({"APPDATA": str(Path(temp_dir) / "roaming"), "HOME": str(Path(temp_dir) / "home"), "XDG_DATA_HOME": str(Path(temp_dir) / "data home")})
        legacy_files = [Path(env["HOME"]) / ".config/mascotmate-desktop/config.json", Path(env["APPDATA"]) / "Godot/app_userdata/MascotMate Desktop/config.json"]
        for legacy in legacy_files:
            legacy.parent.mkdir(parents=True, exist_ok=True)
            legacy.write_text('{"app":{"skin_id":"legacy-do-not-load"}}', encoding="utf-8")
        probe = subprocess.run([str(godot), "--headless", "--path", str(PROJECT), "--script", "res://tests/path_probe.gd"], env=env, capture_output=True, text=True, timeout=30, check=True)
        paths = json.loads(next(line.removeprefix("DATA_PATHS:") for line in probe.stdout.splitlines() if line.startswith("DATA_PATHS:")))
        expected = subprocess.check_output([sys.executable, "-c", "from app_paths import data_dir; print(data_dir())"], cwd=ROOT / "scripts", env=env, text=True).strip()
        if any(Path(path).resolve() != Path(expected).resolve() for path in paths.values()):
            raise RuntimeError(f"Godot/Python default paths differ: {paths}, Python={expected}")
        if any(legacy.read_text(encoding="utf-8") != '{"app":{"skin_id":"legacy-do-not-load"}}' for legacy in legacy_files):
            raise RuntimeError("Legacy data was modified")
        print("Godot/Python platform data paths agree.", flush=True)
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
