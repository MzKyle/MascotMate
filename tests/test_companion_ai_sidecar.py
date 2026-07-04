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


ROOT = Path(__file__).resolve().parents[1]
SIDECAR_PATH = ROOT / "scripts" / "companion_ai_sidecar.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def read_json(url: str) -> tuple[int, dict]:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(url, timeout=5) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode("utf-8"))


def post_json(url: str, payload: dict | str) -> tuple[int, dict]:
    data = payload if isinstance(payload, str) else json.dumps(payload)
    request = urllib.request.Request(
        url,
        data=data.encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(request, timeout=5) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode("utf-8"))


class CompanionAISidecarTests(unittest.TestCase):
    def setUp(self) -> None:
        self.module = load_module("companion_ai_sidecar_test", SIDECAR_PATH)
        self.temp = tempfile.TemporaryDirectory()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_local_stub_health_and_expression(self) -> None:
        server = self.module.make_server("local_stub", port=0)
        self.assertEqual(server.server_address[0], "127.0.0.1")
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_address[1]}"
        try:
            status, health = read_json(f"{base}/health")
            self.assertEqual(status, 200)
            self.assertTrue(health["ok"])
            self.assertEqual(health["provider"], "local_stub")
            status, expression = post_json(f"{base}/v1/expression", {
                "key": "pet_head",
                "fallback_text": "摸摸头。",
                "default_seconds": 1.8,
                "personality": {"tone": "short_cute", "dialogue_style": {"max_chars": 28}},
            })
            self.assertEqual(status, 200)
            self.assertEqual(set(expression.keys()), {"text", "seconds", "emotion", "safety"})
            self.assertEqual(expression["safety"], "ok")
            self.assertTrue(expression["text"])
            status, bad = post_json(f"{base}/v1/expression", "{broken")
            self.assertEqual(status, 400)
            self.assertEqual(bad["safety"], "fallback")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    def test_openai_compatible_missing_config_returns_fallback(self) -> None:
        server = self.module.make_server("openai_compatible", port=0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_address[1]}"
        try:
            status, health = read_json(f"{base}/health")
            self.assertEqual(status, 200)
            self.assertEqual(health["status"], "missing_config")
            status, expression = post_json(f"{base}/v1/expression", {
                "key": "pet_head",
                "fallback_text": "摸摸头。",
                "default_seconds": 1.8,
            })
            self.assertEqual(status, 200)
            self.assertEqual(expression["safety"], "fallback")
            self.assertEqual(expression["text"], "摸摸头。")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
