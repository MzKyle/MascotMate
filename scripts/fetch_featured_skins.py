#!/usr/bin/env python3
"""Build bundled local featured skins from a user-provided Omen/Xenom Shimeji package."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from import_shimeji_skin import install_skin_source


ROOT = SCRIPT_DIR.parent
CATALOG_ROOT = ROOT / "skin_catalog"
DEFAULT_SOURCE_ZIP = ROOT / "resource" / "Omen the Growlithe Shimeji [SFW].zip"
NOTICE_DIR = CATALOG_ROOT / "notices" / "omen_xenom"
ZIP_DATE = (2026, 7, 3, 0, 0, 0)

FEATURED_SKINS = {
    "omen": {
        "name": "Omen",
        "description": "A locally bundled Growlithe Shimeji converted into a MascotMate skin.",
        "tags": ["featured", "local", "shimeji", "growlithe", "omen"],
    },
    "xenom": {
        "name": "Xenom",
        "description": "A locally bundled Growlithe Shimeji variant converted into a MascotMate skin.",
        "tags": ["featured", "local", "shimeji", "growlithe", "xenom"],
    },
}


def write_deterministic_zip(skin_root: Path, zip_path: Path) -> None:
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(skin_root.rglob("*")):
            if not path.is_file():
                continue
            rel = Path(skin_root.name) / path.relative_to(skin_root)
            info = zipfile.ZipInfo(str(rel).replace("\\", "/"), ZIP_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, path.read_bytes())


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_skin_manifest(skin_root: Path) -> dict[str, Any]:
    data = json.loads((skin_root / "skin.json").read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"Invalid skin manifest: {skin_root / 'skin.json'}")
    return data


def cleanup_obsolete_assets(catalog_root: Path) -> None:
    for relative in [
        Path("sources") / "dpets",
        Path("notices") / "dpets",
    ]:
        target = catalog_root / relative
        if target.exists():
            shutil.rmtree(target)


def copy_preview(skin_root: Path, manifest: dict[str, Any], preview_path: Path) -> None:
    frame_root = str(manifest.get("frame_root", "frames"))
    preview = str(manifest.get("preview", ""))
    source = skin_root / frame_root / preview
    if not source.is_file():
        raise SystemExit(f"Missing preview frame for {skin_root.name}: {source}")
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, preview_path)


def package_entries(skin_roots: list[Path], catalog_root: Path = CATALOG_ROOT) -> list[dict[str, Any]]:
    preview_dir = catalog_root / "previews"
    package_dir = catalog_root / "packages"
    preview_dir.mkdir(parents=True, exist_ok=True)
    package_dir.mkdir(parents=True, exist_ok=True)
    for path in preview_dir.glob("*.png"):
        path.unlink()
    for path in package_dir.glob("*.zip"):
        path.unlink()

    by_id = {path.name: path for path in skin_roots if (path / "skin.json").is_file()}
    entries: list[dict[str, Any]] = []
    for skin_id, sample in FEATURED_SKINS.items():
        skin_root = by_id.get(skin_id)
        if skin_root is None:
            raise SystemExit(f"Missing converted skin: {skin_id}")
        manifest = load_skin_manifest(skin_root)
        preview_path = preview_dir / f"{skin_id}.png"
        package_path = package_dir / f"{skin_id}.zip"
        copy_preview(skin_root, manifest, preview_path)
        write_deterministic_zip(skin_root, package_path)
        entries.append({
            "id": skin_id,
            "source_type": "local_package",
            "name": str(manifest.get("name", sample["name"])),
            "description": sample["description"],
            "tags": sample["tags"],
            "license": {
                "type": "user-provided",
                "summary": "Local user-provided Shimeji package. MascotMate does not assert redistribution rights.",
                "redistributable": False,
            },
            "format": "mascotmate_skin_zip",
            "preview": f"previews/{skin_id}.png",
            "package": f"packages/{skin_id}.zip",
            "sha256": sha256(package_path),
            "size_bytes": package_path.stat().st_size,
            "min_app_version": "1.2.0",
        })
    catalog = {
        "schema_version": 1,
        "updated_at": "2026-07-03",
        "skins": entries,
    }
    (catalog_root / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return entries


def generate_catalog(source: Path, catalog_root: Path = CATALOG_ROOT) -> list[dict[str, Any]]:
    cleanup_obsolete_assets(catalog_root)
    with tempfile.TemporaryDirectory(prefix="mascotmate-omen-featured-") as temp_dir:
        imported_root = Path(temp_dir) / "skins"
        imported = install_skin_source(source, imported_root)
        skin_roots = [item.path for item in imported]
        return package_entries(skin_roots, catalog_root)


def write_notices(source: Path, catalog_root: Path = CATALOG_ROOT) -> None:
    notice_dir = catalog_root / "notices" / "omen_xenom"
    notice_dir.mkdir(parents=True, exist_ok=True)
    notice = (
        "Omen/Xenom local featured skins\n"
        "================================\n\n"
        f"Source file: {source.name}\n"
        "These local featured skins are generated from a user-provided Shimeji package.\n"
        "MascotMate does not assert redistribution rights for this package.\n"
    )
    (notice_dir / "NOTICE.txt").write_text(notice, encoding="utf-8")
    if source.is_file() and zipfile.is_zipfile(source):
        with zipfile.ZipFile(source) as zf:
            for member in zf.infolist():
                name = Path(member.filename).name.lower()
                if name in {"readme.txt", "license.txt", "licence.txt"}:
                    target = notice_dir / Path(member.filename).name
                    target.write_bytes(zf.read(member))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-zip", type=Path, default=DEFAULT_SOURCE_ZIP, help="Source Shimeji ZIP containing Omen and Xenom.")
    parser.add_argument("--catalog-root", type=Path, default=CATALOG_ROOT)
    args = parser.parse_args()

    if not args.source_zip.is_file():
        raise SystemExit(f"Missing source ZIP: {args.source_zip}")
    entries = generate_catalog(args.source_zip, args.catalog_root)
    write_notices(args.source_zip, args.catalog_root)
    display_root = args.catalog_root.relative_to(ROOT) if args.catalog_root.is_relative_to(ROOT) else args.catalog_root
    print(f"Generated {len(entries)} local featured skins in {display_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
