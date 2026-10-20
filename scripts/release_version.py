"""Check desktop metadata against the single project version source."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def project_version(root: Path = ROOT) -> str:
    text = (root / "godot_pet" / "project.godot").read_text(encoding="utf-8")
    match = re.search(r'^config/version="(\d+\.\d+\.\d+)"$', text, re.M)
    if not match:
        raise ValueError("project.godot must define an X.Y.Z config/version")
    return match[1]


def check_versions(tag: str | None = None, root: Path = ROOT) -> str:
    version = project_version(root)
    presets = (root / "godot_pet" / "export_presets.cfg").read_text(encoding="utf-8")
    for key, expected in {
        "application/file_version": version + ".0",
        "application/product_version": version + ".0",
        "application/short_version": version,
        "application/version": version,
    }.items():
        if f'{key}="{expected}"' not in presets.splitlines():
            raise ValueError(f"{key} must equal {expected}")
    if tag and tag != "v" + version:
        raise ValueError(f"Tag {tag} does not match v{version}")
    return version


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag")
    args = parser.parse_args()
    print(check_versions(args.tag))
