#!/usr/bin/env python3
"""Skin package validation, normalization, and compatibility scoring."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from PIL import Image, UnidentifiedImageError


SCHEMA_VERSION = 2
CORE_CAPABILITIES = ["resting", "locomotion", "falling", "held", "edge"]
REQUIRED_V2_FIELDS = [
    "schema_version",
    "id",
    "name",
    "metadata",
    "frame_root",
    "preview",
    "license",
    "capabilities",
    "fallbacks",
    "actions",
]
COMPATIBILITY_LEVELS = ["minimal", "partial", "good", "excellent"]


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def is_safe_relative_png(path_text: str) -> bool:
    path = Path(path_text)
    return (
        path_text != ""
        and not path.is_absolute()
        and ".." not in path.parts
        and path.suffix.lower() == ".png"
    )


def normalize_skin_manifest(source: dict[str, Any]) -> dict[str, Any]:
    skin = json.loads(json.dumps(source))
    if "schema_version" not in skin:
        skin["schema_version"] = int(skin.get("version", 1) or 1)
    skin.setdefault("version", 1)
    skin.setdefault("description", "")
    skin.setdefault("preview", "")
    skin.setdefault("frame_root", "")
    skin.setdefault("capabilities", {})
    skin.setdefault("fallbacks", {})
    skin.setdefault("actions", {})
    skin.setdefault("source", {})
    metadata = skin.setdefault("metadata", {})
    if not isinstance(metadata, dict):
        metadata = {}
        skin["metadata"] = metadata
    metadata.setdefault("package_version", "1.0.0")
    metadata.setdefault("authors", [])
    metadata.setdefault("compatibility_level", "minimal")
    metadata.setdefault("compatibility_score", 0)
    license_info = skin.setdefault("license", {})
    if not isinstance(license_info, dict):
        license_info = {"type": str(license_info)}
        skin["license"] = license_info
    license_info.setdefault("type", "unknown")
    license_info.setdefault("summary", str(license_info.get("type", "unknown")))
    license_info.setdefault("redistributable", False)
    return skin


def resolve_frame_root(skin: dict[str, Any], skin_path: Path, repo_root: Path) -> Path:
    frame_root = str(skin.get("frame_root", ""))
    if frame_root.startswith("$repo/"):
        return repo_root / frame_root.removeprefix("$repo/")
    if frame_root.startswith("$config/"):
        return Path.home() / ".config" / "crayon-shinchan-desktop-pet" / frame_root.removeprefix("$config/")
    path = Path(frame_root)
    if path.is_absolute():
        return path
    return skin_path.parent / frame_root


def score_to_level(score: int) -> str:
    if score >= 90:
        return "excellent"
    if score >= 72:
        return "good"
    if score >= 45:
        return "partial"
    return "minimal"


def validate_skin_manifest(
    skin: dict[str, Any],
    skin_path: Path,
    repo_root: Path,
    *,
    check_files: bool = True,
) -> dict[str, Any]:
    normalized = normalize_skin_manifest(skin)
    errors: list[str] = []
    warnings: list[str] = []
    missing_capabilities: list[str] = []
    frame_count = 0
    missing_frames = 0
    mirrored_actions: list[str] = []
    fallback_targets: list[str] = []

    if int(normalized.get("schema_version", 1)) >= SCHEMA_VERSION:
        for field in REQUIRED_V2_FIELDS:
            if field not in skin:
                errors.append(f"Missing required v2 field: {field}")

    actions = normalized.get("actions", {})
    capabilities = normalized.get("capabilities", {})
    fallbacks = normalized.get("fallbacks", {})
    if not isinstance(actions, dict) or not actions:
        errors.append("Skin must contain a non-empty actions object.")
        actions = {}
    if not isinstance(capabilities, dict):
        errors.append("Skin capabilities must be an object.")
        capabilities = {}
    if not isinstance(fallbacks, dict):
        errors.append("Skin fallbacks must be an object.")
        fallbacks = {}

    frame_root = resolve_frame_root(normalized, skin_path, repo_root)
    for capability in CORE_CAPABILITIES:
        candidates = capabilities.get(capability, [])
        if not isinstance(candidates, list) or not candidates:
            missing_capabilities.append(capability)

    for capability, candidates in capabilities.items():
        if not isinstance(candidates, list) or not candidates:
            warnings.append(f"Capability {capability} has no candidates.")
            continue
        for candidate in candidates:
            if not isinstance(candidate, dict):
                errors.append(f"Capability {capability} candidate must be an object.")
                continue
            action_id = str(candidate.get("action", ""))
            if action_id not in actions:
                errors.append(f"Capability {capability} references missing action: {action_id}")

    _validate_fallbacks(fallbacks, capabilities, warnings)

    for action_id, action in actions.items():
        if not isinstance(action, dict):
            errors.append(f"Action {action_id} must be an object.")
            continue
        frames = action.get("frames", [])
        if not isinstance(frames, list) or not frames:
            errors.append(f"Action {action_id} has no frames.")
            continue
        anchors = action.get("anchors", [])
        durations = action.get("durations_ms", [])
        velocities = action.get("velocities", [])
        used_rects = action.get("used_rects", [])
        _validate_optional_sequence_length(action_id, "anchors", anchors, frames, errors)
        _validate_optional_sequence_length(action_id, "durations_ms", durations, frames, errors)
        _validate_optional_sequence_length(action_id, "velocities", velocities, frames, errors)
        _validate_optional_sequence_length(action_id, "used_rects", used_rects, frames, errors)
        if bool(action.get("mirror_x", False)):
            mirrored_actions.append(str(action_id))
        fallback_targets.extend(_fallback_marker_for_action(action_id, capabilities))
        for index, frame in enumerate(frames):
            if not isinstance(frame, str) or not is_safe_relative_png(frame):
                errors.append(f"Action {action_id} has unsafe frame path: {frame!r}")
                continue
            frame_count += 1
            image_size: tuple[int, int] | None = None
            if check_files:
                frame_path = frame_root / frame
                if not frame_path.is_file():
                    errors.append(f"Missing skin frame for {action_id}: {frame}")
                    missing_frames += 1
                    continue
                image_size = _verify_png(frame_path, errors)
            if isinstance(used_rects, list) and index < len(used_rects):
                _validate_used_rect(action_id, index, used_rects[index], image_size, errors)

    preview = str(normalized.get("preview", ""))
    if preview:
        if not is_safe_relative_png(preview):
            errors.append(f"Preview must be a safe relative PNG path: {preview!r}")
        elif check_files and not (frame_root / preview).is_file():
            warnings.append(f"Preview frame is missing: {preview}")
    else:
        warnings.append("Skin has no preview frame.")

    coverage = {
        capability: capability in capabilities
        and isinstance(capabilities.get(capability), list)
        and len(capabilities.get(capability, [])) > 0
        for capability in CORE_CAPABILITIES
    }
    score = 100
    score -= len(missing_capabilities) * 14
    score -= min(30, len(errors) * 10)
    score -= min(18, len(warnings) * 3)
    score -= min(12, missing_frames * 2)
    fallback_count = len(set(fallback_targets))
    score -= min(10, fallback_count * 2)
    score = max(0, min(100, score))
    level = score_to_level(score)

    return {
        "schema_version": int(normalized.get("schema_version", 1)),
        "score": score,
        "level": level,
        "errors": errors,
        "warnings": warnings,
        "capability_coverage": coverage,
        "missing_capabilities": missing_capabilities,
        "action_count": len(actions),
        "frame_count": frame_count,
        "missing_frame_count": missing_frames,
        "mirrored_actions": sorted(set(mirrored_actions)),
        "fallback_actions": sorted(set(fallback_targets)),
    }


def apply_quality_metadata(skin: dict[str, Any], validation: dict[str, Any]) -> dict[str, Any]:
    normalized = normalize_skin_manifest(skin)
    metadata = normalized.setdefault("metadata", {})
    metadata["compatibility_level"] = validation["level"]
    metadata["compatibility_score"] = validation["score"]
    metadata["capability_coverage"] = validation["capability_coverage"]
    metadata["missing_capabilities"] = validation["missing_capabilities"]
    return normalized


def _validate_optional_sequence_length(
    action_id: str,
    field: str,
    value: Any,
    frames: list[Any],
    errors: list[str],
) -> None:
    if value in (None, []):
        return
    if not isinstance(value, list):
        errors.append(f"Action {action_id} {field} must be a list.")
        return
    if len(value) != len(frames):
        errors.append(f"Action {action_id} {field} length must match frames length.")


def _validate_fallbacks(fallbacks: dict[str, Any], capabilities: dict[str, Any], warnings: list[str]) -> None:
    for source in fallbacks.keys():
        visited: set[str] = set()
        cursor = str(source)
        while cursor:
            if cursor in visited:
                warnings.append(f"Fallback chain contains a loop at capability: {cursor}")
                break
            visited.add(cursor)
            target = str(fallbacks.get(cursor, ""))
            if target == "":
                break
            if target not in capabilities and target not in fallbacks:
                warnings.append(f"Fallback {cursor} points to unknown capability: {target}")
                break
            cursor = target


def _fallback_marker_for_action(action_id: str, capabilities: dict[str, Any]) -> list[str]:
    result: list[str] = []
    for capability, candidates in capabilities.items():
        if not isinstance(candidates, list):
            continue
        for candidate in candidates:
            if not isinstance(candidate, dict):
                continue
            if candidate.get("action") == action_id and float(candidate.get("score", 0.0)) <= 30.0:
                result.append(str(capability))
    return result


def _validate_used_rect(
    action_id: str,
    index: int,
    value: Any,
    image_size: tuple[int, int] | None,
    errors: list[str],
) -> None:
    if not isinstance(value, list) or len(value) < 4:
        errors.append(f"Action {action_id} used_rects[{index}] must be [x, y, width, height].")
        return
    try:
        x, y, width, height = [int(value[offset]) for offset in range(4)]
    except (TypeError, ValueError):
        errors.append(f"Action {action_id} used_rects[{index}] must contain integers.")
        return
    if x < 0 or y < 0 or width <= 0 or height <= 0:
        errors.append(f"Action {action_id} used_rects[{index}] has invalid bounds.")
        return
    if image_size is not None and (x + width > image_size[0] or y + height > image_size[1]):
        errors.append(f"Action {action_id} used_rects[{index}] exceeds frame size.")


def _verify_png(path: Path, errors: list[str]) -> tuple[int, int] | None:
    try:
        with Image.open(path) as image:
            size = image.size
            image.verify()
            if image.format != "PNG":
                errors.append(f"Not a PNG image: {path}")
                return None
            return size
    except (OSError, UnidentifiedImageError) as exc:
        errors.append(f"Cannot read PNG {path}: {exc}")
    return None
