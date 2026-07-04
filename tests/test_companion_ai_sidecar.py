from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
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


class FakeOpenAIHandler(BaseHTTPRequestHandler):
    def log_message(self, _format: str, *_args) -> None:
        return

    def do_POST(self) -> None:
        route = self.path.split("?", 1)[0]
        if route == "/http500":
            self.send_response(500)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"upstream failed")
            return
        if route == "/bad-json":
            self._send_raw(b"{broken", "application/json")
            return
        if route == "/non-json":
            self._send_raw(b"not json", "text/plain")
            return
        if route == "/invalid-schema":
            self._send_openai_content({"text": "走一下", "seconds": 1.0, "emotion": "neutral", "safety": "ok", "command": "walk"})
            return
        if route == "/too-long":
            self._send_openai_content({"text": "这是一句非常非常非常非常非常非常非常非常非常非常长的桌宠气泡文案", "seconds": 1.0, "emotion": "neutral", "safety": "ok"})
            return
        if route == "/summary-invalid-schema":
            self._send_openai_content({"favorite_interactions": ["feed_success"], "favorite_mode": "活泼", "favorite_period": "entertainment", "care_tendency": 80, "play_tendency": 20, "interruption_tolerance": "medium", "confidence": 80, "safety": "ok", "notes": "bad"})
            return
        if route == "/summary-low-confidence":
            self._send_openai_content({"favorite_interactions": ["feed_success"], "favorite_mode": "活泼", "favorite_period": "entertainment", "care_tendency": 80, "play_tendency": 20, "interruption_tolerance": "medium", "confidence": 40, "safety": "ok"})
            return
        if route == "/summary-valid":
            self._send_openai_content({"favorite_interactions": ["feed_success"], "favorite_mode": "活泼", "favorite_period": "entertainment", "care_tendency": 80, "play_tendency": 20, "interruption_tolerance": "medium", "confidence": 80, "safety": "ok"})
            return
        self._send_openai_content({"text": "AI摸摸头。", "seconds": 1.0, "emotion": "happy", "safety": "ok"})

    def _send_openai_content(self, content: dict) -> None:
        payload = {"choices": [{"message": {"content": json.dumps(content, ensure_ascii=False)}}]}
        self._send_raw(json.dumps(payload).encode("utf-8"), "application/json")

    def _send_raw(self, data: bytes, content_type: str) -> None:
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


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
            status, summary = post_json(f"{base}/v1/memory-summary", {
                "recent_events": [
                    {"kind": "feed_success", "source": "user", "mode": "活泼", "period": "entertainment"},
                    {"kind": "tease_success", "source": "user", "mode": "活泼", "period": "entertainment"},
                    {"kind": "feed_success", "source": "user", "mode": "活泼", "period": "entertainment"},
                ],
            })
            self.assertEqual(status, 200)
            self.assertEqual(set(summary.keys()), {"favorite_interactions", "favorite_mode", "favorite_period", "care_tendency", "play_tendency", "interruption_tolerance", "confidence", "safety"})
            self.assertEqual(summary["safety"], "ok")
            self.assertIn("feed_success", summary["favorite_interactions"])
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
            status, summary = post_json(f"{base}/v1/memory-summary", {"recent_events": []})
            self.assertEqual(status, 200)
            self.assertEqual(summary["safety"], "fallback")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    def test_openai_compatible_upstream_failures_return_stable_fallback(self) -> None:
        env_keys = [
            "MASCOTMATE_OPENAI_COMPATIBLE_URL",
            "MASCOTMATE_OPENAI_COMPATIBLE_API_KEY",
            "MASCOTMATE_OPENAI_COMPATIBLE_MODEL",
        ]
        previous_env = {key: os.environ.get(key) for key in env_keys}
        fake_upstream = ThreadingHTTPServer(("127.0.0.1", 0), FakeOpenAIHandler)
        fake_thread = threading.Thread(target=fake_upstream.serve_forever, daemon=True)
        fake_thread.start()
        server = self.module.make_server("openai_compatible", port=0, timeout=0.2)
        sidecar_thread = threading.Thread(target=server.serve_forever, daemon=True)
        sidecar_thread.start()
        upstream_base = f"http://127.0.0.1:{fake_upstream.server_address[1]}"
        sidecar_base = f"http://127.0.0.1:{server.server_address[1]}"
        try:
            os.environ["MASCOTMATE_OPENAI_COMPATIBLE_API_KEY"] = "test-key"
            os.environ["MASCOTMATE_OPENAI_COMPATIBLE_MODEL"] = "test-model"
            payload = {
                "key": "pet_head",
                "fallback_text": "摸摸头。",
                "default_seconds": 1.8,
                "personality": {"dialogue_style": {"max_chars": 28}},
            }
            for route in ["http500", "bad-json", "non-json", "invalid-schema", "too-long"]:
                with self.subTest(route=route):
                    os.environ["MASCOTMATE_OPENAI_COMPATIBLE_URL"] = f"{upstream_base}/{route}"
                    status, health = read_json(f"{sidecar_base}/health")
                    self.assertEqual(status, 200)
                    self.assertTrue(health["configured"])
                    status, expression = post_json(f"{sidecar_base}/v1/expression", payload)
                    self.assertEqual(status, 200)
                    self.assertEqual(set(expression.keys()), {"text", "seconds", "emotion", "safety"})
                    self.assertEqual(expression["safety"], "fallback")
                    self.assertEqual(expression["text"], "摸摸头。")
            for route in ["http500", "bad-json", "non-json", "summary-invalid-schema", "summary-low-confidence"]:
                with self.subTest(summary_route=route):
                    os.environ["MASCOTMATE_OPENAI_COMPATIBLE_URL"] = f"{upstream_base}/{route}"
                    status, summary = post_json(f"{sidecar_base}/v1/memory-summary", {"recent_events": payload})
                    self.assertEqual(status, 200)
                    self.assertEqual(summary["safety"], "fallback")
            os.environ["MASCOTMATE_OPENAI_COMPATIBLE_URL"] = f"{upstream_base}/summary-valid"
            status, summary = post_json(f"{sidecar_base}/v1/memory-summary", {"recent_events": []})
            self.assertEqual(status, 200)
            self.assertEqual(summary["safety"], "ok")
            self.assertEqual(summary["favorite_interactions"], ["feed_success"])
        finally:
            for key, value in previous_env.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
            server.shutdown()
            server.server_close()
            sidecar_thread.join(timeout=5)
            fake_upstream.shutdown()
            fake_upstream.server_close()
            fake_thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
