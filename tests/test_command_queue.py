import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import command_queue


class CommandQueueTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="mascotmate-queue-")
        self.addCleanup(temporary.cleanup)
        self.data = Path(temporary.name)
        self.queue = command_queue.CommandQueue(self.data)

    def record(self, request):
        return self.queue.root / request["id"]

    def test_ten_commands_are_accepted_in_order_while_godot_is_offline(self):
        commands = [
            "set_behavior_mode", "set_dialogue_tone", "set_adaptation", "set_ai_expression",
            "set_ai_memory_summary", "check_ai_health", "summarize_memory", "rebuild_memory",
            "run_scenario", "select_skin",
        ]
        receipts = [self.queue.submit(command, {}) for command in commands]
        ids = [receipt["id"] for receipt in receipts]
        self.assertEqual(ids, sorted(ids))
        restarted = command_queue.CommandQueue(self.data)
        self.assertEqual([restarted.status(id)["command"] for id in ids], commands)
        self.assertTrue(all(restarted.status(id)["status"] == "pending" for id in ids))

    def test_concurrent_publish_and_pending_limit(self):
        def submit(value):
            return self.queue.submit("set_dialogue_tone", {"value": value})

        with ThreadPoolExecutor(max_workers=12) as workers:
            receipts = list(workers.map(submit, range(100)))
        ids = {receipt["id"] for receipt in receipts}
        self.assertEqual(len(ids), 100)
        self.assertEqual(len(list(self.queue.root.glob("*/request.json"))), 100)
        self.assertFalse((self.queue.root / ".submit").exists())
        for receipt in receipts:
            self.assertEqual(json.loads((self.record(receipt) / "request.json").read_bytes()), receipt)
        for value in range(100, command_queue.MAX_PENDING):
            submit(value)
        with self.assertLogs(command_queue.LOG, level="WARNING"):
            with self.assertRaises(command_queue.QueueFull):
                submit(999)
        self.assertEqual(len(list(self.queue.root.glob("*/request.json"))), command_queue.MAX_PENDING)

    def test_two_helper_processes_share_sequence_and_capacity(self):
        script = """
import json
import sys
from pathlib import Path
from command_queue import CommandQueue, QueueFull
queue = CommandQueue(Path(sys.argv[1]))
ids = []
for index in range(8):
    try:
        ids.append(queue.submit('set_dialogue_tone', {'input': index})['id'])
    except QueueFull:
        break
print(json.dumps(ids))
"""
        for _ in range(command_queue.MAX_PENDING - 10):
            self.queue.submit("check_ai_health", {})
        children = [
            subprocess.Popen(
                [sys.executable, "-c", script, str(self.data)],
                cwd=SCRIPTS,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            for _ in range(2)
        ]
        try:
            ids = []
            for child in children:
                stdout, stderr = child.communicate(timeout=25)
                self.assertEqual(child.returncode, 0, stderr)
                ids.extend(json.loads(stdout))
            self.assertEqual(len(set(ids)), 10)
            self.assertEqual(sorted(int(id.split("-")[0]) for id in ids), list(range(119, 129)))
        finally:
            for child in children:
                if child.poll() is None:
                    child.kill()
                    child.communicate()

    def test_expiry_and_interrupted_outcomes_use_different_markers(self):
        pending = self.queue.submit("select_skin", {})
        running = self.queue.submit("summarize_memory", {})
        start = time.time() - command_queue.RUN_SECONDS - 1
        (self.record(running) / "pending").rename(self.record(running) / f"running.{int(start * 1000)}")
        with self.assertLogs(command_queue.LOG, level="WARNING"):
            interrupted = self.queue.status(running["id"])
        self.assertEqual(interrupted["status"], "failed")
        self.assertTrue(interrupted["outcome_unknown"])
        self.assertEqual(interrupted["command"], "summarize_memory")
        with mock.patch.object(time, "time", return_value=pending["expires_at"] + 1):
            with self.assertLogs(command_queue.LOG, level="WARNING"):
                expired = self.queue.status(pending["id"])
        self.assertEqual(expired["status"], "expired")
        self.assertNotIn("started_at", expired)
        self.assertTrue((self.record(pending) / "expired").is_file())
        self.assertEqual(self.queue.status(running["id"]), interrupted)

    def test_terminal_results_take_priority_and_are_pruned_after_retention(self):
        with mock.patch.object(command_queue, "MAX_RECORDS", 1):
            request = self.queue.submit("select_skin", {})
            result = {"id": request["id"], "status": "failed", "error": "selection_failed", "finished_at": time.time()}
            (self.record(request) / "result.json").write_text(json.dumps(result), encoding="utf-8")
            self.assertEqual(self.queue.status(request["id"]), result)
            with self.assertLogs(command_queue.LOG, level="WARNING"):
                with self.assertRaises(command_queue.QueueFull):
                    self.queue.submit("set_dialogue_tone", {})
            with mock.patch.object(time, "time", return_value=result["finished_at"] + command_queue.RETENTION_SECONDS + 1):
                replacement = self.queue.submit("set_dialogue_tone", {})
            self.assertIsNone(self.queue.status(request["id"]))
            self.assertNotEqual(replacement["id"], request["id"])

    def test_failed_publish_and_abandoned_stage_do_not_create_commands(self):
        with mock.patch.object(os, "fsync", side_effect=OSError("simulated disk error")):
            with self.assertRaises(OSError):
                self.queue.submit("select_skin", {})
        self.assertFalse(list(self.queue.root.glob("*/request.json")))
        stage = self.queue.root / ".submit"
        stage.mkdir()
        (stage / "request.json").write_text("partial", encoding="utf-8")
        (stage / "pending").touch()
        restarted = command_queue.CommandQueue(self.data)
        restarted.maintain()
        self.assertFalse(stage.exists())
        self.assertEqual(restarted.status(restarted.submit("select_skin", {})["id"])["status"], "pending")
