"""Exercise the HTTP producer and the actual Godot desktop command handlers together."""

import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from test_skin_store import get_json_status, post_json

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from command_queue import RUN_SECONDS
from import_shimeji_skin import install_skin_source
from skin_store_server import make_server
from verify_package import write_test_skin


class GatedAIHandler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        self._respond("health", {"ok": True, "configured": True, "provider": "local_stub", "status": "ready"})

    def do_POST(self):
        self.rfile.read(int(self.headers["Content-Length"]))
        if self.path != "/v1/memory-summary":
            self.send_error(404)
            return
        self._respond("summary", {
            "safety": "ok", "confidence": 85, "favorite_interactions": [], "favorite_mode": "活泼",
            "favorite_period": "entertainment", "care_tendency": 42, "play_tendency": 50,
            "interruption_tolerance": "medium",
        })

    def _respond(self, operation, value):
        self.server.entered[operation].set()
        if not self.server.release[operation].wait(10):
            return
        data = json.dumps(value).encode("utf-8")
        try:
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass  # The crash test deliberately kills the HTTP client.


@unittest.skipUnless(os.environ.get("GODOT_BIN"), "Run with GODOT_BIN via scripts/run_godot_smoke.py")
class DesktopCommandsIntegrationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="mascotmate-ipc-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.data = self.root / "desktop data"
        self.data.mkdir()
        self.token = "queue-integration"
        server = self.start_server(make_server(ROOT, self.data, token=self.token))
        self.base = f"http://127.0.0.1:{server.server_port}"
        self.ai = ThreadingHTTPServer(("127.0.0.1", 0), GatedAIHandler)
        self.ai.entered = {key: threading.Event() for key in ("health", "summary")}
        self.ai.release = {key: threading.Event() for key in self.ai.entered}
        self.start_server(self.ai)
        self.addCleanup(lambda: [event.set() for event in self.ai.release.values()])

    def start_server(self, server):
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join, 5)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return server

    def start_godot(self, name):
        env = {
            **os.environ,
            "CRAYON_PET_CONFIG_DIR": str(self.data),
            "CRAYON_PET_ROOT": str(ROOT),
            "CRAYON_PET_SAFE_WINDOW": "1",
            "CRAYON_PET_TRANSPARENT": "0",
            "CRAYON_PET_MOUSE_PASSTHROUGH": "0",
            "CRAYON_PET_ENABLE_GLOBAL_HOTKEYS": "0",
            "MASCOTMATE_AI_EXPRESSION_URL": f"http://127.0.0.1:{self.ai.server_port}",
        }
        log_path = self.root / f"{name}.log"
        with log_path.open("wb") as log:
            process = subprocess.Popen(
                [str(Path(os.environ["GODOT_BIN"]).resolve()), "--headless", "--verbose", "--path", str(ROOT / "godot_pet")],
                env=env,
                stdout=log,
                stderr=subprocess.STDOUT,
            )
        self.addCleanup(self.stop_godot, process, log_path)
        return process, log_path

    def stop_godot(self, process, log_path):
        if process.poll() is None:
            process.kill()
        process.wait(timeout=10)
        log = log_path.read_text(encoding="utf-8", errors="replace")
        self.assertNotIn("SCRIPT ERROR:", log)
        return log

    def submit(self, command, payload=None):
        status, body = post_json(
            f"{self.base}/api/companion/command", {"command": command, "payload": payload or {}}, self.token
        )
        self.assertEqual(status, 202, body)
        return body["command_id"]

    def query(self, id):
        status, body = get_json_status(f"{self.base}/api/commands/{id}", self.token)
        self.assertEqual(status, 200, body)
        return body["receipt"]

    def wait_until_finished(self, id, timeout=8):
        deadline = time.monotonic() + timeout
        condition = threading.Event()
        while time.monotonic() < deadline:
            receipt = self.query(id)
            if receipt["status"] in ("succeeded", "failed", "expired"):
                return receipt
            condition.wait(0.08)
        self.fail(f"Command did not finish: {self.query(id)}")

    def test_ten_real_actions_fifo_async_completion_and_config_ownership(self):
        config_path = self.data / "config.json"
        config = {"app": {"display_scale": 1.25, "onboarding_version": 1, "extra": {"keep": 7}}, "pins": {"max_count": 2}}
        config_path.write_text(json.dumps(config), encoding="utf-8")
        fixture = self.root / "skin.zip"
        write_test_skin(fixture)
        (self.data / "skins").mkdir()
        install_skin_source(fixture, self.data / "skins")
        ids = [
            self.submit("set_behavior_mode", {"mode": "活泼"}),
            self.submit("set_dialogue_tone", {"tone": "calm"}),
            self.submit("set_adaptation", {"enabled": False, "strength": "subtle"}),
            self.submit("set_ai_expression", {"enabled": True, "timeout_ms": 5000}),
            self.submit("set_ai_memory_summary", {"enabled": True, "timeout_ms": 5000, "min_events": 200}),
            self.submit("check_ai_health"),
            self.submit("summarize_memory"),
            self.submit("rebuild_memory"),
            self.submit("run_scenario", {"scenario_id": "busy_guard"}),
        ]
        status, body = post_json(f"{self.base}/api/select", {"id": "package-check"}, self.token)
        self.assertEqual(status, 202, body)
        ids.append(body["command_id"])
        self.assertEqual(ids, sorted(ids))
        self.assertTrue(all(self.query(id)["status"] == "pending" for id in ids))
        self.assertEqual(json.loads(config_path.read_text(encoding="utf-8")), config)

        process, log_path = self.start_godot("actions")
        for key, index in (("health", 5), ("summary", 6)):
            self.assertTrue(self.ai.entered[key].wait(8), f"Godot did not call {key}")
            self.assertEqual(self.query(ids[index])["status"], "running")
            self.assertEqual(self.query(ids[index + 1])["status"], "pending")
            self.ai.release[key].set()
            self.assertEqual(self.wait_until_finished(ids[index])["status"], "succeeded")

        receipts = [self.wait_until_finished(id) for id in ids]
        self.assertEqual([receipt["status"] for receipt in receipts], ["succeeded"] * 10)
        self.assertTrue(all(a["finished_at"] <= b["started_at"] for a, b in zip(receipts, receipts[1:])))
        _, data = get_json_status(f"{self.base}/api/companion/snapshot", self.token)
        snapshot = data["snapshot"]
        self.assertEqual(snapshot["skin"]["id"], "package-check")
        self.assertEqual(snapshot["runtime"]["behavior_mode"], "活泼")
        self.assertEqual(snapshot["config"]["dialogue_tone"], "calm")
        self.assertEqual(snapshot["config"]["behavior_adaptation"]["strength"], "subtle")
        self.assertEqual(snapshot["ai_expression"]["health"]["status"], "ready")
        self.assertEqual(snapshot["profile"]["ai_summary"]["confidence"], 85)
        _, scenarios = get_json_status(f"{self.base}/api/companion/scenario-result", self.token)
        self.assertEqual(scenarios["result"]["requested"], "busy_guard")
        _, catalog = get_json_status(f"{self.base}/api/catalog", self.token)
        self.assertEqual(catalog["current_skin_id"], "package-check")
        saved = json.loads(config_path.read_text(encoding="utf-8"))
        self.assertEqual(saved["app"]["display_scale"], 1.25)
        self.assertEqual(saved["app"]["extra"], {"keep": 7})
        self.assertEqual(saved["pins"]["max_count"], 2)

        broken = self.data / "skins" / "missing-frames"
        broken.mkdir()
        (broken / "skin.json").write_text(json.dumps({
            "id": "missing-frames", "frame_root": "frames",
            "actions": {"idle": {"frames": ["missing.png"], "size": [12, 14]}},
        }), encoding="utf-8")
        status, body = post_json(f"{self.base}/api/select", {"id": "missing-frames"}, self.token)
        self.assertEqual(status, 202, body)
        self.assertEqual(self.wait_until_finished(body["command_id"])["status"], "failed")
        _, catalog = get_json_status(f"{self.base}/api/catalog", self.token)
        self.assertEqual(catalog["current_skin_id"], "package-check")

        # A Godot-side persistence failure must not become a successful HTTP operation.
        (self.data / "config.json.bak.tmp").mkdir()
        failed_id = self.submit("set_dialogue_tone", {"tone": "short_cute"})
        failure = self.wait_until_finished(failed_id)
        self.assertEqual(failure["status"], "failed")
        self.assertFalse(failure["outcome_unknown"])
        self.assertEqual(json.loads(config_path.read_text(encoding="utf-8")), saved)
        log = self.stop_godot(process, log_path)
        self.assertIn(f"Desktop command {ids[5]} check_ai_health running", log)
        self.assertIn(f"Desktop command {failed_id} set_dialogue_tone failed", log)

    def test_process_crash_never_replays_a_started_command(self):
        (self.data / "config.json").write_text(
            '{"app":{"onboarding_version":1,"ai_expression":{"enabled":true,"timeout_ms":5000}}}', encoding="utf-8"
        )
        running = self.submit("check_ai_health")
        pending = self.submit("set_dialogue_tone", {"tone": "calm"})
        process, log_path = self.start_godot("before-crash")
        self.assertTrue(self.ai.entered["health"].wait(8), "Godot never started the check")
        self.assertEqual(self.query(running)["status"], "running")
        self.stop_godot(process, log_path)
        self.ai.entered["health"].clear()
        self.ai.release["health"].set()
        self.assertEqual(self.query(pending)["status"], "pending")

        new_process, new_log = self.start_godot("after-crash")
        self.assertEqual(self.wait_until_finished(pending, RUN_SECONDS + 7)["status"], "succeeded")
        interrupted = self.query(running)
        self.assertEqual(interrupted["status"], "failed")
        self.assertTrue(interrupted["outcome_unknown"])
        self.assertFalse(self.ai.entered["health"].is_set())
        self.assertIn(f"Desktop command {pending} set_dialogue_tone succeeded", self.stop_godot(new_process, new_log))


if __name__ == "__main__":
    unittest.main()
