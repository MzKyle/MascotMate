#!/usr/bin/env python3
"""Validate the curated skin catalog and bundled featured packages."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
from pathlib import Path
from typing import Any

from PIL import Image, UnidentifiedImageError

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from import_shimeji_skin import install_skin_source


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CATALOG = ROOT / "skin_catalog" / "catalog.json"
MAX_PACKAGE_BYTES = 100 * 1024 * 1024
ALLOWED_FORMATS = {"mascotmate_skin_zip", "shimeji_zip", "shimeji-ee"}
ALLOWED_SOURCE_TYPES = {"curated_package", "external_browser"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_safe_relative_ref(value: str) -> bool:
    path = Path(value)
    return value != "" and not path.is_absolute() and ".." not in path.parts


def load_catalog(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def verify_png(path: Path, errors: list[str]) -> None:
    try:
        with Image.open(path) as image:
            image.verify()
            if image.format != "PNG":
                errors.append(f"Preview is not PNG: {path}")
    except (OSError, UnidentifiedImageError) as exc:
        errors.append(f"Cannot read preview {path}: {exc}")


def validate_catalog(data: dict[str, Any], catalog_dir: Path, *, check_files: bool = True) -> list[str]:
    errors: list[str] = []
    if int(data.get("schema_version", 0)) != 1:
        errors.append("catalog.schema_version must be 1.")
    if not isinstance(data.get("updated_at", ""), str) or data.get("updated_at", "") == "":
        errors.append("catalog.updated_at is required.")
    skins = data.get("skins", [])
    if not isinstance(skins, list) or not skins:
        errors.append("catalog.skins must be a non-empty list.")
        return errors

    seen_ids: set[str] = set()
    with tempfile.TemporaryDirectory(prefix="skin-catalog-validate-") as temp_dir:
        install_root = Path(temp_dir) / "skins"
        for index, entry in enumerate(skins):
            if not isinstance(entry, dict):
                errors.append(f"skins[{index}] must be an object.")
                continue
            skin_id = str(entry.get("id", "")).strip()
            if skin_id == "":
                errors.append(f"skins[{index}].id is required.")
                continue
            if skin_id in seen_ids:
                errors.append(f"Duplicate skin id: {skin_id}")
            seen_ids.add(skin_id)
            source_type = str(entry.get("source_type", "curated_package"))
            if source_type not in ALLOWED_SOURCE_TYPES:
                errors.append(f"{skin_id}.source_type is unsupported: {source_type!r}")
            required_fields = ["name", "description", "format", "min_app_version"]
            if source_type == "curated_package":
                required_fields.extend(["preview", "package", "sha256"])
            else:
                required_fields.extend(["source_url", "preview_url"])
            for field in required_fields:
                if str(entry.get(field, "")).strip() == "":
                    errors.append(f"{skin_id}.{field} is required.")
            if str(entry.get("format", "")) not in ALLOWED_FORMATS:
                errors.append(f"{skin_id}.format is unsupported: {entry.get('format')!r}")
            tags = entry.get("tags", [])
            if not isinstance(tags, list):
                errors.append(f"{skin_id}.tags must be a list.")
            license_info = entry.get("license", {})
            if not isinstance(license_info, dict) or not bool(license_info.get("redistributable", False)):
                if source_type == "curated_package":
                    errors.append(f"{skin_id}.license.redistributable must be true.")
            preview_ref = str(entry.get("preview", ""))
            package_ref = str(entry.get("package", ""))
            if source_type == "curated_package" and not is_safe_relative_ref(preview_ref):
                errors.append(f"{skin_id}.preview must be a safe relative path.")
            if source_type == "curated_package" and not is_safe_relative_ref(package_ref):
                errors.append(f"{skin_id}.package must be a safe relative path.")
            if not check_files:
                continue
            if source_type == "external_browser":
                continue

            preview_path = catalog_dir / preview_ref
            package_path = catalog_dir / package_ref
            if not preview_path.is_file():
                errors.append(f"{skin_id}.preview is missing: {preview_ref}")
            else:
                verify_png(preview_path, errors)
            if not package_path.is_file():
                errors.append(f"{skin_id}.package is missing: {package_ref}")
                continue
            size = package_path.stat().st_size
            if size <= 0 or size > MAX_PACKAGE_BYTES:
                errors.append(f"{skin_id}.package size is invalid: {size}")
            expected_size = int(entry.get("size_bytes", -1))
            if expected_size != size:
                errors.append(f"{skin_id}.size_bytes is {expected_size}, expected {size}.")
            expected_hash = str(entry.get("sha256", "")).lower()
            actual_hash = sha256(package_path)
            if expected_hash != actual_hash:
                errors.append(f"{skin_id}.sha256 mismatch: expected {expected_hash}, got {actual_hash}.")
            try:
                installed = install_skin_source(package_path, install_root)
            except SystemExit as exc:
                errors.append(f"{skin_id}.package cannot be installed: {exc}")
                continue
            if not installed or installed[0].report.get("skin_id") != skin_id:
                errors.append(f"{skin_id}.package installs a different skin id.")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--check", action="store_true", help="Validate files referenced by the catalog.")
    args = parser.parse_args()

    try:
        data = load_catalog(args.catalog)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"Unable to read catalog: {exc}", file=sys.stderr)
        return 1
    errors = validate_catalog(data, args.catalog.parent, check_files=args.check)
    if errors:
        print("Skin catalog validation failed:", file=sys.stderr)
        for item in errors:
            print(f"- {item}", file=sys.stderr)
        return 1
    print("Skin catalog validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
