"""Validate previously accepted artifacts; prepare notes without rebuilding ZIPs."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path

from release_version import check_versions

STABLE_ARCHIVES = {target: f"MascotMateDesktop-{target}-x86_64.zip" for target in ("windows", "linux")}


def prepare(directory: Path, version: str, commit: str) -> str:
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Candidate must identify a full commit SHA")
    if {path.name for path in directory.glob("*.zip")} != set(STABLE_ARCHIVES.values()):
        raise ValueError("Stable release must contain exactly the Windows and Linux ZIPs")
    checksums = []
    for target, filename in STABLE_ARCHIVES.items():
        archive = directory / filename
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if archive.with_suffix(".zip.sha256").read_text(encoding="utf-8").split() != [digest, filename]:
            raise ValueError(f"Checksum mismatch: {filename}")
        report = json.loads((directory / f"acceptance-{target}.json").read_text(encoding="utf-8"))
        with zipfile.ZipFile(archive) as zf:
            info = json.loads(zf.read("BUILD_INFO.json"))
        for value in (info, report):
            if value.get("version") != version or value.get("commit") != commit or value.get("target") != target:
                raise ValueError(f"Candidate version/commit/platform mismatch: {filename}")
        if not info.get("public") or info.get("candidate") or info.get("dirty", True):
            raise ValueError(f"Unqualified source/package for stable release: {filename}")
        if not report.get("passed") or report.get("archive") != filename or report.get("sha256") != digest:
            raise ValueError(f"Missing or mismatched final ZIP acceptance: {filename}")
        if not report.get("app", {}).get("passed"):
            raise ValueError(f"Exported app did not pass acceptance: {filename}")
        if any(report.get(key) is not True for key in ("helper", "skin_import", "skin_store", "companion_console", "restart")):
            raise ValueError(f"Incomplete helper acceptance: {filename}")
        checks = report["app"].get("checks", {})
        if report["app"].get("version") != version or len(checks) < 18 or any(value is not True for value in checks.values()):
            raise ValueError(f"Incomplete desktop acceptance: {filename}")
        checksums.append(f"{digest}  {filename}")
    (directory / "SHA256SUMS.txt").write_text("\n".join(checksums) + "\n", encoding="utf-8")
    base = f"https://github.com/MzKyle/MascotMate/releases/download/v{version}"
    notes = f"""# MascotMate Desktop v{version}

包含主分支的窗口管理重构、配置规范化和首次上手改进，并修复长期统计与公开打包可靠性。

| Platform | Download |
| --- | --- |
| Windows x86_64 | [Windows ZIP]({base}/{STABLE_ARCHIVES['windows']}) |
| Linux x86_64 | [Linux ZIP]({base}/{STABLE_ARCHIVES['linux']}) |

Extract the entire ZIP and keep all files together. There is no installer.
请完整解压并保留整个目录，再运行其中的程序。包内含 README.txt。

- 日聚合长期保留；明细保留最近 200 条。3/7/30 天统计采用包含今天的本地自然日。
- 配置、状态、截图、皮肤和缓存统一到系统应用数据目录。
- **升级变化**：Windows 使用 `%APPDATA%\\mascotmate-desktop`，Linux 使用 `${{XDG_DATA_HOME:-~/.local/share}}/mascotmate-desktop`。旧目录不会自动加载或迁移，原文件保留。
- 公开精选目录只包含明确允许分发的皮肤；仍支持手动导入本地皮肤。
- macOS 新版仅提供 CI 候选产物，未经运行验收，不包含在此稳定版附件中。

Both ZIPs were extracted and exercised before release. The accepted bytes are published unchanged.
对应验收报告及 SHA256SUMS.txt 随附件提供。

Source commit: `{commit}`
"""
    return notes


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--notes", type=Path, required=True)
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    version = check_versions()
    args.notes.write_text(prepare(args.directory, version, args.commit), encoding="utf-8")
    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as output:
            output.write(f"tag=v{version}\n")
    print(f"Accepted artifacts ready for v{version}; no rebuild performed.")
