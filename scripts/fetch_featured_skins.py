#!/usr/bin/env python3
"""Fetch Kenney Animal Pack assets and build bundled featured MascotMate skins."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import shutil
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path
from typing import Any

from PIL import Image, ImageFilter

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from skin_sdk import SCHEMA_VERSION, apply_quality_metadata, validate_skin_manifest


ROOT = SCRIPT_DIR.parent
CATALOG_ROOT = ROOT / "skin_catalog"
PREVIEW_DIR = CATALOG_ROOT / "previews"
PACKAGE_DIR = CATALOG_ROOT / "packages"
NOTICE_DIR = CATALOG_ROOT / "notices" / "kenney_animal_pack"
SOURCE_SUBDIR = Path("PNG") / "Round (outline)"
ZIP_DATE = (2026, 7, 3, 0, 0, 0)
KENNEY_ANIMAL_PACK_URL = "https://opengameart.org/sites/default/files/kenney-animalpack.zip"
KENNEY_PROJECT_URL = "https://opengameart.org/content/animal-pack"

FEATURED_SKINS = [
    {
        "id": "kenney_panda",
        "name": "Kenney Panda",
        "description": "A clean high-resolution panda companion adapted from Kenney's CC0 Animal Pack.",
        "sprite": "panda.png",
        "tags": ["featured", "animal", "panda", "kenney", "cc0"],
        "accent": [31, 157, 112],
    },
    {
        "id": "kenney_rabbit",
        "name": "Kenney Rabbit",
        "description": "A bright high-resolution rabbit companion adapted from Kenney's CC0 Animal Pack.",
        "sprite": "rabbit.png",
        "tags": ["featured", "animal", "rabbit", "kenney", "cc0"],
        "accent": [47, 128, 237],
    },
]


def download_sources(source_dir: Path, timeout: float = 30.0) -> None:
    source_dir.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(
        KENNEY_ANIMAL_PACK_URL,
        headers={"User-Agent": "MascotMateDesktop/1.0"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        archive_bytes = response.read()
    archive_path = source_dir / "kenney-animalpack.zip"
    archive_path.write_bytes(archive_bytes)

    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as zf:
        wanted = {
            "License.txt",
            "Preview.png",
            str(SOURCE_SUBDIR / "panda.png").replace("\\", "/"),
            str(SOURCE_SUBDIR / "rabbit.png").replace("\\", "/"),
        }
        for member in zf.infolist():
            member_path = Path(member.filename)
            if member_path.is_absolute() or ".." in member_path.parts:
                raise SystemExit(f"Unsafe path in Kenney archive: {member.filename}")
            if member.filename not in wanted:
                continue
            target = source_dir / member.filename
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(zf.read(member))


def sprite_path(source_dir: Path, name: str) -> Path:
    return source_dir / SOURCE_SUBDIR / name


def _used_rect(image: Image.Image) -> list[int]:
    bbox = image.getchannel("A").getbbox() or (0, 0, image.width, image.height)
    left, top, right, bottom = bbox
    return [left, top, right - left, bottom - top]


def _fit_source(source: Image.Image, max_extent: int) -> Image.Image:
    image = source.convert("RGBA")
    bbox = image.getchannel("A").getbbox()
    if bbox is not None:
        image = image.crop(bbox)
    scale = min(max_extent / image.width, max_extent / image.height)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    return image.resize(size, Image.Resampling.LANCZOS)


def _shadow(sprite: Image.Image) -> Image.Image:
    alpha = sprite.getchannel("A")
    blur = alpha.filter(ImageFilter.GaussianBlur(2.4))
    shadow = Image.new("RGBA", sprite.size, (23, 35, 44, 0))
    shadow.putalpha(blur.point(lambda value: int(value * 0.24)))
    return shadow


def compose_frame(
    source: Image.Image,
    *,
    canvas_size: int = 192,
    max_extent: int = 164,
    offset: tuple[int, int] = (0, 0),
    scale: float = 1.0,
    mirror: bool = False,
    rotate: float = 0.0,
) -> Image.Image:
    sprite = _fit_source(source, round(max_extent * scale))
    if mirror:
        sprite = sprite.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    if rotate:
        sprite = sprite.rotate(rotate, resample=Image.Resampling.BICUBIC, expand=True)
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    x = (canvas_size - sprite.width) // 2 + offset[0]
    y = canvas_size - sprite.height - 14 + offset[1]
    canvas.alpha_composite(_shadow(sprite), (x + 2, y + 4))
    canvas.alpha_composite(sprite, (x, y))
    return canvas


def _variant_frames(source: Image.Image, action_id: str) -> list[Image.Image]:
    if action_id == "idle":
        return [
            compose_frame(source, offset=(0, 0)),
            compose_frame(source, offset=(0, -3), scale=1.01),
            compose_frame(source, offset=(0, 0)),
            compose_frame(source, offset=(0, 2), scale=0.995),
        ]
    if action_id == "walk_left":
        return [
            compose_frame(source, offset=(-5, 1), rotate=-2.0),
            compose_frame(source, offset=(-1, -3), rotate=1.4),
            compose_frame(source, offset=(4, 1), rotate=2.0),
            compose_frame(source, offset=(0, -2), rotate=-1.2),
        ]
    if action_id == "walk_right":
        return [
            compose_frame(source, offset=(5, 1), rotate=2.0, mirror=True),
            compose_frame(source, offset=(1, -3), rotate=-1.4, mirror=True),
            compose_frame(source, offset=(-4, 1), rotate=-2.0, mirror=True),
            compose_frame(source, offset=(0, -2), rotate=1.2, mirror=True),
        ]
    if action_id == "fall":
        return [compose_frame(source, offset=(0, 8), rotate=8.0, scale=0.98)]
    if action_id == "held":
        return [compose_frame(source, offset=(0, -6), rotate=-5.0, scale=0.96)]
    if action_id == "edge":
        return [compose_frame(source, offset=(-12, -2), rotate=-7.0, scale=0.98)]
    if action_id == "sleep":
        return [compose_frame(source, offset=(0, 10), rotate=-11.0, scale=0.92)]
    if action_id == "playful":
        return [
            compose_frame(source, offset=(0, -8), rotate=-6.0, scale=1.02),
            compose_frame(source, offset=(0, -2), rotate=5.0, scale=1.0),
        ]
    return [compose_frame(source)]


def _write_action(
    skin_root: Path,
    actions: dict[str, Any],
    action_id: str,
    name: str,
    source: Image.Image,
    fps: float,
    *,
    velocity_x: float = 0.0,
    mirror: bool = False,
) -> None:
    frames: list[str] = []
    used_rects: list[list[int]] = []
    anchors: list[list[int]] = []
    velocities: list[list[float]] = []
    durations: list[int] = []
    for out_index, image in enumerate(_variant_frames(source, action_id), start=1):
        rel = Path(action_id) / f"{out_index:03d}.png"
        output = skin_root / "frames" / rel
        output.parent.mkdir(parents=True, exist_ok=True)
        image.save(output)
        frames.append(str(rel).replace("\\", "/"))
        used_rects.append(_used_rect(image))
        anchors.append([96, 178])
        velocities.append([velocity_x, 0.0])
        durations.append(round(1000 / fps))
    actions[action_id] = {
        "name": name,
        "resource": action_id,
        "size": [192, 192],
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
    source = Image.open(sprite_path(source_dir, str(sample["sprite"]))).convert("RGBA")
    actions: dict[str, Any] = {}
    _write_action(skin_root, actions, "idle", "Idle", source, 4.0)
    _write_action(skin_root, actions, "walk_left", "Walk left", source, 8.0, velocity_x=-2.0)
    _write_action(skin_root, actions, "walk_right", "Walk right", source, 8.0, velocity_x=2.0, mirror=True)
    _write_action(skin_root, actions, "fall", "Fall", source, 3.0)
    _write_action(skin_root, actions, "held", "Held", source, 3.0)
    _write_action(skin_root, actions, "edge", "Edge hold", source, 3.0)
    _write_action(skin_root, actions, "sleep", "Sleep", source, 2.0)
    _write_action(skin_root, actions, "playful", "Playful", source, 5.0)
    skin = {
        "schema_version": SCHEMA_VERSION,
        "version": 1,
        "id": skin_id,
        "name": sample["name"],
        "description": sample["description"],
        "metadata": {
            "package_version": "1.0.0",
            "authors": [{"name": "Kenney"}],
            "compatibility_level": "minimal",
            "compatibility_score": 0,
        },
        "preview": "idle/001.png",
        "frame_root": "frames",
        "license": {
            "type": "Creative Commons CC0",
            "summary": "Adapted from Kenney Animal Pack. CC0 assets may be redistributed and used in commercial projects.",
            "redistributable": True,
        },
        "source": {
            "format": "kenney-animal-pack",
            "project": "Animal Pack",
            "project_url": KENNEY_PROJECT_URL,
            "download_url": KENNEY_ANIMAL_PACK_URL,
            "sprite": str(SOURCE_SUBDIR / sample["sprite"]).replace("\\", "/"),
        },
        "behavior_profile": {
            "version": 1,
            "modes": {
                "活泼": {
                    "actions": [
                        {"type": "action", "name": "walk", "weight": 3.0},
                        {"type": "action", "name": "idle", "weight": 2.0},
                        {"type": "action", "name": "playful", "weight": 1.0},
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
            "sleeping": [{"action": "sleep", "score": 78}],
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
    for name in ("License.txt", "Preview.png"):
        source = source_dir / name
        if source.is_file():
            shutil.copy2(source, NOTICE_DIR / name)
    notice = (
        "Kenney Animal Pack featured skins\n"
        "===================================\n\n"
        "The bundled featured skins are adapted from Kenney Animal Pack assets.\n"
        f"Source: {KENNEY_PROJECT_URL}\n"
        "License: Creative Commons CC0. Attribution is appreciated but not required.\n"
    )
    (NOTICE_DIR / "NOTICE.txt").write_text(notice, encoding="utf-8")


def cleanup_obsolete_assets(catalog_root: Path) -> None:
    for relative in [
        Path("sources") / "dpets",
        Path("notices") / "dpets",
    ]:
        target = catalog_root / relative
        if target.exists():
            shutil.rmtree(target)


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
    with tempfile.TemporaryDirectory(prefix="mascotmate-kenney-") as temp_dir:
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
                    "type": "Creative Commons CC0",
                    "summary": "Adapted from Kenney Animal Pack. Attribution is appreciated but not required.",
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
    parser.add_argument("--source-dir", type=Path, help="Use an existing Kenney Animal Pack source directory instead of downloading.")
    parser.add_argument("--catalog-root", type=Path, default=CATALOG_ROOT)
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()

    if args.source_dir is None:
        source_dir = args.catalog_root / "sources" / "kenney_animal_pack"
        download_sources(source_dir, args.timeout)
    else:
        source_dir = args.source_dir
    missing = [
        str(SOURCE_SUBDIR / name)
        for name in ("panda.png", "rabbit.png")
        if not sprite_path(source_dir, name).is_file()
    ]
    if missing:
        raise SystemExit("Missing Kenney source files: " + ", ".join(missing))
    cleanup_obsolete_assets(args.catalog_root)
    entries = generate_catalog(source_dir, args.catalog_root)
    if args.catalog_root == CATALOG_ROOT:
        write_notices(source_dir)
    display_root = args.catalog_root.relative_to(ROOT) if args.catalog_root.is_relative_to(ROOT) else args.catalog_root
    print(f"Generated {len(entries)} featured skins in {display_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
