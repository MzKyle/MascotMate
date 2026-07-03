from __future__ import annotations

import importlib.util
import io
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from contextlib import redirect_stdout

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
IMPORTER_PATH = ROOT / "scripts" / "import_shimeji_skin.py"


def load_importer():
    spec = importlib.util.spec_from_file_location("import_shimeji_skin", IMPORTER_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_png(path: Path, color: tuple[int, int, int, int] = (255, 0, 0, 255)) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGBA", (16, 18), color).save(path)


class ImportShimejiSkinTests(unittest.TestCase):
    def setUp(self) -> None:
        self.importer = load_importer()
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def make_shimeji(self) -> Path:
        image_set = self.root / "source" / "img" / "Buddy"
        for name in ["shime1.png", "shime2.png", "shime3.png", "shime4.png", "shime5.png", "shime11.png"]:
            write_png(image_set / name)
        conf = image_set / "conf"
        conf.mkdir(parents=True)
        (conf / "actions.xml").write_text(
            """<?xml version="1.0" encoding="UTF-8"?>
<Mascot>
  <ActionList>
    <Action Name="Stand" Type="Stay"><Animation>
      <Pose Image="/shime1.png" ImageAnchor="64,128" Velocity="0,0" Duration="250" />
    </Animation></Action>
    <Action Name="Walk" Type="Move"><Animation>
      <Pose Image="/shime1.png" ImageAnchor="64,128" Velocity="-2,0" Duration="6" />
      <Pose Image="/shime2.png" ImageAnchor="64,128" Velocity="-2,0" Duration="6" />
      <Pose Image="/shime3.png" ImageAnchor="64,128" Velocity="-2,0" Duration="6" />
    </Animation></Action>
    <Action Name="Dragged" Type="Stay"><Animation>
      <Pose Image="/shime5.png" ImageAnchor="64,128" Velocity="0,0" Duration="5" />
    </Animation></Action>
  </ActionList>
</Mascot>
""",
            encoding="utf-8",
        )
        (conf / "behaviors.xml").write_text(
            """<?xml version="1.0" encoding="UTF-8"?>
<Mascot>
  <BehaviorList>
    <Behavior Name="WalkAlongWorkAreaFloor" Frequency="100" />
    <Behavior Name="HoldOntoWall" Frequency="50" />
    <Behavior Name="ThrowIEFromLeft" Frequency="20" Condition="${ignored}" />
  </BehaviorList>
</Mascot>
""",
            encoding="utf-8",
        )
        return self.root / "source"

    def test_imports_image_set_with_capabilities_and_durations(self) -> None:
        source = self.make_shimeji()
        output = self.root / "skins"

        result = self.importer.build_skin(source, source / "img" / "Buddy", output, None, None)
        built = result.path

        skin = self.importer.json.loads((built / "skin.json").read_text(encoding="utf-8"))
        report = self.importer.json.loads((built / "import_report.json").read_text(encoding="utf-8"))
        self.assertEqual(skin["schema_version"], 2)
        self.assertEqual(skin["id"], "buddy")
        self.assertIn("stand", skin["actions"])
        self.assertIn("walk", skin["actions"])
        self.assertIn("resting", skin["capabilities"])
        self.assertIn("locomotion", skin["capabilities"])
        self.assertIn("durations_ms", skin["actions"]["walk"])
        self.assertIn("anchors", skin["actions"]["walk"])
        self.assertIn("velocities", skin["actions"]["walk"])
        self.assertIn("used_rects", skin["actions"]["walk"])
        self.assertEqual(len(skin["actions"]["walk"]["anchors"]), len(skin["actions"]["walk"]["frames"]))
        self.assertEqual(len(skin["actions"]["walk"]["used_rects"]), len(skin["actions"]["walk"]["frames"]))
        self.assertEqual(skin["source"]["behaviors_xml"].endswith("behaviors.xml"), True)
        self.assertIn("behavior_profile", skin)
        self.assertIn("活泼", skin["behavior_profile"]["modes"])
        self.assertEqual(report["skin_id"], "buddy")
        self.assertGreaterEqual(report["compatibility_score"], 1)
        self.assertTrue(any("Ignored Shimeji condition" in item for item in report["warnings"]))
        self.assertTrue(any(item.get("direction") == "right" for item in skin["capabilities"]["locomotion"]))

    def test_falls_back_to_standard_shimeji_images_without_actions_xml(self) -> None:
        image_set = self.root / "source" / "img" / "NoConf"
        for name in ["shime1.png", "shime2.png", "shime3.png"]:
            write_png(image_set / name)
        output = self.root / "skins"

        built = self.importer.build_skin(self.root / "source", image_set, output, None, None).path

        skin = self.importer.json.loads((built / "skin.json").read_text(encoding="utf-8"))
        self.assertIn("stand", skin["actions"])
        self.assertIn("walk", skin["actions"])
        self.assertIn("resting", skin["capabilities"])

    def test_ignores_img_root_with_only_icon(self) -> None:
        img_root = self.root / "source" / "img"
        write_png(img_root / "icon.png")
        write_png(img_root / "Buddy" / "shime1.png")

        image_sets = self.importer.find_image_sets(self.root / "source")

        self.assertEqual([path.name for path in image_sets], ["Buddy"])

    def test_cli_json_report_is_parseable(self) -> None:
        source = self.make_shimeji()
        output = self.root / "skins"
        previous_argv = sys.argv
        stdout = io.StringIO()
        try:
            sys.argv = [
                "import_shimeji_skin.py",
                str(source),
                "--output-root",
                str(output),
                "--json-report",
            ]
            with redirect_stdout(stdout):
                code = self.importer.main()
        finally:
            sys.argv = previous_argv

        self.assertEqual(code, 0)
        parsed = self.importer.json.loads(stdout.getvalue())
        self.assertEqual(parsed[0]["report"]["skin_id"], "buddy")
        self.assertTrue((output / "buddy" / "import_report.json").is_file())

    def test_rejects_zip_path_traversal(self) -> None:
        archive = self.root / "bad.zip"
        with zipfile.ZipFile(archive, "w") as zf:
            zf.writestr("../bad.png", b"bad")

        with self.assertRaises(SystemExit):
            self.importer.extract_source(archive, self.root / "extract")

    def test_extract_zip_ignores_root_directory_placeholder(self) -> None:
        archive = self.root / "root-placeholder.zip"
        with zipfile.ZipFile(archive, "w") as zf:
            zf.writestr("/", b"")
            zf.writestr("img/Buddy/shime1.png", b"png")

        extracted = self.importer.extract_source(archive, self.root / "extract")

        self.assertTrue((extracted / "img" / "Buddy" / "shime1.png").is_file())

    def test_rejects_zip_absolute_member(self) -> None:
        archive = self.root / "absolute.zip"
        with zipfile.ZipFile(archive, "w") as zf:
            zf.writestr("/tmp/bad.png", b"bad")

        with self.assertRaises(SystemExit):
            self.importer.extract_source(archive, self.root / "extract")


if __name__ == "__main__":
    unittest.main()
