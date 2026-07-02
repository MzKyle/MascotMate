#!/usr/bin/env python3
"""Run Shimeji-ee import compatibility checks from an external corpus file."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parent.parent
IMPORTER = ROOT / "scripts" / "import_shimeji_skin.py"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_for(entry: dict, cache_dir: Path) -> Path:
    if entry.get("path"):
        path = Path(str(entry["path"])).expanduser()
        if not path.is_file() and not path.is_dir():
            raise FileNotFoundError(path)
        return path
    url = str(entry.get("url", ""))
    if url == "":
        raise ValueError("Corpus entry must define path or url.")
    name = str(entry.get("name", "shimeji")).lower().replace(" ", "-")
    suffix = ".zip" if url.lower().endswith(".zip") else ".bin"
    target = cache_dir / f"{name}{suffix}"
    if not target.exists():
        with urlopen(url, timeout=30) as response:
            target.write_bytes(response.read())
    expected_sha = str(entry.get("sha256", ""))
    if expected_sha and sha256(target) != expected_sha:
        raise ValueError(f"sha256 mismatch for {url}")
    return target


def run_import(source: Path, output_root: Path) -> dict:
    proc = subprocess.run(
        [
            sys.executable,
            str(IMPORTER),
            str(source),
            "--output-root",
            str(output_root),
            "--json-report",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout)
    parsed = json.loads(proc.stdout)
    if not parsed:
        raise RuntimeError("Importer returned no skin reports.")
    return parsed[0]["report"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("corpus", type=Path, help="JSON corpus file, see tests/compat/shimeji_corpus.example.json.")
    args = parser.parse_args()

    corpus = json.loads(args.corpus.read_text(encoding="utf-8"))
    entries = corpus.get("skins", [])
    if not isinstance(entries, list) or not entries:
        raise SystemExit("Corpus must contain a non-empty skins list.")

    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="shimeji-corpus-") as temp_dir:
        temp = Path(temp_dir)
        cache = temp / "cache"
        output = temp / "skins"
        cache.mkdir()
        output.mkdir()
        for entry in entries:
            name = str(entry.get("name", entry.get("path", entry.get("url", "skin"))))
            try:
                source = source_for(entry, cache)
                report = run_import(source, output)
                minimum = int(entry.get("min_score", 45))
                score = int(report.get("compatibility_score", 0))
                level = str(report.get("compatibility_level", "minimal"))
                print(f"{name}: {level} {score}/100")
                if score < minimum:
                    failures.append(f"{name}: score {score} < min_score {minimum}")
            except Exception as exc:
                failures.append(f"{name}: {exc}")

    if failures:
        print("Corpus compatibility failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
