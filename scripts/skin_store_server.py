#!/usr/bin/env python3
"""Local browser skin store server for MascotMate Desktop."""

from __future__ import annotations

import json
import mimetypes
import secrets
import sys
import time
import urllib.parse
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from import_shimeji_skin import install_skin_source


CONFIG_DIR_NAME = "mascotmate-desktop"


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


class SkinStoreApp:
    def __init__(self, repo_root: Path, config_dir: Path) -> None:
        self.repo_root = repo_root.resolve()
        self.config_dir = config_dir.resolve()
        self.catalog_dir = self.repo_root / "skin_catalog"
        self.static_dir = self.repo_root / "skin_store"
        self.user_skin_root = self.config_dir / "skins"
        self.config_path = self.config_dir / "config.json"
        self.command_path = self.config_dir / "skin_store_command.json"

    def catalog_payload(self, token: str) -> dict[str, Any]:
        curated = []
        catalog = self._load_json(self.catalog_dir / "catalog.json")
        for entry in catalog.get("skins", []) if isinstance(catalog.get("skins"), list) else []:
            if not isinstance(entry, dict):
                continue
            item = dict(entry)
            if str(item.get("source_type", "curated_package")) == "curated_package":
                preview = str(item.get("preview", ""))
                if is_safe_relative_ref(preview):
                    item["preview_url"] = self._asset_url(f"skin_catalog/{preview}", token)
            curated.append(item)

        external = []
        external_index = self._load_external_index()
        for entry in external_index.get("entries", []) if isinstance(external_index.get("entries"), list) else []:
            if isinstance(entry, dict):
                external.append(dict(entry))

        installed = self.installed_skins()
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
        if str(entry.get("source_type", "curated_package")) != "curated_package":
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

    def installed_skins(self) -> list[dict[str, Any]]:
        result = [{
            "id": "classic_shinchan",
            "name": "蜡笔小新默认皮肤",
            "kind": "builtin",
            "selected": self.current_skin_id() == "classic_shinchan",
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
                    "selected": skin_id == self.current_skin_id(),
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

    def asset_file(self, relative: str) -> Path:
        target = (self.repo_root / relative).resolve()
        if not is_subpath(target, self.repo_root) or not target.is_file():
            raise FileNotFoundError(relative)
        return target

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
        if parsed.path in ("", "/"):
            try:
                self._send_file(self.server.app.static_file("index.html"))
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
            body = self._read_json()
            if parsed.path == "/api/install":
                self._json(self.server.app.install_curated(str(body.get("id", ""))))
                return
            if parsed.path == "/api/select":
                self._json(self.server.app.select_skin(str(body.get("id", ""))))
                return
            if parsed.path == "/api/open-source":
                self._json(self.server.app.open_source(str(body.get("id", ""))))
                return
            self._json({"ok": False, "error": "not found"}, 404)
        except ValueError as exc:
            self._json({"ok": False, "error": str(exc)}, 400)

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0:
            return {}
        data = json.loads(self.rfile.read(length).decode("utf-8"))
        return data if isinstance(data, dict) else {}

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
) -> int:
    server = make_server(repo_root, config_dir, port=port)
    host, actual_port = server.server_address
    url = f"http://{host}:{actual_port}/?token={urllib.parse.quote(server.token)}"
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
