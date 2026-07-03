from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
FEATURED_PATH = ROOT / "scripts" / "fetch_featured_skins.py"
SERVER_PATH = ROOT / "scripts" / "skin_store_server.py"
VALIDATOR_PATH = ROOT / "scripts" / "validate_skin_catalog.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_sprite_sheet(path: Path, colors: list[tuple[int, int, int, int]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGBA", (128, 32), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    for index, color in enumerate(colors):
        x = index * 32
        draw.rectangle((x + 8, 10, x + 23, 25), fill=color)
        draw.rectangle((x + 12, 6, x + 19, 13), fill=color)
        draw.point((x + 13, 16), fill=(20, 30, 40, 255))
        draw.point((x + 19, 16), fill=(20, 30, 40, 255))
    image.save(path)


def read_json(url: str) -> dict:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(url, timeout=5) as response:
        return json.loads(response.read().decode("utf-8"))


def post_json(url: str, payload: dict, token: str | None = None) -> tuple[int, dict]:
    headers = {"Content-Type": "application/json"}
    if token is not None:
        headers["X-MascotMate-Token"] = token
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(request, timeout=8) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode("utf-8"))


class SkinStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.featured = load_module("fetch_featured_skins_test", FEATURED_PATH)
        self.server_module = load_module("skin_store_server_test", SERVER_PATH)
        self.validator = load_module("validate_skin_catalog_store_test", VALIDATOR_PATH)
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source_dir = self.root / "dpets"
        write_sprite_sheet(self.source_dir / "cat.png", [
            (80, 180, 220, 255),
            (95, 195, 230, 255),
            (70, 160, 210, 255),
            (90, 170, 220, 255),
        ])
        write_sprite_sheet(self.source_dir / "sprite.png", [
            (240, 180, 90, 255),
            (250, 190, 100, 255),
            (220, 150, 70, 255),
            (235, 165, 80, 255),
        ])
        (self.source_dir / "README.md").write_text("free to use with credit", encoding="utf-8")
        (self.source_dir / "LICENSE").write_text("MIT License", encoding="utf-8")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_featured_skin_generation_produces_valid_catalog(self) -> None:
        catalog_root = self.root / "repo" / "skin_catalog"

        entries = self.featured.generate_catalog(self.source_dir, catalog_root)
        catalog = json.loads((catalog_root / "catalog.json").read_text(encoding="utf-8"))
        errors = self.validator.validate_catalog(catalog, catalog_root)

        self.assertEqual([entry["id"] for entry in entries], ["dpets_cat", "dpets_pup"])
        self.assertEqual(errors, [])
        self.assertTrue((catalog_root / "packages" / "dpets_cat.zip").is_file())
        self.assertTrue((catalog_root / "previews" / "dpets_pup.png").is_file())

    def test_skin_store_api_installs_curated_and_rejects_external_install(self) -> None:
        repo = self.root / "repo"
        catalog_root = repo / "skin_catalog"
        self.featured.generate_catalog(self.source_dir, catalog_root)
        (catalog_root / "cachomon_index.json").write_text(json.dumps({
            "schema_version": 1,
            "entries": [{
                "id": "cachomon-419",
                "source_type": "external_browser",
                "name": "Rock Pikmin",
                "source_url": "https://cachomon.com/shimeji.php?id=419",
                "preview_url": "https://cachomon.com/thumbnails/rockPikmin.png",
                "status": "free",
                "artist": "FluffyFoxOfFate",
                "downloads": 33,
                "format": "shimeji-ee",
            }],
        }), encoding="utf-8")
        config_dir = self.root / "config"
        token = "test-token"
        server = self.server_module.make_server(repo, config_dir, token=token)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_address[1]}"
        try:
            catalog = read_json(f"{base}/api/catalog?token={token}")
            self.assertEqual(len(catalog["featured"]), 2)
            self.assertEqual(len(catalog["external"]), 1)

            status, body = post_json(f"{base}/api/install", {"id": "dpets_cat"})
            self.assertEqual(status, 403)
            self.assertFalse(body["ok"])

            status, body = post_json(f"{base}/api/install", {"id": "cachomon-419"}, token)
            self.assertEqual(status, 400)
            self.assertIn("不存在", body["error"])

            status, body = post_json(f"{base}/api/install", {"id": "dpets_cat"}, token)
            self.assertEqual(status, 200)
            self.assertEqual(body["skin_id"], "dpets_cat")
            self.assertTrue((config_dir / "skins" / "dpets_cat" / "skin.json").is_file())

            config = json.loads((config_dir / "config.json").read_text(encoding="utf-8"))
            command = json.loads((config_dir / "skin_store_command.json").read_text(encoding="utf-8"))
            self.assertEqual(config["app"]["skin_id"], "dpets_cat")
            self.assertEqual(command["command"], "select_skin")
            self.assertEqual(command["skin_id"], "dpets_cat")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
