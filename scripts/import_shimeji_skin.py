#!/usr/bin/env python3
"""Import Shimeji-ee image sets into the Godot pet skin format."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from xml.etree import ElementTree

from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from skin_sdk import (
    CORE_CAPABILITIES,
    SCHEMA_VERSION,
    apply_quality_metadata,
    validate_skin_manifest,
)


CONFIG_DIR_NAME = "mascotmate-desktop"
SHIMEJI_DURATION_MS = 40
SAFE_ID_RE = re.compile(r"[^a-z0-9_-]+")
PROJECT_ROOT = Path(__file__).resolve().parent.parent


@dataclass
class Pose:
    image: str
    duration_ms: int
    anchor: list[int]
    velocity: list[float]


@dataclass
class ImportResult:
    path: Path
    report: dict[str, Any]


def natural_key(path: Path) -> list[tuple[int, int | str]]:
    parts: list[tuple[int, int | str]] = []
    for part in re.split(r"(\d+)", path.name):
        if not part:
            continue
        parts.append((1, int(part)) if part.isdigit() else (0, part.casefold()))
    return parts


def safe_id(value: str) -> str:
    normalized = SAFE_ID_RE.sub("-", value.strip().lower()).strip("-")
    return normalized or "shimeji-skin"


def output_root_default() -> Path:
    return Path.home() / ".config" / CONFIG_DIR_NAME / "skins"


def safe_zip_member_path(name: str) -> Path | None:
    normalized = name.replace("\\", "/").strip()
    if normalized in ("", ".", "/"):
        return None
    while normalized.startswith("./"):
        normalized = normalized[2:]
    if normalized in ("", "."):
        return None
    if normalized.startswith("/"):
        raise SystemExit(f"Unsafe path in zip: {name}")
    path = Path(normalized)
    if (
        path.is_absolute()
        or ".." in path.parts
        or any(part == "" for part in path.parts)
        or re.match(r"^[A-Za-z]:", normalized)
    ):
        raise SystemExit(f"Unsafe path in zip: {name}")
    return path


def extract_source(source: Path, temp_root: Path) -> Path:
    if source.is_dir():
        return source
    if not zipfile.is_zipfile(source):
        raise SystemExit(f"Unsupported source: {source}")
    target = temp_root / "source"
    with zipfile.ZipFile(source) as zf:
        for member in zf.infolist():
            member_path = safe_zip_member_path(member.filename)
            if member_path is None:
                continue
            destination = (target / member_path).resolve()
            try:
                destination.relative_to(target.resolve())
            except ValueError as exc:
                raise SystemExit(f"Unsafe path in zip: {member.filename}") from exc
            mode = member.external_attr >> 16
            if mode and (mode & 0o170000) == 0o120000:
                raise SystemExit(f"Unsafe symlink in zip: {member.filename}")
            if member.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(member) as source_file, destination.open("wb") as dest_file:
                shutil.copyfileobj(source_file, dest_file)
    return target


def find_native_skin_manifest(root: Path) -> Path | None:
    direct = root / "skin.json"
    if direct.is_file():
        return direct
    candidates = [
        path
        for path in root.rglob("skin.json")
        if "__MACOSX" not in path.parts and not any(part.startswith(".") for part in path.relative_to(root).parts)
    ]
    if not candidates:
        return None
    return sorted(candidates, key=lambda path: (len(path.relative_to(root).parts), str(path)))[0]


def safe_copytree(source: Path, dest: Path) -> None:
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    for path in sorted(source.rglob("*")):
        rel = path.relative_to(source)
        if "__MACOSX" in rel.parts:
            continue
        if path.is_symlink():
            raise SystemExit(f"Skin package contains a symlink: {rel}")
        target = dest / rel
        if path.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        elif path.is_file():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)


def find_image_sets(root: Path) -> list[Path]:
    candidates: list[Path] = []
    img_dirs = [path for path in root.rglob("img") if path.is_dir()]
    if not img_dirs and any(root.glob("*.png")):
        return [root]
    for img_dir in img_dirs:
        if _looks_like_image_set(img_dir):
            candidates.append(img_dir)
        for child in sorted(img_dir.iterdir(), key=natural_key):
            if child.is_dir() and child.name.lower() != "unused" and _looks_like_image_set(child):
                candidates.append(child)
    seen: set[Path] = set()
    unique: list[Path] = []
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved not in seen:
            seen.add(resolved)
            unique.append(candidate)
    return unique


def _looks_like_image_set(path: Path) -> bool:
    pngs = list(path.glob("*.png"))
    if not pngs:
        return False
    if any(candidate.name.lower().startswith("shime") for candidate in pngs):
        return True
    return (path / "conf" / "actions.xml").is_file()


def find_actions_xml(root: Path, image_set: Path) -> Path | None:
    names = [image_set.name]
    candidates = [
        image_set / "conf" / "actions.xml",
        root / "conf" / image_set.name / "actions.xml",
        root / "conf" / "actions.xml",
    ]
    if image_set.parent.name == "img":
        candidates.append(image_set.parent.parent / "conf" / "actions.xml")
    for name in names:
        candidates.append(root / "conf" / name / "actions.xml")
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def find_behaviors_xml(root: Path, image_set: Path) -> Path | None:
    candidates = [
        image_set / "conf" / "behaviors.xml",
        root / "conf" / image_set.name / "behaviors.xml",
        root / "conf" / "behaviors.xml",
    ]
    if image_set.parent.name == "img":
        candidates.append(image_set.parent.parent / "conf" / "behaviors.xml")
    candidates.append(root / "conf" / image_set.name / "behaviors.xml")
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def attr_value(element: ElementTree.Element, key: str, default: str = "") -> str:
    for attr_key, value in element.attrib.items():
        if attr_key.split("}")[-1] == key:
            return value
    return default


def local_name(element: ElementTree.Element) -> str:
    return element.tag.split("}")[-1]


def parse_pair(value: str, default: tuple[float, float]) -> list[float]:
    parts = [part.strip() for part in value.split(",")]
    if len(parts) < 2:
        return [default[0], default[1]]
    try:
        return [float(parts[0]), float(parts[1])]
    except ValueError:
        return [default[0], default[1]]


def parse_duration(value: str) -> int:
    try:
        raw = int(float(value))
    except ValueError:
        raw = 5
    return max(60, min(10000, raw * SHIMEJI_DURATION_MS))


def parse_actions_xml(path: Path) -> dict[str, list[Pose]]:
    tree = ElementTree.parse(path)
    root = tree.getroot()
    actions: dict[str, list[Pose]] = {}
    for action in root.iter():
        if local_name(action) != "Action":
            continue
        name = attr_value(action, "Name")
        if not name:
            continue
        poses: list[Pose] = []
        for pose_node in action.iter():
            if local_name(pose_node) != "Pose":
                continue
            image = attr_value(pose_node, "Image").lstrip("/")
            if not image:
                continue
            anchor = [int(value) for value in parse_pair(attr_value(pose_node, "ImageAnchor"), (64, 128))]
            velocity = parse_pair(attr_value(pose_node, "Velocity"), (0.0, 0.0))
            poses.append(Pose(
                image=image,
                duration_ms=parse_duration(attr_value(pose_node, "Duration", "5")),
                anchor=anchor,
                velocity=velocity,
            ))
        if poses:
            actions[name] = poses
    return actions


def parse_behaviors_xml(path: Path) -> list[dict[str, Any]]:
    tree = ElementTree.parse(path)
    root = tree.getroot()
    behaviors: list[dict[str, Any]] = []
    for behavior in root.iter():
        if local_name(behavior) != "Behavior":
            continue
        name = attr_value(behavior, "Name")
        if not name:
            continue
        references: list[dict[str, Any]] = []
        for ref in behavior.iter():
            if local_name(ref) != "BehaviorReference":
                continue
            ref_name = attr_value(ref, "Name")
            if not ref_name:
                continue
            references.append({
                "name": ref_name,
                "frequency": _parse_frequency(attr_value(ref, "Frequency", "1"), 1.0),
                "condition": attr_value(ref, "Condition"),
            })
        behaviors.append({
            "name": name,
            "frequency": _parse_frequency(attr_value(behavior, "Frequency", "0"), 0.0),
            "condition": attr_value(behavior, "Condition"),
            "references": references,
        })
    return behaviors


def _parse_frequency(value: str, default: float) -> float:
    try:
        return max(0.0, float(value))
    except ValueError:
        return default


def build_behavior_profile(behaviors: list[dict[str, Any]]) -> tuple[dict[str, Any], dict[str, Any], list[str]]:
    buckets = {
        "walk": 0.0,
        "idle": 0.0,
        "edge": 0.0,
        "mischief": 0.0,
    }
    warnings: list[str] = []
    mapped: list[dict[str, Any]] = []
    for behavior in behaviors:
        names = [str(behavior.get("name", ""))]
        names.extend(str(ref.get("name", "")) for ref in behavior.get("references", []))
        kind = ""
        for candidate in names:
            kind = _behavior_kind(candidate)
            if kind != "":
                break
        if kind == "":
            continue
        frequency = float(behavior.get("frequency", 0.0))
        if frequency <= 0.0:
            frequency = sum(float(ref.get("frequency", 0.0)) for ref in behavior.get("references", []))
        frequency = max(1.0, frequency)
        buckets[kind] += frequency
        mapped.append({
            "source": str(behavior.get("name", "")),
            "kind": kind,
            "weight": round(frequency, 2),
        })
        if str(behavior.get("condition", "")):
            warnings.append("Ignored Shimeji condition on behavior: %s" % behavior.get("name", ""))
        for ref in behavior.get("references", []):
            if str(ref.get("condition", "")):
                warnings.append("Ignored Shimeji condition on behavior reference: %s -> %s" % (
                    behavior.get("name", ""),
                    ref.get("name", ""),
                ))

    active_actions: list[dict[str, Any]] = []
    if buckets["walk"] > 0:
        active_actions.append({"type": "action", "name": "walk", "weight": round(buckets["walk"], 2)})
    if buckets["idle"] > 0:
        active_actions.append({"type": "action", "name": "idle", "weight": round(buckets["idle"], 2)})
    if buckets["edge"] > 0:
        active_actions.append({"type": "action", "name": "edge", "weight": round(buckets["edge"], 2)})
    if buckets["mischief"] > 0:
        active_actions.append({"type": "effect", "name": "footprint", "weight": round(buckets["mischief"], 2)})
    profile: dict[str, Any] = {
        "version": 1,
        "modes": {},
    }
    if active_actions:
        profile["modes"]["活泼"] = {"actions": active_actions}
    if buckets["mischief"] > 0:
        profile["modes"]["捣乱"] = {
            "actions": [{"type": "mischief", "name": "grab", "weight": round(buckets["mischief"], 2)}]
        }
    summary = {
        "mapped": mapped,
        "weights": {key: round(value, 2) for key, value in buckets.items()},
        "behavior_count": len(behaviors),
    }
    return profile, summary, sorted(set(warnings))


def _behavior_kind(name: str) -> str:
    lower = name.lower()
    if any(token in lower for token in ["throw", "pull", "split", "chase", "ie"]):
        return "mischief"
    if any(token in lower for token in ["wall", "ceiling", "edge", "climb", "grab"]):
        return "edge"
    if any(token in lower for token in ["walk", "run", "crawl"]):
        return "walk"
    if any(token in lower for token in ["stand", "sit", "lie", "look", "face", "sprawl"]):
        return "idle"
    return ""


def fallback_standard_actions(image_set: Path) -> dict[str, list[Pose]]:
    def pose(name: str, duration: int = 180, velocity: tuple[float, float] = (0.0, 0.0)) -> Pose:
        return Pose(name, duration, [64, 128], [velocity[0], velocity[1]])

    png_names = {path.name for path in image_set.glob("*.png")}
    actions: dict[str, list[Pose]] = {}
    if "shime1.png" in png_names:
        actions["Stand"] = [pose("shime1.png", 1000)]
    walk = [name for name in ["shime1.png", "shime2.png", "shime1.png", "shime3.png"] if name in png_names]
    if walk:
        actions["Walk"] = [pose(name, 180, (-2.0, 0.0)) for name in walk]
    for action_name, image_name in [
        ("Fall", "shime4.png"),
        ("Dragged", "shime5.png"),
        ("Thrown", "shime6.png"),
        ("Sit", "shime11.png"),
        ("LieDown", "shime21.png"),
    ]:
        if image_name in png_names:
            actions[action_name] = [pose(image_name, 1000)]
    if not actions:
        first = sorted(image_set.glob("*.png"), key=natural_key)[0]
        actions["Stand"] = [pose(first.name, 1000)]
    return actions


def action_id(source_name: str) -> str:
    return safe_id(source_name.replace("_", "-"))


def classify_action(name: str, poses: list[Pose]) -> list[dict]:
    lower = name.lower()
    avg_vx = sum(pose.velocity[0] for pose in poses) / max(1, len(poses))
    direction = "left" if avg_vx < 0 else "right" if avg_vx > 0 else ""
    frame_bonus = min(25.0, len(poses) * 2.0)
    result: list[dict] = []

    def add(capability: str, score: float, direction_value: str = "") -> None:
        item = {"capability": capability, "score": score + frame_bonus}
        if direction_value:
            item["direction"] = direction_value
        result.append(item)

    if lower in ["stand"]:
        add("resting", 125.0)
    elif lower in ["sit", "sprawl", "lie", "liedown"]:
        add("resting", 105.0)
    elif any(token in lower for token in ["face", "look"]):
        add("resting", 72.0)
    elif "spin" in lower:
        add("resting", 50.0)

    vertical_or_interactive = any(token in lower for token in [
        "wall",
        "ceiling",
        "edge",
        "ie",
        "grab",
        "hold",
        "pull",
        "throw",
    ])
    floor_motion = "workareafloor" in lower or lower in ["walk", "run", "dash", "creep", "crawl"]
    if any(token in lower for token in ["walk", "run", "dash", "creep", "crawl"]) and (floor_motion or not vertical_or_interactive):
        if lower == "walk":
            add("locomotion", 125.0, direction or "left")
        elif lower == "run":
            add("locomotion", 112.0, direction or "left")
        elif lower == "dash":
            add("locomotion", 104.0, direction or "left")
        elif "creep" in lower:
            add("locomotion", 68.0, direction or "left")
        else:
            add("locomotion", 80.0, direction or "left")
    if lower == "falling":
        add("falling", 115.0)
    elif "fall" in lower or "thrown" in lower or "jumping" in lower:
        add("falling", 72.0 if "ie" in lower else 95.0)
    if any(token in lower for token in ["drag", "pinch", "resist"]):
        add("held", 95.0)
    if any(token in lower for token in ["sleep", "lie", "sprawl"]):
        add("sleeping", 65.0)
    if any(token in lower for token in ["spin", "jump", "dash", "pull", "split", "chase"]):
        add("playful", 75.0)
    if any(token in lower for token in ["throw", "pull", "split", "chase", "ie"]):
        add("mischief", 70.0)
    if any(token in lower for token in ["wall", "ceiling", "edge", "grab", "hold"]):
        add("edge", 80.0, direction)
    if any(token in lower for token in ["look", "face", "chase", "sit"]):
        add("reaction", 70.0)

    if not result:
        add("resting", 30.0)
    return result


def copy_action_frames(
    image_set: Path,
    output_frames: Path,
    source_name: str,
    poses: list[Pose],
) -> tuple[dict, tuple[int, int], list[str]]:
    aid = action_id(source_name)
    action_dir = output_frames / aid
    action_dir.mkdir(parents=True, exist_ok=True)
    frames: list[str] = []
    durations: list[int] = []
    anchors: list[list[int]] = []
    velocities: list[list[float]] = []
    used_rects: list[list[int]] = []
    failed_frames: list[str] = []
    max_width = 1
    max_height = 1
    for index, pose in enumerate(poses, start=1):
        source = image_set / pose.image
        if not source.is_file():
            failed_frames.append(pose.image)
            continue
        dest_name = f"{index:03d}_{safe_id(source.stem)}.png"
        dest = action_dir / dest_name
        with Image.open(source) as image:
            rgba = image.convert("RGBA")
            rgba.save(dest)
            bbox = rgba.getchannel("A").getbbox()
            if bbox is None:
                used_rects.append([0, 0, rgba.width, rgba.height])
            else:
                left, top, right, bottom = bbox
                used_rects.append([left, top, right - left, bottom - top])
            max_width = max(max_width, rgba.width)
            max_height = max(max_height, rgba.height)
        frames.append(str(Path(aid) / dest_name))
        durations.append(pose.duration_ms)
        anchors.append([int(pose.anchor[0]), int(pose.anchor[1])])
        velocities.append([float(pose.velocity[0]), float(pose.velocity[1])])

    if not frames:
        raise ValueError(f"Action {source_name} has no readable frames")

    avg_duration = sum(durations) / len(durations)
    fps = 1000.0 / max(60.0, avg_duration)
    action = {
        "name": source_name,
        "resource": aid,
        "size": [max_width, max_height],
        "fps": round(fps, 3),
        "loop": True,
        "loop_start": -1,
        "next_action": "",
        "frames": frames,
        "durations_ms": durations,
        "anchors": anchors,
        "velocities": velocities,
        "used_rects": used_rects,
        "source_action": source_name,
    }
    lower = source_name.lower()
    if any(token in lower for token in ["wall", "ceiling", "edge", "grabwall", "holdontowall"]):
        action["native_edge_pose"] = True
    return action, (max_width, max_height), failed_frames


def add_capability(capabilities: dict[str, list[dict]], capability: str, action: str, score: float, direction: str = "") -> None:
    item: dict[str, object] = {"action": action, "score": round(score, 2)}
    if direction:
        item["direction"] = direction
    capabilities.setdefault(capability, []).append(item)


def ensure_directional_mirror(actions: dict, capabilities: dict[str, list[dict]], capability: str) -> list[str]:
    candidates = capabilities.get(capability, [])
    has_left = any(str(item.get("direction", "")) == "left" for item in candidates)
    has_right = any(str(item.get("direction", "")) == "right" for item in candidates)
    if has_left and has_right:
        return []
    source = ""
    source_direction = ""
    best_score = -1.0
    for item in candidates:
        direction = str(item.get("direction", ""))
        score = float(item.get("score", 0.0))
        if direction in ["left", "right"] and score > best_score:
            source = str(item.get("action", ""))
            source_direction = direction
            best_score = score
    if source == "" or source not in actions:
        return []
    target_direction = "right" if source_direction == "left" else "left"
    target = f"{source}_mirror_{target_direction}"
    if target not in actions:
        mirrored = actions[source].copy()
        mirrored["name"] = f"{mirrored.get('name', source)} mirrored {target_direction}"
        mirrored["mirror_x"] = not bool(mirrored.get("mirror_x", False))
        actions[target] = mirrored
    add_capability(capabilities, capability, target, max(70.0, best_score - 15.0), target_direction)
    return [target]


def ensure_locomotion_mirror(actions: dict, capabilities: dict[str, list[dict]]) -> list[str]:
    locomotion = capabilities.get("locomotion", [])
    has_left = any(str(item.get("direction", "")) == "left" for item in locomotion)
    has_right = any(str(item.get("direction", "")) == "right" for item in locomotion)
    if has_left and has_right:
        return []
    source = ""
    source_direction = ""
    for item in locomotion:
        direction = str(item.get("direction", ""))
        if direction in ["left", "right"]:
            source = str(item.get("action", ""))
            source_direction = direction
            break
    if source == "" or source not in actions:
        return []
    target_direction = "right" if source_direction == "left" else "left"
    target = f"{source}_mirror_{target_direction}"
    mirrored = actions[source].copy()
    mirrored["name"] = f"{mirrored.get('name', source)} mirrored {target_direction}"
    mirrored["mirror_x"] = not bool(mirrored.get("mirror_x", False))
    actions[target] = mirrored
    add_capability(capabilities, "locomotion", target, 85.0, target_direction)
    return [target]


def ensure_minimum_capabilities(actions: dict, capabilities: dict[str, list[dict]]) -> None:
    first_action = next(iter(actions.keys()))
    for capability in ["resting", "held", "reaction"]:
        if capability not in capabilities:
            add_capability(capabilities, capability, first_action, 40.0)
    for capability in ["falling", "sleeping", "playful", "mischief", "edge", "feeding", "waking"]:
        if capability not in capabilities:
            add_capability(capabilities, capability, capabilities["resting"][0]["action"], 25.0)


def preview_for(capabilities: dict, actions: dict) -> str:
    resting = capabilities.get("resting", [])
    if resting:
        action = actions.get(str(resting[0].get("action", "")), {})
        frames = action.get("frames", [])
        if frames:
            return str(frames[0])
    first = next(iter(actions.values()))
    return str(first.get("frames", [""])[0])


def build_skin(root: Path, image_set: Path, output_root: Path, forced_id: str | None, forced_name: str | None) -> ImportResult:
    skin_id = safe_id(forced_id or image_set.name)
    skin_name = forced_name or image_set.name
    output_dir = output_root / skin_id
    output_frames = output_dir / "frames"
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_frames.mkdir(parents=True, exist_ok=True)

    actions_xml = find_actions_xml(root, image_set)
    behaviors_xml = find_behaviors_xml(root, image_set)
    source_actions = parse_actions_xml(actions_xml) if actions_xml else {}
    if not source_actions:
        source_actions = fallback_standard_actions(image_set)
    source_behaviors = parse_behaviors_xml(behaviors_xml) if behaviors_xml else []
    behavior_profile, behavior_mapping, behavior_warnings = build_behavior_profile(source_behaviors)

    actions: dict[str, dict] = {}
    capabilities: dict[str, list[dict]] = {}
    failed_frames: list[str] = []
    for source_name, poses in source_actions.items():
        try:
            action, _size, failures = copy_action_frames(image_set, output_frames, source_name, poses)
        except ValueError:
            continue
        failed_frames.extend(f"{source_name}:{failure}" for failure in failures)
        aid = action_id(source_name)
        actions[aid] = action
        for classified in classify_action(source_name, poses):
            add_capability(
                capabilities,
                str(classified["capability"]),
                aid,
                float(classified["score"]),
                str(classified.get("direction", "")),
            )

    if not actions:
        raise SystemExit(f"No usable actions found in {image_set}")

    generated_mirrors: list[str] = []
    generated_mirrors.extend(ensure_locomotion_mirror(actions, capabilities))
    generated_mirrors.extend(ensure_directional_mirror(actions, capabilities, "edge"))
    ensure_minimum_capabilities(actions, capabilities)

    skin = {
        "schema_version": SCHEMA_VERSION,
        "version": 1,
        "id": skin_id,
        "name": skin_name,
        "description": "Imported from a Shimeji-ee image set.",
        "metadata": {
            "package_version": "1.0.0",
            "authors": [],
            "compatibility_level": "minimal",
            "compatibility_score": 0,
        },
        "preview": preview_for(capabilities, actions),
        "frame_root": "frames",
        "license": {
            "type": "user-provided",
            "summary": "User-provided Shimeji assets. Keep distribution rights separate from the app.",
            "redistributable": False,
        },
        "source": {
            "format": "shimeji-ee",
            "image_set": image_set.name,
            "actions_xml": str(actions_xml) if actions_xml else "",
            "behaviors_xml": str(behaviors_xml) if behaviors_xml else "",
        },
        "behavior_profile": behavior_profile,
        "capabilities": capabilities,
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
    validation = validate_skin_manifest(skin, output_dir / "skin.json", PROJECT_ROOT)
    skin = apply_quality_metadata(skin, validation)
    report = {
        "schema_version": SCHEMA_VERSION,
        "skin_id": skin_id,
        "skin_name": skin_name,
        "source": skin["source"],
        "action_count": validation["action_count"],
        "frame_count": validation["frame_count"],
        "capability_coverage": validation["capability_coverage"],
        "missing_capabilities": validation["missing_capabilities"],
        "generated_mirrors": sorted(set(generated_mirrors)),
        "failed_frames": failed_frames,
        "behavior_mapping": behavior_mapping,
        "compatibility_score": validation["score"],
        "compatibility_level": validation["level"],
        "errors": validation["errors"],
        "warnings": sorted(set(validation["warnings"] + behavior_warnings)),
    }
    (output_dir / "skin.json").write_text(json.dumps(skin, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output_dir / "import_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return ImportResult(output_dir, report)


def import_shimeji_root(
    root: Path,
    output_root: Path,
    forced_id: str | None,
    forced_name: str | None,
) -> list[ImportResult]:
    image_sets = find_image_sets(root)
    if not image_sets:
        raise SystemExit("No Shimeji image sets found.")
    if len(image_sets) > 1 and (forced_id or forced_name):
        raise SystemExit("--id and --name can only be used when importing one image set.")
    output_root.mkdir(parents=True, exist_ok=True)
    return [
        build_skin(root, image_set, output_root, forced_id, forced_name)
        for image_set in image_sets
    ]


def import_shimeji_source(
    source: Path,
    output_root: Path,
    forced_id: str | None = None,
    forced_name: str | None = None,
) -> list[ImportResult]:
    with tempfile.TemporaryDirectory(prefix="shimeji-import-") as temp_dir:
        root = extract_source(source.resolve(), Path(temp_dir))
        return import_shimeji_root(root, output_root, forced_id, forced_name)


def install_native_skin_root(skin_root: Path, output_root: Path) -> ImportResult:
    skin_path = skin_root / "skin.json"
    if not skin_path.is_file():
        raise SystemExit(f"Missing native skin manifest: {skin_path}")
    try:
        skin = json.loads(skin_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid skin.json: {exc}") from exc
    if not isinstance(skin, dict):
        raise SystemExit("skin.json must contain an object.")
    skin_id = str(skin.get("id", "")).strip()
    if skin_id == "" or safe_id(skin_id) != skin_id:
        raise SystemExit(f"Skin id must contain only lowercase letters, numbers, '-' or '_': {skin_id!r}")
    validation = validate_skin_manifest(skin, skin_path, PROJECT_ROOT)
    if validation["errors"]:
        raise SystemExit("Invalid skin package: " + "; ".join(validation["errors"]))
    skin = apply_quality_metadata(skin, validation)

    output_root.mkdir(parents=True, exist_ok=True)
    output_dir = output_root / skin_id
    safe_copytree(skin_root, output_dir)
    (output_dir / "skin.json").write_text(json.dumps(skin, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    report = {
        "schema_version": SCHEMA_VERSION,
        "skin_id": skin_id,
        "skin_name": str(skin.get("name", skin_id)),
        "source": skin.get("source", {"format": "mascotmate-skin"}),
        "action_count": validation["action_count"],
        "frame_count": validation["frame_count"],
        "capability_coverage": validation["capability_coverage"],
        "missing_capabilities": validation["missing_capabilities"],
        "generated_mirrors": [],
        "failed_frames": [],
        "behavior_mapping": {},
        "compatibility_score": validation["score"],
        "compatibility_level": validation["level"],
        "errors": validation["errors"],
        "warnings": validation["warnings"],
    }
    (output_dir / "import_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return ImportResult(output_dir, report)


def install_skin_source(
    source: Path,
    output_root: Path,
    forced_id: str | None = None,
    forced_name: str | None = None,
) -> list[ImportResult]:
    with tempfile.TemporaryDirectory(prefix="skin-install-") as temp_dir:
        root = extract_source(source.resolve(), Path(temp_dir))
        native_manifest = find_native_skin_manifest(root)
        if native_manifest is not None:
            if forced_id or forced_name:
                raise SystemExit("--id and --name are only valid for Shimeji imports.")
            return [install_native_skin_root(native_manifest.parent, output_root)]
        return import_shimeji_root(root, output_root, forced_id, forced_name)


def print_results(imported: list[ImportResult], json_report: bool) -> None:
    if json_report:
        print(json.dumps([
            {"path": str(item.path), "report": item.report}
            for item in imported
        ], ensure_ascii=False, indent=2))
    else:
        for item in imported:
            print(item.path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Shimeji-ee zip file or extracted folder.")
    parser.add_argument("--output-root", type=Path, default=output_root_default())
    parser.add_argument("--id", dest="skin_id", help="Override generated skin id. Only valid for one image set.")
    parser.add_argument("--name", dest="skin_name", help="Override generated skin name. Only valid for one image set.")
    parser.add_argument("--json-report", action="store_true", help="Print imported skin paths and reports as JSON.")
    args = parser.parse_args()

    imported = import_shimeji_source(args.source, args.output_root, args.skin_id, args.skin_name)
    print_results(imported, args.json_report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
