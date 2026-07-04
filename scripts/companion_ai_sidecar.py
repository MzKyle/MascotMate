#!/usr/bin/env python3
"""Local AI expression sidecar for MascotMate Desktop."""

from __future__ import annotations

import argparse
import json
import os
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any


ALLOWED_PROVIDERS = {"local_stub", "openai_compatible"}
MAX_BODY_BYTES = 64 * 1024
DEFAULT_TIMEOUT = 8.0


def clean_text(value: Any, *, max_chars: int = 80) -> str:
    text = str(value or "").replace("\r", " ").replace("\n", " ").strip()
    text = "".join(ch for ch in text if ord(ch) >= 32)
    if max_chars > 0 and len(text) > max_chars:
        text = text[:max_chars].strip()
    return text


def fallback_response(fallback_text: str, seconds: float = 1.8, emotion: str = "neutral") -> dict[str, Any]:
    return {
        "text": clean_text(fallback_text, max_chars=80),
        "seconds": clamp_seconds(seconds),
        "emotion": clean_text(emotion, max_chars=24) or "neutral",
        "safety": "fallback",
    }


def ok_response(text: str, seconds: float = 1.8, emotion: str = "neutral") -> dict[str, Any]:
    return {
        "text": clean_text(text, max_chars=80),
        "seconds": clamp_seconds(seconds),
        "emotion": clean_text(emotion, max_chars=24) or "neutral",
        "safety": "ok",
    }


def clamp_seconds(value: Any) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        number = 1.8
    return max(0.5, min(5.0, number))


def max_chars_from_request(payload: dict[str, Any]) -> int:
    personality = payload.get("personality", {})
    if not isinstance(personality, dict):
        return 28
    style = personality.get("dialogue_style", {})
    if not isinstance(style, dict):
        return 28
    try:
        return max(8, min(80, int(style.get("max_chars", 28))))
    except (TypeError, ValueError):
        return 28


class CompanionAIApp:
    def __init__(self, provider: str = "local_stub", timeout: float = DEFAULT_TIMEOUT) -> None:
        self.provider = provider if provider in ALLOWED_PROVIDERS else "local_stub"
        self.timeout = max(0.1, float(timeout))

    def health(self) -> dict[str, Any]:
        configured = self.provider == "local_stub" or self._openai_configured()
        return {
            "ok": True,
            "provider": self.provider,
            "configured": configured,
            "status": "ready" if configured else "missing_config",
        }

    def expression(self, payload: dict[str, Any]) -> dict[str, Any]:
        fallback_text = clean_text(payload.get("fallback_text", ""), max_chars=max_chars_from_request(payload))
        default_seconds = clamp_seconds(payload.get("default_seconds", 1.8))
        if self.provider == "local_stub":
            return self._local_stub_expression(payload, fallback_text, default_seconds)
        if self.provider == "openai_compatible":
            return self._openai_expression(payload, fallback_text, default_seconds)
        return fallback_response(fallback_text, default_seconds)

    def _local_stub_expression(self, payload: dict[str, Any], fallback_text: str, default_seconds: float) -> dict[str, Any]:
        key = str(payload.get("key", ""))
        tone = ""
        personality = payload.get("personality", {})
        if isinstance(personality, dict):
            tone = str(personality.get("tone", ""))
        if key == "auto_prompt:hungry":
            text = "有点饿了，陪我吃点吧。"
        elif key == "auto_prompt:play":
            text = "要不要陪我玩一下？"
        elif key == "feed_success":
            text = "吃到啦，开心。"
        elif key == "tease_success":
            text = "嘿嘿，再来一下。"
        elif key == "pet_head":
            text = "摸摸头，舒服。"
        else:
            text = fallback_text
        if tone == "short_cute" and len(text) > max_chars_from_request(payload):
            text = text[:max_chars_from_request(payload)].strip()
        return ok_response(text or fallback_text, default_seconds, "cute")

    def _openai_expression(self, payload: dict[str, Any], fallback_text: str, default_seconds: float) -> dict[str, Any]:
        if not self._openai_configured():
            return fallback_response(fallback_text, default_seconds)
        endpoint = os.environ.get("MASCOTMATE_OPENAI_COMPATIBLE_URL", "").strip()
        api_key = os.environ.get("MASCOTMATE_OPENAI_COMPATIBLE_API_KEY", "").strip()
        model = os.environ.get("MASCOTMATE_OPENAI_COMPATIBLE_MODEL", "gpt-4o-mini").strip()
        prompt = self._prompt_for_payload(payload, fallback_text)
        request_body = {
            "model": model,
            "messages": [
                {
                    "role": "system",
                    "content": "Return only compact JSON with keys text, seconds, emotion, safety. Generate a short desktop pet bubble in Chinese. Do not include actions or commands.",
                },
                {"role": "user", "content": json.dumps(prompt, ensure_ascii=False)},
            ],
            "temperature": 0.7,
        }
        request = urllib.request.Request(
            endpoint,
            data=json.dumps(request_body).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                raw = json.loads(response.read().decode("utf-8"))
        except (OSError, urllib.error.URLError, json.JSONDecodeError):
            return fallback_response(fallback_text, default_seconds)
        try:
            content = raw["choices"][0]["message"]["content"]
            parsed = json.loads(content)
        except (KeyError, IndexError, TypeError, json.JSONDecodeError):
            return fallback_response(fallback_text, default_seconds)
        if not isinstance(parsed, dict):
            return fallback_response(fallback_text, default_seconds)
        text = clean_text(parsed.get("text", ""), max_chars=max_chars_from_request(payload))
        safety = str(parsed.get("safety", "fallback"))
        if text == "" or safety != "ok":
            return fallback_response(fallback_text, default_seconds)
        return ok_response(text, parsed.get("seconds", default_seconds), parsed.get("emotion", "neutral"))

    def _openai_configured(self) -> bool:
        return (
            os.environ.get("MASCOTMATE_OPENAI_COMPATIBLE_URL", "").strip() != ""
            and os.environ.get("MASCOTMATE_OPENAI_COMPATIBLE_API_KEY", "").strip() != ""
        )

    def _prompt_for_payload(self, payload: dict[str, Any], fallback_text: str) -> dict[str, Any]:
        return {
            "key": payload.get("key", ""),
            "fallback_text": fallback_text,
            "intent": payload.get("intent", {}),
            "state": payload.get("state", {}),
            "memory": payload.get("memory", {}),
            "profile": payload.get("profile", {}),
            "personality": payload.get("personality", {}),
            "recent_expressions": payload.get("recent_expressions", []),
            "max_chars": max_chars_from_request(payload),
        }


class CompanionAIHTTPServer(ThreadingHTTPServer):
    def __init__(self, address, app: CompanionAIApp):
        super().__init__(address, CompanionAIRequestHandler)
        self.app = app
        self.last_request_at = time.monotonic()


class CompanionAIRequestHandler(BaseHTTPRequestHandler):
    server: CompanionAIHTTPServer

    def log_message(self, _format: str, *_args) -> None:
        return

    def do_GET(self) -> None:
        self.server.last_request_at = time.monotonic()
        if self.path.split("?", 1)[0] == "/health":
            self._json(self.server.app.health())
            return
        self._json(fallback_response("", 1.8), 404)

    def do_POST(self) -> None:
        self.server.last_request_at = time.monotonic()
        if self.path.split("?", 1)[0] != "/v1/expression":
            self._json(fallback_response("", 1.8), 404)
            return
        try:
            payload = self._read_json()
        except ValueError:
            self._json(fallback_response("", 1.8), 400)
            return
        self._json(self.server.app.expression(payload))

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0 or length > MAX_BODY_BYTES:
            raise ValueError("invalid request size")
        data = json.loads(self.rfile.read(length).decode("utf-8"))
        if not isinstance(data, dict):
            raise ValueError("request must be object")
        return data

    def _json(self, payload: dict[str, Any], status: int = 200) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)


def make_server(provider: str = "local_stub", *, port: int = 0, timeout: float = DEFAULT_TIMEOUT) -> CompanionAIHTTPServer:
    app = CompanionAIApp(provider, timeout)
    return CompanionAIHTTPServer(("127.0.0.1", port), app)


def serve(provider: str = "local_stub", *, port: int = 8765, idle_timeout: float = 900.0, timeout: float = DEFAULT_TIMEOUT) -> int:
    server = make_server(provider, port=port, timeout=timeout)
    host, actual_port = server.server_address
    print(json.dumps({"url": f"http://{host}:{actual_port}", "port": actual_port, "provider": server.app.provider}, ensure_ascii=False), flush=True)
    server.timeout = 0.5
    try:
        while time.monotonic() - server.last_request_at < idle_timeout:
            server.handle_request()
    finally:
        server.server_close()
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", choices=sorted(ALLOWED_PROVIDERS), default="local_stub")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--idle-timeout", type=float, default=900.0)
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    return serve(args.provider, port=args.port, idle_timeout=args.idle_timeout, timeout=args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
