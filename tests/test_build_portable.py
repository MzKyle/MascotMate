from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD_PORTABLE_PATH = ROOT / "scripts" / "build_portable.py"


def load_module():
    spec = importlib.util.spec_from_file_location("build_portable_test", BUILD_PORTABLE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class BuildPortableTests(unittest.TestCase):
    def setUp(self) -> None:
        self.build_portable = load_module()
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_portable_readme_mentions_artifacts_and_folder_integrity(self) -> None:
        for target, info in self.build_portable.TARGETS.items():
            text = self.build_portable.portable_readme_text(target)

            self.assertIn(f"Package: {info['artifact']}.zip", text)
            self.assertIn("Extract the entire ZIP file.", text)
            self.assertIn("Keep every file and folder together", text)
            self.assertIn('"怎么玩？"', text)

        self.assertIn("keep MascotMateDesktop.app inside this extracted folder", self.build_portable.portable_readme_text("macos"))

    def test_write_readme_and_top_level_size_report(self) -> None:
        package_dir = self.root / "package"
        package_dir.mkdir()
        (package_dir / "small.txt").write_bytes(b"1")
        assets = package_dir / "assets"
        assets.mkdir()
        (assets / "large.bin").write_bytes(b"123456")

        self.build_portable.write_portable_readme(package_dir, "windows")
        report = self.build_portable.top_level_size_report(package_dir)

        self.assertTrue((package_dir / "README.txt").is_file())
        self.assertEqual(report[0][0], "README.txt")
        self.assertTrue(any(name == "assets" and size == 6 for name, size in report))
        self.assertEqual(self.build_portable.format_size(1024), "1.0 KiB")


if __name__ == "__main__":
    unittest.main()
