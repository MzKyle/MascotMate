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


def write_kenney_sprite(path: Path, color: tuple[int, int, int, int], accent: tuple[int, int, int, int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGBA", (320, 300), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((58, 54, 262, 258), fill=color)
    draw.ellipse((88, 22, 142, 92), fill=accent)
    draw.ellipse((178, 22, 232, 92), fill=accent)
    draw.ellipse((112, 132, 128, 148), fill=(20, 30, 40, 255))
    draw.ellipse((192, 132, 208, 148), fill=(20, 30, 40, 255))
    draw.arc((130, 150, 190, 196), 20, 160, fill=(20, 30, 40, 255), width=5)
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


def post_file(url: str, path: Path, token: str | None = None) -> tuple[int, dict]:
    boundary = "----MascotMateTestBoundary"
    payload = b"".join([
        f"--{boundary}\r\n".encode("utf-8"),
        f'Content-Disposition: form-data; name="file"; filename="{path.name}"\r\n'.encode("utf-8"),
        b"Content-Type: application/zip\r\n\r\n",
        path.read_bytes(),
        f"\r\n--{boundary}--\r\n".encode("utf-8"),
    ])
    headers = {"Content-Type": f"multipart/form-data; boundary={boundary}"}
    if token is not None:
        headers["X-MascotMate-Token"] = token
    request = urllib.request.Request(url, data=payload, headers=headers, method="POST")
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
        self.source_dir = self.root / "kenney"
        sprite_root = self.source_dir / "PNG" / "Round (outline)"
        write_kenney_sprite(sprite_root / "panda.png", (246, 247, 239, 255), (40, 50, 60, 255))
        write_kenney_sprite(sprite_root / "rabbit.png", (244, 213, 224, 255), (231, 124, 158, 255))
        (self.source_dir / "License.txt").write_text("Creative Commons CC0", encoding="utf-8")
        Image.new("RGBA", (64, 64), (0, 0, 0, 0)).save(self.source_dir / "Preview.png")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_featured_skin_generation_produces_valid_catalog(self) -> None:
        catalog_root = self.root / "repo" / "skin_catalog"

        entries = self.featured.generate_catalog(self.source_dir, catalog_root)
        catalog = json.loads((catalog_root / "catalog.json").read_text(encoding="utf-8"))
        errors = self.validator.validate_catalog(catalog, catalog_root)

        self.assertEqual([entry["id"] for entry in entries], ["kenney_panda", "kenney_rabbit"])
        self.assertEqual(errors, [])
        self.assertTrue((catalog_root / "packages" / "kenney_panda.zip").is_file())
        self.assertTrue((catalog_root / "previews" / "kenney_rabbit.png").is_file())

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

            status, body = post_json(f"{base}/api/install", {"id": "kenney_panda"})
            self.assertEqual(status, 403)
            self.assertFalse(body["ok"])

            status, body = post_json(f"{base}/api/install", {"id": "cachomon-419"}, token)
            self.assertEqual(status, 400)
            self.assertIn("不存在", body["error"])

            status, body = post_json(f"{base}/api/install", {"id": "kenney_panda"}, token)
            self.assertEqual(status, 200)
            self.assertEqual(body["skin_id"], "kenney_panda")
            self.assertTrue((config_dir / "skins" / "kenney_panda" / "skin.json").is_file())

            config = json.loads((config_dir / "config.json").read_text(encoding="utf-8"))
            command = json.loads((config_dir / "skin_store_command.json").read_text(encoding="utf-8"))
            self.assertEqual(config["app"]["skin_id"], "kenney_panda")
            self.assertEqual(command["command"], "select_skin")
            self.assertEqual(command["skin_id"], "kenney_panda")

            source_url = f"{base}/asset/skin_catalog/packages/kenney_rabbit.zip?token={token}"
            status, body = post_json(f"{base}/api/import-url", {"url": source_url}, token)
            self.assertEqual(status, 200)
            self.assertEqual(body["skin_id"], "kenney_rabbit")
            self.assertTrue((config_dir / "skins" / "kenney_rabbit" / "skin.json").is_file())

            status, body = post_json(f"{base}/api/import-url", {"url": "https://cachomon.com/example.zip"}, token)
            self.assertEqual(status, 400)
            self.assertIn("Cachomon", body["error"])

            upload_source = catalog_root / "packages" / "kenney_rabbit.zip"
            status, body = post_file(f"{base}/api/import-zip", upload_source)
            self.assertEqual(status, 403)
            self.assertFalse(body["ok"])

            status, body = post_file(f"{base}/api/import-zip", upload_source, token)
            self.assertEqual(status, 200)
            self.assertEqual(body["skin_id"], "kenney_rabbit")
            self.assertTrue((config_dir / "skins" / "kenney_rabbit" / "skin.json").is_file())

            refreshed = read_json(f"{base}/api/catalog?token={token}")
            local_ids = {item["id"] for item in refreshed["installed"]}
            self.assertIn("kenney_panda", local_ids)
            self.assertIn("kenney_rabbit", local_ids)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
