#!/usr/bin/env python3
"""Local browser skin store server for MascotMate Desktop."""

from __future__ import annotations

import json
import io
import mimetypes
import secrets
import sys
import time
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
import tempfile
import zipfile

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from import_shimeji_skin import install_skin_source


CONFIG_DIR_NAME = "mascotmate-desktop"
MAX_IMPORT_BYTES = 100 * 1024 * 1024
INSTALLABLE_SOURCE_TYPES = {"curated_package", "local_package"}
COMPANION_COMMANDS = {
    "set_behavior_mode",
    "set_dialogue_tone",
    "set_adaptation",
    "set_ai_expression",
    "set_ai_memory_summary",
    "check_ai_health",
    "summarize_memory",
    "rebuild_memory",
    "run_scenario",
}
COMPANION_MODES = {"安静", "活泼", "捣乱"}
COMPANION_DIALOGUE_TONES = {"gentle", "short_cute", "calm"}
COMPANION_STRENGTHS = {"subtle", "visible", "bold"}
COMPANION_AI_PROVIDERS = {"local_stub", "openai_compatible"}
COMPANION_SCENARIOS = {
    "all",
    "work_focus",
    "hungry_care",
    "low_mood_play",
    "rest_boundary",
    "busy_guard",
    "mischief_forced",
    "profile_low_interrupt",
    "profile_playful",
    "profile_care",
    "profile_work_protected",
    "profile_rest_protected",
}


def default_config_dir() -> Path:
    if sys.platform == "win32":
        base = Path.home() / "AppData" / "Roaming"
        return base / CONFIG_DIR_NAME
    return Path.home() / ".config" / CONFIG_DIR_NAME


def is_safe_relative_ref(value: str) -> bool:
    path = Path(value)
    return value != "" and not path.is_absolute() and ".." not in path.parts


def is_subpath(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def _coerce_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    text = str(value).strip().lower()
    if text in {"0", "false", "off", "no"}:
        return False
    if text in {"1", "true", "on", "yes"}:
        return True
    return bool(value)


def _friendly_import_error(message: str) -> str:
    if "Unsafe path in zip" in message:
        return "ZIP 内包含不安全路径，已拒绝导入。"
    if "No Shimeji image sets found" in message:
        return "未识别到 Shimeji-ee 或 MascotMate 原生皮肤结构。"
    if "Unsupported source" in message:
        return "不支持的皮肤包格式，请选择 ZIP 文件。"
    if "Invalid skin package" in message:
        return "原生皮肤包校验失败。"
    if "Missing native skin manifest" in message:
        return "原生皮肤包缺少 skin.json。"
    return message or "皮肤导入失败。"


def _content_type_param(content_type: str, key: str) -> str:
    for part in content_type.split(";")[1:]:
        if "=" not in part:
            continue
        name, value = part.split("=", 1)
        if name.strip().lower() == key:
            return value.strip().strip('"')
    return ""


def _content_disposition_param(header: str, key: str) -> str:
    for part in header.split(";")[1:]:
        if "=" not in part:
            continue
        name, value = part.split("=", 1)
        if name.strip().lower() == key:
            return value.strip().strip('"')
    return ""


def _parse_multipart_file(raw: bytes, content_type: str) -> tuple[str, bytes]:
    boundary_text = _content_type_param(content_type, "boundary")
    if boundary_text == "":
        raise ValueError("上传表单缺少 boundary。")
    boundary = boundary_text.encode("utf-8")
    delimiter = b"--" + boundary
    for part in raw.split(delimiter):
        part = part.strip(b"\r\n")
        if not part or part == b"--":
            continue
        if part.endswith(b"--"):
            part = part[:-2].rstrip(b"\r\n")
        header_bytes, separator, body = part.partition(b"\r\n\r\n")
        if separator == b"":
            continue
        headers: dict[str, str] = {}
        for line in header_bytes.decode("utf-8", errors="replace").split("\r\n"):
            if ":" not in line:
                continue
            name, value = line.split(":", 1)
            headers[name.strip().lower()] = value.strip()
        disposition = headers.get("content-disposition", "")
        if _content_disposition_param(disposition, "name") != "file":
            continue
        filename = Path(_content_disposition_param(disposition, "filename") or "upload.zip").name
        return filename, body.rstrip(b"\r\n")
    raise ValueError("请选择 ZIP 文件。")


class SkinStoreApp:
    def __init__(self, repo_root: Path, config_dir: Path) -> None:
        self.repo_root = repo_root.resolve()
        self.config_dir = config_dir.resolve()
        self.catalog_dir = self.repo_root / "skin_catalog"
        self.static_dir = self.repo_root / "skin_store"
        self.companion_static_dir = self.repo_root / "companion_console"
        self.user_skin_root = self.config_dir / "skins"
        self.config_path = self.config_dir / "config.json"
        self.command_path = self.config_dir / "skin_store_command.json"
        self.companion_command_path = self.config_dir / "companion_console_command.json"
        self.companion_snapshot_path = self.config_dir / "companion_debug_snapshot.json"
        self.companion_scenario_result_path = self.config_dir / "companion_scenario_result.json"

    def catalog_payload(self, token: str) -> dict[str, Any]:
        curated = []
        catalog = self._load_json(self.catalog_dir / "catalog.json")
        for entry in catalog.get("skins", []) if isinstance(catalog.get("skins"), list) else []:
            if not isinstance(entry, dict):
                continue
            item = dict(entry)
            if str(item.get("source_type", "curated_package")) in INSTALLABLE_SOURCE_TYPES:
                preview = str(item.get("preview", ""))
                if is_safe_relative_ref(preview):
                    item["preview_url"] = self._asset_url(f"skin_catalog/{preview}", token)
            curated.append(item)

        external = []
        external_index = self._load_external_index()
        for entry in external_index.get("entries", []) if isinstance(external_index.get("entries"), list) else []:
            if isinstance(entry, dict):
                external.append(dict(entry))

        installed = self.installed_skins(token)
        current_skin_id = self.current_skin_id()
        installed_ids = {str(item.get("id", "")) for item in installed}
        for entry in curated:
            skin_id = str(entry.get("id", ""))
            entry["installed"] = skin_id in installed_ids
            entry["selected"] = skin_id == current_skin_id
        for entry in external:
            skin_id = str(entry.get("id", ""))
            entry["installed"] = skin_id in installed_ids
            entry["selected"] = skin_id == current_skin_id

        return {
            "ok": True,
            "current_skin_id": current_skin_id,
            "installed": installed,
            "featured": curated,
            "external": external,
        }

    def install_curated(self, skin_id: str) -> dict[str, Any]:
        entry = self._curated_entry(skin_id)
        if not entry:
            raise ValueError("皮肤不存在或不是可安装精选皮肤。")
        if str(entry.get("source_type", "curated_package")) not in INSTALLABLE_SOURCE_TYPES:
            raise ValueError("第三方浏览条目不能由应用内安装。")
        package_ref = str(entry.get("package", ""))
        if not is_safe_relative_ref(package_ref):
            raise ValueError("皮肤包路径不合法。")
        package_path = self.catalog_dir / package_ref
        if not package_path.is_file():
            raise ValueError("本地皮肤包不存在。")
        self.user_skin_root.mkdir(parents=True, exist_ok=True)
        installed = install_skin_source(package_path, self.user_skin_root)
        if not installed:
            raise ValueError("皮肤安装失败。")
        installed_id = str(installed[0].report.get("skin_id", skin_id))
        self.select_skin(installed_id)
        return {
            "ok": True,
            "skin_id": installed_id,
            "message": "皮肤已安装并启用。",
            "report": installed[0].report,
        }

    def import_zip_bytes(self, filename: str, data: bytes) -> dict[str, Any]:
        safe_name = Path(filename or "skin.zip").name
        if not safe_name.lower().endswith(".zip"):
            raise ValueError("请选择 ZIP 格式的皮肤包。")
        if len(data) <= 0:
            raise ValueError("ZIP 文件为空。")
        if len(data) > MAX_IMPORT_BYTES:
            raise ValueError("ZIP 文件超过 100MB 上限。")
        if not zipfile.is_zipfile(io.BytesIO(data)):
            raise ValueError("文件不是有效的 ZIP。")

        self.user_skin_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="mascotmate-skin-upload-") as temp_dir:
            upload_path = Path(temp_dir) / safe_name
            upload_path.write_bytes(data)
            try:
                installed = install_skin_source(upload_path, self.user_skin_root)
            except SystemExit as exc:
                raise ValueError(_friendly_import_error(str(exc))) from exc
        if not installed:
            raise ValueError("未在 ZIP 中找到可用皮肤。")
        selected = installed[0]
        selected_id = str(selected.report.get("skin_id", "")).strip()
        if selected_id == "":
            raise ValueError("导入完成但无法识别皮肤 ID。")
        self.select_skin(selected_id)
        return {
            "ok": True,
            "skin_id": selected_id,
            "skin_name": str(selected.report.get("skin_name", selected_id)),
            "message": "皮肤已导入并启用。",
            "installed": [
                {
                    "skin_id": str(item.report.get("skin_id", "")),
                    "skin_name": str(item.report.get("skin_name", item.report.get("skin_id", ""))),
                    "report": item.report,
                }
                for item in installed
            ],
            "report": selected.report,
        }

    def import_zip_url(self, url: str) -> dict[str, Any]:
        parsed = urllib.parse.urlparse(url)
        host = (parsed.hostname or "").lower()
        if parsed.scheme not in ("http", "https") or host == "":
            raise ValueError("请输入有效的 ZIP 下载链接。")
        if parsed.scheme == "http" and host not in ("127.0.0.1", "localhost"):
            raise ValueError("原站直链必须使用 HTTPS。")
        if host == "cachomon.com" or host.endswith(".cachomon.com"):
            raise ValueError("Cachomon 不允许第三方应用代下载，请打开原站下载后再导入 ZIP。")
        request = urllib.request.Request(url, headers={"User-Agent": "MascotMateDesktop/1.0"})
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({})) if host in ("127.0.0.1", "localhost") else None
        try:
            open_url = opener.open if opener is not None else urllib.request.urlopen
            with open_url(request, timeout=30) as response:
                length = int(response.headers.get("Content-Length", "0") or "0")
                if length > MAX_IMPORT_BYTES:
                    raise ValueError("ZIP 文件超过 100MB 上限。")
                data = response.read(MAX_IMPORT_BYTES + 1)
                final_url = response.geturl()
        except ValueError:
            raise
        except OSError as exc:
            raise ValueError(f"下载失败：{exc}") from exc
        if len(data) > MAX_IMPORT_BYTES:
            raise ValueError("ZIP 文件超过 100MB 上限。")
        filename = Path(urllib.parse.urlparse(final_url).path).name or "download.zip"
        if not filename.lower().endswith(".zip"):
            filename = "download.zip"
        return self.import_zip_bytes(filename, data)

    def select_skin(self, skin_id: str) -> dict[str, Any]:
        if skin_id != "classic_shinchan" and skin_id not in {str(item.get("id", "")) for item in self.installed_skins()}:
            raise ValueError("皮肤未安装。")
        self._write_config_skin(skin_id)
        self._write_command(skin_id)
        return {"ok": True, "skin_id": skin_id, "message": "皮肤已启用。"}

    def open_source(self, skin_id: str) -> dict[str, Any]:
        entry = self._external_entry(skin_id)
        if not entry:
            raise ValueError("外部皮肤条目不存在。")
        url = str(entry.get("source_url", ""))
        if not (url.startswith("https://") or url.startswith("http://")):
            raise ValueError("外部链接不可用。")
        webbrowser.open(url)
        return {"ok": True, "url": url, "message": "已打开原站页面。"}

    def installed_skins(self, token: str | None = None) -> list[dict[str, Any]]:
        current = self.current_skin_id()
        default_preview = self._default_preview_url(token)
        result = [{
            "id": "classic_shinchan",
            "name": "蜡笔小新默认皮肤",
            "kind": "builtin",
            "selected": current == "classic_shinchan",
            "preview_url": default_preview,
        }]
        for root, kind in ((self.repo_root / "skins", "packaged"), (self.user_skin_root, "user")):
            if not root.is_dir():
                continue
            for skin_json in sorted(root.glob("*/skin.json")):
                data = self._load_json(skin_json)
                if not isinstance(data, dict):
                    continue
                skin_id = str(data.get("id", "")).strip()
                if skin_id == "":
                    continue
                result.append({
                    "id": skin_id,
                    "name": str(data.get("name", skin_id)),
                    "kind": kind,
                    "selected": skin_id == current,
                    "preview_url": self._installed_preview_url(skin_id, data, token),
                })
        return result

    def current_skin_id(self) -> str:
        config = self._load_json(self.config_path)
        app = config.get("app", {}) if isinstance(config, dict) else {}
        skin_id = str(app.get("skin_id", "classic_shinchan")).strip()
        return skin_id or "classic_shinchan"

    def static_file(self, relative: str) -> Path:
        target = (self.static_dir / relative).resolve()
        if not is_subpath(target, self.static_dir) or not target.is_file():
            raise FileNotFoundError(relative)
        return target

    def companion_static_file(self, relative: str) -> Path:
        target = (self.companion_static_dir / relative).resolve()
        if not is_subpath(target, self.companion_static_dir) or not target.is_file():
            raise FileNotFoundError(relative)
        return target

    def companion_snapshot(self) -> dict[str, Any]:
        return {
            "ok": True,
            "exists": self.companion_snapshot_path.is_file(),
            "snapshot": self._load_json(self.companion_snapshot_path),
        }

    def companion_scenario_result(self) -> dict[str, Any]:
        return {
            "ok": True,
            "exists": self.companion_scenario_result_path.is_file(),
            "result": self._load_json(self.companion_scenario_result_path),
        }

    def write_companion_command(self, body: dict[str, Any]) -> dict[str, Any]:
        command = str(body.get("command", "")).strip()
        if command not in COMPANION_COMMANDS:
            raise ValueError("未知控制台命令。")
        payload = body.get("payload", {})
        if not isinstance(payload, dict):
            payload = {}
        if command == "set_behavior_mode":
            mode = str(payload.get("mode", body.get("mode", ""))).strip()
            if mode not in COMPANION_MODES:
                raise ValueError("行为模式不合法。")
            payload = {"mode": mode}
        elif command == "set_dialogue_tone":
            tone = str(payload.get("tone", body.get("tone", ""))).strip()
            if tone not in COMPANION_DIALOGUE_TONES:
                raise ValueError("文案语气不合法。")
            payload = {"tone": tone}
        elif command == "set_adaptation":
            strength = str(payload.get("strength", body.get("strength", "visible"))).strip()
            if strength not in COMPANION_STRENGTHS:
                raise ValueError("适配强度不合法。")
            payload = {
                "enabled": _coerce_bool(payload.get("enabled", body.get("enabled", True))),
                "strength": strength,
            }
        elif command == "set_ai_expression":
            provider = str(payload.get("provider", body.get("provider", "local_stub"))).strip()
            if provider not in COMPANION_AI_PROVIDERS:
                raise ValueError("AI provider 不合法。")
            try:
                timeout_ms = int(payload.get("timeout_ms", body.get("timeout_ms", 800)))
            except (TypeError, ValueError):
                timeout_ms = 800
            payload = {
                "enabled": _coerce_bool(payload.get("enabled", body.get("enabled", False))),
                "provider": provider,
                "timeout_ms": max(100, min(5000, timeout_ms)),
            }
        elif command == "set_ai_memory_summary":
            provider = str(payload.get("provider", body.get("provider", "local_stub"))).strip()
            if provider not in COMPANION_AI_PROVIDERS:
                raise ValueError("AI provider 不合法。")
            try:
                timeout_ms = int(payload.get("timeout_ms", body.get("timeout_ms", 1500)))
            except (TypeError, ValueError):
                timeout_ms = 1500
            try:
                min_events = int(payload.get("min_events", body.get("min_events", 12)))
            except (TypeError, ValueError):
                min_events = 12
            try:
                min_interval_seconds = int(payload.get("min_interval_seconds", body.get("min_interval_seconds", 86400)))
            except (TypeError, ValueError):
                min_interval_seconds = 86400
            payload = {
                "enabled": _coerce_bool(payload.get("enabled", body.get("enabled", False))),
                "provider": provider,
                "timeout_ms": max(100, min(5000, timeout_ms)),
                "min_events": max(1, min(200, min_events)),
                "min_interval_seconds": max(60, min(30 * 24 * 60 * 60, min_interval_seconds)),
            }
        elif command == "run_scenario":
            scenario_id = str(payload.get("scenario_id", body.get("scenario_id", "all"))).strip() or "all"
            if scenario_id not in COMPANION_SCENARIOS:
                raise ValueError("回放场景不合法。")
            payload = {"scenario_id": scenario_id}
        else:
            payload = {}
        self._write_companion_command(command, payload)
        return {"ok": True, "command": command, "payload": payload, "message": "命令已发送。"}

    def asset_file(self, relative: str) -> Path:
        target = (self.repo_root / relative).resolve()
        if not is_subpath(target, self.repo_root) or not target.is_file():
            raise FileNotFoundError(relative)
        return target

    def installed_asset_file(self, skin_id: str, relative: str) -> Path:
        if not is_safe_relative_ref(relative) or Path(relative).suffix.lower() != ".png":
            raise FileNotFoundError(relative)
        for root in (self.repo_root / "skins", self.user_skin_root):
            if not root.is_dir():
                continue
            for skin_json in sorted(root.glob("*/skin.json")):
                data = self._load_json(skin_json)
                if str(data.get("id", "")) != skin_id:
                    continue
                frame_root = str(data.get("frame_root", "frames"))
                if not is_safe_relative_ref(frame_root):
                    raise FileNotFoundError(relative)
                target = (skin_json.parent / frame_root / relative).resolve()
                allowed_root = (skin_json.parent / frame_root).resolve()
                if not is_subpath(target, allowed_root) or not target.is_file():
                    raise FileNotFoundError(relative)
                return target
        raise FileNotFoundError(relative)

    def _curated_entry(self, skin_id: str) -> dict[str, Any]:
        catalog = self._load_json(self.catalog_dir / "catalog.json")
        for entry in catalog.get("skins", []) if isinstance(catalog.get("skins"), list) else []:
            if isinstance(entry, dict) and str(entry.get("id", "")) == skin_id:
                return entry
        return {}

    def _external_entry(self, skin_id: str) -> dict[str, Any]:
        index = self._load_external_index()
        for entry in index.get("entries", []) if isinstance(index.get("entries"), list) else []:
            if isinstance(entry, dict) and str(entry.get("id", "")) == skin_id:
                return entry
        return {}

    def _load_external_index(self) -> dict[str, Any]:
        candidates = [
            self.config_dir / "catalog_cache" / "cachomon" / "index.json",
            self.catalog_dir / "cachomon_index.json",
        ]
        for path in candidates:
            data = self._load_json(path)
            if isinstance(data, dict) and isinstance(data.get("entries"), list):
                return data
        return {"entries": []}

    def _asset_url(self, relative: str, token: str) -> str:
        return "/asset/%s?token=%s" % (
            urllib.parse.quote(relative.replace("\\", "/")),
            urllib.parse.quote(token),
        )

    def _installed_asset_url(self, skin_id: str, relative: str, token: str | None) -> str:
        if not token:
            return ""
        return "/installed-asset/%s/%s?token=%s" % (
            urllib.parse.quote(skin_id, safe=""),
            urllib.parse.quote(relative.replace("\\", "/"), safe=""),
            urllib.parse.quote(token),
        )

    def _installed_preview_url(self, skin_id: str, skin: dict[str, Any], token: str | None) -> str:
        preview = str(skin.get("preview", ""))
        if not is_safe_relative_ref(preview) or Path(preview).suffix.lower() != ".png":
            return ""
        return self._installed_asset_url(skin_id, preview, token)

    def _default_preview_url(self, token: str | None) -> str:
        if not token:
            return ""
        resource_root = self.repo_root / "resource_hd"
        if not resource_root.is_dir():
            return ""
        images = sorted(path for path in resource_root.rglob("*.png") if path.is_file())
        if not images:
            return ""
        relative = images[0].relative_to(self.repo_root)
        return self._asset_url(str(relative).replace("\\", "/"), token)

    def _write_config_skin(self, skin_id: str) -> None:
        self.config_dir.mkdir(parents=True, exist_ok=True)
        config = self._load_json(self.config_path)
        if not isinstance(config, dict):
            config = {}
        app = config.get("app", {})
        if not isinstance(app, dict):
            app = {}
        app["skin_id"] = skin_id
        config["app"] = app
        if "version" not in config:
            config["version"] = 1
        temp = self.config_path.with_suffix(".tmp")
        temp.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temp.replace(self.config_path)

    def _write_command(self, skin_id: str) -> None:
        self.config_dir.mkdir(parents=True, exist_ok=True)
        payload = {
            "command": "select_skin",
            "skin_id": skin_id,
            "nonce": secrets.token_hex(8),
            "created_at": time.time(),
        }
        temp = self.command_path.with_suffix(".tmp")
        temp.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")
        temp.replace(self.command_path)

    def _write_companion_command(self, command: str, payload: dict[str, Any]) -> None:
        self.config_dir.mkdir(parents=True, exist_ok=True)
        body = {
            "command": command,
            "payload": payload,
            "nonce": secrets.token_hex(8),
            "created_at": time.time(),
        }
        temp = self.companion_command_path.with_suffix(".tmp")
        temp.write_text(json.dumps(body, ensure_ascii=False) + "\n", encoding="utf-8")
        temp.replace(self.companion_command_path)

    def _load_json(self, path: Path) -> dict[str, Any]:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}
        return data if isinstance(data, dict) else {}


class SkinStoreHTTPServer(ThreadingHTTPServer):
    def __init__(self, address, app: SkinStoreApp, token: str):
        super().__init__(address, SkinStoreRequestHandler)
        self.app = app
        self.token = token
        self.last_request_at = time.monotonic()


class SkinStoreRequestHandler(BaseHTTPRequestHandler):
    server: SkinStoreHTTPServer

    def log_message(self, _format: str, *_args) -> None:
        return

    def do_GET(self) -> None:
        self.server.last_request_at = time.monotonic()
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/companion/snapshot":
            if not self._authorized(parsed):
                self._json({"ok": False, "error": "unauthorized"}, 403)
                return
            self._json(self.server.app.companion_snapshot())
            return
        if parsed.path == "/api/companion/scenario-result":
            if not self._authorized(parsed):
                self._json({"ok": False, "error": "unauthorized"}, 403)
                return
            self._json(self.server.app.companion_scenario_result())
            return
        if parsed.path == "/api/catalog":
            if not self._authorized(parsed):
                self._json({"ok": False, "error": "unauthorized"}, 403)
                return
            self._json(self.server.app.catalog_payload(self.server.token))
            return
        if parsed.path.startswith("/asset/"):
            if not self._authorized(parsed):
                self.send_error(403)
                return
            relative = urllib.parse.unquote(parsed.path.removeprefix("/asset/"))
            try:
                self._send_file(self.server.app.asset_file(relative))
            except FileNotFoundError:
                self.send_error(404)
            return
        if parsed.path.startswith("/installed-asset/"):
            if not self._authorized(parsed):
                self.send_error(403)
                return
            parts = parsed.path.removeprefix("/installed-asset/").split("/", 1)
            if len(parts) != 2:
                self.send_error(404)
                return
            skin_id = urllib.parse.unquote(parts[0])
            relative = urllib.parse.unquote(parts[1])
            try:
                self._send_file(self.server.app.installed_asset_file(skin_id, relative))
            except FileNotFoundError:
                self.send_error(404)
            return
        if parsed.path in ("", "/"):
            try:
                self._send_file(self.server.app.static_file("index.html"))
            except FileNotFoundError:
                self.send_error(404)
            return
        if parsed.path in ("/companion", "/companion/"):
            try:
                self._send_file(self.server.app.companion_static_file("index.html"))
            except FileNotFoundError:
                self.send_error(404)
            return
        if parsed.path.startswith("/companion/"):
            relative = urllib.parse.unquote(parsed.path.removeprefix("/companion/"))
            try:
                self._send_file(self.server.app.companion_static_file(relative))
            except FileNotFoundError:
                self.send_error(404)
            return
        relative = urllib.parse.unquote(parsed.path.lstrip("/"))
        try:
            self._send_file(self.server.app.static_file(relative))
        except FileNotFoundError:
            self.send_error(404)

    def do_POST(self) -> None:
        self.server.last_request_at = time.monotonic()
        parsed = urllib.parse.urlparse(self.path)
        if not self._authorized(parsed):
            self._json({"ok": False, "error": "unauthorized"}, 403)
            return
        try:
            if parsed.path == "/api/import-zip":
                filename, data = self._read_zip_upload()
                self._json(self.server.app.import_zip_bytes(filename, data))
                return
            body = self._read_json()
            if parsed.path == "/api/import-url":
                self._json(self.server.app.import_zip_url(str(body.get("url", ""))))
                return
            if parsed.path == "/api/install":
                self._json(self.server.app.install_curated(str(body.get("id", ""))))
                return
            if parsed.path == "/api/select":
                self._json(self.server.app.select_skin(str(body.get("id", ""))))
                return
            if parsed.path == "/api/open-source":
                self._json(self.server.app.open_source(str(body.get("id", ""))))
                return
            if parsed.path == "/api/companion/command":
                self._json(self.server.app.write_companion_command(body))
                return
            self._json({"ok": False, "error": "not found"}, 404)
        except ValueError as exc:
            self._json({"ok": False, "error": str(exc)}, 400)
        except Exception:
            self._json({"ok": False, "error": "服务器处理上传时失败，请重新打开皮肤商店后再试。"}, 500)

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0:
            return {}
        data = json.loads(self.rfile.read(length).decode("utf-8"))
        return data if isinstance(data, dict) else {}

    def _read_zip_upload(self) -> tuple[str, bytes]:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0:
            raise ValueError("没有收到 ZIP 文件。")
        if length > MAX_IMPORT_BYTES + 2 * 1024 * 1024:
            raise ValueError("ZIP 文件超过 100MB 上限。")
        content_type = self.headers.get("Content-Type", "")
        raw = self.rfile.read(length)
        if content_type.startswith("application/zip"):
            return "upload.zip", raw
        if "multipart/form-data" not in content_type:
            raise ValueError("请使用表单上传 ZIP 文件。")
        filename, data = _parse_multipart_file(raw, content_type)
        if len(data) > MAX_IMPORT_BYTES:
            raise ValueError("ZIP 文件超过 100MB 上限。")
        return filename, data

    def _authorized(self, parsed) -> bool:
        query = urllib.parse.parse_qs(parsed.query)
        token = self.headers.get("X-MascotMate-Token") or query.get("token", [""])[0]
        return secrets.compare_digest(token, self.server.token)

    def _send_file(self, path: Path) -> None:
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _json(self, payload: dict[str, Any], status: int = 200) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)


def make_server(repo_root: Path, config_dir: Path, *, port: int = 0, token: str | None = None) -> SkinStoreHTTPServer:
    app = SkinStoreApp(repo_root, config_dir)
    return SkinStoreHTTPServer(("127.0.0.1", port), app, token or secrets.token_urlsafe(24))


def serve_skin_store(
    repo_root: Path,
    config_dir: Path,
    *,
    open_browser: bool = False,
    idle_timeout: float = 900.0,
    port: int = 0,
    open_path: str = "/",
) -> int:
    server = make_server(repo_root, config_dir, port=port)
    host, actual_port = server.server_address
    clean_path = open_path if open_path.startswith("/") else "/" + open_path
    url = f"http://{host}:{actual_port}{clean_path}?token={urllib.parse.quote(server.token)}"
    print(json.dumps({"url": url, "port": actual_port}, ensure_ascii=False), flush=True)
    if open_browser:
        webbrowser.open(url)
    server.timeout = 0.5
    try:
        while time.monotonic() - server.last_request_at < idle_timeout:
            server.handle_request()
    finally:
        server.server_close()
    return 0


def serve_companion_console(
    repo_root: Path,
    config_dir: Path,
    *,
    open_browser: bool = False,
    idle_timeout: float = 900.0,
    port: int = 0,
) -> int:
    return serve_skin_store(
        repo_root,
        config_dir,
        open_browser=open_browser,
        idle_timeout=idle_timeout,
        port=port,
        open_path="/companion/",
    )
