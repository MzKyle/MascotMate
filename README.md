# MascotMate Desktop

[English](README.md) | [简体中文](README.zh-CN.md)

![MascotMate Desktop](docs/assets/cover.png)

A local Godot desktop pet with transparent-window animation, physics interaction,
companion behavior, mini games, screenshots as sticky desktop pins, and a Shimeji-ee
skin shop with assisted imports.

[Read the documentation](docs/README.md)

## What You Can Do

- Keep an animated desktop pet on top of your desktop.
- Pick it up, throw it, let it fall with gravity, or hide it on a screen edge.
- Use quiet, active, or mischief behavior modes. The behavior model considers time,
  hunger, energy, mood, affection, recent interactions, and interruption cooldowns.
- Feed it, play the catch mini game, or check its local state.
- Capture a screen region with `F1`, paste recent captures as pinned windows with `F3`,
  and close the active pin with `F4`.
- Browse the skin shop, open Shimeji source pages, and import downloaded ZIPs or folders.

## Quick Start From Source

```bash
python3 scripts/setup_dev_environment.py
scripts/setup_godot.sh
python3 scripts/generate_godot_manifest.py
scripts/run_godot_pet.sh
```

If transparent windows do not work correctly on your desktop, start with the safe window
mode:

```bash
CRAYON_PET_SAFE_WINDOW=1 scripts/run_godot_pet.sh
```

## Install Locally on Linux

Build the local portable runtime bundle and install a user-level desktop launcher:

```bash
scripts/build_godot_linux.sh
scripts/install_desktop_entry.sh
```

The launcher is installed to:

```text
~/.local/share/applications/mascotmate-desktop.desktop
```

No system-wide install is required. Run the app from your application launcher or with:

```bash
dist/MascotMateDesktop/MascotMateDesktop
```

## Basic Controls

| Action | Result |
| --- | --- |
| Click head | Pet it |
| Click body | Poke it |
| Hold for 350 ms | Pick it up |
| Release quickly | Throw it |
| Release near screen edge | Enter peek mode |
| Double-click | Start catch mini game |
| Mouse wheel | Show mood, hunger, energy, and affection |
| Right-click | Open actions, skins, modes, screenshot settings, and exit menu |

## Useful Commands

```bash
python3 scripts/generate_godot_manifest.py --check
python3 scripts/validate_resources.py
python3 scripts/validate_skin_catalog.py --check
python3 scripts/run_godot_smoke.py
python3 -m unittest discover tests
```

## Documentation

- [Run the app](docs/guide/run-app.md)
- [Install and package](docs/guide/package-install.md)
- [Architecture overview](docs/architecture/README.md)
- [Behavior system](docs/modules/behavior.md)
- [Screenshot pins](docs/modules/screenshot-pins.md)
- [Skin package spec](docs/sdk/skin-package-spec.md)
- [Skin shop catalog](docs/sdk/skin-catalog.md)
- [Shimeji-ee import](docs/sdk/shimeji-import.md)
- [Troubleshooting](docs/faq/troubleshooting.md)

## License and Assets

Code is released under the [MIT License](LICENSE). Character-related assets in this fan
project are intended for learning, research, and personal local desktop use. Replace them
with original or properly licensed assets before public distribution.
