#!/usr/bin/env python3
"""Import Shimeji-ee image sets into the Godot pet skin format."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path
from xml.etree import ElementTree

from PIL import Image


CONFIG_DIR_NAME = "crayon-shinchan-desktop-pet"
SHIMEJI_DURATION_MS = 40
SAFE_ID_RE = re.compile(r"[^a-z0-9_-]+")


@dataclass
class Pose:
    image: str
    duration_ms: int
    anchor: list[int]
    velocity: list[float]


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


def extract_source(source: Path, temp_root: Path) -> Path:
    if source.is_dir():
        return source
    if not zipfile.is_zipfile(source):
        raise SystemExit(f"Unsupported source: {source}")
    target = temp_root / "source"
    with zipfile.ZipFile(source) as zf:
        for member in zf.infolist():
            member_path = Path(member.filename)
            if member_path.is_absolute() or ".." in member_path.parts:
                raise SystemExit(f"Unsafe path in zip: {member.filename}")
        zf.extractall(target)
    return target


def find_image_sets(root: Path) -> list[Path]:
    candidates: list[Path] = []
    img_dirs = [path for path in root.rglob("img") if path.is_dir()]
    if not img_dirs and any(root.glob("*.png")):
        return [root]
    for img_dir in img_dirs:
        direct_pngs = list(img_dir.glob("*.png"))
        if direct_pngs:
            candidates.append(img_dir)
        for child in sorted(img_dir.iterdir(), key=natural_key):
            if child.is_dir() and child.name.lower() != "unused" and any(child.glob("*.png")):
                candidates.append(child)
    seen: set[Path] = set()
    unique: list[Path] = []
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved not in seen:
            seen.add(resolved)
            unique.append(candidate)
    return unique


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

    if any(token in lower for token in ["stand", "sit", "sprawl", "lie", "face", "look"]):
        add("resting", 85.0)
    if any(token in lower for token in ["walk", "run", "dash", "creep", "crawl", "climb"]):
        add("locomotion", 95.0, direction or "left")
    if "fall" in lower or "thrown" in lower or "jumping" in lower:
        add("falling", 95.0)
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
) -> tuple[dict, tuple[int, int]]:
    aid = action_id(source_name)
    action_dir = output_frames / aid
    action_dir.mkdir(parents=True, exist_ok=True)
    frames: list[str] = []
    durations: list[int] = []
    max_width = 1
    max_height = 1
    for index, pose in enumerate(poses, start=1):
        source = image_set / pose.image
        if not source.is_file():
            continue
        dest_name = f"{index:03d}_{safe_id(source.stem)}.png"
        dest = action_dir / dest_name
        with Image.open(source) as image:
            image.convert("RGBA").save(dest)
            max_width = max(max_width, image.width)
            max_height = max(max_height, image.height)
        frames.append(str(Path(aid) / dest_name))
        durations.append(pose.duration_ms)

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
        "source_action": source_name,
    }
    return action, (max_width, max_height)


def add_capability(capabilities: dict[str, list[dict]], capability: str, action: str, score: float, direction: str = "") -> None:
    item: dict[str, object] = {"action": action, "score": round(score, 2)}
    if direction:
        item["direction"] = direction
    capabilities.setdefault(capability, []).append(item)


def ensure_locomotion_mirror(actions: dict, capabilities: dict[str, list[dict]]) -> None:
    locomotion = capabilities.get("locomotion", [])
    has_left = any(str(item.get("direction", "")) == "left" for item in locomotion)
    has_right = any(str(item.get("direction", "")) == "right" for item in locomotion)
    if has_left and has_right:
        return
    source = ""
    source_direction = ""
    for item in locomotion:
        direction = str(item.get("direction", ""))
        if direction in ["left", "right"]:
            source = str(item.get("action", ""))
            source_direction = direction
            break
    if source == "" or source not in actions:
        return
    target_direction = "right" if source_direction == "left" else "left"
    target = f"{source}_mirror_{target_direction}"
    mirrored = actions[source].copy()
    mirrored["name"] = f"{mirrored.get('name', source)} mirrored {target_direction}"
    mirrored["mirror_x"] = not bool(mirrored.get("mirror_x", False))
    actions[target] = mirrored
    add_capability(capabilities, "locomotion", target, 85.0, target_direction)
    add_capability(capabilities, "edge", target, 75.0, target_direction)


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


def build_skin(root: Path, image_set: Path, output_root: Path, forced_id: str | None, forced_name: str | None) -> Path:
    skin_id = safe_id(forced_id or image_set.name)
    skin_name = forced_name or image_set.name
    output_dir = output_root / skin_id
    output_frames = output_dir / "frames"
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_frames.mkdir(parents=True, exist_ok=True)

    actions_xml = find_actions_xml(root, image_set)
    source_actions = parse_actions_xml(actions_xml) if actions_xml else {}
    if not source_actions:
        source_actions = fallback_standard_actions(image_set)

    actions: dict[str, dict] = {}
    capabilities: dict[str, list[dict]] = {}
    for source_name, poses in source_actions.items():
        try:
            action, _size = copy_action_frames(image_set, output_frames, source_name, poses)
        except ValueError:
            continue
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

    ensure_locomotion_mirror(actions, capabilities)
    ensure_minimum_capabilities(actions, capabilities)

    skin = {
        "version": 1,
        "id": skin_id,
        "name": skin_name,
        "description": "Imported from a Shimeji-ee image set.",
        "preview": preview_for(capabilities, actions),
        "frame_root": "frames",
        "license": {
            "type": "user-provided",
            "summary": "User-provided Shimeji assets. Keep distribution rights separate from the app.",
        },
        "source": {
            "format": "shimeji-ee",
            "image_set": image_set.name,
            "actions_xml": str(actions_xml) if actions_xml else "",
        },
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
    (output_dir / "skin.json").write_text(json.dumps(skin, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return output_dir


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Shimeji-ee zip file or extracted folder.")
    parser.add_argument("--output-root", type=Path, default=output_root_default())
    parser.add_argument("--id", dest="skin_id", help="Override generated skin id. Only valid for one image set.")
    parser.add_argument("--name", dest="skin_name", help="Override generated skin name. Only valid for one image set.")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="shimeji-import-") as temp_dir:
        root = extract_source(args.source.resolve(), Path(temp_dir))
        image_sets = find_image_sets(root)
        if not image_sets:
            raise SystemExit("No Shimeji image sets found.")
        if len(image_sets) > 1 and (args.skin_id or args.skin_name):
            raise SystemExit("--id and --name can only be used when importing one image set.")
        args.output_root.mkdir(parents=True, exist_ok=True)
        imported = [
            build_skin(root, image_set, args.output_root, args.skin_id, args.skin_name)
            for image_set in image_sets
        ]

    for path in imported:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
