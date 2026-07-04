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
ALLOWED_RESPONSE_KEYS = {"text", "seconds", "emotion", "safety"}
ALLOWED_SUMMARY_KEYS = {
    "favorite_interactions",
    "favorite_mode",
    "favorite_period",
    "care_tendency",
    "play_tendency",
    "interruption_tolerance",
    "confidence",
    "safety",
}
VALID_SUMMARY_INTERACTIONS = {
    "pet_head",
    "poke_body",
    "grab_start",
    "release_soft",
    "throw_fast",
    "peek_enter",
    "peek_exit",
    "feed_start",
    "feed_success",
    "tease_start",
    "tease_success",
}
VALID_SUMMARY_MODES = {"", "安静", "活泼", "捣乱"}
VALID_SUMMARY_PERIODS = {"", "work", "entertainment", "rest"}
VALID_INTERRUPTION_TOLERANCE = {"low", "medium", "high"}
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


def fallback_summary_response() -> dict[str, Any]:
    return {
        "favorite_interactions": [],
        "favorite_mode": "",
        "favorite_period": "",
        "care_tendency": 0,
        "play_tendency": 0,
        "interruption_tolerance": "medium",
        "confidence": 0,
        "safety": "fallback",
    }


def ok_summary_response(summary: dict[str, Any]) -> dict[str, Any]:
    return {
        "favorite_interactions": clean_allowed_list(summary.get("favorite_interactions", []), VALID_SUMMARY_INTERACTIONS, 3),
        "favorite_mode": clean_enum(summary.get("favorite_mode", ""), VALID_SUMMARY_MODES, ""),
        "favorite_period": clean_enum(summary.get("favorite_period", ""), VALID_SUMMARY_PERIODS, ""),
        "care_tendency": clamp_int(summary.get("care_tendency", 0), 0, 100),
        "play_tendency": clamp_int(summary.get("play_tendency", 0), 0, 100),
        "interruption_tolerance": clean_enum(summary.get("interruption_tolerance", "medium"), VALID_INTERRUPTION_TOLERANCE, "medium"),
        "confidence": clamp_int(summary.get("confidence", 0), 0, 100),
        "safety": "ok",
    }


def clamp_seconds(value: Any) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        number = 1.8
    return max(0.5, min(5.0, number))


def clamp_int(value: Any, minimum: int, maximum: int) -> int:
    try:
        number = int(value)
    except (TypeError, ValueError):
        number = minimum
    return max(minimum, min(maximum, number))


def clean_enum(value: Any, allowed: set[str], fallback: str) -> str:
    text = str(value or "").strip()
    return text if text in allowed else fallback


def clean_allowed_list(value: Any, allowed: set[str], limit: int) -> list[str]:
    if not isinstance(value, list):
        return []
    result: list[str] = []
    for item in value:
        text = str(item or "").strip()
        if text and text in allowed and text not in result:
            result.append(text)
        if len(result) >= limit:
            break
    return result


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

    def memory_summary(self, payload: dict[str, Any]) -> dict[str, Any]:
        if self.provider == "local_stub":
            return self._local_stub_memory_summary(payload)
        if self.provider == "openai_compatible":
            return self._openai_memory_summary(payload)
        return fallback_summary_response()

    def _local_stub_expression(self, payload: dict[str, Any], fallback_text: str, default_seconds: float) -> dict[str, Any]:
        key = str(payload.get("key", ""))
        tone = ""
        personality = payload.get("personality", {})
        if isinstance(personality, dict):
            tone = str(personality.get("tone", ""))
        lines = {
            "auto_prompt:hungry": {
                "gentle": "我有点饿了，要不要补点能量？",
                "short_cute": "要不要吃点东西？",
                "calm": "有点饿，方便时再照顾我就好。",
            },
            "auto_prompt:play": {
                "gentle": "要不要放松一下？",
                "short_cute": "要不要玩一小会儿？",
                "calm": "休息一下也可以。",
            },
            "feed_success": {
                "gentle": "吃到啦，谢谢你。",
                "short_cute": "补充能量，开心。",
                "calm": "暖暖的，刚刚好。",
            },
            "tease_success": {
                "gentle": "笑一下，放松啦。",
                "short_cute": "今天也很棒，再来一下。",
                "calm": "刚刚好，轻松一点。",
            },
            "pet_head": {
                "gentle": "摸摸头，辛苦啦。",
                "short_cute": "今天也很棒。",
                "calm": "我在这儿，不着急。",
            },
        }
        if key in lines:
            text = lines[key].get(tone, lines[key]["gentle"])
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
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with opener.open(request, timeout=self.timeout) as response:
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
        if any(str(key) not in ALLOWED_RESPONSE_KEYS for key in parsed.keys()):
            return fallback_response(fallback_text, default_seconds)
        max_chars = max_chars_from_request(payload)
        text = clean_text(parsed.get("text", ""), max_chars=0)
        safety = str(parsed.get("safety", "fallback"))
        if text == "" or len(text) > max_chars or safety != "ok":
            return fallback_response(fallback_text, default_seconds)
        return ok_response(text, parsed.get("seconds", default_seconds), parsed.get("emotion", "neutral"))

    def _local_stub_memory_summary(self, payload: dict[str, Any]) -> dict[str, Any]:
        events = payload.get("recent_events", [])
        if not isinstance(events, list):
            events = []
        counts: dict[str, int] = {}
        mode_counts: dict[str, int] = {}
        period_counts: dict[str, int] = {}
        care = 0
        play = 0
        user_events = 0
        for event in events:
            if not isinstance(event, dict):
                continue
            kind = str(event.get("kind", "")).strip()
            if kind:
                counts[kind] = counts.get(kind, 0) + 1
            mode = str(event.get("mode", "")).strip()
            if mode:
                mode_counts[mode] = mode_counts.get(mode, 0) + 1
            period = str(event.get("period", "")).strip()
            if period:
                period_counts[period] = period_counts.get(period, 0) + 1
            if str(event.get("source", "")) == "user" and kind in VALID_SUMMARY_INTERACTIONS:
                user_events += 1
            if kind in {"feed_start", "feed_success", "auto_prompt"}:
                care += 1
            if kind in {"tease_start", "tease_success"}:
                play += 1
        favorite_interactions = [
            key for key, _count in sorted(
                ((key, value) for key, value in counts.items() if key in VALID_SUMMARY_INTERACTIONS),
                key=lambda item: (-item[1], item[0]),
            )[:3]
        ]
        total = max(1, len(events))
        summary = {
            "favorite_interactions": favorite_interactions,
            "favorite_mode": self._top_key(mode_counts, VALID_SUMMARY_MODES),
            "favorite_period": self._top_key(period_counts, VALID_SUMMARY_PERIODS),
            "care_tendency": round(care / total * 100),
            "play_tendency": round(play / total * 100),
            "interruption_tolerance": "high" if user_events >= 8 else "medium",
            "confidence": 75 if len(events) >= 3 else 55,
        }
        return ok_summary_response(summary)

    def _openai_memory_summary(self, payload: dict[str, Any]) -> dict[str, Any]:
        if not self._openai_configured():
            return fallback_summary_response()
        endpoint = os.environ.get("MASCOTMATE_OPENAI_COMPATIBLE_URL", "").strip()
        api_key = os.environ.get("MASCOTMATE_OPENAI_COMPATIBLE_API_KEY", "").strip()
        model = os.environ.get("MASCOTMATE_OPENAI_COMPATIBLE_MODEL", "gpt-4o-mini").strip()
        prompt = self._memory_summary_prompt(payload)
        request_body = {
            "model": model,
            "messages": [
                {
                    "role": "system",
                    "content": "Return only compact JSON with keys favorite_interactions, favorite_mode, favorite_period, care_tendency, play_tendency, interruption_tolerance, confidence, safety. Do not include free text.",
                },
                {"role": "user", "content": json.dumps(prompt, ensure_ascii=False)},
            ],
            "temperature": 0.2,
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
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with opener.open(request, timeout=self.timeout) as response:
                raw = json.loads(response.read().decode("utf-8"))
        except (OSError, urllib.error.URLError, json.JSONDecodeError):
            return fallback_summary_response()
        try:
            content = raw["choices"][0]["message"]["content"]
            parsed = json.loads(content)
        except (KeyError, IndexError, TypeError, json.JSONDecodeError):
            return fallback_summary_response()
        if not isinstance(parsed, dict):
            return fallback_summary_response()
        if any(str(key) not in ALLOWED_SUMMARY_KEYS for key in parsed.keys()):
            return fallback_summary_response()
        if str(parsed.get("safety", "fallback")) != "ok":
            return fallback_summary_response()
        summary = ok_summary_response(parsed)
        if summary["confidence"] < 60:
            return fallback_summary_response()
        return summary

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

    def _memory_summary_prompt(self, payload: dict[str, Any]) -> dict[str, Any]:
        return {
            "recent_events": payload.get("recent_events", []),
            "memory": payload.get("memory", {}),
            "profile": payload.get("profile", {}),
            "personality": payload.get("personality", {}),
            "local_preferences": payload.get("local_preferences", {}),
            "allowed": {
                "favorite_interactions": sorted(VALID_SUMMARY_INTERACTIONS),
                "favorite_mode": sorted(VALID_SUMMARY_MODES),
                "favorite_period": sorted(VALID_SUMMARY_PERIODS),
                "interruption_tolerance": sorted(VALID_INTERRUPTION_TOLERANCE),
            },
        }

    def _top_key(self, counts: dict[str, int], allowed: set[str]) -> str:
        candidates = [(key, value) for key, value in counts.items() if key in allowed and key]
        if not candidates:
            return ""
        candidates.sort(key=lambda item: (-item[1], item[0]))
        return candidates[0][0]


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
        route = self.path.split("?", 1)[0]
        if route not in {"/v1/expression", "/v1/memory-summary"}:
            self._json(fallback_response("", 1.8), 404)
            return
        try:
            payload = self._read_json()
        except ValueError:
            self._json(fallback_summary_response() if route == "/v1/memory-summary" else fallback_response("", 1.8), 400)
            return
        if route == "/v1/memory-summary":
            self._json(self.server.app.memory_summary(payload))
        else:
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
