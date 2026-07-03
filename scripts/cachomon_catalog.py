#!/usr/bin/env python3
"""Fetch and parse Cachomon Shimeji browser metadata.

The helper intentionally indexes only public metadata and preview URLs. It does
not mirror or expose third-party Shimeji download files.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from html import unescape
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, quote_plus, urljoin, urlparse
from urllib.request import Request, urlopen


CACHOMON_SAFE_GRID_URL = "https://cachomon.com/grid.php?a=0&g=1&m=0&t=1"
USER_AGENT = "MascotMateDesktop/1.0 (+https://github.com/MzKyle/Crayon-Shinchan-Desktop-Pat)"
CONFIG_DIR_NAME = "mascotmate-desktop"
BOX_RE = re.compile(
    r'<div class="shimejibox">.*?(?=<div class="shimejibox">|</div>\s*</div>\s*</div>\s*<div class="footer">)',
    re.DOTALL,
)
ATTR_RE_TEMPLATE = r'{name}\s*=\s*["\']([^"\']+)["\']'


def config_cache_root() -> Path:
    return Path.home() / ".config" / CONFIG_DIR_NAME / "catalog_cache" / "cachomon"


def fetch_html(url: str, timeout: float = 12.0) -> str:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", "replace")


def parse_grid_html(html: str, base_url: str = CACHOMON_SAFE_GRID_URL) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    boxes = ['<div class="shimejibox">' + chunk for chunk in html.split('<div class="shimejibox">')[1:]]
    if not boxes:
        boxes = BOX_RE.findall(html)
    for box in boxes:
        entry = parse_box(box, base_url)
        if entry:
            entries.append(entry)
    return entries


def parse_box(box: str, base_url: str) -> dict[str, Any] | None:
    raw_id = _first_match(r"(?:copyURLToClipboard\(|[?&]id=)(\d+)", box)
    if not raw_id:
        return None
    name = _text_from_named_link(box, raw_id) or f"Shimeji {raw_id}"
    detail_href = _first_match(r'href=["\']([^"\']*shimeji\.php[^"\']*id=%s[^"\']*)["\']' % re.escape(raw_id), box)
    source_url = urljoin(base_url, unescape(detail_href or f"shimeji.php?id={raw_id}"))
    preview_src = _first_match(r'<img\s+[^>]*class=["\']shimeji["\'][^>]*src=["\']([^"\']+)["\']', box)
    if not preview_src:
        preview_src = _first_match(r'<img\s+[^>]*src=["\']([^"\']+)["\'][^>]*class=["\']shimeji["\']', box)
    preview_url = urljoin(base_url, unescape(preview_src or ""))

    icon_labels = _icon_labels(box)
    download_labels = _download_labels(box)
    status = _status_from_labels(download_labels)
    complexity = _complexity_from_labels(icon_labels)
    safe_level = _safe_level_from_labels(icon_labels)
    features = _features_from_labels(icon_labels, download_labels)
    artist = _artist_from_box(box)
    downloads = _parse_int(_first_match(r'<div class="shimejiboxcounter">\s*([0-9,]+)\s*</div>', box))

    return {
        "id": f"cachomon-{raw_id}",
        "source_type": "external_browser",
        "source": "cachomon",
        "name": name,
        "description": "Open the original Cachomon page to download this Shimeji.",
        "source_url": source_url,
        "preview_url": preview_url,
        "artist": artist,
        "status": status,
        "complexity": complexity,
        "features": features,
        "downloads": downloads,
        "safe_level": safe_level,
        "format": "shimeji-ee",
        "tags": ["shimeji", "cachomon", status] + features,
    }


def fetch_index(*, safe: bool = True, timeout: float = 12.0) -> dict[str, Any]:
    url = CACHOMON_SAFE_GRID_URL if safe else CACHOMON_SAFE_GRID_URL
    html = fetch_html(url, timeout)
    entries = parse_grid_html(html, url)
    return {
        "schema_version": 1,
        "source": "cachomon",
        "source_url": url,
        "safe": safe,
        "fetched_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "count": len(entries),
        "entries": entries,
    }


def cache_index(index: dict[str, Any], cache_root: Path) -> Path:
    cache_root.mkdir(parents=True, exist_ok=True)
    path = cache_root / "index.json"
    path.write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def _first_match(pattern: str, text: str) -> str:
    match = re.search(pattern, text, flags=re.DOTALL | re.IGNORECASE)
    return unescape(match.group(1)).strip() if match else ""


def _text_from_named_link(box: str, raw_id: str) -> str:
    pattern = r'<div class="shimejitext">\s*<a\s+[^>]*id=%s[^>]*>(.*?)</a>' % re.escape(raw_id)
    text = _first_match(pattern, box)
    return _strip_tags(text)


def _strip_tags(text: str) -> str:
    text = re.sub(r"<[^>]+>", "", text)
    return unescape(text).strip()


def _attr_values(attr: str, html: str) -> list[str]:
    pattern = re.compile(ATTR_RE_TEMPLATE.format(name=re.escape(attr)), re.IGNORECASE)
    return [unescape(value).strip() for value in pattern.findall(html) if value.strip()]


def _icon_labels(box: str) -> list[str]:
    labels: list[str] = []
    for label in _attr_values("alt", box) + _attr_values("title", box):
        if label and label not in labels:
            labels.append(label)
    return labels


def _download_labels(box: str) -> list[str]:
    block = _first_match(r'<div class="shimejiboxdownload">(.*?)</div>', box)
    return _icon_labels(block)


def _status_from_labels(labels: list[str]) -> str:
    joined = " ".join(labels).lower()
    if "download now" in joined or "free" in joined:
        return "free"
    if "beta" in joined:
        return "beta"
    if "patreon" in joined or "exclusive" in joined:
        return "patreon"
    if "not downloadable" in joined:
        return "unavailable"
    return "unknown"


def _complexity_from_labels(labels: list[str]) -> str:
    for label in labels:
        if "complexity" not in label.lower():
            continue
        return label.replace(" Complexity", "").replace(" complexity", "").strip()
    return ""


def _safe_level_from_labels(labels: list[str]) -> str:
    lowered = [label.lower() for label in labels]
    if any("adult" in label for label in lowered):
        return "adult"
    if any("mature" in label for label in lowered):
        return "mature"
    if any("sfw" in label or "safe" in label or "general" in label for label in lowered):
        return "sfw"
    return "sfw"


def _features_from_labels(labels: list[str], download_labels: list[str]) -> list[str]:
    ignored = {
        "copy link",
        "sfw",
        "safe",
        "general content on",
        "download now!",
        "download now",
        "beta",
        "beta download",
        "patreon exclusive",
        "not downloadable",
    }
    result: list[str] = []
    for label in labels:
        clean = label.strip()
        lower = clean.lower()
        if lower in ignored or lower.startswith("art by ") or "complexity" in lower:
            continue
        if clean in download_labels:
            continue
        if clean not in result:
            result.append(clean)
    return result


def _artist_from_box(box: str) -> str:
    artist = _first_match(r'alt=["\']Art by ([^"\']+)["\']', box)
    if artist:
        return artist
    artist_href = _first_match(r'grid\.php\?[^"\']*[?&]s=([^"\']+)["\']', box)
    return unescape(artist_href.replace("+", " ")).strip()


def _parse_int(text: str) -> int:
    try:
        return int(text.replace(",", "").strip())
    except ValueError:
        return 0


def search_url(query: str) -> str:
    return f"https://cachomon.com/grid.php?g=1&m=0&a=0&t=1&s={quote_plus(query)}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--safe", action="store_true", default=True)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--cache-root", type=Path, default=config_cache_root())
    parser.add_argument("--timeout", type=float, default=12.0)
    parser.add_argument("--html-fixture", type=Path)
    args = parser.parse_args()

    if args.html_fixture:
        html = args.html_fixture.read_text(encoding="utf-8")
        entries = parse_grid_html(html, CACHOMON_SAFE_GRID_URL)
        index = {
            "schema_version": 1,
            "source": "cachomon",
            "source_url": CACHOMON_SAFE_GRID_URL,
            "safe": True,
            "fetched_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "count": len(entries),
            "entries": entries,
        }
    else:
        index = fetch_index(safe=args.safe, timeout=args.timeout)
    cache_index(index, args.cache_root)
    if args.json:
        print(json.dumps(index, ensure_ascii=False, indent=2))
    else:
        print(args.cache_root / "index.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
