# MascotMate Desktop

[English](README.md) | [简体中文](README.zh-CN.md)

![MascotMate Desktop](docs/assets/cover.png)

MascotMate Desktop is a local desktop pet app. It puts an animated companion on
your desktop, lets you interact with it directly, and adds a few small utilities
for screenshots, sticky image pins, skins, and low-pressure companion prompts.

It is built for personal desktop use: no account, no cloud backend, and no
always-on chat requirement. The pet runs locally through Godot.

## What It Does

- Shows an animated desktop pet in a transparent, always-on-top window.
- Lets you pet, poke, pick up, drop, throw, or hide the pet on a screen edge.
- Provides quiet, active, and mischief behavior modes.
- Shows gentle interaction bubbles, with selectable dialogue tone: gentle,
  cheerful, or calm.
- Supports feeding and cursor-teasing mini interactions.
- Lets you capture a screen region, paste recent captures as desktop pins, and
  close pins with shortcuts.
- Includes a browser skin shop for bundled skins and assisted Shimeji-ee imports.
- Can be built as a local Linux portable bundle with a desktop launcher.

## Quick Start

From the project root:

```bash
python3 scripts/setup_dev_environment.py
scripts/setup_godot.sh
python3 scripts/generate_godot_manifest.py
scripts/run_godot_pet.sh
```

If transparent windows do not behave correctly on your desktop, start in safe
window mode:

```bash
CRAYON_PET_SAFE_WINDOW=1 scripts/run_godot_pet.sh
```

## Install on Linux

Build the portable runtime bundle and install a user-level launcher:

```bash
scripts/build_godot_linux.sh
scripts/install_desktop_entry.sh
```

Then launch **MascotMate Desktop** from your app launcher, or run:

```bash
dist/MascotMateDesktop/MascotMateDesktop
```

The launcher is installed under your home directory:

```text
~/.local/share/applications/mascotmate-desktop.desktop
~/.local/share/icons/hicolor/256x256/apps/mascotmate-desktop.png
```

## How to Use It

| Action | Result |
| --- | --- |
| Click the head | Pet the companion |
| Click the body | Poke gently |
| Hold for about 350 ms | Pick it up |
| Release slowly | Put it down |
| Release quickly | Throw it |
| Release near a screen edge | Enter peek mode |
| Click while peeking | Come back from the edge |
| Double-click | Start the tease interaction |
| Mouse wheel | Show mood, hunger, energy, and affection |
| Right-click | Open the menu |

The right-click menu includes walking, feeding, sleep/wake, tease, display size,
gravity, skin shop, companion console, screenshot settings, behavior mode,
dialogue tone, cleanup, and exit.

## Screenshot Pins

Default shortcuts:

| Shortcut | Result |
| --- | --- |
| `F1` | Select a screen region and save/copy the screenshot |
| `F3` | Paste or cycle recent screenshots as desktop pins |
| `F4` | Close the active pin |

The screenshot settings window is available from the right-click menu.

## Companion Behavior

MascotMate keeps a small local state: mood, hunger, energy, and affection. It can
use recent interactions and long-term aggregate preferences to choose when to
show low-pressure prompts, such as food or a short play break.

Behavior stays local and bounded:

- Quiet mode avoids spontaneous movement except low-frequency care prompts.
- Active mode can walk, idle, peek at the edge, invite play, or show small effects.
- Mischief mode plays a visual “grab” performance; it does not move or lock your
  real mouse.
- Optional AI expression support is off by default and only affects bubble text.

## Skins

The built-in skin keeps compatibility with the original local animation assets.
The skin shop can install packaged featured skins or help import Shimeji-ee ZIPs
and folders into the local user config directory.

Imported user skins are stored under:

```text
~/.config/mascotmate-desktop/skins/
```

## User Data

Runtime data is written to:

```text
~/.config/mascotmate-desktop/
```

This includes app config, state, screenshot history, companion memory summaries,
diagnostic snapshots, and imported skins.

## Developer Docs

The detailed docs are written for maintainers and contributors:

- [Developer documentation](docs/README.md)
- [Run from source](docs/guide/run-app.md)
- [Install and package](docs/guide/package-install.md)
- [Architecture overview](docs/architecture/README.md)
- [Behavior system](docs/modules/behavior.md)
- [Screenshot pins](docs/modules/screenshot-pins.md)
- [Skin package spec](docs/sdk/skin-package-spec.md)
- [Troubleshooting](docs/faq/troubleshooting.md)

## Checks

Useful developer checks:

```bash
python3 scripts/generate_godot_manifest.py --check
python3 scripts/validate_resources.py
python3 scripts/validate_skin_catalog.py --check
python3 scripts/run_godot_smoke.py
python3 -m unittest discover tests
```

## License and Assets

Code is released under the [Apache License 2.0](LICENSE). Character-related
assets in this fan project are intended for learning, research, and personal
local desktop use. Replace them with original or properly licensed assets before
public distribution.
