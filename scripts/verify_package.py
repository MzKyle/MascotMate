"""Verify the final public ZIP, then exercise its exported app and frozen helper."""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import signal
import subprocess
import tempfile
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

from catalog_policy import INSTALLABLE_SOURCE_TYPES, catalog_asset, public_entry
from package_archive import extract_archive


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect_package(package: Path) -> dict:
    info = json.loads((package / "BUILD_INFO.json").read_text(encoding="utf-8"))
    if not info.get("public") or info.get("target") not in ("windows", "linux") or info.get("candidate"):
        raise ValueError("Only public Windows/Linux packages can pass stable acceptance")
    required = ["LICENSE", "README.txt", "skin_catalog/catalog.json", "skin_store/index.html", "companion_console/index.html"]
    required += [f"assets/character/peek_{edge}.png" for edge in ("left", "right", "top", "bottom")]
    for name in required:
        if not (package / name).is_file():
            raise ValueError(f"Required file missing: {name}")
    if (package / "skins").exists():
        raise ValueError("Local private skin directory found in public package")
    actual_files = {path.relative_to(package).as_posix() for path in package.rglob("*") if path.is_file() and not path.is_symlink()}
    if actual_files != set(info["files"]) | {"BUILD_INFO.json"}:
        raise ValueError("Package file inventory differs from BUILD_INFO.json")
    for name, expected in info["files"].items():
        if digest(catalog_asset(package, name)) != expected:
            raise ValueError(f"Package file digest mismatch: {name}")
    catalog_root = package / "skin_catalog"
    catalog = json.loads((catalog_root / "catalog.json").read_text(encoding="utf-8"))
    referenced = set()
    for entry in catalog["skins"]:
        if not public_entry(entry):
            raise ValueError(f"Restricted curated package: {entry.get('id')}")
        if entry.get("source_type", "curated_package") in INSTALLABLE_SOURCE_TYPES:
            for key in ("package", "preview"):
                referenced.add(catalog_asset(catalog_root, entry[key]).relative_to(catalog_root).as_posix())
    bundled = {p.relative_to(catalog_root).as_posix() for folder in ("packages", "previews") for p in (catalog_root / folder).rglob("*") if p.is_file()}
    if bundled != referenced:
        raise ValueError("Unreferenced or missing curated skin assets")
    return info


def run_checked(command: list[str], cwd: Path, env: dict) -> subprocess.CompletedProcess:
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=90)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {command}\n{result.stdout}\n{result.stderr}")
    if "SCRIPT ERROR:" in result.stderr:
        raise RuntimeError(result.stderr)
    return result


def check_server(helper: Path, command: str, package: Path, data: Path, cwd: Path, env: dict) -> None:
    process = subprocess.Popen([str(helper), command, "--repo-root", str(package), "--config-dir", str(data), "--idle-timeout", "30"], cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace", start_new_session=os.name != "nt")
    try:
        pool = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        try:
            line = pool.submit(process.stdout.readline).result(timeout=25)
        finally:
            pool.shutdown(wait=False, cancel_futures=True)
        try:
            url = json.loads(line)["url"]
        except (ValueError, KeyError):
            raise RuntimeError(f"Frozen {command} failed to announce its local URL: {line}")
        parts = urllib.parse.urlsplit(url)
        base = f"{parts.scheme}://{parts.netloc}"
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        for path in ("/", "/companion/", "/api/catalog"):
            with opener.open(base + path + "?" + parts.query, timeout=10) as response:
                payload = response.read()
                if response.status != 200 or not payload:
                    raise RuntimeError(f"Empty {command} response for {path}")
    finally:
        if os.name == "nt":
            subprocess.run([str(Path(os.environ["SystemRoot"]) / "System32" / "taskkill.exe"), "/PID", str(process.pid), "/T", "/F"], capture_output=True, timeout=10)
        else:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        try:
            process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()


def write_test_skin(archive: Path) -> None:
    from PIL import Image
    import io

    buffer = io.BytesIO()
    Image.new("RGBA", (12, 14), (20, 150, 220, 255)).save(buffer, format="PNG")
    skin = {"schema_version": 2, "version": 1, "id": "package-check", "name": "Acceptance fixture", "description": "Generated acceptance fixture", "metadata": {"package_version": "1.0.0", "authors": []}, "frame_root": "frames", "preview": "idle/001.png", "license": {"type": "CC0-1.0", "redistributable": True}, "source": {"format": "test"}, "capabilities": {key: [{"action": "idle", "score": 100}] for key in ("resting", "locomotion", "falling", "held", "edge")}, "fallbacks": {}, "actions": {"idle": {"name": "Idle", "resource": "idle", "size": [12, 14], "fps": 4, "loop": True, "frames": ["idle/001.png"]}}}
    with zipfile.ZipFile(archive, "w") as zf:
        zf.writestr("package-check/skin.json", json.dumps(skin))
        zf.writestr("package-check/frames/idle/001.png", buffer.getvalue())


def verify(archive: Path, report_path: Path) -> dict:
    archive = archive.resolve()
    checksum = archive.with_suffix(".zip.sha256")
    expected = checksum.read_text(encoding="utf-8").split()
    if expected != [digest(archive), archive.name]:
        raise ValueError("Archive checksum does not match its sidecar")
    with tempfile.TemporaryDirectory(prefix="mascotmate-acceptance-") as temporary:
        root = Path(temporary)
        package = root / "解压 package with spaces"
        extract_archive(archive, package)
        info = inspect_package(package)
        cwd = root / "unrelated working directory"
        cwd.mkdir()
        data = root / "全新 data"
        env = os.environ.copy()
        for name in ("CRAYON_PET_ROOT", "PYTHONPATH", "PYTHONHOME", "PYTHON", "CRAYON_PET_SAFE_WINDOW", "CRAYON_PET_TRANSPARENT", "CRAYON_PET_MOUSE_PASSTHROUGH"):
            env.pop(name, None)
        env.update({"CRAYON_PET_CONFIG_DIR": str(data), "CRAYON_PET_ENABLE_GLOBAL_HOTKEYS": "0", "PYTHONUTF8": "1"})
        # Only the bundled binaries may satisfy helper launches.
        env["PATH"] = str(Path(os.environ["SystemRoot"]) / "System32") if info["target"] == "windows" else "/usr/bin:/bin"
        helper = package / "scripts" / ("pet_helper.exe" if info["target"] == "windows" else "pet_helper")
        run_checked([str(helper), "--help"], cwd, env)
        fixture = root / "acceptance-skin.zip"
        write_test_skin(fixture)
        run_checked([str(helper), "install-skin", str(fixture), "--output-root", str(data / "skins"), "--json-report"], cwd, env)
        if not (data / "skins" / "package-check" / "skin.json").is_file():
            raise RuntimeError("Frozen helper did not install the acceptance skin")
        for command in ("skin-store", "companion-console"):
            check_server(helper, command, package, data, cwd, env)
        program = package / ("MascotMateDesktop.exe" if info["target"] == "windows" else "MascotMateDesktop")
        if info["target"] == "windows":
            import pefile
            with pefile.PE(str(program)) as binary:
                version_info = binary.VS_FIXEDFILEINFO[0]
                expected_version = [int(part) for part in info["version"].split(".")] + [0]
                for ms, ls in ((version_info.FileVersionMS, version_info.FileVersionLS), (version_info.ProductVersionMS, version_info.ProductVersionLS)):
                    if [ms >> 16, ms & 65535, ls >> 16, ls & 65535] != expected_version:
                        raise ValueError("Windows executable version metadata does not match BUILD_INFO.json")
        result_path = root / "app-check.json"
        try:
            result = run_checked([str(program), "--", "--package-check", str(result_path)], cwd, env)
        except RuntimeError as exc:
            if result_path.is_file():
                raise RuntimeError("Exported app checks: " + result_path.read_text(encoding="utf-8")) from exc
            raise
        app_report = json.loads(result_path.read_text(encoding="utf-8"))
        if not app_report.get("passed") or app_report.get("version") != info["version"]:
            raise RuntimeError(f"Exported app acceptance failed: {app_report}\n{result.stdout}\n{result.stderr}")
        if Path(app_report["resource_root"]).resolve() != package.resolve() or Path(app_report["data_dir"]).resolve() != data.resolve():
            raise RuntimeError("Exported app resolved resources or data outside the extracted package/test directory")
        restart_path = root / "restart-check.json"
        run_checked([str(program), "--", "--package-check", str(restart_path)], cwd, env)
        restart = json.loads(restart_path.read_text(encoding="utf-8"))
        if not restart.get("passed") or restart.get("startup_settings") != {"display_scale": 1.25, "gravity_enabled": False, "behavior_mode": "安静"}:
            raise RuntimeError(f"Settings did not survive an exported app restart: {restart}")
        report = {"passed": True, "version": info["version"], "commit": info["commit"], "target": info["target"], "archive": archive.name, "sha256": digest(archive), "helper": True, "skin_import": True, "skin_store": True, "companion_console": True, "restart": True, "app": app_report}
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(verify(args.archive, args.report), ensure_ascii=False, indent=2))
