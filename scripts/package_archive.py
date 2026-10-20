"""ZIP round trips preserving POSIX executable modes and app symlinks."""

from __future__ import annotations

import os
import stat
import zipfile
from pathlib import Path, PurePosixPath


def extract_archive(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    root = destination.resolve()
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            name = PurePosixPath(info.filename.replace("\\", "/"))
            if name.is_absolute() or ".." in name.parts or ":" in str(name):
                raise ValueError(f"Unsafe ZIP entry: {info.filename}")
            target = destination.joinpath(*name.parts)
            if not target.resolve().is_relative_to(root):
                raise ValueError(f"ZIP entry escapes extraction root: {info.filename}")
            mode = info.external_attr >> 16
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            elif stat.S_ISLNK(mode):
                link = zf.read(info).decode("utf-8")
                if Path(link).is_absolute() or not (target.parent / link).resolve().is_relative_to(root):
                    raise ValueError(f"Unsafe ZIP symlink: {info.filename}")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(link)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(zf.read(info))
                if mode & 0o777:
                    target.chmod(mode & 0o777)


def create_archive(source: Path, archive: Path) -> None:
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(source.rglob("*")):
            relative = path.relative_to(source).as_posix()
            if path.is_symlink():
                info = zipfile.ZipInfo(relative)
                info.create_system = 3
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
                zf.writestr(info, os.readlink(path))
            else:
                zf.write(path, relative)
