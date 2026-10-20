#!/usr/bin/env python3
"""Build a portable Godot bundle for the current desktop platform."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import importlib.metadata
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from catalog_policy import stage_public_catalog
from package_archive import create_archive, extract_archive
from release_version import check_versions

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
        "artifact": f"MascotMateDesktop-macos-{platform.machine().lower()}-candidate",
    },
}


def format_size(size: int) -> str:
    units = ("B", "KiB", "MiB", "GiB")
    value = float(max(0, size))
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.1f} {unit}" if unit != "B" else f"{int(value)} B"
        value /= 1024
    return f"{size} B"


def path_size(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    total = 0
    for item in path.rglob("*"):
        if item.is_file():
            total += item.stat().st_size
    return total


def top_level_size_report(package_dir: Path) -> list[tuple[str, int]]:
    entries = [(path.name, path_size(path)) for path in package_dir.iterdir()]
    return sorted(entries, key=lambda item: item[1], reverse=True)


def print_package_size_report(package_dir: Path, zip_path: Path) -> None:
    print("Package size report:")
    print(f"  archive: {format_size(zip_path.stat().st_size)}")
    for name, size in top_level_size_report(package_dir):
        print(f"  {name}: {format_size(size)}")


def portable_readme_text(target: str) -> str:
    if target == "windows":
        run_hint = "Double-click MascotMateDesktop.exe."
    elif target == "macos":
        run_hint = "Open MascotMateDesktop.app from this extracted folder."
    else:
        run_hint = "Run ./MascotMateDesktop from this extracted folder."
    macos_note = (
        "\nmacOS note: keep MascotMateDesktop.app inside this extracted folder. "
        "Moving only the .app can break skins, helper tools, and bundled assets.\n"
        if target == "macos"
        else ""
    )
    artifact = TARGETS[target]["artifact"]
    return f"""MascotMate Desktop Portable

Package: {artifact}.zip
Version: {check_versions()}

Local data
Windows: %APPDATA%\\mascotmate-desktop
macOS: ~/Library/Application Support/mascotmate-desktop
Linux: ${{XDG_DATA_HOME:-~/.local/share}}/mascotmate-desktop
v1.3 does not load or migrate old data folders. Existing files remain untouched.
Daily aggregates are retained independently of the latest 200 raw events.

Quick start
1. Extract the entire ZIP file.
2. Keep every file and folder together in the extracted directory.
3. {run_hint}
4. Right-click the pet and choose "怎么玩？" any time to replay the basic tips.

Do not move only the executable or app bundle out of this folder. MascotMate uses
the bundled resource_hd, assets, skin_catalog, skin_store, companion_console, and
scripts folders at runtime.{macos_note}

Basic controls
- Left-click the head to pet it; left-click the body to poke it.
- Hold the pet to pick it up, then release gently or fling it.
- Drag it near a screen edge and release to enter peek mode.
- Double-click to play the tease interaction.
- Use the mouse wheel to show local pet state.
- Right-click to open the menu for feeding, sleep, skins, screenshots, settings,
  help, and exit.

中文快速说明
1. 请完整解压 ZIP，不要只拖走可执行文件或 .app。
2. 在解压目录中运行应用。
3. 右键桌宠选择 "怎么玩？" 可以重播基础提示。
4. 双击可以逗一逗，长按可以抱起，滚轮可以查看状态。

Project and updates
https://github.com/MzKyle/MascotMate
https://github.com/MzKyle/MascotMate/releases
"""


def write_portable_readme(package_dir: Path, target: str) -> None:
    (package_dir / "README.txt").write_text(portable_readme_text(target), encoding="utf-8")


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


def helper_fingerprint() -> str:
    sources = sorted((ROOT / "scripts").glob("*.py")) + [ROOT / "requirements.txt"]
    digest = hashlib.sha256()
    digest.update(f"{sys.version}|{platform.system()}|{platform.machine()}".encode())
    for distribution in sorted(importlib.metadata.distributions(), key=lambda item: item.metadata["Name"].lower()):
        digest.update(f"{distribution.metadata['Name']}=={distribution.version}".encode())
    for path in sources:
        digest.update(path.name.encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def build_helper() -> Path:
    dist_dir = ROOT / "build" / "helper" / platform.machine().lower()
    work_dir = ROOT / "build" / "pyinstaller"
    spec_dir = ROOT / "build" / "spec"
    helper_path = dist_dir / HELPER_NAME
    fingerprint_path = dist_dir / "fingerprint.txt"
    fingerprint = helper_fingerprint()
    if helper_path.exists() and fingerprint_path.exists() and fingerprint_path.read_text() == fingerprint:
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
    architecture_args = ["--target-arch", platform.machine().lower()] if platform.system() == "Darwin" else []
    run([
        pyinstaller,
        *architecture_args,
        "--onefile",
        "--clean",
        "--hidden-import", "skin_store_server",
        "--hidden-import", "import_shimeji_skin",
        "--hidden-import", "skin_sdk",
        "--hidden-import", "cachomon_catalog",
        "--hidden-import", "companion_ai_sidecar",
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
    fingerprint_path.write_text(fingerprint)
    return helper_path


def copy_external_assets(package_dir: Path, helper_path: Path, private_skins_dir: Path | None = None) -> None:
    shutil.copy2(ROOT / "LICENSE", package_dir / "LICENSE")
    for name in ("resource_hd", "assets", "skin_store", "companion_console"):
        source = ROOT / name
        if source.exists():
            shutil.copytree(source, package_dir / name, dirs_exist_ok=True)
    stage_public_catalog(ROOT / "skin_catalog", package_dir / "skin_catalog")
    scripts_dir = package_dir / "scripts"
    scripts_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(helper_path, scripts_dir / helper_path.name)
    shutil.copy2(ROOT / "scripts" / "pet_helper.py", scripts_dir / "pet_helper.py")
    for name in ("app_paths.py", "catalog_policy.py"):
        shutil.copy2(ROOT / "scripts" / name, scripts_dir / name)
    importer = ROOT / "scripts" / "import_shimeji_skin.py"
    if importer.exists():
        shutil.copy2(importer, scripts_dir / "import_shimeji_skin.py")
    skin_sdk = ROOT / "scripts" / "skin_sdk.py"
    if skin_sdk.exists():
        shutil.copy2(skin_sdk, scripts_dir / "skin_sdk.py")
    cachomon_catalog = ROOT / "scripts" / "cachomon_catalog.py"
    if cachomon_catalog.exists():
        shutil.copy2(cachomon_catalog, scripts_dir / "cachomon_catalog.py")
    skin_store_server = ROOT / "scripts" / "skin_store_server.py"
    if skin_store_server.exists():
        shutil.copy2(skin_store_server, scripts_dir / "skin_store_server.py")
    companion_ai_sidecar = ROOT / "scripts" / "companion_ai_sidecar.py"
    if companion_ai_sidecar.exists():
        shutil.copy2(companion_ai_sidecar, scripts_dir / "companion_ai_sidecar.py")
    featured_skins = ROOT / "scripts" / "fetch_featured_skins.py"
    if featured_skins.exists():
        shutil.copy2(featured_skins, scripts_dir / "fetch_featured_skins.py")
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
        extract_archive(export_path, package_dir)
        export_path.unlink()
        # Godot can name the bundle after config/name rather than the ZIP.
        bundles = sorted(package_dir.glob("*.app"))
        if len(bundles) != 1 or not bundles[0].is_dir():
            raise RuntimeError(f"Expected one exported macOS app bundle, found {len(bundles)}")
        app = package_dir / "MascotMateDesktop.app"
        if bundles[0] != app:
            bundles[0].rename(app)
        with (app / "Contents" / "Info.plist").open("rb") as handle:
            executable = plistlib.load(handle)["CFBundleExecutable"]
        program = app / "Contents" / "MacOS" / executable
        program.chmod(program.stat().st_mode | 0o755)
    elif target != "windows" and export_path.exists():
        export_path.chmod(export_path.stat().st_mode | 0o755)


def zip_package(package_dir: Path, artifact_name: str) -> Path:
    zip_path = DIST / f"{artifact_name}.zip"
    if zip_path.exists():
        zip_path.unlink()
    create_archive(package_dir, zip_path)
    digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    zip_path.with_suffix(".zip.sha256").write_text(f"{digest}  {zip_path.name}\n", encoding="utf-8")
    return zip_path


def working_tree_status(require_clean: bool = False) -> str:
    status = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    if require_clean and status:
        raise RuntimeError(f"Packaging requires a clean source tree. Commit these changes first:\n{status}")
    return status


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", choices=sorted(TARGETS), default=current_target())
    parser.add_argument("--require-clean", action="store_true", help="Reject uncommitted source changes before and after export (used by CI).")
    parser.add_argument(
        "--private-skins-dir",
        type=Path,
        help="Optional local-only skin directory copied into the package as skins/. Never used by CI by default.",
    )
    args = parser.parse_args()
    if args.target != current_target() and os.environ.get("CRAYON_PET_ALLOW_CROSS_PACKAGE") != "1":
        raise SystemExit("Build each portable target on its matching OS, or set CRAYON_PET_ALLOW_CROSS_PACKAGE=1.")

    if args.target in ("windows", "linux") and platform.machine().lower() not in ("amd64", "x86_64"):
        raise SystemExit("Stable Windows/Linux packages require an x86_64 build host and helper.")
    version = check_versions()
    working_tree_status(args.require_clean)
    target_info = TARGETS[args.target]
    run([sys.executable, str(ROOT / "scripts" / "generate_godot_manifest.py")])
    helper_path = build_helper()

    package_dir = DIST / target_info["artifact"]
    if package_dir.exists():
        shutil.rmtree(package_dir)
    package_dir.mkdir(parents=True)

    export_project(args.target, package_dir)
    copy_external_assets(package_dir, helper_path, args.private_skins_dir)
    write_portable_readme(package_dir, args.target)
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    status = working_tree_status(args.require_clean)
    info = {"version": version, "commit": commit, "target": args.target,
            "architecture": platform.machine().lower(), "public": args.private_skins_dir is None,
            "dirty": bool(status),
            "candidate": args.target == "macos", "files": {}}
    for path in sorted(package_dir.rglob("*")):
        if path.is_file() and not path.is_symlink():
            info["files"][path.relative_to(package_dir).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    (package_dir / "BUILD_INFO.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
    zip_path = zip_package(package_dir, target_info["artifact"])
    print_package_size_report(package_dir, zip_path)
    print(f"Built {zip_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
