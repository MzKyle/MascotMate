#!/usr/bin/env python3
"""Generate bundled sample skins for the curated online catalog."""

from __future__ import annotations

import hashlib
import json
import shutil
import tempfile
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw

from skin_sdk import SCHEMA_VERSION, apply_quality_metadata, validate_skin_manifest


ROOT = Path(__file__).resolve().parent.parent
CATALOG_ROOT = ROOT / "skin_catalog"
PREVIEW_DIR = CATALOG_ROOT / "previews"
PACKAGE_DIR = CATALOG_ROOT / "packages"
ZIP_DATE = (2026, 7, 3, 0, 0, 0)


SAMPLES = [
    {
        "id": "mint_buddy",
        "name": "Mint Buddy",
        "description": "A calm mint desktop companion with soft idle and walk frames.",
        "base": (89, 197, 160, 255),
        "accent": (34, 132, 105, 255),
        "highlight": (239, 255, 247, 255),
        "tags": ["sample", "fresh", "soft"],
    },
    {
        "id": "sunny_pixel",
        "name": "Sunny Pixel",
        "description": "A bright pixel-style sample skin for testing online downloads.",
        "base": (248, 199, 82, 255),
        "accent": (227, 110, 67, 255),
        "highlight": (255, 248, 203, 255),
        "tags": ["sample", "bright", "pixel"],
    },
]


def draw_frame(path: Path, sample: dict, pose: str, step: int) -> list[int]:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    base = sample["base"]
    accent = sample["accent"]
    highlight = sample["highlight"]
    x_shift = 0
    y_shift = 0
    angle_mark = 0
    if pose == "idle":
        y_shift = -2 if step % 2 else 0
    elif pose == "walk":
        x_shift = -4 + step * 3
        y_shift = -2 if step == 1 else 0
    elif pose == "fall":
        angle_mark = 1
        x_shift = 6
        y_shift = 10
    elif pose == "held":
        y_shift = -8
    elif pose == "edge":
        x_shift = -10
        y_shift = -2
    elif pose == "playful":
        x_shift = 5 if step % 2 else -5
        y_shift = -6

    cx = 64 + x_shift
    cy = 70 + y_shift
    draw.ellipse((30, 104, 98, 115), fill=(31, 41, 55, 42))
    draw.ellipse((cx - 34, cy - 38, cx + 34, cy + 34), fill=base)
    draw.ellipse((cx - 20, cy - 56, cx - 2, cy - 32), fill=base)
    draw.ellipse((cx + 2, cy - 56, cx + 20, cy - 32), fill=base)
    draw.ellipse((cx - 22, cy - 20, cx - 12, cy - 10), fill=(29, 45, 61, 255))
    draw.ellipse((cx + 12, cy - 20, cx + 22, cy - 10), fill=(29, 45, 61, 255))
    draw.arc((cx - 15, cy - 10, cx + 15, cy + 12), 20, 160, fill=(29, 45, 61, 255), width=3)
    draw.ellipse((cx - 16, cy + 10, cx + 16, cy + 28), fill=accent)
    draw.ellipse((cx - 20, cy - 34, cx - 4, cy - 20), fill=highlight)
    draw.line((cx - 36, cy - 3, cx - 50, cy + 6 + angle_mark * 12), fill=accent, width=5)
    draw.line((cx + 36, cy - 3, cx + 50, cy + 6 - angle_mark * 6), fill=accent, width=5)
    draw.line((cx - 16, cy + 32, cx - 26, cy + 46 + (step % 2) * 4), fill=accent, width=6)
    draw.line((cx + 16, cy + 32, cx + 26, cy + 46 + ((step + 1) % 2) * 4), fill=accent, width=6)
    if pose == "edge":
        draw.rounded_rectangle((18, 32, 24, 110), radius=3, fill=(68, 96, 125, 230))
    if pose == "playful":
        draw.ellipse((94, 28, 106, 40), fill=(96, 165, 250, 230))
        draw.ellipse((20, 34, 30, 44), fill=(251, 113, 133, 230))
    image.save(path)
    bbox = image.getchannel("A").getbbox() or (0, 0, image.width, image.height)
    left, top, right, bottom = bbox
    return [left, top, right - left, bottom - top]


def add_action(
    skin_root: Path,
    sample: dict,
    actions: dict,
    action_id: str,
    name: str,
    pose: str,
    count: int,
    fps: float,
    velocity_x: float = 0.0,
) -> None:
    frames: list[str] = []
    used_rects: list[list[int]] = []
    anchors: list[list[int]] = []
    velocities: list[list[float]] = []
    durations: list[int] = []
    for index in range(1, count + 1):
        rel = Path(action_id) / f"{index:03d}.png"
        frame_path = skin_root / "frames" / rel
        used_rects.append(draw_frame(frame_path, sample, pose, index - 1))
        frames.append(str(rel).replace("\\", "/"))
        anchors.append([64, 112])
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


def build_skin(sample: dict, temp_root: Path) -> Path:
    skin_id = sample["id"]
    skin_root = temp_root / skin_id
    actions: dict = {}
    add_action(skin_root, sample, actions, "idle", "Idle", "idle", 2, 3.0)
    add_action(skin_root, sample, actions, "walk_left", "Walk left", "walk", 3, 7.0, -2.0)
    add_action(skin_root, sample, actions, "fall", "Fall", "fall", 1, 2.0)
    add_action(skin_root, sample, actions, "held", "Held", "held", 1, 2.0)
    add_action(skin_root, sample, actions, "edge", "Edge hold", "edge", 1, 2.0)
    add_action(skin_root, sample, actions, "playful", "Playful", "playful", 2, 4.0)
    skin = {
        "schema_version": SCHEMA_VERSION,
        "version": 1,
        "id": skin_id,
        "name": sample["name"],
        "description": sample["description"],
        "metadata": {
            "package_version": "1.0.0",
            "authors": [{"name": "MascotMate Desktop"}],
            "compatibility_level": "minimal",
            "compatibility_score": 0,
        },
        "preview": "idle/001.png",
        "frame_root": "frames",
        "license": {
            "type": "CC0-1.0",
            "summary": "Original procedural sample skin generated for MascotMate Desktop.",
            "redistributable": True,
        },
        "source": {
            "format": "mascotmate-sample",
            "image_set": skin_id,
        },
        "behavior_profile": {
            "version": 1,
            "modes": {
                "活泼": {
                    "actions": [
                        {"type": "action", "name": "walk", "weight": 3.0},
                        {"type": "action", "name": "idle", "weight": 2.0},
                    ],
                }
            },
        },
        "capabilities": {
            "resting": [{"action": "idle", "score": 100}],
            "locomotion": [{"action": "walk_left", "score": 95, "direction": "left"}],
            "falling": [{"action": "fall", "score": 90}],
            "held": [{"action": "held", "score": 90}],
            "edge": [{"action": "edge", "score": 80, "direction": "left"}],
            "playful": [{"action": "playful", "score": 80}],
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


def main() -> int:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    PACKAGE_DIR.mkdir(parents=True, exist_ok=True)
    for path in PREVIEW_DIR.glob("*.png"):
        path.unlink()
    for path in PACKAGE_DIR.glob("*.zip"):
        path.unlink()

    entries = []
    with tempfile.TemporaryDirectory(prefix="mascotmate-samples-") as temp_dir:
        temp_root = Path(temp_dir)
        for sample in SAMPLES:
            skin_root = build_skin(sample, temp_root)
            preview_path = PREVIEW_DIR / f"{sample['id']}.png"
            shutil.copyfile(skin_root / "frames" / "idle" / "001.png", preview_path)
            package_path = PACKAGE_DIR / f"{sample['id']}.zip"
            write_deterministic_zip(skin_root, package_path)
            entries.append({
                "id": sample["id"],
                "source_type": "curated_package",
                "name": sample["name"],
                "description": sample["description"],
                "tags": sample["tags"],
                "license": {
                    "type": "CC0-1.0",
                    "summary": "Original procedural sample skin generated for MascotMate Desktop.",
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
    (CATALOG_ROOT / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {len(entries)} sample skins in {CATALOG_ROOT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
