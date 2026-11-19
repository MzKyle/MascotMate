"""Run the real helper CLI without launching a browser during the Godot test."""

import sys
import threading
import webbrowser
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from pet_helper import main

if __name__ == "__main__":
    opened = Path(sys.argv.pop(1))

    def open_browser(url):
        staging = opened.with_suffix(".tmp")
        staging.write_text(url, encoding="utf-8")
        staging.replace(opened)
        # Model an opener that stays attached to a browser process.
        threading.Event().wait()

    webbrowser.open = open_browser
    raise SystemExit(main())
