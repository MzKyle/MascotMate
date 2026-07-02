#!/usr/bin/env python3
"""Validate Godot pet runtime resources and generated manifests."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, UnidentifiedImageError


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


def is_safe_relative_png(path_text: str) -> bool:
    path = Path(path_text)
    return (
        path_text != ""
        and not path.is_absolute()
        and ".." not in path.parts
        and path.suffix.lower() == ".png"
    )


def verify_png(path: Path, errors: list[str]) -> None:
    try:
        with Image.open(path) as image:
            image.verify()
            if image.format != "PNG":
                error(f"Not a PNG image: {path.relative_to(ROOT)}", errors)
    except (OSError, UnidentifiedImageError) as exc:
        error(f"Cannot read PNG {path.relative_to(ROOT)}: {exc}", errors)


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
        resource = action.get("resource", "")
        if not isinstance(resource, str) or resource == "":
            error(f"Action {action_id} has an invalid resource directory.", errors)
        expected_prefix = Path(resource)
        for frame in frames:
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
            verify_png(frame_path, errors)
    return referenced


def resolve_skin_frame_root(skin: dict, skin_path: Path, errors: list[str]) -> Path:
    frame_root = skin.get("frame_root", "")
    if not isinstance(frame_root, str) or frame_root == "":
        error(f"{skin_path.relative_to(ROOT)} has an invalid frame_root.", errors)
        return RESOURCE_ROOT
    if frame_root.startswith("$repo/"):
        return ROOT / frame_root.removeprefix("$repo/")
    if Path(frame_root).is_absolute():
        return Path(frame_root)
    return skin_path.parent / frame_root


def validate_skin_manifest(errors: list[str]) -> None:
    skin = load_json(DEFAULT_SKIN_PATH, errors)
    if not skin:
        return
    for key in ("id", "name", "frame_root", "capabilities", "fallbacks", "actions"):
        if key not in skin:
            error(f"{DEFAULT_SKIN_PATH.relative_to(ROOT)} is missing {key}.", errors)
    capabilities = skin.get("capabilities", {})
    if not isinstance(capabilities, dict) or "resting" not in capabilities:
        error("default skin must define a resting capability.", errors)
    actions = skin.get("actions", {})
    if not isinstance(actions, dict) or not actions:
        error("default skin must contain actions.", errors)
        return
    frame_root = resolve_skin_frame_root(skin, DEFAULT_SKIN_PATH, errors)
    for capability, candidates in capabilities.items():
        if not isinstance(candidates, list) or not candidates:
            error(f"Capability {capability} must contain at least one candidate.", errors)
            continue
        for candidate in candidates:
            if not isinstance(candidate, dict):
                error(f"Capability {capability} candidate must be an object.", errors)
                continue
            action_id = candidate.get("action", "")
            if action_id not in actions:
                error(f"Capability {capability} references missing action: {action_id}", errors)
    for action_id, action in actions.items():
        frames = action.get("frames", []) if isinstance(action, dict) else []
        if not isinstance(frames, list) or not frames:
            error(f"Skin action {action_id} has no frames.", errors)
            continue
        for frame in frames:
            if not isinstance(frame, str) or not is_safe_relative_png(frame):
                error(f"Skin action {action_id} has unsafe frame path: {frame!r}", errors)
                continue
            frame_path = frame_root / frame
            if not frame_path.is_file():
                error(f"Missing skin frame for {action_id}: {frame_path.relative_to(ROOT)}", errors)
                continue
            verify_png(frame_path, errors)


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
