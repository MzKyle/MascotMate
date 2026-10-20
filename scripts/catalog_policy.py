"""Public curated catalogs never offer packages without explicit permission."""

from __future__ import annotations

import json
import shutil
from pathlib import Path, PurePosixPath

INSTALLABLE_SOURCE_TYPES = {"curated_package", "local_package"}


def public_entry(entry: object) -> bool:
    if not isinstance(entry, dict):
        return False
    source_type = entry.get("source_type", "curated_package")
    if source_type == "external_browser":
        return True
    license_info = entry.get("license", {})
    return (source_type in INSTALLABLE_SOURCE_TYPES and isinstance(license_info, dict)
            and license_info.get("redistributable") is True)


def catalog_asset(root: Path, reference: str) -> Path:
    ref = PurePosixPath(reference.replace("\\", "/"))
    if not reference or ref.is_absolute() or ".." in ref.parts or ":" in reference:
        raise ValueError(f"Unsafe catalog asset: {reference!r}")
    path = (root / Path(*ref.parts)).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError(f"Missing or unsafe catalog asset: {reference!r}")
    return path


def stage_public_catalog(source: Path, destination: Path) -> None:
    if destination.exists() and any(destination.iterdir()):
        raise ValueError("Public catalog staging requires an empty destination")
    catalog = json.loads((source / "catalog.json").read_text(encoding="utf-8"))
    catalog["skins"] = [entry for entry in catalog.get("skins", []) if public_entry(entry)]
    destination.mkdir(parents=True, exist_ok=True)
    for entry in catalog["skins"]:
        if entry.get("source_type", "curated_package") in INSTALLABLE_SOURCE_TYPES:
            for key in ("preview", "package"):
                reference = entry[key]
                asset = catalog_asset(source, reference)
                target = destination / asset.relative_to(source.resolve())
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(asset, target)
    for name in ("cachomon_index.json", "NOTICE.md", "README.md"):
        if (source / name).is_file():
            shutil.copy2(source / name, destination / name)
    (destination / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
