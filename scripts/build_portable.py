#!/usr/bin/env python3
"""Build a portable Godot bundle for the current desktop platform."""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
HELPER_NAME = "pet_helper.exe" if platform.system() == "Windows" else "pet_helper"

TARGETS = {
    "linux": {
        "preset": "Linux",
        "export": "MascotMateDesktop",
        "artifact": "MascotMateDesktop-linux-x86_64",
    },
    "windows": {
        "preset": "Windows Desktop",
        "export": "MascotMateDesktop.exe",
        "artifact": "MascotMateDesktop-windows-x86_64",
    },
    "macos": {
        "preset": "macOS",
        "export": "MascotMateDesktop.zip",
        "artifact": "MascotMateDesktop-macos-universal",
    },
}


def current_target() -> str:
    system = platform.system()
    if system == "Windows":
        return "windows"
    if system == "Darwin":
        return "macos"
    return "linux"


def run(cmd: list[str], cwd: Path = ROOT) -> None:
    print("+", " ".join(cmd))
    subprocess.check_call(cmd, cwd=cwd)


def find_godot() -> str:
    env = os.environ.get("GODOT_BIN")
    if env:
        return env
    for name in ("godot4", "godot"):
        found = shutil.which(name)
        if found:
            return found
    if platform.system() == "Linux":
        out = subprocess.check_output([str(ROOT / "scripts" / "setup_godot.sh")], text=True)
        return out.strip().splitlines()[-1]
    raise RuntimeError("Godot was not found. Set GODOT_BIN before packaging.")


def build_helper() -> Path:
    dist_dir = ROOT / "build" / "helper"
    work_dir = ROOT / "build" / "pyinstaller"
    spec_dir = ROOT / "build" / "spec"
    helper_path = dist_dir / HELPER_NAME
    helper_sources = [
        ROOT / "scripts" / "pet_helper.py",
        ROOT / "scripts" / "import_shimeji_skin.py",
        ROOT / "scripts" / "skin_sdk.py",
        ROOT / "scripts" / "cachomon_catalog.py",
    ]
    if helper_path.exists() and helper_path.stat().st_mtime >= max(path.stat().st_mtime for path in helper_sources if path.exists()):
        return helper_path
    pyinstaller = shutil.which("pyinstaller")
    if not pyinstaller:
        pyinstaller = shutil.which("pyinstaller.exe")
    if not pyinstaller:
        local = ROOT / ".venv" / ("Scripts" if platform.system() == "Windows" else "bin")
        for name in ("pyinstaller.exe", "pyinstaller"):
            candidate = local / name
            if candidate.exists():
                pyinstaller = str(candidate)
                break
    if not pyinstaller:
        raise RuntimeError("PyInstaller is required to build the packaged helper.")
    run([
        pyinstaller,
        "--onefile",
        "--clean",
        "--name",
        "pet_helper",
        "--distpath",
        str(dist_dir),
        "--workpath",
        str(work_dir),
        "--specpath",
        str(spec_dir),
        str(ROOT / "scripts" / "pet_helper.py"),
    ])
    if not helper_path.exists():
        raise FileNotFoundError(helper_path)
    return helper_path


def copy_external_assets(package_dir: Path, helper_path: Path, private_skins_dir: Path | None = None) -> None:
    for name in ("resource_hd", "assets", "skin_catalog"):
        source = ROOT / name
        if source.exists():
            shutil.copytree(source, package_dir / name, dirs_exist_ok=True)
    scripts_dir = package_dir / "scripts"
    scripts_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(helper_path, scripts_dir / helper_path.name)
    shutil.copy2(ROOT / "scripts" / "pet_helper.py", scripts_dir / "pet_helper.py")
    importer = ROOT / "scripts" / "import_shimeji_skin.py"
    if importer.exists():
        shutil.copy2(importer, scripts_dir / "import_shimeji_skin.py")
    skin_sdk = ROOT / "scripts" / "skin_sdk.py"
    if skin_sdk.exists():
        shutil.copy2(skin_sdk, scripts_dir / "skin_sdk.py")
    cachomon_catalog = ROOT / "scripts" / "cachomon_catalog.py"
    if cachomon_catalog.exists():
        shutil.copy2(cachomon_catalog, scripts_dir / "cachomon_catalog.py")
    if private_skins_dir is not None:
        if not private_skins_dir.is_dir():
            raise FileNotFoundError(private_skins_dir)
        shutil.copytree(private_skins_dir, package_dir / "skins", dirs_exist_ok=True)


def export_project(target: str, package_dir: Path) -> None:
    godot = find_godot()
    target_info = TARGETS[target]
    export_path = package_dir / target_info["export"]
    run([
        godot,
        "--headless",
        "--path",
        str(ROOT / "godot_pet"),
        "--export-release",
        target_info["preset"],
        str(export_path),
    ])
    if target == "macos":
        with zipfile.ZipFile(export_path) as zf:
            zf.extractall(package_dir)
        export_path.unlink()
    elif target != "windows" and export_path.exists():
        export_path.chmod(export_path.stat().st_mode | 0o755)


def zip_package(package_dir: Path, artifact_name: str) -> Path:
    zip_path = DIST / f"{artifact_name}.zip"
    if zip_path.exists():
        zip_path.unlink()
    shutil.make_archive(str(zip_path.with_suffix("")), "zip", package_dir)
    return zip_path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", choices=sorted(TARGETS), default=current_target())
    parser.add_argument(
        "--private-skins-dir",
        type=Path,
        help="Optional local-only skin directory copied into the package as skins/. Never used by CI by default.",
    )
    args = parser.parse_args()
    if args.target != current_target() and os.environ.get("CRAYON_PET_ALLOW_CROSS_PACKAGE") != "1":
        raise SystemExit("Build each portable target on its matching OS, or set CRAYON_PET_ALLOW_CROSS_PACKAGE=1.")

    target_info = TARGETS[args.target]
    run([sys.executable, str(ROOT / "scripts" / "generate_godot_manifest.py")])
    helper_path = build_helper()

    package_dir = DIST / target_info["artifact"]
    if package_dir.exists():
        shutil.rmtree(package_dir)
    package_dir.mkdir(parents=True)

    export_project(args.target, package_dir)
    copy_external_assets(package_dir, helper_path, args.private_skins_dir)
    zip_path = zip_package(package_dir, target_info["artifact"])
    print(f"Built {zip_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
