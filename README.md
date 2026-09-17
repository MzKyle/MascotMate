# MascotMate Desktop

[English](README.md) | [简体中文](README.zh-CN.md)

![MascotMate Desktop](docs/assets/cover.png)

MascotMate Desktop is a local desktop pet app. It puts an animated companion on
your desktop, lets you interact with it directly, and adds small local utilities
for screenshots, sticky image pins, skins, and low-pressure companion prompts.

It is built for personal desktop use: no account, no cloud backend, and no
always-on chat requirement. The pet runs locally through Godot.

## Download

Portable builds are published on GitHub Releases. There is no installer:
download the ZIP for your system, extract the whole ZIP, and run the app from
the extracted folder.

| System | Download | Run |
| --- | --- | --- |
| Windows x86_64 | [MascotMateDesktop-windows-x86_64.zip](https://github.com/MzKyle/MascotMate/releases/latest/download/MascotMateDesktop-windows-x86_64.zip) | `MascotMateDesktop.exe` |
| macOS universal | [MascotMateDesktop-macos-universal.zip](https://github.com/MzKyle/MascotMate/releases/latest/download/MascotMateDesktop-macos-universal.zip) | `MascotMateDesktop.app` |
| Linux x86_64 | [MascotMateDesktop-linux-x86_64.zip](https://github.com/MzKyle/MascotMate/releases/latest/download/MascotMateDesktop-linux-x86_64.zip) | `MascotMateDesktop` |

[View all releases](https://github.com/MzKyle/MascotMate/releases)

Keep every extracted file and folder together. MascotMate uses the bundled
`resource_hd`, `assets`, `skin_catalog`, `skin_store`, `companion_console`, and
`scripts` folders at runtime. On macOS, keep `MascotMateDesktop.app` inside the
extracted folder instead of moving only the app bundle elsewhere.

## Quick Start

1. Download the package for your system from the table above.
2. Extract the ZIP file.
3. Run the app from the extracted folder.
4. Right-click the pet and choose **怎么玩？** any time to replay the basic tips.

Windows may show a SmartScreen prompt for unsigned local builds. macOS may ask
you to confirm opening the app the first time.

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

The right-click menu includes walking, feeding, sleep/wake, tease, help, display
size, gravity, skin shop, companion console, screenshot settings, behavior mode,
dialogue tone, cleanup, and exit.

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
- Mischief mode plays a visual "grab" performance; it does not move or lock your
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

## Local Data

Runtime data is written to:

```text
~/.config/mascotmate-desktop/
```

This includes app config, state, screenshot history, companion memory summaries,
diagnostic snapshots, and imported skins.

## Troubleshooting

- If the pet cannot find skins or assets, make sure you are running it from the
  extracted portable folder and did not move only the executable or app bundle.
- If transparent windows do not behave correctly on Linux, developers can run
  from source with `CRAYON_PET_SAFE_WINDOW=1`.
- If a release download link is unavailable, open the
  [releases page](https://github.com/MzKyle/MascotMate/releases) and download the
  newest matching package.

## For Developers

Run from source:

```bash
python3 scripts/setup_dev_environment.py
scripts/setup_godot.sh
python3 scripts/generate_godot_manifest.py
scripts/run_godot_pet.sh
```

Safe window mode:

```bash
CRAYON_PET_SAFE_WINDOW=1 scripts/run_godot_pet.sh
```

Build a local Linux portable bundle and install a user-level launcher:

```bash
scripts/build_godot_linux.sh
scripts/install_desktop_entry.sh
```

Useful checks:

```bash
python3 scripts/generate_godot_manifest.py --check
python3 scripts/validate_resources.py
python3 scripts/validate_skin_catalog.py --check
python3 scripts/run_godot_smoke.py
python3 -m unittest discover tests
```

Detailed docs:

- [Developer documentation](docs/README.md)
- [Run from source](docs/guide/run-app.md)
- [Install and package](docs/guide/package-install.md)
- [Architecture overview](docs/architecture/README.md)
- [Behavior system](docs/modules/behavior.md)
- [Screenshot pins](docs/modules/screenshot-pins.md)
- [Skin package spec](docs/sdk/skin-package-spec.md)
- [Troubleshooting](docs/faq/troubleshooting.md)

## License and Assets

Code is released under the [Apache License 2.0](LICENSE). Character-related
assets in this fan project are intended for learning, research, and personal
local desktop use. Replace them with original or properly licensed assets before
public distribution.
