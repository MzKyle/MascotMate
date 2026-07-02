#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "godot_pet" / "assets" / "actions.json"
SKIN_OUT = ROOT / "godot_pet" / "assets" / "skins" / "classic_shinchan" / "skin.json"
NUMBER_RE = re.compile(r"(\d+)")


def natural_key(path: Path) -> list[tuple[int, int | str]]:
    parts: list[tuple[int, int | str]] = []
    for part in NUMBER_RE.split(path.name):
        if not part:
            continue
        parts.append((1, int(part)) if part.isdigit() else (0, part.casefold()))
    return parts


def frame_files(relative_dir: str) -> list[Path]:
    root = ROOT / "resource_hd" / relative_dir
    return sorted(root.glob("*.png"), key=natural_key)


def frames(relative_dir: str) -> list[str]:
    return [str(Path(relative_dir) / path.name) for path in frame_files(relative_dir)]


def used_rects(relative_dir: str) -> list[list[int]]:
    rects: list[list[int]] = []
    for path in frame_files(relative_dir):
        with Image.open(path) as image:
            rgba = image.convert("RGBA")
            bbox = rgba.getchannel("A").getbbox()
            if bbox is None:
                rects.append([0, 0, rgba.width, rgba.height])
            else:
                left, top, right, bottom = bbox
                rects.append([left, top, right - left, bottom - top])
    return rects


def action(
    name: str,
    resource: str,
    size: tuple[int, int],
    fps: float,
    loop: bool = True,
    loop_start: int = -1,
    next_action: str = "",
) -> dict:
    return {
        "name": name,
        "resource": resource,
        "size": list(size),
        "fps": fps,
        "loop": loop,
        "loop_start": loop_start,
        "next_action": next_action,
        "frames": frames(resource),
        "used_rects": used_rects(resource),
    }


def build_manifest() -> dict:
    return {
        "version": 1,
        "actions": {
            "idle": action("闲置", "xianzhi", (130, 130), 10.0),
            "walk_left": action("向左散步", "sanbu/zuo", (130, 130), 10.0),
            "walk_right": action("向右散步", "sanbu/you", (130, 130), 10.0),
            "mischief_grab": action("费力抢鼠标", "mischief_grab", (190, 160), 8.0),
            "fall": action("下落", "xialuo", (150, 150), 30.0, next_action="idle"),
            "exercise": action("运动", "yundong", (150, 180), 8.0),
            "eat": action("吃饭", "eat", (160, 90), 40.0, loop=True, loop_start=122),
            "sleep": action("睡觉", "sleep", (162, 149), 50.0, loop=False),
            "wake": action("唤醒", "waken", (162, 149), 33.0, loop=False, next_action="idle"),
            "pipi": action("屁屁舞", "pipi", (300, 130), 40.0),
            "transform": action("动感光波", "xiandanchaoren", (160, 130), 60.0),
            "snack": action("偷吃宵夜", "snack", (400, 200), 50.0, loop=False, next_action="sleep"),
            "meet": action("见到小白", "meet", (150, 150), 30.0, loop=False, next_action="idle"),
            "xiaobai": action("小白", "xiaobai", (125, 85), 50.0),
        },
    }


def candidate(action_id: str, score: float = 100.0, **metadata: object) -> dict:
    value = {"action": action_id, "score": score}
    value.update(metadata)
    return value


def build_skin_manifest(actions_manifest: dict) -> dict:
    actions = actions_manifest["actions"]
    idle_frames = actions.get("idle", {}).get("frames", [])
    preview = idle_frames[0] if idle_frames else ""
    return {
        "version": 1,
        "id": "classic_shinchan",
        "name": "蜡笔小新默认皮肤",
        "description": "项目内置蜡笔小新动作资源，作为旧资源管线的兼容默认皮肤。",
        "preview": preview,
        "frame_root": "$repo/resource_hd",
        "license": {
            "type": "local-personal-use",
            "summary": "部分角色资源仅用于本地个人测试；公开发行请替换为授权或原创素材。",
        },
        "capabilities": {
            "resting": [candidate("idle", 120.0)],
            "locomotion": [
                candidate("walk_left", 120.0, direction="left"),
                candidate("walk_right", 120.0, direction="right"),
                candidate("exercise", 70.0),
            ],
            "falling": [candidate("fall", 120.0)],
            "held": [candidate("idle", 90.0)],
            "sleeping": [candidate("sleep", 120.0)],
            "waking": [candidate("wake", 120.0)],
            "feeding": [candidate("eat", 120.0)],
            "playful": [
                candidate("pipi", 120.0),
                candidate("exercise", 95.0),
                candidate("meet", 80.0),
            ],
            "mischief": [
                candidate("mischief_grab", 120.0),
                candidate("snack", 90.0),
            ],
            "edge": [
                candidate("walk_left", 100.0, direction="left"),
                candidate("walk_right", 100.0, direction="right"),
            ],
            "reaction": [
                candidate("transform", 110.0),
                candidate("meet", 90.0),
                candidate("idle", 50.0),
            ],
            "companion": [candidate("xiaobai", 100.0)],
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
            "companion": "resting",
        },
        "actions": actions,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Exit non-zero if generated manifests are out of date.")
    args = parser.parse_args()

    manifest = build_manifest()
    manifest_text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    skin_manifest = build_skin_manifest(manifest)
    skin_manifest_text = json.dumps(skin_manifest, ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not OUT.exists():
            print(f"Missing {OUT}", file=sys.stderr)
            return 1
        current = OUT.read_text(encoding="utf-8")
        if current != manifest_text:
            print(f"{OUT} is out of date. Run scripts/generate_godot_manifest.py.", file=sys.stderr)
            return 1
        if not SKIN_OUT.exists():
            print(f"Missing {SKIN_OUT}", file=sys.stderr)
            return 1
        current_skin = SKIN_OUT.read_text(encoding="utf-8")
        if current_skin != skin_manifest_text:
            print(f"{SKIN_OUT} is out of date. Run scripts/generate_godot_manifest.py.", file=sys.stderr)
            return 1
        print(f"{OUT} is up to date.")
        print(f"{SKIN_OUT} is up to date.")
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(manifest_text, encoding="utf-8")
    SKIN_OUT.parent.mkdir(parents=True, exist_ok=True)
    SKIN_OUT.write_text(skin_manifest_text, encoding="utf-8")
    print(f"Wrote {OUT}")
    print(f"Wrote {SKIN_OUT}")
    for key, value in manifest["actions"].items():
        print(f"{key}: {len(value['frames'])} frames")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
