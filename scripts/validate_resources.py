#!/usr/bin/env python3
"""Validate Godot pet runtime resources and generated manifests."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, UnidentifiedImageError

from skin_sdk import (
    is_safe_relative_png,
    validate_skin_manifest as validate_skin_package,
)


ROOT = Path(__file__).resolve().parent.parent
RESOURCE_ROOT = ROOT / "resource_hd"
MANIFEST_PATH = ROOT / "godot_pet" / "assets" / "actions.json"
DEFAULT_SKIN_PATH = ROOT / "godot_pet" / "assets" / "skins" / "classic_shinchan" / "skin.json"
BEHAVIOR_PATH = ROOT / "godot_pet" / "assets" / "behavior.json"


def error(message: str, errors: list[str]) -> None:
    errors.append(message)


def load_json(path: Path, errors: list[str]) -> dict:
    if not path.is_file():
        error(f"Missing {path.relative_to(ROOT)}", errors)
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        error(f"Invalid JSON in {path.relative_to(ROOT)}: {exc}", errors)
        return {}


def verify_png(path: Path, errors: list[str]) -> tuple[int, int] | None:
    try:
        with Image.open(path) as image:
            size = image.size
            image.verify()
            if image.format != "PNG":
                error(f"Not a PNG image: {path.relative_to(ROOT)}", errors)
                return None
            return size
    except (OSError, UnidentifiedImageError) as exc:
        error(f"Cannot read PNG {path.relative_to(ROOT)}: {exc}", errors)
    return None


def validate_used_rect(action_id: str, index: int, value: object, size: tuple[int, int] | None, errors: list[str]) -> None:
    if not isinstance(value, list) or len(value) < 4:
        error(f"Action {action_id} used_rects[{index}] must be [x, y, width, height].", errors)
        return
    try:
        x, y, width, height = [int(value[offset]) for offset in range(4)]
    except (TypeError, ValueError):
        error(f"Action {action_id} used_rects[{index}] must contain integers.", errors)
        return
    if x < 0 or y < 0 or width <= 0 or height <= 0:
        error(f"Action {action_id} used_rects[{index}] has invalid bounds.", errors)
        return
    if size is not None and (x + width > size[0] or y + height > size[1]):
        error(f"Action {action_id} used_rects[{index}] exceeds frame size.", errors)


def validate_actions(manifest: dict, errors: list[str]) -> set[Path]:
    actions = manifest.get("actions", {})
    if not isinstance(actions, dict) or not actions:
        error("actions.json must contain a non-empty actions object.", errors)
        return set()

    referenced: set[Path] = set()
    for action_id, action in actions.items():
        if not isinstance(action, dict):
            error(f"Action {action_id} must be an object.", errors)
            continue
        frames = action.get("frames", [])
        if not isinstance(frames, list) or not frames:
            error(f"Action {action_id} has no frames.", errors)
            continue
        used_rects = action.get("used_rects", [])
        if used_rects and (not isinstance(used_rects, list) or len(used_rects) != len(frames)):
            error(f"Action {action_id} used_rects length must match frames length.", errors)
        resource = action.get("resource", "")
        if not isinstance(resource, str) or resource == "":
            error(f"Action {action_id} has an invalid resource directory.", errors)
        expected_prefix = Path(resource)
        for index, frame in enumerate(frames):
            if not isinstance(frame, str) or not is_safe_relative_png(frame):
                error(f"Action {action_id} has unsafe frame path: {frame!r}", errors)
                continue
            frame_path = RESOURCE_ROOT / frame
            if expected_prefix.parts and not Path(frame).parts[: len(expected_prefix.parts)] == expected_prefix.parts:
                error(f"Action {action_id} frame is outside its resource directory: {frame}", errors)
            if not frame_path.is_file():
                error(f"Missing frame for {action_id}: {frame}", errors)
                continue
            referenced.add(frame_path.resolve())
            size = verify_png(frame_path, errors)
            if isinstance(used_rects, list) and index < len(used_rects):
                validate_used_rect(action_id, index, used_rects[index], size, errors)
    return referenced


def validate_skin_manifest(errors: list[str]) -> None:
    skin = load_json(DEFAULT_SKIN_PATH, errors)
    if not skin:
        return
    result = validate_skin_package(skin, DEFAULT_SKIN_PATH, ROOT)
    for item in result["errors"]:
        error(item, errors)


def validate_resource_coverage(referenced: set[Path], errors: list[str]) -> None:
    if not RESOURCE_ROOT.is_dir():
        error("Missing resource_hd directory.", errors)
        return
    all_pngs = {path.resolve() for path in RESOURCE_ROOT.rglob("*.png")}
    missing_from_manifest = sorted(all_pngs - referenced)
    for path in missing_from_manifest:
        error(f"Unreferenced PNG in resource_hd: {path.relative_to(ROOT)}", errors)


def validate_behavior_config(errors: list[str]) -> None:
    behavior = load_json(BEHAVIOR_PATH, errors)
    modes = behavior.get("modes", {})
    if not isinstance(modes, dict):
        error("behavior.json must contain a modes object.", errors)
        return
    for mode in ("安静", "活泼", "捣乱"):
        if mode not in modes:
            error(f"behavior.json is missing mode: {mode}", errors)
    companion = behavior.get("companion", {})
    if companion and not isinstance(companion, dict):
        error("behavior.json companion must be an object.", errors)
    if isinstance(companion, dict) and "cooldowns" in companion:
        cooldowns = companion.get("cooldowns", {})
        if not isinstance(cooldowns, dict):
            error("behavior.json companion.cooldowns must be an object.", errors)
        else:
            for mode in ("安静", "活泼", "捣乱"):
                if mode in cooldowns:
                    try:
                        value = float(cooldowns[mode])
                    except (TypeError, ValueError):
                        error(f"behavior.json companion cooldown for {mode} must be numeric.", errors)
                        continue
                    if value < 30.0:
                        error(f"behavior.json companion cooldown for {mode} must be at least 30 seconds.", errors)


def main() -> int:
    errors: list[str] = []
    manifest = load_json(MANIFEST_PATH, errors)
    referenced = validate_actions(manifest, errors) if manifest else set()
    validate_resource_coverage(referenced, errors)
    validate_skin_manifest(errors)
    validate_behavior_config(errors)

    if errors:
        print("Resource validation failed:", file=sys.stderr)
        for item in errors:
            print(f"- {item}", file=sys.stderr)
        return 1
    print("Resource validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
