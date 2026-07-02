from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SDK_PATH = ROOT / "scripts" / "skin_sdk.py"


def load_sdk():
    spec = importlib.util.spec_from_file_location("skin_sdk", SDK_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_png(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGBA", (8, 8), (0, 0, 0, 255)).save(path)


class SkinSdkTests(unittest.TestCase):
    def setUp(self) -> None:
        self.sdk = load_sdk()
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def base_skin(self) -> dict:
        write_png(self.root / "skin" / "frames" / "idle" / "001.png")
        return {
            "id": "sample",
            "name": "Sample",
            "frame_root": "frames",
            "preview": "idle/001.png",
            "license": {"type": "test"},
            "capabilities": {
                "resting": [{"action": "idle", "score": 100}],
                "locomotion": [{"action": "idle", "score": 20}],
                "falling": [{"action": "idle", "score": 20}],
                "held": [{"action": "idle", "score": 20}],
                "edge": [{"action": "idle", "score": 20}],
            },
            "fallbacks": {"locomotion": "resting"},
            "actions": {
                "idle": {
                    "name": "Idle",
                    "resource": "idle",
                    "size": [8, 8],
                    "fps": 10,
                    "loop": True,
                    "frames": ["idle/001.png"],
                }
            },
        }

    def test_v1_skin_is_normalized_and_valid(self) -> None:
        skin = self.base_skin()

        result = self.sdk.validate_skin_manifest(skin, self.root / "skin" / "skin.json", self.root)

        self.assertEqual(result["schema_version"], 1)
        self.assertEqual(result["errors"], [])
        self.assertIn(result["level"], ["partial", "good", "excellent"])

    def test_v2_missing_required_field_and_bad_references_are_errors(self) -> None:
        skin = self.base_skin()
        skin["schema_version"] = 2
        skin["capabilities"]["resting"] = [{"action": "missing", "score": 100}]
        skin["actions"]["idle"]["anchors"] = [[1, 1], [2, 2]]

        result = self.sdk.validate_skin_manifest(skin, self.root / "skin" / "skin.json", self.root)

        self.assertTrue(any("Missing required v2 field: metadata" in item for item in result["errors"]))
        self.assertTrue(any("references missing action" in item for item in result["errors"]))
        self.assertTrue(any("anchors length" in item for item in result["errors"]))

    def test_fallback_loop_is_reported(self) -> None:
        skin = self.base_skin()
        skin["fallbacks"] = {"locomotion": "edge", "edge": "locomotion"}

        result = self.sdk.validate_skin_manifest(skin, self.root / "skin" / "skin.json", self.root)

        self.assertTrue(any("Fallback chain contains a loop" in item for item in result["warnings"]))

    def test_used_rects_are_validated(self) -> None:
        skin = self.base_skin()
        skin["actions"]["idle"]["used_rects"] = [[0, 0, 12, 12]]

        result = self.sdk.validate_skin_manifest(skin, self.root / "skin" / "skin.json", self.root)

        self.assertTrue(any("used_rects[0] exceeds frame size" in item for item in result["errors"]))


if __name__ == "__main__":
    unittest.main()
