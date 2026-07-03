from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
IMPORTER_PATH = ROOT / "scripts" / "import_shimeji_skin.py"
CATALOG_VALIDATOR_PATH = ROOT / "scripts" / "validate_skin_catalog.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_png(path: Path, color: tuple[int, int, int, int] = (0, 128, 255, 255)) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGBA", (12, 14), color).save(path)


def write_native_skin(root: Path, skin_id: str = "sample_skin") -> Path:
    skin_root = root / skin_id
    write_png(skin_root / "frames" / "idle" / "001.png")
    skin = {
        "schema_version": 2,
        "version": 1,
        "id": skin_id,
        "name": "Sample Skin",
        "description": "Test skin.",
        "metadata": {"package_version": "1.0.0", "authors": []},
        "preview": "idle/001.png",
        "frame_root": "frames",
        "license": {"type": "CC0-1.0", "summary": "Test", "redistributable": True},
        "source": {"format": "test"},
        "capabilities": {
            "resting": [{"action": "idle", "score": 100}],
            "locomotion": [{"action": "idle", "score": 50}],
            "falling": [{"action": "idle", "score": 50}],
            "held": [{"action": "idle", "score": 50}],
            "edge": [{"action": "idle", "score": 50}],
        },
        "fallbacks": {"locomotion": "resting"},
        "actions": {
            "idle": {
                "name": "Idle",
                "resource": "idle",
                "size": [12, 14],
                "fps": 4,
                "loop": True,
                "frames": ["idle/001.png"],
            },
        },
    }
    (skin_root / "skin.json").write_text(json.dumps(skin, ensure_ascii=False), encoding="utf-8")
    return skin_root


def zip_skin(skin_root: Path, archive: Path) -> Path:
    archive.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive, "w") as zf:
        for path in sorted(skin_root.rglob("*")):
            if path.is_file():
                zf.write(path, Path(skin_root.name) / path.relative_to(skin_root))
    return archive


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


class SkinCatalogTests(unittest.TestCase):
    def setUp(self) -> None:
        self.importer = load_module("import_shimeji_skin_test", IMPORTER_PATH)
        self.validator = load_module("validate_skin_catalog_test", CATALOG_VALIDATOR_PATH)
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_install_native_skin_zip(self) -> None:
        archive = zip_skin(write_native_skin(self.root / "source"), self.root / "sample.zip")
        output = self.root / "installed"

        result = self.importer.install_skin_source(archive, output)

        self.assertEqual(result[0].report["skin_id"], "sample_skin")
        self.assertTrue((output / "sample_skin" / "skin.json").is_file())
        self.assertTrue((output / "sample_skin" / "import_report.json").is_file())

    def test_install_skin_rejects_zip_path_traversal(self) -> None:
        archive = self.root / "bad.zip"
        with zipfile.ZipFile(archive, "w") as zf:
            zf.writestr("../bad.png", b"bad")

        with self.assertRaises(SystemExit):
            self.importer.install_skin_source(archive, self.root / "installed")

    def test_catalog_validator_accepts_valid_catalog(self) -> None:
        catalog_dir = self.root / "catalog"
        preview = catalog_dir / "previews" / "sample.png"
        package = catalog_dir / "packages" / "sample.zip"
        write_png(preview)
        zip_skin(write_native_skin(self.root / "source"), package)
        data = {
            "schema_version": 1,
            "updated_at": "2026-07-03",
            "skins": [{
                "id": "sample_skin",
                "name": "Sample Skin",
                "description": "Test skin.",
                "tags": ["test"],
                "license": {"type": "CC0-1.0", "summary": "Test", "redistributable": True},
                "format": "mascotmate_skin_zip",
                "preview": "previews/sample.png",
                "package": "packages/sample.zip",
                "sha256": sha256(package),
                "size_bytes": package.stat().st_size,
                "min_app_version": "1.2.0",
            }],
        }

        errors = self.validator.validate_catalog(data, catalog_dir)

        self.assertEqual(errors, [])

    def test_catalog_validator_reports_hash_mismatch(self) -> None:
        catalog_dir = self.root / "catalog"
        preview = catalog_dir / "previews" / "sample.png"
        package = catalog_dir / "packages" / "sample.zip"
        write_png(preview)
        zip_skin(write_native_skin(self.root / "source"), package)
        data = {
            "schema_version": 1,
            "updated_at": "2026-07-03",
            "skins": [{
                "id": "sample_skin",
                "name": "Sample Skin",
                "description": "Test skin.",
                "tags": ["test"],
                "license": {"type": "CC0-1.0", "summary": "Test", "redistributable": True},
                "format": "mascotmate_skin_zip",
                "preview": "previews/sample.png",
                "package": "packages/sample.zip",
                "sha256": "0" * 64,
                "size_bytes": package.stat().st_size,
                "min_app_version": "1.2.0",
            }],
        }

        errors = self.validator.validate_catalog(data, catalog_dir)

        self.assertTrue(any("sha256 mismatch" in item for item in errors))


if __name__ == "__main__":
    unittest.main()
