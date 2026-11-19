"""Bounded file queue shared by the local HTTP helpers and Godot."""

from __future__ import annotations

import contextlib
import json
import logging
import os
import re
import secrets
import threading
import time
from pathlib import Path

if os.name == "nt":
    import msvcrt
else:
    import fcntl

DIRECTORY = "commands-v1"
MAX_PENDING = 128
MAX_RECORDS = 512
MAX_BYTES = 4096
PENDING_SECONDS = 120
RUN_SECONDS = 20
RETENTION_SECONDS = 1800
SWEEP_SECONDS = 15

ID_RE = re.compile(r"[0-9]{12}-[0-9a-f]{24}")
MARKER_RE = re.compile(r"(?:running\.[0-9]+|interrupted\.[0-9]+\.[0-9]+)")
LOCK = threading.Lock()
LOG = logging.getLogger(__name__)


class QueueFull(Exception):
    pass


class CommandQueue:
    def __init__(self, data_dir: Path):
        self.root = data_dir / DIRECTORY
        self.next_sweep = 0.0

    @contextlib.contextmanager
    def _producer_lock(self):
        self.root.mkdir(parents=True, exist_ok=True)
        with LOCK, (self.root / ".producer.lock").open("a+b") as handle:
            # Closing the handle releases the OS lock even if a helper exits.
            if os.name == "nt":
                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
            else:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            yield

    def submit(self, command: str, payload: dict) -> dict:
        with self._producer_lock():
            records = self._records()
            if time.monotonic() >= self.next_sweep or self._full(records):
                self._sweep(records)
                records = self._records()
            if self._full(records):
                LOG.warning("Desktop command queue at capacity (%d retained records)", len(records))
                raise QueueFull("桌宠暂时无法接收更多操作，请稍后重试。")
            sequence = int(max((path.name for path in records), default="0").split("-", 1)[0]) + 1
            command_id = f"{sequence:012d}-{secrets.token_hex(12)}"
            now = time.time()
            request = {
                "id": command_id,
                "command": command,
                "payload": payload,
                "created_at": now,
                "expires_at": now + PENDING_SECONDS,
            }
            encoded = json.dumps(request, ensure_ascii=False, allow_nan=False).encode("utf-8")
            if len(encoded) > MAX_BYTES:
                raise ValueError("操作内容过长。")
            stage = self.root / ".submit"
            stage.mkdir(exist_ok=True)
            try:
                with (stage / "request.json").open("wb") as handle:
                    handle.write(encoded)
                    handle.flush()
                    os.fsync(handle.fileno())
                (stage / "pending").touch()
                stage.rename(self.root / command_id)
            finally:
                self._remove_stage(stage)
            LOG.debug("Accepted desktop command %s %s (%d retained)", command_id, command, len(records) + 1)
            return request

    def status(self, command_id: str) -> dict | None:
        if not ID_RE.fullmatch(command_id):
            return None
        # A marker can move while we read the directory. Try the new state once.
        for _ in range(2):
            try:
                return self._current_status(self.root / command_id, time.time())
            except FileNotFoundError:
                continue
        return None

    def maintain(self) -> None:
        if time.monotonic() < self.next_sweep or not self.root.is_dir():
            return
        with self._producer_lock():
            self._remove_stage(self.root / ".submit")
            self._sweep(self._records())

    def _records(self) -> list[Path]:
        return [path for path in self.root.iterdir() if ID_RE.fullmatch(path.name) and not path.is_symlink() and path.is_dir()]

    @staticmethod
    def _full(records: list[Path]) -> bool:
        if len(records) >= MAX_RECORDS:
            return True
        # Keep a slot reserved while the command is running. Directory names
        # survive state transitions, so moving markers cannot lose a slot.
        active = 0
        for path in records:
            names = {entry.name for entry in path.iterdir()}
            terminal = (
                "result.json" in names or "expired" in names
                or any(name.startswith("interrupted.") and MARKER_RE.fullmatch(name) for name in names)
            )
            if not terminal:
                active += 1
        return active >= MAX_PENDING

    @staticmethod
    def _read(path: Path) -> dict:
        with path.open("rb") as handle:
            data = handle.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise ValueError("oversized queue record")
        value = json.loads(data)
        if not isinstance(value, dict):
            raise ValueError("invalid queue record")
        return value

    def _current_status(self, record: Path, now: float) -> dict | None:
        if record.is_symlink():
            return None
        names = {entry.name for entry in record.iterdir()}
        if "result.json" in names:
            result = self._read(record / "result.json")
            if result.get("id") != record.name or result.get("status") not in ("succeeded", "failed", "expired"):
                raise ValueError("invalid queue result")
            return result

        marker = self._active_marker(names)
        if not marker:
            return None
        fields = marker.split(".")
        state = fields[0]
        started_at = int(fields[1]) / 1000 if state in ("running", "interrupted") else None
        try:
            data = self._read(record / "request.json")
            receipt = {key: data[key] for key in ("command", "created_at", "expires_at")}
            if data.get("id") != record.name or not isinstance(receipt["expires_at"], (int, float)):
                raise ValueError("invalid queue request")
        except (KeyError, ValueError) as exc:
            # Godot records a definite invalid-request failure after claiming it.
            LOG.warning("Unreadable desktop command %s: %s", record.name, exc)
            receipt = {}

        target = None
        if state == "pending" and now >= receipt.get("expires_at", float("inf")):
            target = "expired"
        elif state == "running" and now >= started_at + RUN_SECONDS:
            target = f"interrupted.{fields[1]}.{int(now * 1000)}"
        if target:
            try:
                (record / marker).rename(record / target)
            except PermissionError:
                LOG.debug("Could not move desktop command %s yet", record.name, exc_info=True)
            else:
                fields = target.split(".")
                state = fields[0]
                LOG.warning("Desktop command %s %s %s", record.name, receipt.get("command", ""), state)

        receipt.update(id=record.name, status=state)
        if started_at is not None:
            receipt["started_at"] = started_at
        if state == "expired":
            receipt.update(finished_at=receipt.get("expires_at", now), error="not_started")
        elif state == "interrupted":
            receipt.update(
                status="failed",
                finished_at=int(fields[2]) / 1000,
                error="execution_interrupted",
                outcome_unknown=True,
            )
        return receipt

    @staticmethod
    def _active_marker(names: set[str]) -> str:
        if "expired" in names:
            return "expired"
        for kind in ("interrupted.", "running."):
            for name in names:
                if name.startswith(kind) and MARKER_RE.fullmatch(name):
                    return name
        return "pending" if "pending" in names else ""

    def _sweep(self, records: list[Path]) -> None:
        now = time.time()
        for record in records:
            try:
                status = self._current_status(record, now)
                if not status or status["status"] not in ("succeeded", "failed", "expired"):
                    continue
                if now - status["finished_at"] < RETENTION_SECONDS:
                    continue
                paths = list(record.iterdir())
                if any(path.name not in ("request.json", "result.json", "result.json.tmp", "expired", "pending")
                       and not MARKER_RE.fullmatch(path.name) for path in paths):
                    LOG.warning("Unexpected files prevent cleanup of desktop command %s", record.name)
                    continue
                # Remove any duplicate request marker before the terminal marker.
                (record / "pending").unlink(missing_ok=True)
                for path in paths:
                    path.unlink(missing_ok=True)
                record.rmdir()
            except FileNotFoundError:
                pass  # Godot moved a marker while we were reading it.
            except (KeyError, OSError, ValueError) as exc:
                LOG.warning("Could not clean desktop command %s: %s", record.name, exc)
        self.next_sweep = time.monotonic() + SWEEP_SECONDS

    @staticmethod
    def _remove_stage(stage: Path) -> None:
        if stage.is_dir():
            (stage / "request.json").unlink(missing_ok=True)
            (stage / "pending").unlink(missing_ok=True)
            stage.rmdir()
