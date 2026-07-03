#!/usr/bin/env python3
"""Cross-platform helper for the Godot desktop pet.

The helper keeps OS-specific clipboard and global-hotkey code outside Godot.
It is runnable as a Python script during development and can be packaged into
a standalone binary with PyInstaller for release bundles.
"""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import importlib.util
import os
import platform
import shutil
import socket
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    from PIL import Image as _PIL_IMAGE_FOR_SHIMEJI_IMPORT  # noqa: F401
except Exception:
    _PIL_IMAGE_FOR_SHIMEJI_IMPORT = None


KEY_PRESS = 2
GRAB_MODE_ASYNC = 1
SHIFT_MASK = 1 << 0
LOCK_MASK = 1 << 1
CONTROL_MASK = 1 << 2
MOD1_MASK = 1 << 3
MOD2_MASK = 1 << 4
MOD4_MASK = 1 << 6
X_ERROR_HANDLER = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)
_ERROR_HANDLER_REF = None


@dataclass(frozen=True)
class Hotkey:
    command: str
    shortcut: str
    keysym: int
    keycode: int
    modifiers: int


class XKeyEvent(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int),
        ("serial", ctypes.c_ulong),
        ("send_event", ctypes.c_int),
        ("display", ctypes.c_void_p),
        ("window", ctypes.c_ulong),
        ("root", ctypes.c_ulong),
        ("subwindow", ctypes.c_ulong),
        ("time", ctypes.c_ulong),
        ("x", ctypes.c_int),
        ("y", ctypes.c_int),
        ("x_root", ctypes.c_int),
        ("y_root", ctypes.c_int),
        ("state", ctypes.c_uint),
        ("keycode", ctypes.c_uint),
        ("same_screen", ctypes.c_int),
    ]


class XEvent(ctypes.Union):
    _fields_ = [
        ("type", ctypes.c_int),
        ("xkey", XKeyEvent),
        ("pad", ctypes.c_long * 24),
    ]


def copy_image(path: Path) -> int:
    if not path.is_file():
        print(f"Image not found: {path}", file=sys.stderr)
        return 2
    system = platform.system()
    if system == "Windows":
        return copy_image_windows(path)
    if system == "Darwin":
        return copy_image_macos(path)
    if system == "Linux":
        return copy_image_linux(path)
    print(f"Unsupported clipboard platform: {system}", file=sys.stderr)
    return 1


def load_importer_module():
    script = Path(__file__).resolve().with_name("import_shimeji_skin.py")
    if not script.is_file() and getattr(sys, "frozen", False):
        script = Path(sys.executable).resolve().with_name("import_shimeji_skin.py")
    if not script.is_file():
        print("import_shimeji_skin.py was not found.", file=sys.stderr)
        return None
    spec = importlib.util.spec_from_file_location("import_shimeji_skin", script)
    if spec == None or spec.loader == None:
        print("Unable to load import_shimeji_skin.py.", file=sys.stderr)
        return None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def import_shimeji(args: argparse.Namespace) -> int:
    module = load_importer_module()
    if module is None:
        return 2
    script = Path(module.__file__).resolve()
    argv = [str(script), str(args.source), "--output-root", str(args.output_root)]
    if args.skin_id:
        argv += ["--id", args.skin_id]
    if args.skin_name:
        argv += ["--name", args.skin_name]
    if args.json_report:
        argv += ["--json-report"]
    previous_argv = sys.argv
    try:
        sys.argv = argv
        return int(module.main())
    finally:
        sys.argv = previous_argv


def install_skin(args: argparse.Namespace) -> int:
    module = load_importer_module()
    if module is None:
        return 2
    imported = module.install_skin_source(args.source, args.output_root, args.skin_id, args.skin_name)
    module.print_results(imported, args.json_report)
    return 0


def load_cachomon_module():
    script = Path(__file__).resolve().with_name("cachomon_catalog.py")
    if not script.is_file() and getattr(sys, "frozen", False):
        script = Path(sys.executable).resolve().with_name("cachomon_catalog.py")
    if not script.is_file():
        print("cachomon_catalog.py was not found.", file=sys.stderr)
        return None
    spec = importlib.util.spec_from_file_location("cachomon_catalog", script)
    if spec == None or spec.loader == None:
        print("Unable to load cachomon_catalog.py.", file=sys.stderr)
        return None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def fetch_cachomon_index(args: argparse.Namespace) -> int:
    module = load_cachomon_module()
    if module is None:
        return 2
    if args.html_fixture:
        html = args.html_fixture.read_text(encoding="utf-8")
        entries = module.parse_grid_html(html, module.CACHOMON_SAFE_GRID_URL)
        index = {
            "schema_version": 1,
            "source": "cachomon",
            "source_url": module.CACHOMON_SAFE_GRID_URL,
            "safe": True,
            "fetched_at": module.datetime.now(module.timezone.utc).isoformat(timespec="seconds"),
            "count": len(entries),
            "entries": entries,
        }
    else:
        index = module.fetch_index(safe=args.safe, timeout=args.timeout)
    module.cache_index(index, args.cache_root)
    if args.json_report:
        print(module.json.dumps(index, ensure_ascii=False, indent=2))
    else:
        print(args.cache_root / "index.json")
    return 0


def copy_image_windows(path: Path) -> int:
    powershell = shutil.which("powershell.exe") or shutil.which("powershell")
    if not powershell:
        print("PowerShell was not found.", file=sys.stderr)
        return 1
    script = r"""
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$path = $env:CRAYON_PET_CLIPBOARD_IMAGE
for ($i = 0; $i -lt 5; $i++) {
    try {
        $img = [System.Drawing.Image]::FromFile($path)
        [System.Windows.Forms.Clipboard]::SetImage($img)
        $img.Dispose()
        exit 0
    } catch {
        if ($img -ne $null) { $img.Dispose() }
        Start-Sleep -Milliseconds 120
    }
}
exit 1
"""
    env = os.environ.copy()
    env["CRAYON_PET_CLIPBOARD_IMAGE"] = str(path)
    proc = subprocess.run(
        [powershell, "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-Command", script],
        env=env,
        text=True,
    )
    return proc.returncode


def copy_image_macos(path: Path) -> int:
    osascript = shutil.which("osascript")
    if not osascript:
        print("osascript was not found.", file=sys.stderr)
        return 1
    script = """
set imagePath to system attribute "CRAYON_PET_CLIPBOARD_IMAGE"
set imageFile to POSIX file imagePath
set the clipboard to (read imageFile as «class PNGf»)
"""
    env = os.environ.copy()
    env["CRAYON_PET_CLIPBOARD_IMAGE"] = str(path)
    proc = subprocess.run([osascript, "-e", script], env=env, text=True)
    return proc.returncode


def copy_image_linux(path: Path) -> int:
    wl_copy = shutil.which("wl-copy")
    if wl_copy:
        with path.open("rb") as image_file:
            proc = subprocess.run([wl_copy, "--type", "image/png"], stdin=image_file)
        if proc.returncode == 0:
            return 0

    xclip = shutil.which("xclip")
    if xclip:
        with path.open("rb") as image_file:
            proc = subprocess.run(
                [xclip, "-selection", "clipboard", "-target", "image/png", "-i"],
                stdin=image_file,
            )
        return proc.returncode

    print("Install wl-copy or xclip to copy PNG screenshots on Linux.", file=sys.stderr)
    return 1


def run_hotkeys(args: argparse.Namespace) -> int:
    if platform.system() == "Linux" and os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        return run_x11_hotkeys(args)
    return run_pynput_hotkeys(args)


def run_pynput_hotkeys(args: argparse.Namespace) -> int:
    try:
        from pynput import keyboard
    except Exception as exc:
        print(f"pynput is required for global hotkeys on this platform: {exc}", file=sys.stderr)
        return 1

    bindings = {
        normalize_pynput_shortcut(args.screenshot): make_sender(args.port, "screenshot"),
        normalize_pynput_shortcut(args.paste_pin): make_sender(args.port, "paste_pin"),
        normalize_pynput_shortcut(args.close_pin): make_sender(args.port, "close_pin"),
    }
    try:
        with keyboard.GlobalHotKeys(bindings) as listener:
            listener.join()
    except Exception as exc:
        print(f"Unable to register global hotkeys: {exc}", file=sys.stderr)
        return 1
    return 0


def normalize_pynput_shortcut(shortcut: str) -> str:
    parts = [part.strip() for part in shortcut.split("+") if part.strip()]
    if not parts:
        raise ValueError("empty shortcut")
    converted: list[str] = []
    modifier_map = {
        "ctrl": "<ctrl>",
        "control": "<ctrl>",
        "alt": "<alt>",
        "option": "<alt>",
        "shift": "<shift>",
        "super": "<cmd>",
        "meta": "<cmd>",
        "win": "<cmd>",
        "command": "<cmd>",
    }
    key_map = {
        "escape": "<esc>",
        "esc": "<esc>",
        "enter": "<enter>",
        "return": "<enter>",
        "space": "<space>",
        "tab": "<tab>",
    }
    for part in parts[:-1]:
        converted.append(modifier_map.get(part.lower(), part.lower()))
    key = parts[-1]
    lower = key.lower()
    if lower in key_map:
        converted.append(key_map[lower])
    elif lower.startswith("f") and lower[1:].isdigit():
        converted.append(f"<{lower}>")
    elif len(key) == 1:
        converted.append(key.lower())
    else:
        converted.append(f"<{lower}>")
    return "+".join(converted)


def make_sender(port: int, command: str):
    def send_command() -> None:
        sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sender.sendto(command.encode("utf-8"), ("127.0.0.1", port))
        finally:
            sender.close()

    return send_command


def load_x11() -> ctypes.CDLL:
    path = ctypes.util.find_library("X11")
    if not path:
        raise RuntimeError("libX11 not found")
    lib = ctypes.CDLL(path)
    lib.XOpenDisplay.argtypes = [ctypes.c_char_p]
    lib.XOpenDisplay.restype = ctypes.c_void_p
    lib.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    lib.XDefaultRootWindow.restype = ctypes.c_ulong
    lib.XStringToKeysym.argtypes = [ctypes.c_char_p]
    lib.XStringToKeysym.restype = ctypes.c_ulong
    lib.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
    lib.XKeysymToKeycode.restype = ctypes.c_uint
    lib.XGrabKey.argtypes = [
        ctypes.c_void_p,
        ctypes.c_int,
        ctypes.c_uint,
        ctypes.c_ulong,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
    ]
    lib.XGrabKey.restype = ctypes.c_int
    lib.XUngrabKey.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_uint, ctypes.c_ulong]
    lib.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
    lib.XNextEvent.argtypes = [ctypes.c_void_p, ctypes.POINTER(XEvent)]
    lib.XCloseDisplay.argtypes = [ctypes.c_void_p]
    lib.XSetErrorHandler.argtypes = [X_ERROR_HANDLER]
    return lib


def parse_x11_shortcut(lib: ctypes.CDLL, display: ctypes.c_void_p, command: str, shortcut: str) -> Hotkey:
    parts = [part.strip() for part in shortcut.split("+") if part.strip()]
    if not parts:
        raise ValueError(f"empty shortcut for {command}")
    modifiers = 0
    key_name = parts[-1]
    for part in parts[:-1]:
        lower = part.lower()
        if lower in ("ctrl", "control"):
            modifiers |= CONTROL_MASK
        elif lower == "shift":
            modifiers |= SHIFT_MASK
        elif lower in ("alt", "option"):
            modifiers |= MOD1_MASK
        elif lower in ("super", "meta", "win", "command"):
            modifiers |= MOD4_MASK
        else:
            raise ValueError(f"unknown modifier '{part}' in {shortcut}")

    x11_name = normalize_x11_key_name(key_name)
    keysym = int(lib.XStringToKeysym(x11_name.encode("utf-8")))
    if keysym == 0 and len(key_name) == 1:
        keysym = int(lib.XStringToKeysym(key_name.lower().encode("utf-8")))
    if keysym == 0:
        raise ValueError(f"unknown key '{key_name}' in {shortcut}")
    keycode = int(lib.XKeysymToKeycode(display, keysym))
    if keycode == 0:
        raise ValueError(f"no keycode for {shortcut}")
    return Hotkey(command, shortcut, keysym, keycode, modifiers)


def normalize_x11_key_name(name: str) -> str:
    aliases = {
        "Esc": "Escape",
        "Return": "Return",
        "Enter": "Return",
        "Space": "space",
        "PgUp": "Page_Up",
        "PageUp": "Page_Up",
        "PgDown": "Page_Down",
        "PageDown": "Page_Down",
        "Plus": "plus",
        "Minus": "minus",
    }
    if name in aliases:
        return aliases[name]
    if len(name) == 1:
        return name.lower()
    return name


def grab_x11_hotkeys(lib: ctypes.CDLL, display: ctypes.c_void_p, root: int, hotkeys: list[Hotkey]) -> None:
    global _ERROR_HANDLER_REF
    _ERROR_HANDLER_REF = X_ERROR_HANDLER(lambda _display, _event: 0)
    lib.XSetErrorHandler(_ERROR_HANDLER_REF)
    ignored_locks = (0, LOCK_MASK, MOD2_MASK, LOCK_MASK | MOD2_MASK)
    for hotkey in hotkeys:
        for extra in ignored_locks:
            lib.XGrabKey(
                display,
                hotkey.keycode,
                hotkey.modifiers | extra,
                root,
                True,
                GRAB_MODE_ASYNC,
                GRAB_MODE_ASYNC,
            )
    lib.XSync(display, False)


def run_x11_hotkeys(args: argparse.Namespace) -> int:
    lib = load_x11()
    display = lib.XOpenDisplay(None)
    if not display:
        print("Unable to open X11 display.", file=sys.stderr)
        return 1
    root = int(lib.XDefaultRootWindow(display))
    hotkeys = [
        parse_x11_shortcut(lib, display, "screenshot", args.screenshot),
        parse_x11_shortcut(lib, display, "paste_pin", args.paste_pin),
        parse_x11_shortcut(lib, display, "close_pin", args.close_pin),
    ]
    grab_x11_hotkeys(lib, display, root, hotkeys)
    by_key = {(hotkey.keycode, hotkey.modifiers): hotkey.command for hotkey in hotkeys}
    sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    event = XEvent()
    try:
        while True:
            lib.XNextEvent(display, ctypes.byref(event))
            if event.type != KEY_PRESS:
                continue
            state = int(event.xkey.state) & ~(LOCK_MASK | MOD2_MASK)
            command = by_key.get((int(event.xkey.keycode), state))
            if command:
                sender.sendto(command.encode("utf-8"), ("127.0.0.1", args.port))
    finally:
        sender.close()
        lib.XCloseDisplay(display)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    hotkeys = subparsers.add_parser("hotkeys")
    hotkeys.add_argument("--port", type=int, required=True)
    hotkeys.add_argument("--screenshot", required=True)
    hotkeys.add_argument("--paste-pin", required=True)
    hotkeys.add_argument("--close-pin", required=True)

    copy = subparsers.add_parser("copy-image")
    copy.add_argument("path", type=Path)

    import_skin = subparsers.add_parser("import-shimeji")
    import_skin.add_argument("source", type=Path)
    import_skin.add_argument("--output-root", type=Path, required=True)
    import_skin.add_argument("--id", dest="skin_id")
    import_skin.add_argument("--name", dest="skin_name")
    import_skin.add_argument("--json-report", action="store_true")

    install_skin_parser = subparsers.add_parser("install-skin")
    install_skin_parser.add_argument("source", type=Path)
    install_skin_parser.add_argument("--output-root", type=Path, required=True)
    install_skin_parser.add_argument("--id", dest="skin_id")
    install_skin_parser.add_argument("--name", dest="skin_name")
    install_skin_parser.add_argument("--json-report", action="store_true")

    cachomon = subparsers.add_parser("fetch-cachomon-index")
    cachomon.add_argument("--safe", action="store_true", default=True)
    cachomon.add_argument("--json", dest="json_report", action="store_true")
    cachomon.add_argument("--cache-root", type=Path, default=Path.home() / ".config" / "mascotmate-desktop" / "catalog_cache" / "cachomon")
    cachomon.add_argument("--timeout", type=float, default=12.0)
    cachomon.add_argument("--html-fixture", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "hotkeys":
            return run_hotkeys(args)
        if args.command == "copy-image":
            return copy_image(args.path)
        if args.command == "import-shimeji":
            return import_shimeji(args)
        if args.command == "install-skin":
            return install_skin(args)
        if args.command == "fetch-cachomon-index":
            return fetch_cachomon_index(args)
    except Exception as exc:
        print(f"pet_helper.py: {exc}", file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
