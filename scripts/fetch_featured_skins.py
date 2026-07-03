#!/usr/bin/env python3
"""Fetch DPets sprites and build bundled featured MascotMate skins."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path
from typing import Any

from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from skin_sdk import SCHEMA_VERSION, apply_quality_metadata, validate_skin_manifest


ROOT = SCRIPT_DIR.parent
CATALOG_ROOT = ROOT / "skin_catalog"
PREVIEW_DIR = CATALOG_ROOT / "previews"
PACKAGE_DIR = CATALOG_ROOT / "packages"
NOTICE_DIR = CATALOG_ROOT / "notices" / "dpets"
ZIP_DATE = (2026, 7, 3, 0, 0, 0)
DPETS_RAW = "https://raw.githubusercontent.com/Denellyne/DPets/main"

FEATURED_SKINS = [
    {
        "id": "dpets_cat",
        "name": "DPets Cat",
        "description": "A crisp pixel cat companion adapted from the DPets desktop pet sprites.",
        "sprite": "cat.png",
        "tags": ["featured", "pixel", "cat", "dpets"],
        "accent": [56, 189, 248],
    },
    {
        "id": "dpets_pup",
        "name": "DPets Pup",
        "description": "A tiny pixel dog companion adapted from the DPets desktop pet sprites.",
        "sprite": "sprite.png",
        "tags": ["featured", "pixel", "dog", "dpets"],
        "accent": [34, 197, 94],
    },
]


def download_sources(source_dir: Path, timeout: float = 20.0) -> None:
    files = {
        "cat.png": f"{DPETS_RAW}/src/Graphics/cat.png",
        "sprite.png": f"{DPETS_RAW}/src/Graphics/sprite.png",
        "README.md": f"{DPETS_RAW}/README.md",
        "LICENSE": f"{DPETS_RAW}/LICENSE",
    }
    source_dir.mkdir(parents=True, exist_ok=True)
    for name, url in files.items():
        request = urllib.request.Request(url, headers={"User-Agent": "MascotMateDesktop/1.0"})
        with urllib.request.urlopen(request, timeout=timeout) as response:
            (source_dir / name).write_bytes(response.read())


def split_sprite_sheet(path: Path) -> list[Image.Image]:
    image = Image.open(path).convert("RGBA")
    if image.width % 4 != 0:
        raise ValueError(f"Sprite sheet width must be divisible by 4: {path}")
    frame_w = image.width // 4
    frames: list[Image.Image] = []
    for index in range(4):
        frame = image.crop((index * frame_w, 0, (index + 1) * frame_w, image.height))
        frames.append(_normalize_frame(frame))
    return frames


def _normalize_frame(frame: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    scale = min(3, max(1, 112 // max(frame.width, frame.height)))
    scaled = frame.resize((frame.width * scale, frame.height * scale), Image.Resampling.NEAREST)
    x = (canvas.width - scaled.width) // 2
    y = canvas.height - scaled.height - 12
    canvas.alpha_composite(scaled, (x, y))
    return canvas


def _used_rect(image: Image.Image) -> list[int]:
    bbox = image.getchannel("A").getbbox() or (0, 0, image.width, image.height)
    left, top, right, bottom = bbox
    return [left, top, right - left, bottom - top]


def _write_action(
    skin_root: Path,
    actions: dict[str, Any],
    action_id: str,
    name: str,
    source_frames: list[Image.Image],
    frame_indices: list[int],
    fps: float,
    *,
    mirror: bool = False,
    velocity_x: float = 0.0,
) -> None:
    frames: list[str] = []
    used_rects: list[list[int]] = []
    anchors: list[list[int]] = []
    velocities: list[list[float]] = []
    durations: list[int] = []
    for out_index, frame_index in enumerate(frame_indices, start=1):
        image = source_frames[frame_index]
        if mirror:
            image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        rel = Path(action_id) / f"{out_index:03d}.png"
        output = skin_root / "frames" / rel
        output.parent.mkdir(parents=True, exist_ok=True)
        image.save(output)
        frames.append(str(rel).replace("\\", "/"))
        used_rects.append(_used_rect(image))
        anchors.append([64, 116])
        velocities.append([velocity_x, 0.0])
        durations.append(round(1000 / fps))
    actions[action_id] = {
        "name": name,
        "resource": action_id,
        "size": [128, 128],
        "fps": fps,
        "loop": True,
        "loop_start": -1,
        "next_action": "",
        "frames": frames,
        "durations_ms": durations,
        "anchors": anchors,
        "velocities": velocities,
        "used_rects": used_rects,
    }
    if mirror:
        actions[action_id]["mirror_x"] = True


def build_skin(sample: dict[str, Any], source_dir: Path, temp_root: Path) -> Path:
    skin_id = str(sample["id"])
    skin_root = temp_root / skin_id
    frames = split_sprite_sheet(source_dir / str(sample["sprite"]))
    actions: dict[str, Any] = {}
    _write_action(skin_root, actions, "idle", "Idle", frames, [0, 1], 3.0)
    _write_action(skin_root, actions, "walk_left", "Walk left", frames, [0, 1, 2, 3], 8.0, velocity_x=-2.0)
    _write_action(skin_root, actions, "walk_right", "Walk right", frames, [0, 1, 2, 3], 8.0, mirror=True, velocity_x=2.0)
    _write_action(skin_root, actions, "fall", "Fall", frames, [2], 3.0)
    _write_action(skin_root, actions, "held", "Held", frames, [1], 3.0)
    _write_action(skin_root, actions, "edge", "Edge hold", frames, [0], 3.0)
    _write_action(skin_root, actions, "playful", "Playful", frames, [2, 3], 5.0)
    skin = {
        "schema_version": SCHEMA_VERSION,
        "version": 1,
        "id": skin_id,
        "name": sample["name"],
        "description": sample["description"],
        "metadata": {
            "package_version": "1.0.0",
            "authors": [{"name": "Gustavo dos Santos / Denellyne"}],
            "compatibility_level": "minimal",
            "compatibility_score": 0,
        },
        "preview": "idle/001.png",
        "frame_root": "frames",
        "license": {
            "type": "MIT + attribution",
            "summary": "Adapted from DPets sprites by Gustavo dos Santos / Denellyne. DPets README says the two bundled sprites are free to use with credit.",
            "redistributable": True,
        },
        "source": {
            "format": "dpets-sprite-sheet",
            "project": "DPets",
            "project_url": "https://github.com/Denellyne/DPets",
            "sprite": str(sample["sprite"]),
        },
        "behavior_profile": {
            "version": 1,
            "modes": {
                "活泼": {
                    "actions": [
                        {"type": "action", "name": "walk", "weight": 3.0},
                        {"type": "action", "name": "idle", "weight": 2.0},
                    ],
                },
            },
        },
        "capabilities": {
            "resting": [{"action": "idle", "score": 100}],
            "locomotion": [
                {"action": "walk_left", "score": 96, "direction": "left"},
                {"action": "walk_right", "score": 96, "direction": "right"},
            ],
            "falling": [{"action": "fall", "score": 90}],
            "held": [{"action": "held", "score": 90}],
            "edge": [{"action": "edge", "score": 82, "direction": "left"}],
            "playful": [{"action": "playful", "score": 88}],
            "reaction": [{"action": "idle", "score": 70}],
        },
        "fallbacks": {
            "locomotion": "resting",
            "falling": "resting",
            "held": "resting",
            "sleeping": "resting",
            "waking": "resting",
            "feeding": "playful",
            "playful": "resting",
            "mischief": "playful",
            "edge": "locomotion",
            "reaction": "resting",
        },
        "actions": actions,
    }
    validation = validate_skin_manifest(skin, skin_root / "skin.json", ROOT)
    if validation["errors"]:
        raise SystemExit(f"{skin_id} failed validation: {validation['errors']}")
    skin = apply_quality_metadata(skin, validation)
    (skin_root / "skin.json").write_text(json.dumps(skin, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return skin_root


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


def write_notices(source_dir: Path) -> None:
    NOTICE_DIR.mkdir(parents=True, exist_ok=True)
    for name in ("README.md", "LICENSE"):
        source = source_dir / name
        if source.is_file():
            shutil.copy2(source, NOTICE_DIR / name)
    notice = (
        "DPets featured skins\n"
        "=====================\n\n"
        "The two bundled featured skins are adapted from the two sprites included with DPets.\n"
        "Credit: Gustavo dos Santos / Denellyne, https://github.com/Denellyne/DPets\n"
        "The original README states that these two sprites are free to use as long as credit is given.\n"
    )
    (NOTICE_DIR / "NOTICE.txt").write_text(notice, encoding="utf-8")


def generate_catalog(source_dir: Path, catalog_root: Path = CATALOG_ROOT) -> list[dict[str, Any]]:
    preview_dir = catalog_root / "previews"
    package_dir = catalog_root / "packages"
    preview_dir.mkdir(parents=True, exist_ok=True)
    package_dir.mkdir(parents=True, exist_ok=True)
    for path in preview_dir.glob("*.png"):
        path.unlink()
    for path in package_dir.glob("*.zip"):
        path.unlink()

    entries: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="mascotmate-dpets-") as temp_dir:
        temp_root = Path(temp_dir)
        for sample in FEATURED_SKINS:
            skin_root = build_skin(sample, source_dir, temp_root)
            preview_path = preview_dir / f"{sample['id']}.png"
            shutil.copyfile(skin_root / "frames" / "idle" / "001.png", preview_path)
            package_path = package_dir / f"{sample['id']}.zip"
            write_deterministic_zip(skin_root, package_path)
            entries.append({
                "id": sample["id"],
                "source_type": "curated_package",
                "name": sample["name"],
                "description": sample["description"],
                "tags": sample["tags"],
                "license": {
                    "type": "MIT + attribution",
                    "summary": "Adapted from DPets sprites by Gustavo dos Santos / Denellyne. Credit required by the DPets README.",
                    "redistributable": True,
                },
                "format": "mascotmate_skin_zip",
                "preview": f"previews/{sample['id']}.png",
                "package": f"packages/{sample['id']}.zip",
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, help="Use an existing DPets source directory instead of downloading.")
    parser.add_argument("--catalog-root", type=Path, default=CATALOG_ROOT)
    parser.add_argument("--timeout", type=float, default=20.0)
    args = parser.parse_args()

    if args.source_dir is None:
        source_dir = args.catalog_root / "sources" / "dpets"
        download_sources(source_dir, args.timeout)
    else:
        source_dir = args.source_dir
    missing = [name for name in ("cat.png", "sprite.png") if not (source_dir / name).is_file()]
    if missing:
        raise SystemExit("Missing DPets source files: " + ", ".join(missing))
    entries = generate_catalog(source_dir, args.catalog_root)
    if args.catalog_root == CATALOG_ROOT:
        write_notices(source_dir)
    print(f"Generated {len(entries)} featured skins in {args.catalog_root.relative_to(ROOT) if args.catalog_root.is_relative_to(ROOT) else args.catalog_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
