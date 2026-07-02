#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_EXEC="$ROOT_DIR/dist/MascotMateDesktop/MascotMateDesktop"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
DESKTOP_FILE="$DESKTOP_DIR/mascotmate-desktop.desktop"
LEGACY_DESKTOP_FILE="$DESKTOP_DIR/crayon-shinchan-desktop-pet.desktop"
ICON_NAME="mascotmate-desktop"
ICON_FILE="$ICON_DIR/$ICON_NAME.png"
LEGACY_ICON_FILE="$ICON_DIR/crayon-shinchan-desktop-pet.png"
ICON_SOURCE="$(find "$ROOT_DIR/resource_hd/xianzhi" -maxdepth 1 -type f -name '*.png' 2>/dev/null | sort | head -n 1)"

if [[ -x "$GODOT_EXEC" ]]; then
  APP_EXEC="$GODOT_EXEC"
else
  echo "Godot packaged app not found." >&2
  echo "Run scripts/build_godot_linux.sh first." >&2
  exit 1
fi

mkdir -p "$DESKTOP_DIR" "$ICON_DIR"
rm -f "$LEGACY_DESKTOP_FILE" "$LEGACY_ICON_FILE"
if [[ -n "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$ICON_FILE"
fi

sed \
  -e "s#__EXEC__#$APP_EXEC#g" \
  -e "s#__ICON__#$ICON_NAME#g" \
  "$ROOT_DIR/packaging/mascotmate-desktop.desktop.in" > "$DESKTOP_FILE"

chmod +x "$DESKTOP_FILE"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
fi

echo "Installed launcher: $DESKTOP_FILE"
